//! Shared bounded PNG decode adapter for the notdef (C), space (E) and IoU (F) routes.
//!
//! Contract:
//! - Limits are an explicit caller input (`DecodeLimits` + a `LimitsOrigin`).
//!   There is no `Default` here and no default injection; callers that want the
//!   hub default must say so via `LimitsOrigin::ConfigNotWired`.
//! - The decode itself is `capture::decode_png_gray_bounded` (two-pass IDAT
//!   budget check before allocation). Typed `PngDecodeError` is returned
//!   unchanged (no String conversion).
//! - The success value carries a receipt with the exact limits and their origin.
//!
//! Limits kept honest (chief): the budget covers the major payload only
//! (idat copy / raw / recon / gray), NOT allocator overhead, RSS or Huffman
//! scratch. Chunk CRCs are NOT validated. Bit-identity with the previous
//! decode is claimed only for inputs within the supplied limits; inputs above
//! them are refused (explicit threshold change owned by the caller's limits).
use crate::capture::{decode_png_gray_bounded, DecodeLimits, PngDecodeError};

/// Where the limits a caller passed came from. Recorded in the receipt verbatim.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LimitsOrigin {
    /// Hardcoded hub default, RunConfig wiring pending (same wording as the
    /// pipeline `png_decode_limits` receipt line).
    ConfigNotWired(&'static str),
    /// Limits supplied by a named explicit source (e.g. a RunConfig field).
    Explicit(String),
}
impl LimitsOrigin {
    pub fn hub_default_not_wired() -> Self {
        LimitsOrigin::ConfigNotWired("hardcoded hub default; RunConfig wiring pending")
    }
    pub fn render(&self) -> String {
        match self {
            LimitsOrigin::ConfigNotWired(s) => format!("ConfigNotWired({s})"),
            LimitsOrigin::Explicit(s) => format!("Explicit({s})"),
        }
    }
}

/// Which route called the adapter (receipt label only; no behavioural effect).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Route { Notdef, Space, Iou }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BoundedPngReceipt {
    pub route: Route,
    pub limits: DecodeLimits,
    pub limits_origin: LimitsOrigin,
    pub width: usize,
    pub height: usize,
}
impl BoundedPngReceipt {
    /// Tab-separated line in the same shape as the pipeline `png_decode_limits` line.
    pub fn render(&self) -> String {
        format!(
            "png_decode_limits\tmax_input_bytes\t{}\tmax_pixels\t{}\tmax_working_bytes\t{}\torigin\t{}\tbudget_scope\tmajor_payload_only\tcrc\tnot_validated",
            self.limits.max_input_bytes, self.limits.max_pixels, self.limits.max_working_bytes, self.limits_origin.render()
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BoundedGray {
    pub width: usize,
    pub height: usize,
    pub gray: Vec<u8>,
    pub receipt: BoundedPngReceipt,
}

/// Decode `bytes` under the caller's explicit limits. Never substitutes limits.
pub fn decode_gray(
    route: Route,
    bytes: &[u8],
    limits: &DecodeLimits,
    origin: LimitsOrigin,
) -> Result<BoundedGray, PngDecodeError> {
    let (width, height, gray) = decode_png_gray_bounded(bytes, limits)?;
    Ok(BoundedGray {
        width,
        height,
        gray,
        receipt: BoundedPngReceipt { route, limits: *limits, limits_origin: origin, width, height },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::capture::decode_png_gray;

    fn chunk(typ: &[u8; 4], body: &[u8]) -> Vec<u8> {
        let mut v = (body.len() as u32).to_be_bytes().to_vec();
        v.extend_from_slice(typ);
        v.extend_from_slice(body);
        v.extend_from_slice(&0u32.to_be_bytes()); // CRC unused by the decoder
        v
    }
    fn adler(d: &[u8]) -> u32 {
        let (mut a, mut b) = (1u32, 0u32);
        for &x in d { a = (a + x as u32) % 65521; b = (b + a) % 65521; }
        (b << 16) | a
    }
    fn zlib_stored(raw: &[u8]) -> Vec<u8> {
        let mut v = vec![0x78, 0x01, 1];
        v.extend_from_slice(&(raw.len() as u16).to_le_bytes());
        v.extend_from_slice(&(!(raw.len() as u16)).to_le_bytes());
        v.extend_from_slice(raw);
        v.extend_from_slice(&adler(raw).to_be_bytes());
        v
    }
    fn png_raw(w: u32, h: u32, idat: &[u8], iend_body: &[u8]) -> Vec<u8> {
        let mut ihdr = w.to_be_bytes().to_vec();
        ihdr.extend_from_slice(&h.to_be_bytes());
        ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);
        let mut v = b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR", &ihdr));
        v.extend_from_slice(&chunk(b"IDAT", idat));
        v.extend_from_slice(&chunk(b"IEND", iend_body));
        v
    }
    fn gray_png(w: usize, h: usize, px: &[u8]) -> Vec<u8> {
        let mut raw = Vec::new();
        for y in 0..h { raw.push(0u8); raw.extend_from_slice(&px[y * w..(y + 1) * w]); }
        png_raw(w as u32, h as u32, &zlib_stored(&raw), &[])
    }
    fn lim(i: usize, p: usize, w: usize) -> DecodeLimits {
        DecodeLimits { max_input_bytes: i, max_pixels: p, max_working_bytes: w }
    }
    const BIG: usize = 1 << 26;

    #[test]
    fn within_limit_parity_with_existing_decode() {
        let px: Vec<u8> = (0..35u32).map(|i| (i * 7 % 256) as u8).collect();
        let p = gray_png(7, 5, &px);
        let l = DecodeLimits::default();
        let a = decode_gray(Route::Space, &p, &l, LimitsOrigin::hub_default_not_wired()).unwrap();
        let direct = decode_png_gray_bounded(&p, &l).unwrap();
        let compat = decode_png_gray(&p).unwrap();
        assert_eq!((a.width, a.height, a.gray.clone()), direct);
        assert_eq!((a.width, a.height, a.gray.clone()), compat);
        assert_eq!(a.gray, px);
    }

    #[test]
    fn receipt_records_exact_limits_and_origin_no_default_injection() {
        let p = gray_png(2, 2, &[1, 2, 3, 4]);
        let l = lim(1 << 20, 100, 1 << 20); // deliberately non-default
        let r = decode_gray(Route::Notdef, &p, &l, LimitsOrigin::Explicit("test-config".into())).unwrap().receipt;
        assert_eq!(r.limits, l);
        assert_ne!(r.limits, DecodeLimits::default());
        assert_eq!(r.limits_origin, LimitsOrigin::Explicit("test-config".into()));
        assert_eq!(r.route, Route::Notdef);
        let line = r.render();
        assert!(line.contains("max_pixels\t100"), "{line}");
        assert!(line.contains("origin\tExplicit(test-config)"), "{line}");
        let r2 = decode_gray(Route::Iou, &p, &DecodeLimits::default(), LimitsOrigin::hub_default_not_wired()).unwrap().receipt;
        assert!(r2.render().contains("origin\tConfigNotWired(hardcoded hub default; RunConfig wiring pending)"));
    }

    #[test]
    fn budget_exceeded_before_allocation() {
        // Header declares 60000x60000 gray (3.6e9 px) with a few real bytes. If any
        // buffer were allocated first this would abort/OOM; it must refuse typed.
        let p = png_raw(60000, 60000, &zlib_stored(&[0u8; 4]), &[]);
        let e = decode_gray(Route::Space, &p, &lim(1 << 20, 4_194_304, BIG), LimitsOrigin::hub_default_not_wired()).unwrap_err();
        assert!(matches!(e, PngDecodeError::TooManyPixels { .. }), "{e:?}");
        // pixels allowed, working budget too small: refused on the budget, not allocation
        let p2 = gray_png(8, 8, &[9u8; 64]);
        let e2 = decode_gray(Route::Space, &p2, &lim(1 << 20, 1 << 20, 16), LimitsOrigin::hub_default_not_wired()).unwrap_err();
        assert!(matches!(e2, PngDecodeError::WorkingBudgetExceeded { .. }), "{e2:?}");
        // input byte cap
        let e3 = decode_gray(Route::Iou, &p2, &lim(8, 1 << 20, BIG), LimitsOrigin::hub_default_not_wired()).unwrap_err();
        assert!(matches!(e3, PngDecodeError::InputTooLarge { .. }), "{e3:?}");
    }

    #[test]
    fn checked_arithmetic_extreme_dims_no_panic() {
        // u32::MAX x u32::MAX with permissive-looking limits: products overflow
        // usize once multiplied by channels/stride; must be typed refusal.
        let p = png_raw(u32::MAX, u32::MAX, &zlib_stored(&[0u8; 4]), &[]);
        for l in [lim(1 << 20, usize::MAX, usize::MAX), DecodeLimits::default()] {
            let e = decode_gray(Route::Space, &p, &l, LimitsOrigin::hub_default_not_wired()).unwrap_err();
            assert!(
                matches!(e, PngDecodeError::TooManyPixels { .. } | PngDecodeError::WorkingBudgetExceeded { .. } | PngDecodeError::AllocationRefused { .. }),
                "{e:?}"
            );
        }
        let q = png_raw(u32::MAX, 1, &zlib_stored(&[0u8; 4]), &[]);
        let e = decode_gray(Route::Space, &q, &lim(1 << 20, usize::MAX, 1 << 20), LimitsOrigin::hub_default_not_wired()).unwrap_err();
        assert!(matches!(e, PngDecodeError::WorkingBudgetExceeded { .. } | PngDecodeError::TooManyPixels { .. }), "{e:?}");
    }

    #[test]
    fn malformed_iend_typed() {
        let mut raw = vec![0u8, 5, 6, 7, 8];
        raw.splice(3..3, [0u8]); // 2 rows of width 2: [0,5,6][0,7,8]
        let idat = zlib_stored(&raw);
        let p = png_raw(2, 2, &idat, &[0, 0]);
        let e = decode_gray(Route::Notdef, &p, &DecodeLimits::default(), LimitsOrigin::hub_default_not_wired()).unwrap_err();
        assert_eq!(e, PngDecodeError::IendLength { len: 2 });
        // missing IEND entirely
        let mut q = gray_png(2, 2, &[1, 2, 3, 4]);
        q.truncate(q.len() - 12);
        let e = decode_gray(Route::Notdef, &q, &DecodeLimits::default(), LimitsOrigin::hub_default_not_wired()).unwrap_err();
        assert_eq!(e, PngDecodeError::MissingIend);
    }

    #[test]
    fn typed_error_not_stringified_and_not_png() {
        let e = decode_gray(Route::Iou, b"not a png at all", &DecodeLimits::default(), LimitsOrigin::hub_default_not_wired()).unwrap_err();
        assert_eq!(e, PngDecodeError::NotPng);
    }
}

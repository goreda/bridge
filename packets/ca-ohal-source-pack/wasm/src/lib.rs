mod sep;
mod fd1;
mod fd2;
mod bs;
mod fd3;
mod parasites;
mod sim;
mod tr;
mod spores;
mod swarm;
mod worms;
// ca2core: metaball field + pixel pass (port of drawMetaballsCPU). No DOM, no deps.
static mut CELLS: Vec<f64> = Vec::new(); // per cell: cx, cy, radius, wr, wg, wb
static mut F_SUM: Vec<f32> = Vec::new();
static mut F_R: Vec<f32> = Vec::new();
static mut F_G: Vec<f32> = Vec::new();
static mut F_B: Vec<f32> = Vec::new();
static mut OUT: Vec<u8> = Vec::new();

#[no_mangle]
pub extern "C" fn cells_ptr(n: usize) -> *mut f64 {
    unsafe {
        let c = &mut *std::ptr::addr_of_mut!(CELLS);
        c.resize(n * 6, 0.0);
        c.as_mut_ptr()
    }
}
#[no_mangle]
pub extern "C" fn out_ptr() -> *const u8 {
    unsafe { (*std::ptr::addr_of!(OUT)).as_ptr() }
}
fn rnd_u8(v: f64) -> u8 {
    // Uint8ClampedArray store: clamp, round half to even
    if !(v > 0.0) { return 0; }
    if v >= 255.0 { return 255; }
    let f = v.floor();
    let d = v - f;
    let r = if d < 0.5 { f } else if d > 0.5 { f + 1.0 } else if (f as i64) % 2 == 0 { f } else { f + 1.0 };
    r as u8
}
/// n cells already written via cells_ptr. Returns 0 on success.
#[no_mangle]
pub extern "C" fn mb_field(n: usize, bw: usize, bh: usize, s: f64, ms: f64, th: f64, br: f64, bgc: f64, bb: f64) -> i32 {
    unsafe {
        let np = bw * bh;
        let (fs, fr, fg, fb, out) = (
            &mut *std::ptr::addr_of_mut!(F_SUM), &mut *std::ptr::addr_of_mut!(F_R),
            &mut *std::ptr::addr_of_mut!(F_G), &mut *std::ptr::addr_of_mut!(F_B), &mut *std::ptr::addr_of_mut!(OUT));
        if fs.len() != np { fs.clear(); fs.resize(np, 0.0); fr.clear(); fr.resize(np, 0.0); fg.clear(); fg.resize(np, 0.0); fb.clear(); fb.resize(np, 0.0); out.clear(); out.resize(np * 4, 0); }
        else { fs.fill(0.0); fr.fill(0.0); fg.fill(0.0); fb.fill(0.0); }
        let cells = &*std::ptr::addr_of!(CELLS);
        let inv = 1.0 / s;
        let k = (ms / (th * 0.03)).sqrt().max(3.0);
        for i in 0..n {
            let c = &cells[i * 6..i * 6 + 6];
            let (cx, cy, rad) = (c[0], c[1], c[2]);
            let r2 = ms * rad * rad;
            let rc = rad * k;
            let x0 = (((cx - rc) * s).floor()).max(0.0) as usize;
            let x1 = (((cx + rc) * s).ceil()).min(bw as f64 - 1.0);
            let y0 = (((cy - rc) * s).floor()).max(0.0) as usize;
            let y1 = (((cy + rc) * s).ceil()).min(bh as f64 - 1.0);
            if x1 < 0.0 || y1 < 0.0 { continue; }
            let (x1, y1) = (x1 as usize, y1 as usize);
            let (wr, wg, wb) = (c[3], c[4], c[5]);
            for y in y0..=y1 {
                let dy = (y as f64 + 0.5) * inv - cy;
                let row = y * bw;
                let mut x = x0;
                #[cfg(target_feature = "simd128")]
                {
                    use std::arch::wasm32::*;
                    let vdy2 = f64x2_splat(dy * dy);
                    let vr2 = f64x2_splat(r2);
                    let veps = f64x2_splat(0.0001);
                    let vinv = f64x2_splat(inv);
                    let vcx = f64x2_splat(cx);
                    let vh = f64x2_splat(0.5);
                    while x + 1 <= x1 {
                        let vx = f64x2((x as f64) + 0.0, (x as f64) + 1.0);
                        let dx = f64x2_sub(f64x2_mul(f64x2_add(vx, vh), vinv), vcx);
                        let inf = f64x2_div(vr2, f64x2_add(f64x2_add(f64x2_mul(dx, dx), vdy2), veps));
                        let i2 = f64x2_mul(inf, inf);
                        let p = row + x;
                        let (a0, a1) = (f64x2_extract_lane::<0>(inf), f64x2_extract_lane::<1>(inf));
                        let (b0, b1) = (f64x2_extract_lane::<0>(i2), f64x2_extract_lane::<1>(i2));
                        fs[p] = (fs[p] as f64 + a0) as f32; fs[p + 1] = (fs[p + 1] as f64 + a1) as f32;
                        if wr != 0.0 { fr[p] = (fr[p] as f64 + b0 * wr) as f32; fr[p + 1] = (fr[p + 1] as f64 + b1 * wr) as f32; }
                        if wg != 0.0 { fg[p] = (fg[p] as f64 + b0 * wg) as f32; fg[p + 1] = (fg[p + 1] as f64 + b1 * wg) as f32; }
                        if wb != 0.0 { fb[p] = (fb[p] as f64 + b0 * wb) as f32; fb[p + 1] = (fb[p + 1] as f64 + b1 * wb) as f32; }
                        x += 2;
                    }
                }
                while x <= x1 {
                    let dx = (x as f64 + 0.5) * inv - cx;
                    let inf = r2 / (dx * dx + dy * dy + 0.0001);
                    let i2 = inf * inf;
                    let p = row + x;
                    fs[p] = (fs[p] as f64 + inf) as f32;
                    if wr != 0.0 { fr[p] = (fr[p] as f64 + i2 * wr) as f32; }
                    if wg != 0.0 { fg[p] = (fg[p] as f64 + i2 * wg) as f32; }
                    if wb != 0.0 { fb[p] = (fb[p] as f64 + i2 * wb) as f32; }
                    x += 1;
                }
            }
        }
        let band = th * 0.08;
        let lim = th * 0.96;
        let (br8, bg8, bb8) = (br as i64 as u8, bgc as i64 as u8, bb as i64 as u8);
        for p in 0..np {
            let s = fs[p] as f64;
            let q = p << 2;
            if s > lim {
                let (mut r, mut g, mut b) = (fr[p] as f64, fg[p] as f64, fb[p] as f64);
                let t = r + g + b;
                if t > 0.0 { r /= t; g /= t; b /= t; }
                let a = ((s - lim) / band).min(1.0);
                out[q] = rnd_u8(r * 255.0); out[q + 1] = rnd_u8(g * 255.0); out[q + 2] = rnd_u8(b * 255.0); out[q + 3] = rnd_u8(a * 255.0);
            } else { out[q] = br8; out[q + 1] = bg8; out[q + 2] = bb8; out[q + 3] = 0; }
        }
    }
    0
}

// ---- fast f32 variant: interleaved accumulator [sum,r,g,b] per pixel, f32 math. Not bit-equal to the JS path (differences of at most a few 8-bit levels on edge pixels).
static mut ACC: Vec<f32> = Vec::new();
#[no_mangle]
pub extern "C" fn mb_field_f32(n: usize, bw: usize, bh: usize, s: f64, ms: f64, th: f64, br: f64, bgc: f64, bb: f64) -> i32 {
    unsafe {
        let np = bw * bh;
        let (acc, out) = (&mut *std::ptr::addr_of_mut!(ACC), &mut *std::ptr::addr_of_mut!(OUT));
        if acc.len() != np * 4 { acc.clear(); acc.resize(np * 4, 0.0); out.clear(); out.resize(np * 4, 0); } else { acc.fill(0.0); }
        let cells = &*std::ptr::addr_of!(CELLS);
        let sf = s as f32;
        let invf = (1.0 / s) as f32;
        let k = (ms / (th * 0.03)).sqrt().max(3.0);
        for i in 0..n {
            let c = &cells[i * 6..i * 6 + 6];
            let (cx, cy, rad) = (c[0], c[1], c[2]);
            let rc = rad * k;
            let x0 = (((cx - rc) * s).floor()).max(0.0) as usize;
            let x1 = (((cx + rc) * s).ceil()).min(bw as f64 - 1.0);
            let y0 = (((cy - rc) * s).floor()).max(0.0) as usize;
            let y1 = (((cy + rc) * s).ceil()).min(bh as f64 - 1.0);
            if x1 < 0.0 || y1 < 0.0 { continue; }
            let (x1, y1) = (x1 as usize, y1 as usize);
            let r2 = (ms * rad * rad) as f32;
            let (cxf, cyf) = (cx as f32, cy as f32);
            let w = [1.0f32, c[3] as f32, c[4] as f32, c[5] as f32];
            let _ = sf;
            for y in y0..=y1 {
                let dy = (y as f32 + 0.5) * invf - cyf;
                let dy2 = dy * dy + 0.0001;
                let row = y * bw;
                let mut dx = (x0 as f32 + 0.5) * invf - cxf;
                for x in x0..=x1 {
                    let inf = r2 / (dx * dx + dy2);
                    let i2 = inf * inf;
                    let a = &mut acc[(row + x) * 4..(row + x) * 4 + 4];
                    a[0] += inf; a[1] += i2 * w[1]; a[2] += i2 * w[2]; a[3] += i2 * w[3];
                    dx += invf;
                }
            }
        }
        let band = th * 0.08;
        let lim = th * 0.96;
        let (br8, bg8, bb8) = (br as i64 as u8, bgc as i64 as u8, bb as i64 as u8);
        for p in 0..np {
            let a = &acc[p * 4..p * 4 + 4];
            let s = a[0] as f64;
            let q = p << 2;
            if s > lim {
                let (mut r, mut g, mut b) = (a[1] as f64, a[2] as f64, a[3] as f64);
                let t = r + g + b;
                if t > 0.0 { r /= t; g /= t; b /= t; }
                let al = ((s - lim) / band).min(1.0);
                out[q] = rnd_u8(r * 255.0); out[q + 1] = rnd_u8(g * 255.0); out[q + 2] = rnd_u8(b * 255.0); out[q + 3] = rnd_u8(al * 255.0);
            } else { out[q] = br8; out[q + 1] = bg8; out[q + 2] = bb8; out[q + 3] = 0; }
        }
    }
    0
}

// ---- sim exports ----
#[no_mangle] pub extern "C" fn sim_cells(cap: usize) -> *mut f64 { let s = sim::sim(); s.cap = cap; s.cells.resize(cap * sim::ST, 0.0); s.cells.as_mut_ptr() }
#[no_mangle] pub extern "C" fn sim_set_n(n: usize) { sim::sim().n = n; }
#[no_mangle] pub extern "C" fn sim_food(cap: usize) -> *mut f64 { let s = sim::sim(); s.fx.resize(cap, 0.0); s.fy.resize(cap, 0.0); s.fgone.resize(cap, 0.0); s.fx.as_mut_ptr() }
#[no_mangle] pub extern "C" fn sim_food_y() -> *mut f64 { sim::sim().fy.as_mut_ptr() }
#[no_mangle] pub extern "C" fn sim_food_gone() -> *mut f64 { sim::sim().fgone.as_mut_ptr() }
#[no_mangle] pub extern "C" fn sim_set_nf(n: usize) { let s = sim::sim(); s.nf = n; for i in 0..n { s.fgone[i] = 0.0; } }
#[no_mangle] pub extern "C" fn sim_cm(cap: usize) -> *mut f64 { let s = sim::sim(); s.cm.resize(cap * 5, 0.0); s.cm_id.resize(cap, 0.0); s.cm.as_mut_ptr() }
#[no_mangle] pub extern "C" fn sim_cm_ids() -> *mut f64 { sim::sim().cm_id.as_mut_ptr() }
#[no_mangle] pub extern "C" fn sim_cm_count(n: usize) { let s = sim::sim(); s.cm_id.truncate(n); }
#[no_mangle] pub extern "C" fn sim_params() -> *mut f64 { sim::sim().p.as_mut_ptr() }
#[no_mangle] pub extern "C" fn sim_out() -> *const f64 { sim::sim().out.as_ptr() }
#[no_mangle] pub extern "C" fn sim_step(s0: f64, s1: f64) { sim::sim().step(s0, s1); }
#[no_mangle] pub extern "C" fn sim_log() -> *const f64 { sim::sim().log.as_ptr() }
#[no_mangle] pub extern "C" fn sim_cap() -> usize { sim::sim().cap }
#[no_mangle] pub extern "C" fn sim_cells_ptr() -> *mut f64 { sim::sim().cells.as_mut_ptr() }

#[no_mangle] pub extern "C" fn sp_in(n: usize) -> *mut f64 { let s = spores::sp(); s.inb.resize(n * 9 + 9, 0.0); s.inb.as_mut_ptr() }
#[no_mangle] pub extern "C" fn sp_run(n: usize, x0: f64, x1: f64, y0: f64, y1: f64, dtms: f64, cap: f64, s0: f64, s1: f64) -> f64 { spores::sp().step(n, x0, x1, y0, y1, dtms, cap, s0, s1) as f64 }
#[no_mangle] pub extern "C" fn sp_out() -> *const f64 { spores::sp().out.as_ptr() }
#[no_mangle] pub extern "C" fn sp_stat() -> *const f64 { spores::sp().stat.as_ptr() }

#[no_mangle] pub extern "C" fn fd1_in(cap: usize) -> *mut f64 { let s = fd1::fd1(); s.rows.resize(cap * 3 + 3, 0.0); s.rows.as_mut_ptr() }
#[no_mangle] pub extern "C" fn fd1_flow(n: usize, x0: f64, y0: f64, x1: f64, y1: f64) -> f64 { fd1::fd1().flow(n, x0, y0, x1, y1) as f64 }
#[no_mangle] pub extern "C" fn fd1_tick(n: usize, gs: f64, x0: f64, y0: f64, x1: f64, y1: f64, cw: f64, ch: f64, density: f64, s0: f64, s1: f64) -> f64 { fd1::fd1().tick(n, gs, x0, y0, x1, y1, cw, ch, density, s0, s1) as f64 }
#[no_mangle] pub extern "C" fn fd1_out() -> *const f64 { fd1::fd1().out.as_ptr() }
#[no_mangle] pub extern "C" fn fd1_stat() -> *const f64 { fd1::fd1().stat.as_ptr() }

#[no_mangle] pub extern "C" fn fb_blobs(cap: usize) -> *mut f64 { let s = fd2::fd2(); s.blobs.resize(cap * 7 + 7, 0.0); s.blobs.as_mut_ptr() }
#[no_mangle] pub extern "C" fn fb_dots(cap: usize) -> *mut f64 { let s = fd2::fd2(); s.dots.resize(cap * 6 + 6, 0.0); s.dots.as_mut_ptr() }
#[no_mangle] pub extern "C" fn fb_run(nb: usize, nd: usize, tt: f64, x0: f64, y0: f64, x1: f64, y1: f64, s0: f64, s1: f64) -> f64 { fd2::fd2().step(nb, nd, tt, x0, y0, x1, y1, s0, s1) as f64 }

#[no_mangle] pub extern "C" fn fk_in(cap: usize) -> *mut f64 { let s = fd3::fd3(); s.rows.resize(cap * 5 + 5, 0.0); s.rows.as_mut_ptr() }
#[no_mangle] pub extern "C" fn fk_run(n: usize, x0: f64, y0: f64, x1: f64, y1: f64) -> f64 { fd3::fd3().run(n, x0, y0, x1, y1) as f64 }

#[no_mangle] pub extern "C" fn bs_alloc(cap: usize) -> *mut f64 { bs::bs().cap(cap).0 }
#[no_mangle] pub extern "C" fn bs_out() -> *const f32 { bs::bs().out.as_ptr() }
#[no_mangle] pub extern "C" fn bs_run(n: usize, elapsed: f64, t0: f64, cx: f64, cy: f64, cw: f64, ch: f64, cell_shapes: f64, src_max: f64, bgap: f64) -> f64 { bs::bs().run(n, elapsed, t0, cx, cy, cw, ch, cell_shapes != 0.0, src_max, bgap) as f64 }
#[no_mangle] pub extern "C" fn bs_stat() -> *const f64 { bs::bs().stat.as_ptr() }

#[no_mangle] pub extern "C" fn tr_cells(cap: usize) -> *mut f64 { let s = tr::tr(); s.cells.resize(cap * 13 + 13, 0.0); s.cells.as_mut_ptr() }
#[no_mangle] pub extern "C" fn tr_run(n: usize, now: f64, dt: f64, t0: f64, dur: f64, cr: f64, plan: f64, s0: f64, s1: f64) -> f64 { tr::tr().step(n, now, dt, t0, dur, cr, plan != 0.0, s0, s1) as f64 }
#[no_mangle] pub extern "C" fn tr_stat() -> *const f64 { tr::tr().stat.as_ptr() }

#[no_mangle] pub extern "C" fn pa_cells(cap: usize) -> *mut f64 { let s = parasites::pa(); s.ci.resize(cap * 5 + 5, 0.0); s.ci.as_mut_ptr() }
#[no_mangle] pub extern "C" fn pa_energy(cap: usize) -> *mut f64 { let s = parasites::pa(); s.en.resize(cap + 1, 0.0); s.en.as_mut_ptr() }
#[no_mangle] pub extern "C" fn pa_in(cap: usize) -> *mut f64 { let s = parasites::pa(); s.pi.resize(cap * 7 + 7, 0.0); s.pi.as_mut_ptr() }
#[no_mangle] pub extern "C" fn pa_run(n: usize, m: usize, now: f64, on: f64, frac: f64, sight: f64, nerv: f64, drain: f64, eff: f64, hard: f64, hard_ms: f64, s0: f64, s1: f64) -> f64 { parasites::pa().step(n, m, now, on != 0.0, frac, sight, nerv, drain, eff, hard, hard_ms, s0, s1) as f64 }
#[no_mangle] pub extern "C" fn pa_out() -> *const f64 { parasites::pa().po.as_ptr() }
#[no_mangle] pub extern "C" fn pa_stat() -> *const f64 { parasites::pa().stat.as_ptr() }

#[no_mangle] pub extern "C" fn wm_hdr(cap: usize) -> *mut f64 { let s = worms::wm(); s.hdr.resize(cap * 6 + 6, 0.0); s.hdr.as_mut_ptr() }
#[no_mangle] pub extern "C" fn wm_lnk(cap: usize) -> *mut f64 { let s = worms::wm(); s.lnk.resize(cap * 4 + 4, 0.0); s.lnk.as_mut_ptr() }
#[no_mangle] pub extern "C" fn wm_run(nw: usize, nl: usize, x0: f64, x1: f64, y0: f64, y1: f64, tt: f64, sp_gap: f64, life: f64, want: f64, s0: f64, s1: f64) -> f64 { worms::wm().step(nw, nl, x0, x1, y0, y1, tt, sp_gap, life != 0.0, want, s0, s1) as f64 }
#[no_mangle] pub extern "C" fn wm_ohdr() -> *const f64 { worms::wm().oh.as_ptr() }
#[no_mangle] pub extern "C" fn wm_olnk() -> *const f64 { worms::wm().ol.as_ptr() }
#[no_mangle] pub extern "C" fn wm_stat() -> *const f64 { worms::wm().stat.as_ptr() }

#[no_mangle] pub extern "C" fn sw_in(n: usize) -> *mut f64 { let s = swarm::sw(); s.inb.resize(n * 6 + 6, 0.0); s.inb.as_mut_ptr() }
#[no_mangle] pub extern "C" fn sw_run(n: usize, x0: f64, x1: f64, y0: f64, y1: f64, life: f64, can_birth: f64, low_cap: f64, s0: f64, s1: f64) -> f64 { swarm::sw().step(n, x0, x1, y0, y1, life != 0.0, can_birth != 0.0, low_cap, s0, s1) as f64 }
#[no_mangle] pub extern "C" fn sw_out() -> *const f64 { swarm::sw().out.as_ptr() }
#[no_mangle] pub extern "C" fn sw_stat() -> *const f64 { swarm::sw().stat.as_ptr() }

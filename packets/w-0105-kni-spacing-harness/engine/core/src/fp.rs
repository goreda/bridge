const P1: u64 = 0x9E3779B185EBCA87;
const P2: u64 = 0xC2B2AE3D27D4EB4F;
const P3: u64 = 0x165667B19E3779F9;
const P4: u64 = 0x85EBCA77C2B2AE63;
const P5: u64 = 0x27D4EB2F165667C5;

#[inline]
fn round(acc: u64, input: u64) -> u64 {
    acc.wrapping_add(input.wrapping_mul(P2)).rotate_left(31).wrapping_mul(P1)
}
#[inline]
fn merge_round(mut h: u64, v: u64) -> u64 {
    h ^= round(0, v);
    h = h.wrapping_mul(P1).wrapping_add(P4);
    h
}
#[inline]
fn u64le(b: &[u8], i: usize) -> u64 {
    u64::from_le_bytes(b[i..i + 8].try_into().unwrap())
}
#[inline]
fn u32le(b: &[u8], i: usize) -> u32 {
    u32::from_le_bytes(b[i..i + 4].try_into().unwrap())
}

pub fn xxh64(data: &[u8], seed: u64) -> u64 {
    let len = data.len();
    let mut i = 0usize;
    let mut h: u64;
    if len >= 32 {
        let mut v1 = seed.wrapping_add(P1).wrapping_add(P2);
        let mut v2 = seed.wrapping_add(P2);
        let mut v3 = seed;
        let mut v4 = seed.wrapping_sub(P1);
        while i + 32 <= len {
            v1 = round(v1, u64le(data, i));
            v2 = round(v2, u64le(data, i + 8));
            v3 = round(v3, u64le(data, i + 16));
            v4 = round(v4, u64le(data, i + 24));
            i += 32;
        }
        h = v1.rotate_left(1).wrapping_add(v2.rotate_left(7))
            .wrapping_add(v3.rotate_left(12)).wrapping_add(v4.rotate_left(18));
        h = merge_round(h, v1);
        h = merge_round(h, v2);
        h = merge_round(h, v3);
        h = merge_round(h, v4);
    } else {
        h = seed.wrapping_add(P5);
    }
    h = h.wrapping_add(len as u64);
    while i + 8 <= len {
        h ^= round(0, u64le(data, i));
        h = h.rotate_left(27).wrapping_mul(P1).wrapping_add(P4);
        i += 8;
    }
    if i + 4 <= len {
        h ^= (u32le(data, i) as u64).wrapping_mul(P1);
        h = h.rotate_left(23).wrapping_mul(P2).wrapping_add(P3);
        i += 4;
    }
    while i < len {
        h ^= (data[i] as u64).wrapping_mul(P5);
        h = h.rotate_left(11).wrapping_mul(P1);
        i += 1;
    }
    h ^= h >> 33;
    h = h.wrapping_mul(P2);
    h ^= h >> 29;
    h = h.wrapping_mul(P3);
    h ^= h >> 32;
    h
}


#[cfg(test)]
mod xxh64_tests {
    use super::xxh64;
    #[test]
    fn known_vectors() {
        // Reference: python-xxhash 4.0.1 (independent implementation), verified 2026-10-17
        assert_eq!(xxh64(b"", 0), 0xef46db3751d8e999);
        assert_eq!(xxh64(b"", 1), 0xd5afba1336a3be4b);
        assert_eq!(xxh64(b"abc", 0), 0x44bc2cf5ad770999);
        assert_eq!(xxh64(b"ring:0/span:0", 0), 0x95f1d8363f6247e7);
    }
}

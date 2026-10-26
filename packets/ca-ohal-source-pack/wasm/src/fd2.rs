// ca2core food mode 2 (amorphous blobs, port of the stepBlobs per-frame pass): blob drift +
// soft neighbor push + inflow pull + dot wobble placement. The blob life tick (grow/split/
// shrink/die/seed, object churn on food[]) and gone-dot cleanup stay in JS. Blob row: 7 f64
// (x, y, vx, vy, r, ph, w). Dot row: 6 f64 (a, f, q, blobIdx, x out, y out).
pub struct Fd2 { pub blobs: Vec<f64>, pub dots: Vec<f64>, s0: u64, s1: u64 }
pub static mut FD2: Option<Fd2> = None;
pub fn fd2() -> &'static mut Fd2 {
    unsafe {
        let s = &mut *std::ptr::addr_of_mut!(FD2);
        if s.is_none() { *s = Some(Fd2 { blobs: vec![], dots: vec![], s0: 1, s1: 2 }); }
        s.as_mut().unwrap()
    }
}
impl Fd2 {
    fn r01(&mut self) -> f64 {
        let (mut x, y) = (self.s0, self.s1);
        self.s0 = y; x ^= x << 23; self.s1 = x ^ y ^ (x >> 17) ^ (y >> 26);
        ((self.s1.wrapping_add(y)) >> 11) as f64 * (1.0 / 9007199254740992.0)
    }
    #[allow(clippy::too_many_arguments)]
    pub fn step(&mut self, nb: usize, nd: usize, tt: f64, x0: f64, y0: f64, x1: f64, y1: f64, s0: f64, s1: f64) -> i64 {
        self.s0 = ((s0 as u64) << 32) | 0x9E3779B9; self.s1 = ((s1 as u64) << 32) | 0x85EBCA6B;
        for _ in 0..8 { self.r01(); }
        if self.blobs.len() < nb * 7 || self.dots.len() < nd * 6 { return -1; }
        for i in 0..nb {
            let (x, y) = (self.blobs[i * 7], self.blobs[i * 7 + 1]);
            if !(x.is_finite() && y.is_finite()) { return -1; }
        }
        for i in 0..nb {
            let b = i * 7;
            let (mut bx, mut by, mut vx, mut vy) = (self.blobs[b], self.blobs[b + 1], self.blobs[b + 2], self.blobs[b + 3]);
            vx = vx * 0.95 + (self.r01() - 0.5) * 0.12; vy = vy * 0.95 + (self.r01() - 0.5) * 0.12;
            for k in 0..nb { if k == i { continue; }
                let dx = bx - self.blobs[k * 7]; let dy = by - self.blobs[k * 7 + 1];
                let d2 = dx * dx + dy * dy;
                if d2 < 900.0 && d2 > 1.0 { let dd = d2.sqrt(); vx += dx / dd * 0.02; vy += dy / dd * 0.02; }
            }
            bx += vx; by += vy;
            if bx < x0 || bx > x1 || by < y0 || by > y1 {
                bx += (bx.max(x0 + 4.0).min(x1 - 4.0) - bx) * 0.25;
                by += (by.max(y0 + 4.0).min(y1 - 4.0) - by) * 0.25;
            }
            self.blobs[b] = bx; self.blobs[b + 1] = by; self.blobs[b + 2] = vx; self.blobs[b + 3] = vy;
        }
        // dot wobble placement (needs the dot count per blob for rr)
        let mut ndots = vec![0f64; nb.max(1)];
        for j in 0..nd { let bi = self.dots[j * 6 + 3] as usize; if bi < nb { ndots[bi] += 1.0; } }
        for j in 0..nd {
            let d = j * 6; let bi = self.dots[d + 3] as usize; if bi >= nb { return -1; }
            let b = bi * 7;
            let rr = self.blobs[b + 4] * (1.0 + 0.25 * (tt * self.blobs[b + 6] + self.blobs[b + 5]).sin()) * (0.6 + 0.08 * ndots[bi]);
            let ang = self.dots[d] + tt * 0.25 * self.blobs[b + 6];
            let rad = rr * (0.45 + 0.55 * (tt * self.dots[d + 1] + self.dots[d + 2]).sin().abs());
            self.dots[d + 4] = self.blobs[b] + ang.cos() * rad;
            self.dots[d + 5] = self.blobs[b + 1] + ang.sin() * rad;
        }
        0
    }
}

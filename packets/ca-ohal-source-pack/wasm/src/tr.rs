// ca2core transition pass (port of the stepTrans per-cell loops): the radius drift toward the new
// CELL_RADIUS trait (both paths) fused with the stepComposition morph chase (plan path). Spawn/kill
// decisions, P lerps, completion checks and newShape body plans stay in JS. One shared buffer,
// mutated in place. Row: 13 f64 (x, y, radius, mutRate, alive, dstx, dsty, dl, durK, pace, bend,
// dying, hasDst). stat: deaths, (open is the return value).
pub struct Tr { pub cells: Vec<f64>, pub stat: [f64; 4], s0: u64, s1: u64 }
pub static mut TR: Option<Tr> = None;
pub fn tr() -> &'static mut Tr {
    unsafe {
        let s = &mut *std::ptr::addr_of_mut!(TR);
        if s.is_none() { *s = Some(Tr { cells: vec![], stat: [0.0; 4], s0: 1, s1: 2 }); }
        s.as_mut().unwrap()
    }
}
fn clamp(v: f64, a: f64, b: f64) -> f64 { v.max(a).min(b) }
fn hyp(x: f64, y: f64) -> f64 { (x * x + y * y).sqrt() }
impl Tr {
    fn r01(&mut self) -> f64 {
        let (mut x, y) = (self.s0, self.s1);
        self.s0 = y; x ^= x << 23; self.s1 = x ^ y ^ (x >> 17) ^ (y >> 26);
        ((self.s1.wrapping_add(y)) >> 11) as f64 * (1.0 / 9007199254740992.0)
    }
    #[allow(clippy::too_many_arguments)]
    pub fn step(&mut self, n: usize, now: f64, dt: f64, t0: f64, dur: f64, cr: f64, plan: bool, s0: f64, s1: f64) -> i64 {
        self.s0 = ((s0 as u64) << 32) | 0x9E3779B9; self.s1 = ((s1 as u64) << 32) | 0x85EBCA6B;
        for _ in 0..8 { self.r01(); }
        self.stat = [0.0; 4];
        if self.cells.len() < n * 13 { return -1; }
        let late = now - t0 > dur * 1.5;
        let mut open = 0i64;
        for i in 0..n {
            let b = i * 13;
            let (mut x, mut y, mut rad, mr, mut alive) = (self.cells[b], self.cells[b + 1], self.cells[b + 2], self.cells[b + 3], self.cells[b + 4]);
            if !(x.is_finite() && y.is_finite()) { return -1; }
            rad += (cr - rad) * (1f64).min(0.004 * mr); // radius drift, all cells, both paths
            self.cells[b + 2] = rad;
            if plan && self.cells[b + 12] != 0.0 && alive != 0.0 {
                let (dx, dy) = (self.cells[b + 5] - x, self.cells[b + 6] - y);
                let d = hyp(dx, dy);
                let el = now - t0 - self.cells[b + 7];
                if el <= 0.0 { open += 1; } else {
                    let win = (80f64).max(dur * self.cells[b + 8]);
                    let pr = clamp(el / win, 0.0, 1.0);
                    let kc = 1.0 - (-dt * 3.0 / win).exp();
                    let ease = 0.35 + 0.65 * (pr * std::f64::consts::PI).sin();
                    let k = (1f64).min(kc * self.cells[b + 9] * ease * 1.31);
                    x += dx * k + (self.r01() - 0.5) * 0.6; y += dy * k + (self.r01() - 0.5) * 0.6;
                    let bend = self.cells[b + 10];
                    if bend != 0.0 { let lat = k * d.min(200.0) * bend * 0.35 * (pr * std::f64::consts::PI).sin(); let il = 1.0 / if d == 0.0 { 1.0 } else { d }; x += -dy * il * lat; y += dx * il * lat; }
                    if self.cells[b + 11] != 0.0 && (d < 14.0 || (late && self.r01() < 0.08)) { alive = 0.0; self.stat[0] += 1.0; }
                    else if d > 14.0 { open += 1; }
                }
            }
            self.cells[b] = x; self.cells[b + 1] = y; self.cells[b + 4] = alive;
        }
        open
    }
}

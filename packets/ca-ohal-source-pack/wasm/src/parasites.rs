// ca2core parasites step (port of stepParasites): free parasites seek the nearest cell (clustered
// cells preferred), attach as a host, orbit it and drain its energy; starve off past parasiteHard,
// split when fed. JS keeps object identity: hosts come back as cell indices, energy drains write
// back to the packed cell rows. in cells: n x 5 (x, y, radius, cl, alive); energy in/out: n x 1.
// in parasites: m x 7 (x, y, e, host index or -1, a, ph, lost ms). out parasites: q x 8 (x, y, e, host idx, a, ph, lost, src or -1).
// out cell energy: n x 1 (full write-back). stat: pdeath, pbirth, rehost, spawned.
pub struct Pa { pub ci: Vec<f64>, pub en: Vec<f64>, pub pi: Vec<f64>, pub po: Vec<f64>, pub stat: [f64; 4], s0: u64, s1: u64 }
pub static mut PA: Option<Pa> = None;
pub fn pa() -> &'static mut Pa {
    unsafe {
        let s = &mut *std::ptr::addr_of_mut!(PA);
        if s.is_none() { *s = Some(Pa { ci: vec![], en: vec![], pi: vec![], po: vec![], stat: [0.0; 4], s0: 1, s1: 2 }); }
        s.as_mut().unwrap()
    }
}
fn hyp(x: f64, y: f64) -> f64 { (x * x + y * y).sqrt() }
fn lerp(a: f64, b: f64, t: f64) -> f64 { a + (b - a) * t }
impl Pa {
    fn r01(&mut self) -> f64 {
        let (mut x, y) = (self.s0, self.s1);
        self.s0 = y; x ^= x << 23; self.s1 = x ^ y ^ (x >> 17) ^ (y >> 26);
        ((self.s1.wrapping_add(y)) >> 11) as f64 * (1.0 / 9007199254740992.0)
    }
    #[allow(clippy::too_many_arguments)]
    pub fn step(&mut self, n: usize, m: usize, now: f64, on: bool, frac: f64, sight: f64, nerv: f64, drain: f64, eff: f64, hard: f64, hard_ms: f64, s0: f64, s1: f64) -> i64 {
        self.s0 = ((s0 as u64) << 32) | 0x9E3779B9; self.s1 = ((s1 as u64) << 32) | 0x85EBCA6B;
        for _ in 0..8 { self.r01(); }
        self.stat = [0.0; 4]; self.po.clear();
        if self.ci.len() < n * 5 || self.en.len() < n || self.pi.len() < m * 7 { return -1; }
        if !on || n == 0 { return 0; } // JS: parasites.length = 0
        for i in 0..n { if !(self.ci[i * 5].is_finite() && self.ci[i * 5 + 1].is_finite()) { return -1; } }
        let target = (n as f64 * frac).round() as i64;
        // host parasite counts (pc)
        let mut pc = vec![0f64; n];
        for i in 0..m { let h = self.pi[i * 7 + 3]; if h >= 0.0 && (h as usize) < n { pc[h as usize] += 1.0; } }
        let mut ps: Vec<[f64; 8]> = (0..m).map(|i| { let b = i * 7; [self.pi[b], self.pi[b + 1], self.pi[b + 2], self.pi[b + 3], self.pi[b + 4], self.pi[b + 5], self.pi[b + 6], i as f64] }).collect();
        // JS spawns before its backward loop, so the newborn is not processed this frame: emit it unprocessed
        let mut newborn: Vec<[f64; 8]> = vec![];
        if (ps.len() as i64) < target && self.r01() < 0.08 {
            let c = (self.r01() * n as f64).floor() as usize % n;
            newborn.push([self.ci[c * 5], self.ci[c * 5 + 1], 6.0, -1.0, self.r01() * 6.2832, 0.0, 0.0, -1.0]);
            self.stat[3] += 1.0;
        }
        let tt = now / 1000.0;
        let mut out: Vec<[f64; 8]> = Vec::with_capacity(ps.len() + 4);
        for p in ps.into_iter() {
            let (mut x, mut y, mut e, mut host, mut a, ph0, mut lost, src) = (p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7]);
            if host >= 0.0 && (host as usize >= n || self.ci[host as usize * 5 + 4] == 0.0) { host = -1.0; lost = now; }
            if host < 0.0 {
                let mut best: i64 = -1; let mut bd = sight * sight;
                if lost == 0.0 { lost = now; }
                let ph = if ph0 == 0.0 { self.r01() * 6.28 } else { ph0 };
                for j in 0..n {
                    let b = j * 5;
                    let mut d = (self.ci[b] - x) * (self.ci[b] - x) + (self.ci[b + 1] - y) * (self.ci[b + 1] - y);
                    if self.ci[b + 3] != 0.0 { d *= 0.5; }
                    if d < bd { bd = d; best = j as i64; }
                }
                let mut phn = ph;
                if best >= 0 {
                    let b = best as usize * 5;
                    let dd = bd.sqrt().max(1e-9); let dd = if bd.sqrt() == 0.0 { 1.0 } else { dd };
                    let osc = (tt * (2.0 + 2.0 * nerv) + ph).sin();
                    let want = self.ci[b + 2] * (1.1 + 0.5 * nerv * (1.0 + osc));
                    let dir = if dd > want { 1.0 } else { -0.6 * nerv };
                    let sp = (6.0f64).min((1.2f64).max(dd * 0.08)) * (1.0 + 0.5 * nerv * osc);
                    x += (self.ci[b] - x) / dd * sp * dir + (self.r01() - 0.5) * 2.0 * nerv;
                    y += (self.ci[b + 1] - y) / dd * sp * dir + (self.r01() - 0.5) * 2.0 * nerv;
                    if hyp(self.ci[b] - x, self.ci[b + 1] - y) < self.ci[b + 2] { host = best as f64; lost = 0.0; self.stat[2] += 1.0; }
                }
                if now - lost > hard_ms { e -= 0.004; }
                out.push([x, y, e, host, a, phn, lost, src]);
                let e2 = out.last().unwrap()[2];
                if e2 <= -hard { out.pop(); self.stat[0] += 1.0; continue; }
                if e2 > 12.0 && (out.len() as f64) < n as f64 * 0.8 + 3.0 { let q = out.last_mut().unwrap(); q[2] /= 2.0; let (qx, qy, qe, qh) = (q[0], q[1], q[2], q[3]); out.push([qx, qy, qe, qh, self.r01() * 6.2832, 0.0, 0.0, -1.0]); self.stat[1] += 1.0; }
            } else {
                let h = host as usize; let b = h * 5;
                let nvr = 0.85 + 0.2 * nerv * (now / 400.0 + ph0).sin();
                let tx = self.ci[b] + a.cos() * self.ci[b + 2] * nvr;
                let ty = self.ci[b + 1] + a.sin() * self.ci[b + 2] * nvr;
                a += 0.01 + 0.03 * nerv * (now / 700.0 + ph0).sin();
                x = lerp(x, tx, 0.5); y = lerp(y, ty, 0.5);
                let crowd = (pc[h] - 1.0).max(0.0);
                let dr = drain * (0.4 + self.en[h].min(20.0) * 0.03) / (1.0 + 0.4 * crowd);
                self.en[h] -= dr; e += dr * eff - 0.012 * (1.0 + 0.7 * crowd);
                out.push([x, y, e, host, a, ph0, lost, src]);
                let e2 = out.last().unwrap()[2];
                if e2 <= -hard { out.pop(); self.stat[0] += 1.0; continue; }
                if e2 > 12.0 && (out.len() as f64) < n as f64 * 0.8 + 3.0 { let q = out.last_mut().unwrap(); q[2] /= 2.0; let (qx, qy, qe, qh) = (q[0], q[1], q[2], q[3]); out.push([qx, qy, qe, qh, self.r01() * 6.2832, 0.0, 0.0, -1.0]); self.stat[1] += 1.0; }
            }
        }
        for p in out.iter().chain(newborn.iter()) { self.po.extend_from_slice(p); }
        self.po.len() as i64 / 8
    }
}

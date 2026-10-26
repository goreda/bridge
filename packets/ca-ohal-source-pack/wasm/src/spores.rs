// ca2core spores food (port of stepSpores, foodMode 5): rooted spores mature, burst into drifting
// motes; motes that survive settle as new spores. JS packs/unpacks; no DOM. Object identity stays in
// JS: rows carry their source index, newborns carry -1 (same contract as swarm.rs).
// in: n x 9 f64 (x, y, r, st, age, ph, vx, vy, gone). out: m x 10 f64 (x, y, r, st, age, ph, vx, vy, src, pad).
// stat: eaten, burst, died, settled, born.
pub struct Sp { pub inb: Vec<f64>, pub out: Vec<f64>, pub stat: [f64; 8], s0: u64, s1: u64 }
pub static mut SP: Option<Sp> = None;
pub fn sp() -> &'static mut Sp {
    unsafe {
        let s = &mut *std::ptr::addr_of_mut!(SP);
        if s.is_none() { *s = Some(Sp { inb: vec![], out: vec![], stat: [0.0; 8], s0: 1, s1: 2 }); }
        s.as_mut().unwrap()
    }
}
fn clamp(v: f64, a: f64, b: f64) -> f64 { v.max(a).min(b) }
impl Sp {
    fn r01(&mut self) -> f64 {
        let (mut x, y) = (self.s0, self.s1);
        self.s0 = y; x ^= x << 23; self.s1 = x ^ y ^ (x >> 17) ^ (y >> 26);
        ((self.s1.wrapping_add(y)) >> 11) as f64 * (1.0 / 9007199254740992.0)
    }
    pub fn step(&mut self, n: usize, x0: f64, x1: f64, y0: f64, y1: f64, dtms: f64, cap: f64, s0: f64, s1: f64) -> i64 {
        self.s0 = ((s0 as u64) << 32) | 0x9E3779B9; self.s1 = ((s1 as u64) << 32) | 0x85EBCA6B;
        for _ in 0..8 { self.r01(); }
        self.stat = [0.0; 8]; self.out.clear();
        if self.inb.len() < n * 9 { return -1; }
        let mut kept: Vec<[f64; 10]> = Vec::with_capacity(n);
        let mut born_rows: Vec<[f64; 10]> = vec![];
        let mut cur_len = n as f64; // mirrors spores.length mid-loop in the JS backward pass
        let mut rooted = 0f64;
        for i in (0..n).rev() {
            let b = i * 9;
            let (mut x, mut y, r, mut st, mut age, ph, mut vx, mut vy, gone) =
                (self.inb[b], self.inb[b + 1], self.inb[b + 2], self.inb[b + 3], self.inb[b + 4], self.inb[b + 5], self.inb[b + 6], self.inb[b + 7], self.inb[b + 8]);
            if !(x.is_finite() && y.is_finite()) { return -1; }
            if gone != 0.0 { self.stat[0] += 1.0; cur_len -= 1.0; continue; }
            age += dtms;
            if st == 0.0 {
                rooted += 1.0;
                if age > 5000.0 + ph * 1200.0 {
                    if cur_len < cap { // burst into motes
                        self.stat[1] += 1.0; self.stat[2] += 1.0; cur_len -= 1.0;
                        let nm = 4 + (self.r01() * 4.0).floor() as usize;
                        for _ in 0..nm {
                            let a2 = self.r01() * 6.2832; let v = 0.6 + self.r01() * 1.2;
                            born_rows.push([x, y, self.r01(), 1.0, 0.0, self.r01() * 6.2832, a2.cos() * v, a2.sin() * v, -1.0, 0.0]);
                            self.stat[4] += 1.0;
                        }
                        continue;
                    } else if self.r01() < 0.4 { self.stat[2] += 1.0; cur_len -= 1.0; continue; } // crowded: retire
                    else { age = 0.0; } // crowded: wait another cycle
                }
            } else {
                vx = vx * 0.965 + (self.r01() - 0.5) * 0.05; vy = vy * 0.965 + (self.r01() - 0.5) * 0.05;
                x += vx; y += vy;
                if x < x0 || x > x1 { vx = -vx * 0.6; x = clamp(x, x0, x1); }
                if y < y0 || y > y1 { vy = -vy * 0.6; y = clamp(y, y0, y1); }
                if age > 1400.0 + ph * 300.0 { // landing
                    if self.r01() < 0.75 { st = 0.0; age = 0.0; vx = 0.0; vy = 0.0; self.stat[3] += 1.0; self.stat[4] += 1.0; }
                    else { self.stat[2] += 1.0; cur_len -= 1.0; continue; }
                }
            }
            kept.push([x, y, r, st, age, ph, vx, vy, i as f64, 0.0]);
        }
        let want = (cap * 0.6).round();
        if rooted < want && self.r01() < 0.35 {
            let nb = (3f64).min(want - rooted) as usize;
            for _ in 0..nb {
                born_rows.push([x0 + self.r01() * (x1 - x0), y0 + self.r01() * (y1 - y0), self.r01(), 0.0, 0.0, self.r01() * 6.2832, 0.0, 0.0, -1.0, 0.0]);
                self.stat[4] += 1.0;
            }
        }
        kept.reverse(); // back to ascending source order; newborns appended after
        for row in kept.iter().chain(born_rows.iter()) { self.out.extend_from_slice(row); }
        (self.out.len() / 10) as i64
    }
}

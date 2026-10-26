// ca2core food mode 1 (Conway lattice, port of stepFood): per-frame inflow pull for dots outside
// the plate, plus the lattice tick (dedup, 8-neighbor counts, survival 2/3, birth on empty 3,
// low-population 3x3 blob seeding). JS keeps food[] object identity outside the tick, the tick
// timer and foodStat bookkeeping; the tick rebuilds the food array from out rows (as JS does).
use std::collections::HashMap;
pub struct Fd1 { pub rows: Vec<f64>, pub out: Vec<f64>, pub stat: [f64; 4], s0: u64, s1: u64 }
pub static mut FD1: Option<Fd1> = None;
pub fn fd1() -> &'static mut Fd1 {
    unsafe {
        let s = &mut *std::ptr::addr_of_mut!(FD1);
        if s.is_none() { *s = Some(Fd1 { rows: vec![], out: vec![], stat: [0.0; 4], s0: 1, s1: 2 }); }
        s.as_mut().unwrap()
    }
}
const M: i64 = 100003;
fn key(ix: i64, iy: i64) -> i64 { (ix + 20000) * M + (iy + 20000) }
impl Fd1 {
    fn r01(&mut self) -> f64 {
        let (mut x, y) = (self.s0, self.s1);
        self.s0 = y; x ^= x << 23; self.s1 = x ^ y ^ (x >> 17) ^ (y >> 26);
        ((self.s1.wrapping_add(y)) >> 11) as f64 * (1.0 / 9007199254740992.0)
    }
    pub fn flow(&mut self, n: usize, x0: f64, y0: f64, x1: f64, y1: f64) -> i64 {
        if self.rows.len() < n * 3 { return -1; }
        let mut infl = 0i64;
        for i in 0..n {
            let b = i * 3;
            let (mut x, mut y) = (self.rows[b], self.rows[b + 1]);
            if !(x.is_finite() && y.is_finite()) { return -1; }
            if x < x0 || x > x1 || y < y0 || y > y1 {
                // the shared boundary rule (port of ca2.js wallPull, vel=false): absolute wall (owner 22 Oct)
                if x < x0 { x = x0; } else if x > x1 { x = x1; }
                if y < y0 { y = y0; } else if y > y1 { y = y1; }
                infl += 1;
                self.rows[b] = x; self.rows[b + 1] = y;
            }
        }
        infl
    }
    #[allow(clippy::too_many_arguments)]
    pub fn tick(&mut self, n: usize, gs: f64, x0: f64, y0: f64, x1: f64, y1: f64, cw: f64, ch: f64, density: f64, s0: f64, s1: f64) -> i64 {
        self.s0 = ((s0 as u64) << 32) | 0x9E3779B9; self.s1 = ((s1 as u64) << 32) | 0x85EBCA6B;
        for _ in 0..8 { self.r01(); }
        self.stat = [0.0; 4];
        if self.rows.len() < n * 3 { return -1; }
        // dedup lattice map, first dot per cell, insertion order preserved
        let mut map: HashMap<i64, usize> = HashMap::with_capacity(n);
        let mut order: Vec<i64> = vec![];
        for i in 0..n {
            let (x, y) = (self.rows[i * 3], self.rows[i * 3 + 1]);
            if !(x.is_finite() && y.is_finite()) { return -1; }
            let ix = (x / gs).floor() as i64; let iy = (y / gs).floor() as i64;
            let k = key(ix, iy);
            if !map.contains_key(&k) { map.insert(k, i); order.push(k); }
        }
        // 8-neighbor counts, insertion order preserved
        let mut cidx: HashMap<i64, usize> = HashMap::new();
        let mut counts: Vec<(i64, i64)> = vec![];
        for &k in &order {
            let ix = k / M - 20000; let iy = k % M - 20000;
            for dx in -1..=1i64 { for dy in -1..=1i64 { if dx == 0 && dy == 0 { continue; }
                let kk = key(ix + dx, iy + dy);
                match cidx.get(&kk) { Some(&j) => counts[j].1 += 1, None => { cidx.insert(kk, counts.len()); counts.push((kk, 1)); } }
            } }
        }
        self.out.clear();
        let mut died = 0i64; let mut born = 0i64;
        for &k in &order {
            let cnt = cidx.get(&k).map(|&j| counts[j].1).unwrap_or(0);
            if cnt == 2 || cnt == 3 { let i = map[&k]; self.out.push(self.rows[i * 3]); self.out.push(self.rows[i * 3 + 1]); self.out.push(self.rows[i * 3 + 2]); }
            else { died += 1; }
        }
        for &(kk, c) in &counts {
            if c == 3 && !map.contains_key(&kk) {
                let ix = kk / M - 20000; let iy = kk % M - 20000;
                let nx = (ix as f64 + 0.5) * gs; let ny = (iy as f64 + 0.5) * gs;
                if nx > x0 && nx < x1 && ny > y0 && ny < y1 { let rv = self.r01(); self.out.push(nx); self.out.push(ny); self.out.push(rv); born += 1; }
            }
        }
        // reseeding moved to the shared JS driver (reseedFood): one mechanism for every dot mode
        let _ = density; let _ = cw; let _ = ch;
        self.stat[0] = died as f64; self.stat[1] = born as f64;
        (self.out.len() / 3) as i64
    }
}

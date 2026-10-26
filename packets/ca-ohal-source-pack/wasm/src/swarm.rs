// ca2core swarm food (port of stepSwarm): cellular-automaton-like boids on a 18 px grid. JS packs/unpacks; no DOM.
// in: n x 6 f64 (x, y, vx, vy, r, unused). out: m x 7 f64 (x, y, vx, vy, r, src index or -1 for newborn, unused). stats: died, born.
pub struct Sw { pub inb: Vec<f64>, pub out: Vec<f64>, pub stat: [f64; 4], s0: u64, s1: u64 }
pub static mut SW: Option<Sw> = None;
pub fn sw() -> &'static mut Sw {
    unsafe {
        let s = &mut *std::ptr::addr_of_mut!(SW);
        if s.is_none() { *s = Some(Sw { inb: vec![], out: vec![], stat: [0.0; 4], s0: 1, s1: 2 }); }
        s.as_mut().unwrap()
    }
}
impl Sw {
    fn r01(&mut self) -> f64 {
        let (mut x, y) = (self.s0, self.s1);
        self.s0 = y; x ^= x << 23; self.s1 = x ^ y ^ (x >> 17) ^ (y >> 26);
        ((self.s1.wrapping_add(y)) >> 11) as f64 * (1.0 / 9007199254740992.0)
    }
    // returns output count, or -1 when the grid would be too large (JS fallback)
    pub fn step(&mut self, n: usize, x0: f64, x1: f64, y0: f64, y1: f64, life: bool, can_birth: bool, low_cap: f64, s0: f64, s1: f64) -> i64 {
        const G: f64 = 18.0;
        self.s0 = ((s0 as u64) << 32) | 0x9E3779B9; self.s1 = ((s1 as u64) << 32) | 0x85EBCA6B;
        for _ in 0..8 { self.r01(); }
        self.stat = [0.0; 4]; self.out.clear();
        if self.inb.len() < n * 6 { return -1; }
        let mut gx = vec![0i32; n]; let mut gy = vec![0i32; n];
        let (mut minx, mut maxx, mut miny, mut maxy) = (i32::MAX, i32::MIN, i32::MAX, i32::MIN);
        for i in 0..n {
            let (x, y) = (self.inb[i * 6], self.inb[i * 6 + 1]);
            if !(x.is_finite() && y.is_finite()) { return -1; }
            gx[i] = (x / G).floor() as i32; gy[i] = (y / G).floor() as i32;
            minx = minx.min(gx[i]); maxx = maxx.max(gx[i]); miny = miny.min(gy[i]); maxy = maxy.max(gy[i]);
        }
        if n == 0 { minx = 0; maxx = 0; miny = 0; maxy = 0; }
        let (w, h) = ((maxx - minx + 3) as i64, (maxy - miny + 3) as i64);
        if w * h > 4_000_000 { return -1; }
        let (w, h) = (w as usize, h as usize);
        let idx = |cx: i32, cy: i32| -> usize { ((cx - minx + 1) as usize) * h + (cy - miny + 1) as usize };
        let mut start = vec![0u32; w * h + 1];
        for i in 0..n { start[idx(gx[i], gy[i]) + 1] += 1; }
        for k in 0..w * h { start[k + 1] += start[k]; }
        let mut fill = start.clone(); let mut order = vec![0u32; n];
        for i in 0..n { let c = idx(gx[i], gy[i]); order[fill[c] as usize] = i as u32; fill[c] += 1; }
        let mut kept = 0usize;
        for i in 0..n {
            let (fx0, fy0) = (self.inb[i * 6], self.inb[i * 6 + 1]);
            let (mut mx, mut my, mut sx, mut sy, mut c) = (0.0f64, 0.0f64, 0.0f64, 0.0f64, 0i32);
            for dx in -1..=1 { for dy in -1..=1 {
                let cc = idx(gx[i] + dx, gy[i] + dy);
                for p in start[cc]..start[cc + 1] {
                    let m = order[p as usize] as usize; if m == i { continue; }
                    let (ex, ey) = (self.inb[m * 6] - fx0, self.inb[m * 6 + 1] - fy0);
                    let d2 = ex * ex + ey * ey;
                    if d2 < G * G { c += 1; mx += ex; my += ey; if d2 < 36.0 && d2 > 0.1 { sx -= ex / d2; sy -= ey / d2; } }
                }
            } }
            let (mut x, mut y, mut vx, mut vy) = (self.inb[i * 6], self.inb[i * 6 + 1], self.inb[i * 6 + 2], self.inb[i * 6 + 3]);
            if c > 0 { let cf = c as f64; vx += mx / cf * 0.004 + sx * 0.6; vy += my / cf * 0.004 + sy * 0.6; }
            vx = vx * 0.97 + (self.r01() - 0.5) * 0.08; vy = vy * 0.97 + (self.r01() - 0.5) * 0.08;
            x += vx; y += vy;
            if x < x0 || x > x1 || y < y0 || y > y1 {
                // the shared boundary-morph rule (port of ca2.js wallPull, vel=false)
                // absolute wall (owner 22 Oct), the same rule cells use
                if x < x0 { x = x0; } else if x > x1 { x = x1; }
                if y < y0 { y = y0; } else if y > y1 { y = y1; }
                vx *= 0.8; vy *= 0.8;
            }
            self.inb[i * 6] = x; self.inb[i * 6 + 1] = y; self.inb[i * 6 + 2] = vx; self.inb[i * 6 + 3] = vy;
            let mut keep = true;
            if life {
                if c < 2 && self.r01() < 0.3 { keep = false; self.stat[0] += 1.0; }
                else if c > 5 && self.r01() < 0.4 { keep = false; self.stat[0] += 1.0; }
                else if (c == 2 || c == 3) && self.r01() < 0.3 && can_birth {
                    let (a, b) = (self.r01(), self.r01()); let r = self.r01();
                    self.out.extend_from_slice(&[x + (a - 0.5) * 6.0, y + (b - 0.5) * 6.0, 0.0, 0.0, r, -1.0, 0.0]); self.stat[1] += 1.0;
                }
            }
            if keep { let r = self.inb[i * 6 + 4]; self.out.extend_from_slice(&[x, y, vx, vy, r, i as f64, 0.0]); kept += 1; }
        }
        let _ = kept;
        if life && (self.out.len() / 7) as f64 > -1.0 && ((self.out.len() / 7) as f64) < low_cap {
            for _ in 0..12 {
                let cx = x0 + self.r01() * (x1 - x0); let cy = y0 + self.r01() * (y1 - y0);
                for _ in 0..4 { let (a, b, r) = (self.r01(), self.r01(), self.r01()); self.out.extend_from_slice(&[cx + (a - 0.5) * 12.0, cy + (b - 0.5) * 12.0, 0.0, 0.0, r, -1.0, 0.0]); }
            }
        }
        (self.out.len() / 7) as i64
    }
}

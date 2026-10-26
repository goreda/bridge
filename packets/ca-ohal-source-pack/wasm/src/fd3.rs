// ca2core foodKeepIn (port): clamp stray dots back into the plate, halving velocity when present.
// Row: 5 f64 (x, y, vx, vy, hasV). JS keeps food[] identity and does a pre-scan so clean frames
// never marshal at all.
pub struct Fd3 { pub rows: Vec<f64> }
pub static mut FD3: Option<Fd3> = None;
pub fn fd3() -> &'static mut Fd3 {
    unsafe {
        let s = &mut *std::ptr::addr_of_mut!(FD3);
        if s.is_none() { *s = Some(Fd3 { rows: vec![] }); }
        s.as_mut().unwrap()
    }
}
impl Fd3 {
    pub fn run(&mut self, n: usize, x0: f64, y0: f64, x1: f64, y1: f64) -> i64 {
        if self.rows.len() < n * 5 { return -1; }
        let mut pulled = 0i64;
        for i in 0..n {
            let b = i * 5;
            let (mut x, mut y) = (self.rows[b], self.rows[b + 1]);
            if !(x.is_finite() && y.is_finite()) { return -1; }
            if x < x0 || x > x1 || y < y0 || y > y1 {
                x = x.max(x0).min(x1); y = y.max(y0).min(y1);
                if self.rows[b + 4] != 0.0 { self.rows[b + 2] *= 0.5; self.rows[b + 3] *= 0.5; }
                self.rows[b] = x; self.rows[b + 1] = y; pulled += 1;
            }
        }
        pulled
    }
}

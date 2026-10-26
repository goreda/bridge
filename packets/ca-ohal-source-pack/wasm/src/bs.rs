// ca2core buildSources + emitCell (port): per-cell metaball source emission (default disc,
// string silhouette, lobed satellites) with the SRC_MAX allowance split. Pure math on packed
// shp fields; newShape/mixShape stay in JS. Row in: 17 f64 (x, y, radius, popD, alive, shpT, th,
// asp, dir, wsp, ph, wig, sat, ph2, wr, wg, wb). Out: f32, six contiguous arrays x/y/r/wr/wg/wb,
// cap12 rows each. stat: n sources, alive cells.
pub struct Bs { pub rows: Vec<f64>, pub out: Vec<f32>, pub stat: [f64; 4], cap12: usize }
pub static mut BS: Option<Bs> = None;
pub fn bs() -> &'static mut Bs {
    unsafe {
        let s = &mut *std::ptr::addr_of_mut!(BS);
        if s.is_none() { *s = Some(Bs { rows: vec![], out: vec![], stat: [0.0; 4], cap12: 0 }); }
        s.as_mut().unwrap()
    }
}
impl Bs {
    pub fn cap(&mut self, cap: usize) -> (*mut f64, *mut f32) {
        self.rows.resize(cap * 17 + 17, 0.0);
        self.cap12 = cap * 12 + 12;
        self.out.resize(self.cap12 * 6, 0.0);
        (self.rows.as_mut_ptr(), self.out.as_mut_ptr())
    }
    #[allow(clippy::too_many_arguments)]
    #[allow(clippy::too_many_arguments)]
    pub fn run(&mut self, n: usize, elapsed: f64, t0: f64, cx: f64, cy: f64, cw: f64, ch: f64, cell_shapes: bool, src_max: f64, bgap: f64) -> i64 {
        self.stat = [0.0; 4];
        if self.rows.len() < n * 17 { return -1; }
        let mut alive = 0i64;
        for i in 0..n {
            let b = i * 17;
            let (x, y) = (self.rows[b], self.rows[b + 1]);
            if !(x.is_finite() && y.is_finite()) { return -1; }
            if self.rows[b + 4] != 0.0 && elapsed >= self.rows[b + 3] && x >= cx && x <= cx + cw && y >= cy && y <= cy + ch { alive += 1; }
        }
        let allowance = if alive > 1 { (src_max / alive as f64).floor().max(1.0) } else { src_max };
        let c12 = self.cap12;
        let mut m = 0usize;
        for i in 0..n {
            let b = i * 17;
            let (x, y, radius) = (self.rows[b], self.rows[b + 1], self.rows[b + 2]);
            if self.rows[b + 4] == 0.0 || elapsed < self.rows[b + 3] || x < cx || x > cx + cw || y < cy || y > cy + ch { continue; }
            let (bx, by) = (x - cx, y - cy);
            let (wr, wg, wb) = (self.rows[b + 14], self.rows[b + 15], self.rows[b + 16]);
            let sht = self.rows[b + 5];
            let start = m;
            // wall squeeze (desktop fix 625f4e8): drawn body never crosses the gap line
            let gap2 = 0f64.max(bgap);
            let rfree = 1f64.max((bx - gap2).min(cw - gap2 - bx).min(by - gap2).min(ch - gap2 - by));
            let cr = radius.min(1f64.max(rfree)) * (1.0 - 0.18 * (1.0 - 0f64.max(rfree - radius) / 8.0).max(0.0).min(1.0));
            if cell_shapes && sht == 1.0 && allowance > 1.0 {
                let th = self.rows[b + 6]; let asp = self.rows[b + 7];
                let rs = cr * th; let span = 2.0 * cr * th * (asp - 1.0);
                let want = (9f64).min((2f64).max((span / (1.15 * rs)).round() + 1.0));
                let nn = want.min(allowance) as i64;
                if nn >= 2 {
                    let dir = self.rows[b + 8]; let wsp = self.rows[b + 9]; let ph = self.rows[b + 10]; let wig = self.rows[b + 11];
                    let ux = dir.cos(); let uy = dir.sin(); let px = -uy; let py = ux;
                    let ds = span / (nn - 1) as f64; let tq = t0 / 850.0 * (1.0 + wsp) + ph;
                    for k in 0..nn {
                        let d0 = -span / 2.0 + ds * k as f64; let off2 = wig * rs * (tq + k as f64 * 0.85).sin();
                        if m >= c12 { return -1; }
                        self.out[m] = (bx + ux * d0 + px * off2) as f32; self.out[c12 + m] = (by + uy * d0 + py * off2) as f32; self.out[2 * c12 + m] = rs as f32; m += 1;
                    }
                }
            } else if cell_shapes && sht == 2.0 && allowance > 2.0 {
                let wsp = self.rows[b + 9]; let ph = self.rows[b + 10]; let sat = self.rows[b + 12] as i64; let ph2 = self.rows[b + 13];
                let r0 = cr * 0.78; let rot = t0 / 4200.0 * wsp + ph;
                if m >= c12 { return -1; }
                self.out[m] = bx as f32; self.out[c12 + m] = by as f32; self.out[2 * c12 + m] = r0 as f32; m += 1;
                for q2 in 0..sat {
                    let aa = rot + q2 as f64 * 2.4 + ph2;
                    let dd = cr * (0.42 + 0.24 * ((q2 as f64 * 0.731 + ph) % 1.0));
                    let rr2 = cr * (0.3 + 0.22 * ((q2 as f64 * 0.377 + ph2) % 1.0));
                    if m >= c12 { return -1; }
                    self.out[m] = (bx + aa.cos() * dd) as f32; self.out[c12 + m] = (by + aa.sin() * dd) as f32; self.out[2 * c12 + m] = rr2 as f32; m += 1;
                }
            }
            if m == start { // default single disc
                if m >= c12 { return -1; }
                self.out[m] = bx as f32; self.out[c12 + m] = by as f32; self.out[2 * c12 + m] = cr as f32; m += 1;
            }
            // per-source squeeze (owner 22 Oct), 1:1 with ca2.js emitCell pushSrc: tails/satellites narrow by their own gap-line distance
            for k in start..m { let sx = self.out[k] as f64; let sy = self.out[c12 + k] as f64; let d = (sx - gap2).min(cw - gap2 - sx).min(sy - gap2).min(ch - gap2 - sy); let rr = self.out[2 * c12 + k] as f64; self.out[2 * c12 + k] = rr.min(0.4f64.max(d)) as f32; }
            for k in start..m { self.out[3 * c12 + k] = wr as f32; self.out[4 * c12 + k] = wg as f32; self.out[5 * c12 + k] = wb as f32; }
        }
        self.stat[0] = m as f64; self.stat[1] = alive as f64; self.stat[2] = self.cap12 as f64;
        m as i64
    }
}

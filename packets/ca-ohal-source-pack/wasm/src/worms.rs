// ca2core worms food (port of the stepWorms move/grow/split core, foodMode 4): the head wanders
// with a wave, the body follows link by link; on a growth tick a worm grows at the tail and splits
// in two when long. JS keeps object identity, food[] membership, the eaten-link/dissolve pre-pass
// and the growth-tick timer; structural results come back as output rows (same contract as swarm.rs).
// hdr in: w x 6 (x, y, a, sp, fr, ph). lnk in: l x 4 (x, y, r, worm index).
// hdr out: m x 7 (x, y, a, sp, fr, ph, src or -1 for split/spawned). lnk out: q x 5 (x, y, r, out worm index, src or -1).
// stat: split, born.
pub struct Wm { pub hdr: Vec<f64>, pub lnk: Vec<f64>, pub oh: Vec<f64>, pub ol: Vec<f64>, pub stat: [f64; 4], s0: u64, s1: u64 }
pub static mut WM: Option<Wm> = None;
pub fn wm() -> &'static mut Wm {
    unsafe {
        let s = &mut *std::ptr::addr_of_mut!(WM);
        if s.is_none() { *s = Some(Wm { hdr: vec![], lnk: vec![], oh: vec![], ol: vec![], stat: [0.0; 4], s0: 1, s1: 2 }); }
        s.as_mut().unwrap()
    }
}
fn hyp(x: f64, y: f64) -> f64 { (x * x + y * y).sqrt() }
impl Wm {
    fn r01(&mut self) -> f64 {
        let (mut x, y) = (self.s0, self.s1);
        self.s0 = y; x ^= x << 23; self.s1 = x ^ y ^ (x >> 17) ^ (y >> 26);
        ((self.s1.wrapping_add(y)) >> 11) as f64 * (1.0 / 9007199254740992.0)
    }
    fn rnd(&mut self, a: f64, b: f64) -> f64 { a + self.r01() * (b - a) }
    pub fn step(&mut self, nw: usize, nl: usize, x0: f64, x1: f64, y0: f64, y1: f64, tt: f64, sp_gap: f64, life: bool, want: f64, s0: f64, s1: f64) -> i64 {
        self.s0 = ((s0 as u64) << 32) | 0x9E3779B9; self.s1 = ((s1 as u64) << 32) | 0x85EBCA6B;
        for _ in 0..8 { self.r01(); }
        self.stat = [0.0; 4]; self.oh.clear(); self.ol.clear();
        if self.hdr.len() < nw * 6 || self.lnk.len() < nl * 4 { return -1; }
        // per-worm link ranges (links packed worm-major)
        let mut wstart = vec![0usize; nw + 1];
        for i in 0..nl { let w = self.lnk[i * 4 + 3] as usize; if w >= nw { return -1; } wstart[w + 1] += 1; }
        for w in 0..nw { wstart[w + 1] += wstart[w]; }
        // sanity: links must be grouped by worm in ascending order
        for w in 0..nw { for i in wstart[w]..wstart[w + 1] { if self.lnk[i * 4 + 3] as usize != w { return -1; } } }
        // working copy of headers + per-worm link chains (indices into self.lnk, kept in order)
        let mut hs: Vec<[f64; 6]> = (0..nw).map(|w| { let b = w * 6; [self.hdr[b], self.hdr[b + 1], self.hdr[b + 2], self.hdr[b + 3], self.hdr[b + 4], self.hdr[b + 5]] }).collect();
        let mut chains: Vec<Vec<usize>> = (0..nw).map(|w| (wstart[w]..wstart[w + 1]).collect()).collect();
        let mut lxy: Vec<[f64; 3]> = (0..nl).map(|i| { let b = i * 4; [self.lnk[b], self.lnk[b + 1], self.lnk[b + 2]] }).collect();
        for i in 0..nl { if !(lxy[i][0].is_finite() && lxy[i][1].is_finite()) { return -1; } }
        // 1) head wander + follow chain
        let m = 26.0; let ccx = (x0 + x1) / 2.0; let ccy = (y0 + y1) / 2.0;
        for w in 0..nw {
            let h = &mut hs[w];
            h[2] += (self.r01() - 0.5) * 0.35 + (tt * h[4] + h[5]).sin() * 0.06;
            if h[0] < x0 + m || h[0] > x1 - m || h[1] < y0 + m || h[1] > y1 - m {
                let ca = (ccy - h[1]).atan2(ccx - h[0]); let mut da = ca - h[2];
                while da > 3.1416 { da -= 6.2832; } while da < -3.1416 { da += 6.2832; }
                h[2] += da * 0.04;
            }
            let spd = h[3] * (1.0 + 0.35 * (tt * h[4] * 2.0 + h[5]).sin());
            h[0] += h[2].cos() * spd; h[1] += h[2].sin() * spd;
            let (mut hx, mut hy) = (h[0], h[1]);
            for &li in chains[w].iter() {
                let l = &mut lxy[li];
                let (dx, dy) = (hx - l[0], hy - l[1]);
                let dd = hyp(dx, dy).max(1e-9); let dd = if dd == 0.0 { 1.0 } else { dd };
                let mv = dd - sp_gap;
                if mv > 0.0 { l[0] += dx / dd * mv; l[1] += dy / dd * mv; }
                hx = l[0]; hy = l[1];
            }
        }
        // 2) growth tick: tail growth, binary fission, spawns
        // out worm list: starts as input worms (src = input index), splits/spawns appended (src = -1)
        let mut out_src: Vec<f64> = (0..nw).map(|w| w as f64).collect();
        let mut new_links: Vec<[f64; 5]> = vec![]; // x, y, r, out worm, src(-1)
        if life {
            for w in 0..nw {
                let dl = chains[w].len();
                if dl < 16 && self.r01() < 0.45 {
                    let tl = lxy[*chains[w].last().unwrap()];
                    new_links.push([tl[0], tl[1], self.r01(), w as f64, -1.0]);
                }
                if dl >= 9 && self.r01() < 0.3 && out_src.len() < 120 { // fission: tail half walks away
                    let half = (dl + 1) / 2;
                    let tail: Vec<usize> = chains[w].split_off(half);
                    let t0 = lxy[tail[0]];
                    let nwidx = out_src.len();
                    hs.push([t0[0], t0[1], self.rnd(0.0, 6.2832), self.rnd(0.25, 0.8), self.rnd(0.6, 1.6), self.rnd(0.0, 6.2832)]);
                    out_src.push(-1.0);
                    chains.push(tail);
                    self.stat[0] += 1.0; self.stat[1] += 1.0;
                    let _ = nwidx;
                }
            }
            let kk = (5f64).min(want - out_src.len() as f64) as i64;
            for _ in 0..kk.max(0) {
                let (x, y) = (x0 + self.r01() * (x1 - x0), y0 + self.r01() * (y1 - y0));
                let len = 3 + (self.r01() * 4.0).floor() as usize;
                let widx = out_src.len();
                hs.push([x, y, self.rnd(0.0, 6.2832), self.rnd(0.25, 0.8), self.rnd(0.6, 1.6), self.rnd(0.0, 6.2832)]);
                out_src.push(-1.0);
                chains.push(vec![]);
                for _ in 0..len { new_links.push([x, y, self.r01(), widx as f64, -1.0]); }
                self.stat[1] += 1.0;
            }
        }
        // 3) emit: headers worm-major, then links grouped by out worm in chain order, then new links in place
        for (w, h) in hs.iter().enumerate() { self.oh.extend_from_slice(&[h[0], h[1], h[2], h[3], h[4], h[5], out_src[w]]); }
        for (w, ch) in chains.iter().enumerate() {
            for &li in ch.iter() { let l = lxy[li]; self.ol.extend_from_slice(&[l[0], l[1], l[2], w as f64, li as f64]); }
            for nlr in new_links.iter() { if nlr[3] as usize == w { self.ol.extend_from_slice(nlr); } }
        }
        self.stat[2] = (self.ol.len() / 5) as f64;
        hs.len() as i64
    }
}

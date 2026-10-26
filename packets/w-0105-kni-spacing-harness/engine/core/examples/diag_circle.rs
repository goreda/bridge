use kni_core::capture::capture_png;
use kni_core::form::circle_fit;
use kni_core::reference_slice::Point;
fn resample_closed(points: &[Point], spacing: f64) -> Vec<Point> {
    let n = points.len();
    if n < 2 || !(spacing > 0.0) { return points.to_vec(); }
    let mut out = Vec::new();
    for i in 0..n {
        let a = points[i]; let b = points[(i + 1) % n];
        let l = (b.x - a.x).hypot(b.y - a.y);
        out.push(a);
        if l > spacing {
            let m = (l / spacing).ceil() as usize;
            for j in 1..m {
                let t = j as f64 / m as f64;
                out.push(Point { x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y) });
            }
        }
    }
    out
}
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let png = std::fs::read(&args[1]).unwrap();
    let scale: f64 = args.get(2).map(|s| s.parse().unwrap()).unwrap_or(1000.0 / 1118.0);
    let mc = capture_png(&png, 0.5).unwrap();
    let t_circle = 1.0 * scale; let eps = 0.5 * scale;
    for (i, r) in mc.rings.iter().enumerate() {
        let pts: Vec<Point> = r.points.iter().map(|p| Point { x: p.x * scale, y: p.y * scale }).collect();
        let dense = resample_closed(&pts, eps);
        match circle_fit(&pts) {
            None => println!("ring{}: pts={} corners={} -> no circle fit", i, pts.len(), r.corners.len()),
            Some((c, rad, vresid)) => {
                let mut dresid = 0.0f64;
                for p in &dense { dresid = dresid.max(((p.x - c.x).hypot(p.y - c.y) - rad).abs()); }
                let (mut mnx, mut mny, mut mxx, mut mxy) = (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
                for p in &dense { mnx = mnx.min(p.x); mxx = mxx.max(p.x); mny = mny.min(p.y); mxy = mxy.max(p.y); }
                let bbox_ok = ((mxx - mnx) - 2.0 * rad).abs() <= t_circle && ((mxy - mny) - 2.0 * rad).abs() <= t_circle;
                let limit = 3.0 * (2.0 * eps / rad).sqrt();
                let mut ang: Vec<f64> = dense.iter().map(|p| (p.y - c.y).atan2(p.x - c.x)).collect();
                ang.sort_by(|a, b| a.partial_cmp(b).unwrap());
                let mut gap = 0.0f64;
                for j in 0..ang.len() { let d = if j + 1 < ang.len() { ang[j + 1] - ang[j] } else { ang[0] + std::f64::consts::TAU - ang[j] }; gap = gap.max(d); }
                println!("ring{}: pts={} corners={} r={:.1} vresid={:.3} dresid={:.3} (T={:.3}) bbox_ok={} gap={:.1}deg limit={:.1}deg",
                    i, pts.len(), r.corners.len(), rad, vresid, dresid, t_circle, bbox_ok, gap.to_degrees(), limit.to_degrees());
            }
        }
    }
}

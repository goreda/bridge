//! Diagnostic dump of raw C3/C4 values for external formula comparison.
//! Input: text file, lines "R x y" (ring start), "L x y", "C x1 y1 x2 y2 x y".
//! Output: single-line JSON {"c3":[...],"c3_abstain":n,"c4":[...],"c4_abstain":n}.
use kni_core::c3c4_roles::*;
use kni_core::reference_slice::{Point, ReferenceRing, Span};

fn main() {
    let path = std::env::args().nth(1).unwrap();
    let text = std::fs::read_to_string(path).unwrap();
    let mut rings: Vec<ReferenceRing> = Vec::new();
    for line in text.lines() {
        let t: Vec<&str> = line.split_whitespace().collect();
        match t[0] {
            "R" => rings.push(ReferenceRing { start: Point { x: t[1].parse().unwrap(), y: t[2].parse().unwrap() }, spans: vec![] }),
            "L" => rings.last_mut().unwrap().spans.push(Span::Line { end: Point { x: t[1].parse().unwrap(), y: t[2].parse().unwrap() } }),
            "C" => rings.last_mut().unwrap().spans.push(Span::Cubic {
                control_one: Point { x: t[1].parse().unwrap(), y: t[2].parse().unwrap() },
                control_two: Point { x: t[3].parse().unwrap(), y: t[4].parse().unwrap() },
                end: Point { x: t[5].parse().unwrap(), y: t[6].parse().unwrap() } }),
            _ => panic!("bad line"),
        }
    }
    let noise = measure_noise(&rings);
    let origin = format!("{:?}", noise.origin);
    let c3 = c3_measure(&rings, &noise, InputPath::Vector);
    let c4 = c4_measure(&rings, &noise, InputPath::Vector);
    let c3v: Vec<String> = c3.elements.iter().filter_map(|e| e.deviation_rad.map(|v| format!("{:.17e}", v))).collect();
    let c4v: Vec<String> = c4.nodes.iter().filter_map(|e| e.join_rad.map(|v| format!("{:.17e}", v))).collect();
    println!("{{\"noise_origin\":\"{}\",\"sigma\":{:.17e},\"c3\":[{}],\"c3_aligned\":{},\"c3_deviant\":{},\"c3_abstain\":{},\"c4\":[{}],\"c4_smooth\":{},\"c4_corner\":{},\"c4_abstain\":{}}}",
        origin, noise.sigma, c3v.join(","), c3.aligned, c3.deviant, c3.abstain, c4v.join(","), c4.smooth, c4.corner, c4.abstain);
}

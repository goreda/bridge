//! Master-set compatibility: the interpolation precondition.
//!
//! Masters of one glyph can interpolate only when they agree in structure:
//! same upm, same contour count, same stroke names in the same order, same
//! segment-kind sequence per contour, same winding direction, and the same
//! node-role sequence per stroke. Coordinates and advance may differ.
//! Nothing here uses a numeric norm: every comparison is structural, and the
//! per-master validator derives its own tolerances from that master.

use crate::check::stroke_polygon;
use crate::model::{MasterGlyph, SegKind};
use crate::validate::{validate, Report, ValidateError};

#[derive(Debug, Clone, PartialEq)]
pub struct CompatIssue {
    /// C1 glyph name, C2 upm, C3 contour count, C4 stroke order, C5 segment
    /// kinds, C6 winding, C7 role sequence, V0 master failed validation setup,
    /// V1 master has validator violations.
    pub rule: &'static str,
    /// Index of the master that differs from master 0 (the reference).
    pub master: usize,
    pub stroke: String,
    pub what: String,
}

#[derive(Debug)]
pub struct CompatReport {
    pub issues: Vec<CompatIssue>,
    /// One validator result per master, in input order.
    pub validated: Vec<Result<Report, ValidateError>>,
}

impl CompatReport {
    pub fn ok(&self) -> bool {
        self.issues.is_empty()
    }
    pub fn rule_ok(&self, rule: &str) -> bool {
        !self.issues.iter().any(|i| i.rule == rule)
    }
}

fn kinds(g: &MasterGlyph, ci: usize) -> Vec<SegKind> {
    g.contours[ci].segments().iter().map(|s| s.kind).collect()
}

fn winding(g: &MasterGlyph, ci: usize) -> i8 {
    let p = stroke_polygon(&g.contours[ci]);
    let n = p.len();
    let a: f64 = (0..n).map(|i| p[i].0 * p[(i + 1) % n].1 - p[(i + 1) % n].0 * p[i].1).sum();
    if a > 0.0 { 1 } else if a < 0.0 { -1 } else { 0 }
}

fn roles_of(r: &Report, stroke: &str) -> Vec<crate::validate::Role> {
    r.roles.iter().filter(|x| x.0 == stroke).map(|x| x.2).collect()
}

/// Check a master set against its first member and validate every master.
/// Fewer than two masters is valid input: only validation runs.
pub fn check_set(masters: &[MasterGlyph]) -> CompatReport {
    let mut issues = Vec::new();
    let validated: Vec<_> = masters.iter().map(validate).collect();
    for (i, v) in validated.iter().enumerate() {
        match v {
            Err(e) => issues.push(CompatIssue { rule: "V0", master: i, stroke: String::new(), what: format!("{:?}", e) }),
            Ok(r) if !r.ok() => issues.push(CompatIssue {
                rule: "V1",
                master: i,
                stroke: String::new(),
                what: format!("{} validator violations", r.violations.len()),
            }),
            _ => {}
        }
    }
    let Some(base) = masters.first() else {
        return CompatReport { issues, validated };
    };
    for (i, m) in masters.iter().enumerate().skip(1) {
        let mut push = |rule, stroke: &str, what: String| {
            issues.push(CompatIssue { rule, master: i, stroke: stroke.to_string(), what })
        };
        if m.name != base.name {
            push("C1", "", format!("glyph name {} vs {}", m.name, base.name));
        }
        if m.upm != base.upm {
            push("C2", "", format!("upm {} vs {}", m.upm, base.upm));
        }
        if m.contours.len() != base.contours.len() {
            push("C3", "", format!("{} contours vs {}", m.contours.len(), base.contours.len()));
        }
        // Per-contour checks are by index; a stroke-name mismatch is an order
        // error, and structural checks still run on the same index.
        for ci in 0..m.contours.len().min(base.contours.len()) {
            let (bn, mn) = (&base.contours[ci].stroke, &m.contours[ci].stroke);
            if bn != mn {
                push("C4", mn, format!("contour {} is stroke {} but master 0 has {}", ci, mn, bn));
            }
            let (bk, mk) = (kinds(base, ci), kinds(m, ci));
            if bk != mk {
                let at = bk.iter().zip(mk.iter()).position(|(a, b)| a != b);
                push("C5", mn, match (bk.len() == mk.len(), at) {
                    (false, _) => format!("{} segments vs {}", mk.len(), bk.len()),
                    (true, Some(k)) => format!("segment {} is {:?} vs {:?}", k, mk[k], bk[k]),
                    _ => "segment kinds differ".to_string(),
                });
            }
            let (bw, mw) = (winding(base, ci), winding(m, ci));
            if bw != mw {
                push("C6", mn, format!("winding {} vs {}", mw, bw));
            }
            if let (Ok(rb), Ok(rm)) = (&validated[0], &validated[i]) {
                if roles_of(rb, bn) != roles_of(rm, mn) {
                    push("C7", mn, "node role sequence differs".to_string());
                }
            }
        }
    }
    CompatReport { issues, validated }
}

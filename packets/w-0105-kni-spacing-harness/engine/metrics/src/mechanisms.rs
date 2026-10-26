//! STEP 5: mechanisms - the solver core.
//!
//! Architecture (iKern-derived): activation-conditioned mechanisms with
//! displacement / property / parameter / message outputs, modulation and
//! inhibition, feedback to convergence. Per-pair residual + uncertainty +
//! active-mechanism IDs + iteration count recorded; EXPLICIT nonconvergence,
//! never silently averaged.
//!
//! PROVENANCE BOUNDARY: iKern's original force/density/membership equations
//! are NOT public; the published material is qualitative (mechanism names
//! and activation conditions from the 2022 panel). Seed rules beyond
//! near_contact therefore register as INACTIVE stubs whose documented
//! activation conditions are the published ones and whose parameters, when
//! they arrive with step 4 air/stress features, are OUR CANDIDATES - labeled
//! as such, never "real iKern algorithm" claims.
//!
//! near_contact is the one fully worked seed: its geometry is code-grounded
//! (BubbleKern v2 lockstep wall gap) and its role is the boundary below:
//! wall-contact offset is a CONSTRAINT + solver initializer, NOT the
//! perceptual target. Collision geometry alone is not letterfitting.

use crate::positions::{lockstep_wall_gap, WallGap};
use crate::side_walls::Wall;

/// Mechanism identifier (stable, ledger-referenced).
pub type MechanismId = &'static str;

/// Published iKern side-class tags (2022 panel). Assigned per glyph SIDE.
/// Boundary-shape tags (Stem/Curve) are separate in the source material and
/// arrive with side_classes (step 3); membership degrees are continuous
/// there, not binary.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SideTag {
    /// B: central-closed.
    CentralClosed,
    /// B+: central-open.
    CentralOpen,
    /// HD: high-density.
    HighDensity,
    /// A: diagonal-closed.
    DiagonalClosed,
    /// A+: diagonal-open.
    DiagonalOpen,
    /// Tag unknown at this step (side_classes not yet wired).
    Untagged,
}

/// Everything a mechanism may read about the pair at the current iteration.
pub struct PairContext<'a> {
    pub left_wall: &'a Wall,
    pub right_wall: &'a Wall,
    pub side_tags: (SideTag, SideTag),
    /// Current PairOriginDistance candidate (displacement of the right
    /// wall relative to the left wall's frame).
    pub displacement: f64,
    /// Exact wall gap at the current displacement.
    pub wall_gap: Option<WallGap>,
}

/// One mechanism's effect for one iteration.
pub struct MechanismEffect {
    /// Requested change to the pair displacement (plane units).
    pub displacement_delta: f64,
}

/// The mechanism surface: deterministic, side-effect-free.
pub trait Mechanism {
    fn id(&self) -> MechanismId;
    /// Activation strength in [0, 1]; 0 means inactive this iteration.
    fn activation(&self, ctx: &PairContext) -> f64;
    /// The effect when applied. Must be deterministic.
    fn effect(&self, ctx: &PairContext) -> MechanismEffect;
}

/// Per-pair solve receipt (evidence discipline).
#[derive(Debug, Clone)]
pub struct SolveReceipt {
    pub iterations: usize,
    pub converged: bool,
    /// |total displacement delta| of the final iteration.
    pub residual: f64,
    /// Mechanisms with nonzero activation at any iteration, in
    /// first-activation order (the set that shaped the outcome).
    pub active: Vec<MechanismId>,
    /// Reserved for the Ahrens uncertainty model (tier c). None until that
    /// model lands; no placeholder numbers.
    pub uncertainty: Option<f64>,
}

/// Solver outcome: converged with the final displacement, or LOUD failure.
#[derive(Debug)]
pub enum SolveOutcome {
    Converged { displacement: f64, receipt: SolveReceipt },
    /// Explicit nonconvergence; the receipt carries the state at the cap.
    /// Never silently averaged.
    NotConverged { receipt: SolveReceipt },
}

/// Deterministic fixed-point solver: every iteration recomputes the exact
/// wall gap at the current displacement, gathers activation-weighted effects
/// in the mechanisms' given order, applies the damped sum, and checks
/// convergence on the residual.
pub fn solve(
    mechanisms: &[Box<dyn Mechanism>],
    left_wall: &Wall,
    right_wall: &Wall,
    side_tags: (SideTag, SideTag),
    initial_displacement: f64,
    damping: f64,
    epsilon: f64,
    max_iter: usize,
) -> SolveOutcome {
    let mut displacement = initial_displacement;
    let mut residual = f64::INFINITY;
    let mut active: Vec<MechanismId> = Vec::new();
    let mut iter = 0usize;
    // `active` accumulates the union over iterations (first-activation
    // order): the audit question is which mechanisms shaped the outcome,
    // not which happened to fire in the final, converged round.
    while iter < max_iter {
        iter += 1;
        let gap = lockstep_wall_gap(left_wall, right_wall, displacement);
        let ctx = PairContext {
            left_wall,
            right_wall,
            side_tags,
            displacement,
            wall_gap: gap,
        };
        let mut total = 0.0;
        for m in mechanisms {
            let a = m.activation(&ctx);
            if a > 0.0 {
                let eff = m.effect(&ctx);
                total += a * eff.displacement_delta;
                if !active.contains(&m.id()) {
                    active.push(m.id());
                }
            }
        }
        displacement += damping * total;
        residual = total.abs();
        if residual < epsilon {
            return SolveOutcome::Converged {
                displacement,
                receipt: SolveReceipt {
                    iterations: iter,
                    converged: true,
                    residual,
                    active,
                    uncertainty: None,
                },
            };
        }
    }
    SolveOutcome::NotConverged {
        receipt: SolveReceipt {
            iterations: iter,
            converged: false,
            residual,
            active,
            uncertainty: None,
        },
    }
}

/// near_contact (fully worked seed, code-grounded geometry): the wall-contact
/// CONSTRAINT. Active only when the walls interpenetrate at the current
/// displacement (min_gap < 0); effect pushes the pair apart by the exact
/// contact delta. This enforces collision-free placement; it is the
/// constraint/initializer, NOT the perceptual target.
pub struct NearContact;

impl Mechanism for NearContact {
    fn id(&self) -> MechanismId {
        "near_contact"
    }

    fn activation(&self, ctx: &PairContext) -> f64 {
        match &ctx.wall_gap {
            Some(g) if g.min_gap < 0.0 => 1.0,
            _ => 0.0,
        }
    }

    fn effect(&self, ctx: &PairContext) -> MechanismEffect {
        let delta = ctx.wall_gap.map(|g| g.contact_delta).unwrap_or(0.0);
        MechanismEffect { displacement_delta: delta }
    }
}

macro_rules! inactive_seed {
    ($name:ident, $id:literal, $doc:literal) => {
        #[doc = $doc]
        pub struct $name;

        impl Mechanism for $name {
            fn id(&self) -> MechanismId {
                $id
            }

            fn activation(&self, _ctx: &PairContext) -> f64 {
                0.0 // semantics arrive with step 4 air/stress features
            }

            fn effect(&self, _ctx: &PairContext) -> MechanismEffect {
                MechanismEffect { displacement_delta: 0.0 }
            }
        }
    };
}

inactive_seed!(
    Penetration,
    "penetration",
    "Seed stub (INACTIVE). Published activation condition (2022 panel): \
     open-central + convex side pairing. Semantics and parameters arrive \
     with step 4 features; they are OUR CANDIDATES, not the real iKern \
     equations (which are not public)."
);

inactive_seed!(
    Sliding,
    "sliding",
    "Seed stub (INACTIVE). Published activation condition: closed-diagonal \
     + convex. Semantics arrive with step 4; OUR CANDIDATES when they do."
);

inactive_seed!(
    Balancing,
    "balancing",
    "Seed stub (INACTIVE). Published activation condition: diagonal + \
     diagonal. Semantics arrive with step 4; OUR CANDIDATES when they do."
);

inactive_seed!(
    InverseReaction,
    "inverse_reaction",
    "Seed stub (INACTIVE). Published case: open + closed-diagonal inverse \
     reaction (the TA case). Semantics arrive with step 4; OUR CANDIDATES \
     when they do."
);

#[cfg(test)]
mod tests {
    use super::*;
    use crate::side_walls::{Side, Wall, WallSource};

    fn wall(side: Side, pts: Vec<(f64, f64)>) -> Wall {
        Wall { side, points: pts, source: WallSource::DesignerOverride }
    }

    fn ms(m: impl Mechanism + 'static) -> Box<dyn Mechanism> {
        Box::new(m)
    }

    #[test]
    fn near_contact_pushes_overlapping_pair_apart() {
        let l = wall(Side::Right, vec![(0.0, 90.0), (100.0, 90.0)]);
        let r = wall(Side::Left, vec![(0.0, 100.0), (100.0, 100.0)]);
        // Initial displacement -20: walls interpenetrate by 10.
        let out = solve(
            &[ms(NearContact)],
            &l,
            &r,
            (SideTag::Untagged, SideTag::Untagged),
            -20.0,
            1.0,
            1e-9,
            50,
        );
        match out {
            SolveOutcome::Converged { displacement, receipt } => {
                assert!((displacement - (-10.0)).abs() < 1e-9);
                assert_eq!(receipt.active, vec!["near_contact"]);
                assert!(receipt.converged);
            }
            _ => panic!("must converge"),
        }
    }

    #[test]
    fn no_active_mechanisms_converges_immediately() {
        let l = wall(Side::Right, vec![(0.0, 50.0), (100.0, 50.0)]);
        let r = wall(Side::Left, vec![(0.0, 100.0), (100.0, 100.0)]);
        let out = solve(
            &[ms(NearContact), ms(Penetration), ms(Sliding)],
            &l,
            &r,
            (SideTag::CentralOpen, SideTag::Untagged),
            0.0,
            0.5,
            1e-9,
            50,
        );
        match out {
            SolveOutcome::Converged { displacement, receipt } => {
                assert_eq!(displacement, 0.0);
                assert_eq!(receipt.iterations, 1);
                assert!(receipt.active.is_empty());
            }
            _ => panic!("must converge"),
        }
    }

    #[test]
    fn determinism() {
        let l = wall(Side::Right, vec![(0.0, 90.0), (100.0, 90.0)]);
        let r = wall(Side::Left, vec![(0.0, 100.0), (100.0, 100.0)]);
        let run = || {
            match solve(&[ms(NearContact)], &l, &r, (SideTag::Untagged, SideTag::Untagged), -20.0, 1.0, 1e-9, 50) {
                SolveOutcome::Converged { displacement, receipt } => (displacement, receipt.iterations),
                _ => panic!(),
            }
        };
        assert_eq!(run(), run());
    }

    struct PingPong;
    impl Mechanism for PingPong {
        fn id(&self) -> MechanismId {
            "pingpong"
        }
        fn activation(&self, _ctx: &PairContext) -> f64 {
            1.0
        }
        fn effect(&self, ctx: &PairContext) -> MechanismEffect {
            MechanismEffect {
                displacement_delta: if ctx.displacement < 0.0 { 10.0 } else { -10.0 },
            }
        }
    }

    #[test]
    fn nonconvergence_is_explicit_never_averaged() {
        let l = wall(Side::Right, vec![(0.0, 0.0), (100.0, 0.0)]);
        let r = wall(Side::Left, vec![(0.0, 100.0), (100.0, 100.0)]);
        let out = solve(
            &[ms(PingPong)],
            &l,
            &r,
            (SideTag::Untagged, SideTag::Untagged),
            5.0,
            1.0,
            1e-9,
            25,
        );
        match out {
            SolveOutcome::NotConverged { receipt } => {
                assert!(!receipt.converged);
                assert_eq!(receipt.iterations, 25);
                assert!(receipt.residual > 0.0);
                assert_eq!(receipt.active, vec!["pingpong"]);
            }
            _ => panic!("must report loud nonconvergence"),
        }
    }
}

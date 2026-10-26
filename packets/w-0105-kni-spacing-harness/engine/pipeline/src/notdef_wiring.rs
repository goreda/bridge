//! K3 — .notdef scan wiring v2: pipeline seam + behaviour tests.
//!
//! Add-only. v2 answers review items 1–10 (2026-10-19):
//!   1. drop_from_font only when the group is a CONFIRMED notdef — a bare
//!      candidate never excludes anything (no evidence-free exclusion).
//!   2. Blank rule is a parameter (`BlankRule`), derived per font upstream;
//!      the black-on-white default is no longer a hidden constant.
//!   3. Hash buckets are content-verified (`same_content`): a hash collision
//!      can neither merge two forms nor cause a wrong drop.
//!   4. Representative is content-deterministic: smallest (glyph_name,
//!      codepoint) inside the winning group — input order never matters.
//!   5. gray length is enforced (== width*height); violations classify as
//!      Malformed with a diagnostic, never a silent remainder skip.
//!   6. Confirmation is group all-or-nothing; a partially in-cmap group
//!      stays Candidate as a whole (test: partial_membership_*).
//!   7. No dead code; ties report their member groups (`tie_groups`) and
//!      anomalies land in `diagnostics`.
//!   8. Duplicate glyph_name values flag the report ambiguous (never block).
//!  10. Registration hunk: see notdef_wiring.registration.md (base snapshot
//!      was not reachable from the patch author — one-line hub edit).
//!
//! Owner rule (owner-channel iMessage 2026-10-16 01:03:26 +03, original
//! verified this session): ".notdef kaynakta tekrar eden grafikse o, boşsa
//! boş" — the MOST repeated non-blank form is the .notdef (never a
//! "seen twice" rule); blank tiles are ABSENT characters, never votes;
//! a notdef problem NEVER stops output.

use std::collections::{HashMap, HashSet};

/// One decoded source tile (the engine's own PNG decoder produces these).
pub struct Tile<'a> {
    pub glyph_name: &'a str,
    /// Codepoint this tile claims to render, when known from the tile name.
    pub codepoint: Option<u32>,
    pub width: u32,
    pub height: u32,
    /// Gray raster, row-major; well-formed iff len == width * height.
    /// The engine's only public decoded surface is gray (capture composites
    /// alpha to white upstream; there is no RGBA8 API) — K1 contract 15:20.
    pub gray: &'a [u8],
}

/// What the font claims to contain (per-font glyph-set list).
/// `known == false` means there is NO list: nothing can be confirmed.
pub struct CmapEvidence {
    pub codepoints: HashSet<u32>,
    pub known: bool,
}

/// Blank-tile rule, derived per font upstream (item 2 — no hidden constants).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct BlankRule {
    /// 0..=255. Light background: a gray pixel is background when >=
    /// threshold. Dark background: when <= 255-threshold.
    pub background_threshold: u8,
    pub dark_ink_on_light: bool,
}
impl Default for BlankRule {
    fn default() -> Self {
        BlankRule { background_threshold: 250, dark_ink_on_light: true }
    }
}
impl BlankRule {
    pub fn is_background(&self, v: u8) -> bool {
        if self.dark_ink_on_light {
            v >= self.background_threshold
        } else {
            v <= 255u8.saturating_sub(self.background_threshold)
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Class {
    Real,
    /// Blank tile: the font lacks this character. Never a notdef vote.
    Absent,
    /// gray length != width*height. Flagged, excluded, never panics.
    Malformed,
    /// Repeated form, cmap evidence confirms every member is outside the
    /// font -> designer-drawn .notdef.
    Notdef,
    /// Most-repeated form without usable cmap evidence -> stays 'candidate';
    /// NOTHING is dropped on a candidate alone.
    Candidate,
}

#[derive(Clone, Debug)]
pub struct Classification {
    pub glyph_name: String,
    pub class: Class,
    pub group_size: usize,
    /// Absent/Malformed tiles and non-representative members of a CONFIRMED
    /// notdef group never reach the font. Candidates are never dropped.
    pub drop_from_font: bool,
}

pub struct ScanReport {
    pub classifications: Vec<Classification>,
    /// Representative of the candidate/confirmed group, when one exists.
    pub notdef_representative: Option<String>,
    /// Tie at the top group size, duplicate glyph_name, or any anomaly:
    /// a human reads, output continues with everything classified Real.
    pub ambiguous: bool,
    /// Member names of every content group tied at the top size (item 7).
    pub tie_groups: Vec<Vec<String>>,
    /// Human-readable anomalies: malformed tiles, duplicate names, ...
    pub diagnostics: Vec<String>,
}

/// Hash seam the core author implements (engine hasher may replace FNV).
pub trait NotdefHasher {
    fn hash_tile(tile: &Tile) -> u64;
}

/// Reference hasher so the wiring + tests run before the core lands:
/// FNV-1a over (width, height, gray).
pub struct FnvHasher;
impl NotdefHasher for FnvHasher {
    fn hash_tile(t: &Tile) -> u64 {
        let mut h: u64 = 0xcbf29ce484222325;
        let mix = |h: &mut u64, b: u8| {
            *h ^= b as u64;
            *h = h.wrapping_mul(0x100000001b3);
        };
        for b in t.width.to_le_bytes() { mix(&mut h, b); }
        for b in t.height.to_le_bytes() { mix(&mut h, b); }
        for &b in t.gray { mix(&mut h, b); }
        h
    }
}

/// Item 5: exact buffer shape is enforced; no silent chunk remainder.
pub fn is_well_formed(t: &Tile) -> bool {
    t.gray.len() == t.width as usize * t.height as usize
}

pub fn is_blank_with(t: &Tile, rule: &BlankRule) -> bool {
    if t.gray.is_empty() {
        return true;
    }
    t.gray.iter().all(|&v| rule.is_background(v))
}

/// Item 3: content equality — the collision guard behind every hash group.
fn same_content(a: &Tile, b: &Tile) -> bool {
    a.width == b.width && a.height == b.height && a.gray == b.gray
}

/// Classify every tile. Never fails: worst case everything is Real and
/// `ambiguous` is set. This is the single pipeline-entry call.
pub fn classify_tiles<H: NotdefHasher>(tiles: &[Tile], ev: &CmapEvidence, rule: &BlankRule) -> ScanReport {
    let mut diagnostics: Vec<String> = Vec::new();

    // Item 8: glyph_name uniqueness (flags ambiguous, never blocks).
    let mut seen_names: HashSet<&str> = HashSet::new();
    let mut dup_names = false;
    for t in tiles {
        if !seen_names.insert(t.glyph_name) {
            dup_names = true;
            diagnostics.push(format!(
                "duplicate glyph_name '{}': tiles kept, report flagged ambiguous",
                t.glyph_name
            ));
        }
    }

    let mut buckets: HashMap<u64, Vec<usize>> = HashMap::new();
    let mut pre: Vec<Option<Class>> = Vec::with_capacity(tiles.len());
    for (i, t) in tiles.iter().enumerate() {
        if !is_well_formed(t) {
            diagnostics.push(format!(
                "tile '{}': malformed buffer (len {} != {}*{})",
                t.glyph_name,
                t.gray.len(),
                t.width,
                t.height
            ));
            pre.push(Some(Class::Malformed));
        } else if is_blank_with(t, rule) {
            pre.push(Some(Class::Absent)); // absent: no vote
        } else {
            pre.push(None);
            buckets.entry(H::hash_tile(t)).or_default().push(i);
        }
    }

    // Item 3: split every hash bucket into content-verified groups, so a
    // collision can never merge two forms into one drop decision.
    let mut groups: Vec<Vec<usize>> = Vec::new();
    for (_hash, idxs) in buckets.iter() {
        for &i in idxs {
            match groups.iter_mut().find(|g| same_content(&tiles[g[0]], &tiles[i])) {
                Some(g) => g.push(i),
                None => groups.push(vec![i]),
            }
        }
    }

    // The MOST repeated content group wins (owner: "iki kez değil, en çok").
    // Only a strictly-largest group qualifies; a tie at size >= 2 is ambiguous.
    let max_len = groups.iter().map(|g| g.len()).max().unwrap_or(0);
    let winners: Vec<&Vec<usize>> = groups.iter().filter(|g| g.len() == max_len).collect();
    let (cand, tie_ambiguous): (Vec<usize>, bool) = if max_len >= 2 && winners.len() == 1 {
        (winners[0].clone(), false)
    } else if max_len >= 2 {
        (Vec::new(), true)
    } else {
        (Vec::new(), false)
    };
    let mut tie_groups: Vec<Vec<String>> = Vec::new();
    if tie_ambiguous {
        for g in &winners {
            let mut names: Vec<String> = g.iter().map(|&i| tiles[i].glyph_name.to_string()).collect();
            names.sort();
            tie_groups.push(names);
        }
        tie_groups.sort();
    }

    // Item 4: representative is content-deterministic — smallest
    // (glyph_name, codepoint) in the group; input order never decides.
    let rep_idx = cand.iter().copied().min_by(|&a, &b| {
        tiles[a]
            .glyph_name
            .cmp(tiles[b].glyph_name)
            .then(tiles[a].codepoint.cmp(&tiles[b].codepoint))
    });

    // Item 6: group all-or-nothing confirmation — every member's codepoint
    // known AND outside the cmap. Partial membership -> whole group stays
    // Candidate; no evidence -> Candidate; nothing else promotes.
    let confirmed = !cand.is_empty()
        && ev.known
        && cand
            .iter()
            .all(|&i| tiles[i].codepoint.map_or(false, |cp| !ev.codepoints.contains(&cp)));

    let cand_set: HashSet<usize> = cand.iter().copied().collect();
    let classifications = tiles
        .iter()
        .enumerate()
        .map(|(i, t)| {
            if let Some(pre_cls) = pre[i] {
                // Absent and Malformed tiles never enter the font.
                return Classification {
                    glyph_name: t.glyph_name.into(),
                    class: pre_cls,
                    group_size: 0,
                    drop_from_font: true,
                };
            }
            if cand_set.contains(&i) {
                let is_rep = rep_idx == Some(i);
                Classification {
                    glyph_name: t.glyph_name.into(),
                    class: if confirmed { Class::Notdef } else { Class::Candidate },
                    group_size: cand.len(),
                    // Item 1: evidence-free exclusion is forbidden.
                    drop_from_font: confirmed && !is_rep,
                }
            } else {
                Classification {
                    glyph_name: t.glyph_name.into(),
                    class: Class::Real,
                    group_size: 1,
                    drop_from_font: false,
                }
            }
        })
        .collect();

    ScanReport {
        classifications,
        notdef_representative: rep_idx.map(|i| tiles[i].glyph_name.to_string()),
        ambiguous: tie_ambiguous || dup_names,
        tie_groups,
        diagnostics,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tile<'a>(name: &'a str, cp: Option<u32>, gray: &'a [u8]) -> Tile<'a> {
        Tile { glyph_name: name, codepoint: cp, width: 2, height: 2, gray }
    }
    fn solid(v: u8) -> [u8; 4] {
        [v, v, v, v]
    }
    fn no_cmap() -> CmapEvidence {
        CmapEvidence { codepoints: HashSet::new(), known: false }
    }
    fn cmap_with(cps: &[u32]) -> CmapEvidence {
        CmapEvidence { codepoints: cps.iter().copied().collect(), known: true }
    }
    fn class_of<'r>(r: &'r ScanReport, name: &str) -> &'r Classification {
        r.classifications.iter().find(|c| c.glyph_name == name).unwrap()
    }
    fn default_rule() -> BlankRule {
        BlankRule::default()
    }

    #[test]
    fn most_frequent_nonblank_group_is_candidate() {
        let r_form = solid(0);
        let (a, b, d) = (solid(10), solid(20), solid(30));
        let tiles = [
            tile("uniE000", Some(0xE000), &r_form),
            tile("A", Some(0x41), &a),
            tile("uniE001", Some(0xE001), &r_form),
            tile("B", Some(0x42), &b),
            tile("uniE002", Some(0xE002), &r_form),
            tile("C", Some(0x43), &d),
        ];
        let rep = classify_tiles::<FnvHasher>(&tiles, &no_cmap(), &default_rule());
        assert_eq!(class_of(&rep, "uniE000").class, Class::Candidate);
        assert_eq!(class_of(&rep, "uniE000").group_size, 3);
        assert_eq!(class_of(&rep, "A").class, Class::Real);
        assert_eq!(rep.notdef_representative.as_deref(), Some("uniE000"));
        assert!(!rep.ambiguous);
    }

    #[test]
    fn most_repeated_wins_over_lesser_repeats() {
        // H12 correction: NOT "seen twice" — the MOST repeated group.
        let (x, y, u) = (solid(1), solid(2), solid(3));
        let tiles = [
            tile("x1", Some(1), &x), tile("y1", Some(10), &y),
            tile("x2", Some(2), &x), tile("y2", Some(11), &y),
            tile("y3", Some(12), &y), tile("y4", Some(13), &y),
            tile("u", Some(20), &u),
        ];
        let rep = classify_tiles::<FnvHasher>(&tiles, &no_cmap(), &default_rule());
        assert_eq!(class_of(&rep, "y1").class, Class::Candidate);
        assert_eq!(class_of(&rep, "x1").class, Class::Real, "2 repeats lose to 4 repeats");
    }

    #[test]
    fn no_cmap_evidence_stays_candidate() {
        let f = solid(0);
        let u = solid(9);
        let tiles = [tile("d1", Some(100), &f), tile("d2", Some(101), &f), tile("A", Some(0x41), &u)];
        let rep = classify_tiles::<FnvHasher>(&tiles, &no_cmap(), &default_rule());
        assert_eq!(class_of(&rep, "d1").class, Class::Candidate, "cmap kanıtsız aday 'candidate'");
    }

    #[test]
    fn cmap_evidence_confirms_notdef() {
        let f = solid(0);
        let u = solid(9);
        let tiles = [
            tile("d1", Some(0xE000), &f), tile("d2", Some(0xE001), &f),
            tile("d3", Some(0xE002), &f), tile("A", Some(0x41), &u),
        ];
        let rep = classify_tiles::<FnvHasher>(&tiles, &cmap_with(&[0x41]), &default_rule());
        assert_eq!(class_of(&rep, "d1").class, Class::Notdef);
    }

    #[test]
    fn cmap_listed_codepoints_do_not_confirm() {
        let f = solid(0);
        let u = solid(9);
        let tiles = [tile("q1", Some(0x51), &f), tile("q2", Some(0x52), &f), tile("A", Some(0x41), &u)];
        let rep = classify_tiles::<FnvHasher>(&tiles, &cmap_with(&[0x41, 0x51, 0x52]), &default_rule());
        assert_eq!(class_of(&rep, "q1").class, Class::Candidate, "in-cmap repetition is not confirmation");
    }

    #[test]
    fn partial_membership_keeps_whole_group_candidate() {
        // Item 6: all-or-nothing — one member in-cmap blocks confirmation
        // for the whole group.
        let f = solid(0);
        let u = solid(9);
        let tiles = [
            tile("d1", Some(0xE000), &f),
            tile("d2", Some(0x41), &f), // this one IS in the cmap
            tile("d3", Some(0xE001), &f),
            tile("A", Some(0x42), &u),
        ];
        let rep = classify_tiles::<FnvHasher>(&tiles, &cmap_with(&[0x41, 0x42]), &default_rule());
        for n in ["d1", "d2", "d3"] {
            assert_eq!(class_of(&rep, n).class, Class::Candidate, "partial membership: whole group stays candidate");
            assert!(!class_of(&rep, n).drop_from_font);
        }
    }

    #[test]
    fn blank_tiles_are_absent_and_never_votes() {
        let blank = solid(255);
        let f = solid(0);
        let u = solid(7);
        let tiles = [
            tile("z1", None, &blank), tile("z2", None, &blank), tile("z3", None, &blank),
            tile("z4", None, &blank), tile("z5", None, &blank),
            tile("d1", Some(0xE000), &f), tile("d2", Some(0xE001), &f), tile("d3", Some(0xE002), &f),
            tile("A", Some(0x41), &u),
        ];
        let rep = classify_tiles::<FnvHasher>(&tiles, &no_cmap(), &default_rule());
        assert_eq!(class_of(&rep, "z1").class, Class::Absent);
        assert!(class_of(&rep, "z1").drop_from_font);
        assert_eq!(class_of(&rep, "d1").class, Class::Candidate, "blanks never vote even when they outnumber");
    }

    #[test]
    fn all_unique_no_candidate() {
        let (a, b, c) = (solid(1), solid(2), solid(3));
        let tiles = [tile("A", Some(0x41), &a), tile("B", Some(0x42), &b), tile("C", Some(0x43), &c)];
        let rep = classify_tiles::<FnvHasher>(&tiles, &no_cmap(), &default_rule());
        assert!(rep.classifications.iter().all(|c| c.class == Class::Real));
        assert_eq!(rep.notdef_representative, None);
        assert!(!rep.ambiguous);
    }

    #[test]
    fn tie_is_ambiguous_and_reports_groups() {
        let (x, y) = (solid(1), solid(2));
        let tiles = [tile("x1", Some(1), &x), tile("x2", Some(2), &x), tile("y1", Some(3), &y), tile("y2", Some(4), &y)];
        let rep = classify_tiles::<FnvHasher>(&tiles, &no_cmap(), &default_rule());
        assert!(rep.ambiguous);
        assert!(rep.classifications.iter().all(|c| c.class == Class::Real), "no silent pick on a tie");
        assert_eq!(rep.notdef_representative, None);
        // Item 7: the tied groups are reported.
        assert_eq!(rep.tie_groups.len(), 2);
        assert!(rep.tie_groups.contains(&vec!["x1".to_string(), "x2".to_string()]));
        assert!(rep.tie_groups.contains(&vec!["y1".to_string(), "y2".to_string()]));
    }

    #[test]
    fn empty_and_single_inputs_never_panic() {
        let rep0 = classify_tiles::<FnvHasher>(&[], &no_cmap(), &default_rule());
        assert!(rep0.classifications.is_empty() && !rep0.ambiguous);
        let a = solid(5);
        let tiles = [tile("A", Some(0x41), &a)];
        let rep1 = classify_tiles::<FnvHasher>(&tiles, &no_cmap(), &default_rule());
        assert_eq!(rep1.classifications.len(), 1);
        assert_eq!(rep1.classifications[0].class, Class::Real);
    }

    #[test]
    fn confirmed_notdef_drops_duplicates_keeps_rep() {
        // Fixed review item 1: drops happen ONLY on a confirmed notdef.
        let f = solid(0);
        let u = solid(8);
        let tiles = [
            tile("d1", Some(0xE000), &f), tile("d2", Some(0xE001), &f),
            tile("d3", Some(0xE002), &f), tile("A", Some(0x41), &u),
        ];
        let rep = classify_tiles::<FnvHasher>(&tiles, &cmap_with(&[0x41]), &default_rule());
        assert_eq!(class_of(&rep, "d1").class, Class::Notdef);
        assert!(!class_of(&rep, "d1").drop_from_font, "representative survives");
        assert!(class_of(&rep, "d2").drop_from_font);
        assert!(class_of(&rep, "d3").drop_from_font);
    }

    #[test]
    fn representative_is_input_order_independent() {
        // Item 4: same tiles, shuffled order -> same representative.
        let f = solid(0);
        let u = solid(8);
        let fwd = [
            tile("d3", Some(0xE002), &f), tile("d1", Some(0xE000), &f),
            tile("d2", Some(0xE001), &f), tile("A", Some(0x41), &u),
        ];
        let rev = [
            tile("A", Some(0x41), &u), tile("d2", Some(0xE001), &f),
            tile("d1", Some(0xE000), &f), tile("d3", Some(0xE002), &f),
        ];
        let r1 = classify_tiles::<FnvHasher>(&fwd, &no_cmap(), &default_rule());
        let r2 = classify_tiles::<FnvHasher>(&rev, &no_cmap(), &default_rule());
        assert_eq!(r1.notdef_representative, r2.notdef_representative);
        assert_eq!(r1.notdef_representative.as_deref(), Some("d1"));
    }

    #[test]
    fn hash_collisions_do_not_merge_content() {
        // Item 3: a constant hasher forces every tile into ONE bucket;
        // content verification must still keep distinct forms apart.
        struct ConstHasher;
        impl NotdefHasher for ConstHasher {
            fn hash_tile(_: &Tile) -> u64 { 0 }
        }
        let (f, g, h) = (solid(0), solid(1), solid(2));
        let tiles = [
            tile("d1", Some(0xE000), &f), tile("d2", Some(0xE001), &f), tile("d3", Some(0xE002), &f),
            tile("b1", Some(10), &g), tile("b2", Some(11), &g),
            tile("c1", Some(20), &h),
        ];
        let rep = classify_tiles::<ConstHasher>(&tiles, &no_cmap(), &default_rule());
        assert_eq!(class_of(&rep, "d1").class, Class::Candidate, "true most-frequent content wins under collision");
        assert_eq!(class_of(&rep, "b1").class, Class::Real, "collided foreign form is not merged into the group");
        assert_eq!(class_of(&rep, "c1").class, Class::Real);
        assert!(!rep.ambiguous);
    }

    #[test]
    fn blank_rule_polarity_is_parametric() {
        // Item 2: light-ink-on-dark font — dark tiles are the background.
        let bg = solid(0);
        let ink = solid(255);
        let tiles = [
            tile("z1", None, &bg), tile("z2", None, &bg),
            tile("d1", Some(0xE000), &ink), tile("d2", Some(0xE001), &ink), tile("d3", Some(0xE002), &ink),
        ];
        let dark_rule = BlankRule { background_threshold: 250, dark_ink_on_light: false };
        let rep = classify_tiles::<FnvHasher>(&tiles, &no_cmap(), &dark_rule);
        assert_eq!(class_of(&rep, "z1").class, Class::Absent, "dark background tiles are blank under dark rule");
        assert_eq!(class_of(&rep, "d1").class, Class::Candidate);
        // Same tiles under the default light rule invert the reading.
        let rep_light = classify_tiles::<FnvHasher>(&tiles, &no_cmap(), &default_rule());
        assert_eq!(class_of(&rep_light, "d1").class, Class::Absent);
    }
}

/// Negative-control tests: states that must NEVER be classified as a
/// confirmed .notdef, and failure modes that must never panic or block.
#[cfg(test)]
mod negative_tests {
    use super::*;

    fn tile<'a>(name: &'a str, cp: Option<u32>, gray: &'a [u8]) -> Tile<'a> {
        Tile { glyph_name: name, codepoint: cp, width: 2, height: 2, gray }
    }
    fn solid(v: u8) -> [u8; 4] {
        [v, v, v, v]
    }
    fn default_rule() -> BlankRule {
        BlankRule::default()
    }

    #[test]
    fn negative_unknown_codepoints_cannot_confirm() {
        let f = solid(0);
        let u = solid(9);
        let tiles = [tile("d1", None, &f), tile("d2", None, &f), tile("A", Some(0x41), &u)];
        let ev = CmapEvidence { codepoints: [0x41u32].into_iter().collect(), known: true };
        let rep = classify_tiles::<FnvHasher>(&tiles, &ev, &default_rule());
        assert_eq!(rep.classifications[0].class, Class::Candidate);
    }

    #[test]
    fn negative_blank_form_is_never_notdef() {
        let b = solid(255);
        let (a, c) = (solid(1), solid(2));
        let tiles = [tile("z1", None, &b), tile("z2", None, &b), tile("z3", None, &b),
                     tile("A", Some(0x41), &a), tile("C", Some(0x43), &c)];
        let rep = classify_tiles::<FnvHasher>(&tiles, &CmapEvidence { codepoints: HashSet::new(), known: false }, &default_rule());
        assert!(rep.classifications.iter().all(|c| c.class != Class::Notdef && c.class != Class::Candidate));
        assert_eq!(rep.notdef_representative, None);
        assert!(!rep.ambiguous);
    }

    #[test]
    fn negative_candidate_group_never_drops_anything() {
        // Fixed review item 1: a bare candidate excludes NOTHING.
        let f = solid(0);
        let u = solid(9);
        let tiles = [tile("d1", Some(0xE000), &f), tile("d2", Some(0xE001), &f), tile("A", Some(0x41), &u)];
        let rep = classify_tiles::<FnvHasher>(&tiles, &CmapEvidence { codepoints: HashSet::new(), known: false }, &default_rule());
        let group: Vec<_> = rep.classifications.iter().filter(|c| c.group_size == 2).collect();
        assert_eq!(group.len(), 2);
        assert!(group.iter().all(|c| !c.drop_from_font), "candidate members all survive");
    }

    #[test]
    fn negative_malformed_pixels_flagged_never_panic() {
        // Item 5: wrong-length buffers classify as Malformed with a
        // diagnostic; output continues.
        let bad: [u8; 3] = [1, 2, 3];
        let empty: [u8; 0] = [];
        let a = solid(7);
        let tiles = [tile("bad", Some(1), &bad), tile("nil", Some(2), &empty), tile("A", Some(0x41), &a)];
        let rep = classify_tiles::<FnvHasher>(&tiles, &CmapEvidence { codepoints: HashSet::new(), known: false }, &default_rule());
        assert_eq!(rep.classifications.len(), 3);
        assert_eq!(rep.classifications[0].class, Class::Malformed);
        assert_eq!(rep.classifications[1].class, Class::Malformed);
        assert_eq!(rep.classifications[2].class, Class::Real);
        assert!(rep.diagnostics.iter().any(|d| d.contains("bad")));
        assert!(rep.diagnostics.iter().any(|d| d.contains("nil")));
    }

    #[test]
    fn negative_duplicate_glyph_name_flags_ambiguous() {
        // Item 8: two tiles sharing a glyph_name must not pass silently.
        let (f, u) = (solid(0), solid(9));
        let tiles = [tile("dup", Some(0xE000), &f), tile("dup", Some(0xE001), &f), tile("A", Some(0x41), &u)];
        let rep = classify_tiles::<FnvHasher>(&tiles, &CmapEvidence { codepoints: HashSet::new(), known: false }, &default_rule());
        assert!(rep.ambiguous);
        assert!(rep.diagnostics.iter().any(|d| d.contains("duplicate glyph_name 'dup'")));
    }
}

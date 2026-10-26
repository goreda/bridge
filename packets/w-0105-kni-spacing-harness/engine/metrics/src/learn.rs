//! LEARN: pair generation learned from a font's existing kern data
//! (new pairs are LEARNED from existing ones; existing pairs are a
//! read-only learning source, never modified).
//!
//! Pipeline: PairInventory (parse + stats) -> learned fit (side-class
//! structure from pair behavior + wall-gap relation) -> generation for
//! uncovered (left, right) combinations -> additive output (existing set
//! preserved byte-identical in value, new pairs in a separate section
//! with tier tags).
//!
//! This module lands the inventory + additive-set discipline; the fit
//! lands when the actual kern data arrives (its format drives the parser).
//! SOURCE-FIRST: the engine complements source pairs, it does not replace
//! them.

use std::collections::{BTreeMap, BTreeSet};

/// One existing kern pair from the font's own data.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct ExistingPair {
    pub left: String,
    pub right: String,
    pub kern: i32,
}

/// Inventory over the existing kern data.
#[derive(Debug, Clone)]
pub struct PairInventory {
    pub pairs: Vec<ExistingPair>,
}

/// Summary stats for the inventory report.
#[derive(Debug, Clone)]
pub struct InventoryStats {
    pub pair_count: usize,
    pub glyph_count_left: usize,
    pub glyph_count_right: usize,
    pub min_kern: i32,
    pub max_kern: i32,
    /// Most common absolute-value buckets (value, count), top 10.
    pub value_histogram: Vec<(i32, usize)>,
    /// Duplicate (left,right) entries, which real-world kern data does
    /// contain; reported, never silently merged.
    pub duplicates: Vec<(String, String)>,
}

impl PairInventory {
    pub fn new(mut pairs: Vec<ExistingPair>) -> Self {
        pairs.sort();
        Self { pairs }
    }

    pub fn stats(&self) -> InventoryStats {
        let mut lefts = BTreeSet::new();
        let mut rights = BTreeSet::new();
        let mut hist: BTreeMap<i32, usize> = BTreeMap::new();
        let mut seen = BTreeSet::new();
        let mut dups = BTreeSet::new();
        let mut min_k = i32::MAX;
        let mut max_k = i32::MIN;
        for p in &self.pairs {
            lefts.insert(p.left.clone());
            rights.insert(p.right.clone());
            *hist.entry(p.kern).or_default() += 1;
            min_k = min_k.min(p.kern);
            max_k = max_k.max(p.kern);
            if !seen.insert((p.left.clone(), p.right.clone())) {
                dups.insert((p.left.clone(), p.right.clone()));
            }
        }
        let mut value_histogram: Vec<(i32, usize)> = hist.into_iter().collect();
        value_histogram.sort_by(|a, b| b.1.cmp(&a.1));
        value_histogram.truncate(10);
        InventoryStats {
            pair_count: self.pairs.len(),
            glyph_count_left: lefts.len(),
            glyph_count_right: rights.len(),
            min_kern: if self.pairs.is_empty() { 0 } else { min_k },
            max_kern: if self.pairs.is_empty() { 0 } else { max_k },
            value_histogram,
            duplicates: dups.into_iter().collect(),
        }
    }

    /// Does the inventory already cover this (left, right) combination?
    pub fn covers(&self, left: &str, right: &str) -> bool {
        self.pairs.iter().any(|p| p.left == left && p.right == right)
    }

    /// Value of an existing pair (None if uncovered). On duplicates the
    /// first sorted entry wins; duplicates are reported in stats, never
    /// silently resolved.
    pub fn value(&self, left: &str, right: &str) -> Option<i32> {
        self.pairs.iter().find(|p| p.left == left && p.right == right).map(|p| p.kern)
    }
}

/// The additive set: existing pairs preserved exactly, generated pairs in
/// a separate section. Serializing or writing must go through this type;
/// it is the structural guarantee of the rule that "existing pairs are
/// not crushed".
#[derive(Debug, Clone)]
pub struct AdditiveKernSet {
    /// Existing pairs, verbatim from the learning source.
    pub existing: Vec<ExistingPair>,
    /// Generated pairs (learned), each carrying its tier tag note.
    pub generated: Vec<(ExistingPair, String)>,
}

impl AdditiveKernSet {
    pub fn new(inventory: &PairInventory) -> Self {
        Self { existing: inventory.pairs.clone(), generated: Vec::new() }
    }

    /// Add a generated pair. Refuses (returns false) when the combination
    /// already exists, either in the source data or in the generated
    /// section: the engine never overwrites and never double-writes.
    pub fn add_generated(&mut self, pair: ExistingPair, tier_note: &str) -> bool {
        if self.existing.iter().any(|p| p.left == pair.left && p.right == pair.right)
            || self.generated.iter().any(|(p, _)| p.left == pair.left && p.right == pair.right)
        {
            return false;
        }
        self.generated.push((pair, tier_note.to_string()));
        true
    }

    /// Verification for the additive guarantee: the existing section
    /// equals the source data EXACTLY as a sorted multiset (duplicates
    /// included - they are reported in stats, never silently resolved).
    /// Callers run this before export and attach the result to the
    /// delivery report.
    pub fn verify_additive(&self, source: &PairInventory) -> Result<(), String> {
        let mut mine = self.existing.clone();
        mine.sort();
        let mut src = source.pairs.clone();
        src.sort();
        if mine == src {
            return Ok(());
        }
        for (a, b) in mine.iter().zip(src.iter()) {
            if a != b {
                return Err(format!(
                    "additive violation at {} {}: output {:?} vs source {:?}",
                    b.left, b.right, a, b
                ));
            }
        }
        Err(format!(
            "additive violation: {} output pairs vs {} source pairs",
            mine.len(),
            src.len()
        ))
    }

    pub fn generated_count(&self) -> usize {
        self.generated.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn inv() -> PairInventory {
        PairInventory::new(vec![
            ExistingPair { left: "V".into(), right: "a".into(), kern: -80 },
            ExistingPair { left: "V".into(), right: "o".into(), kern: -90 },
            ExistingPair { left: "T".into(), right: "o".into(), kern: -90 },
            ExistingPair { left: "T".into(), right: "o".into(), kern: -85 }, // duplicate
        ])
    }

    #[test]
    fn stats_cover_glyphs_values_and_duplicates() {
        let s = inv().stats();
        assert_eq!(s.pair_count, 4);
        assert_eq!(s.glyph_count_left, 2);
        assert_eq!(s.glyph_count_right, 2);
        assert_eq!(s.min_kern, -90);
        assert_eq!(s.max_kern, -80);
        assert_eq!(s.duplicates, vec![("T".to_string(), "o".to_string())]);
        assert_eq!(s.value_histogram[0], (-90, 2));
    }

    #[test]
    fn covers_and_value() {
        let i = inv();
        assert!(i.covers("V", "a"));
        assert!(!i.covers("V", "t"));
        assert_eq!(i.value("V", "o"), Some(-90));
    }

    #[test]
    fn additive_set_refuses_overwrites_and_duplicates() {
        let i = inv();
        let mut set = AdditiveKernSet::new(&i);
        assert!(!set.add_generated(ExistingPair { left: "V".into(), right: "a".into(), kern: -50 }, "x"));
        assert!(set.add_generated(ExistingPair { left: "V".into(), right: "t".into(), kern: -45 }, "ClassDerived"));
        assert!(!set.add_generated(ExistingPair { left: "V".into(), right: "t".into(), kern: -40 }, "dup"));
        assert_eq!(set.generated_count(), 1);
    }

    #[test]
    fn additive_verification() {
        let i = inv();
        let mut set = AdditiveKernSet::new(&i);
        set.add_generated(ExistingPair { left: "i".into(), right: "V".into(), kern: 0 }, "EngineDerived");
        assert!(set.verify_additive(&i).is_ok());
        set.existing[0].kern = -1;
        assert!(set.verify_additive(&i).is_err());
    }
}

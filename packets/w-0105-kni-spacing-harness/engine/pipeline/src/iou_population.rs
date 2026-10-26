//! IoU population is the declared manifest, not the successfully fitted subset.
//! Keep GID filtering keyed: a missing GID produces a failed row, never a shift
//! in the readback result associated with the next glyph.
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PopulationError {
    DuplicateExpected(String),
    DuplicateOutcome(String),
    UnexpectedOutcome(String),
    MissingOutcome(String),
    EmptyName,
}
impl std::fmt::Display for PopulationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{self:?}")
    }
}

/// Expected population includes assembly-only glyphs. It is derived before
/// outcomes, so exclusions/refusals can never shrink the denominator.
pub fn expected_population(
    manifest: &[String],
    has_space: bool,
) -> Result<Vec<String>, PopulationError> {
    let mut expected = manifest.to_vec();
    expected.push(".notdef".into());
    if has_space {
        expected.push("space".into());
    }
    let mut seen = BTreeSet::new();
    for name in &expected {
        if name.is_empty() {
            return Err(PopulationError::EmptyName);
        }
        if !seen.insert(name) {
            return Err(PopulationError::DuplicateExpected(name.clone()));
        }
    }
    Ok(expected)
}

/// Refused and intentional-empty stage-1 entries both count as outcomes. Their
/// classification is preserved at the call site as failed rows or exclusions.
pub fn validate_outcomes(expected: &[String], outcomes: &[String]) -> Result<(), PopulationError> {
    let mut all = BTreeSet::new();
    for name in expected {
        if !all.insert(name) {
            return Err(PopulationError::DuplicateExpected(name.clone()));
        }
    }
    let mut seen = BTreeSet::new();
    for name in outcomes {
        if !all.contains(name) {
            return Err(PopulationError::UnexpectedOutcome(name.clone()));
        }
        if !seen.insert(name) {
            return Err(PopulationError::DuplicateOutcome(name.clone()));
        }
    }
    for name in expected {
        if !seen.contains(name) {
            return Err(PopulationError::MissingOutcome(name.clone()));
        }
    }
    Ok(())
}

/// Keys travel alongside filtered GIDs through readback. Unmapped glyphs are
/// explicitly absent from this map and must become typed failed rows, not skips.
pub fn wanted_gids(
    names: &[String],
    mut gid: impl FnMut(&str) -> Option<u16>,
) -> Vec<(String, u16)> {
    names
        .iter()
        .filter_map(|name| gid(name).map(|id| (name.clone(), id)))
        .collect()
}
pub fn bind_readbacks<T>(
    wanted: &[(String, u16)],
    results: Vec<T>,
) -> Result<BTreeMap<String, T>, PopulationError> {
    if wanted.len() != results.len() {
        return Err(PopulationError::MissingOutcome(
            "readback result cardinality".into(),
        ));
    }
    let mut bound = BTreeMap::new();
    for ((name, _), result) in wanted.iter().zip(results) {
        if bound.insert(name.clone(), result).is_some() {
            return Err(PopulationError::DuplicateOutcome(name.clone()));
        }
    }
    Ok(bound)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn names(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }
    #[test]
    fn manifest_processed_excluded_refused_space_notdef_exact_partition() {
        let declared = names(&["processed", "excluded", "refused", "missing_gid"]);
        let expected = expected_population(&declared, true).unwrap();
        let processed = names(&["processed", "missing_gid"]);
        let excluded = names(&["excluded"]);
        let refused = names(&["refused"]);
        let assembly = names(&["space", ".notdef"]);
        let outcomes: Vec<_> = processed
            .into_iter()
            .chain(excluded)
            .chain(refused)
            .chain(assembly)
            .collect();
        validate_outcomes(&expected, &outcomes).unwrap();
        for index in 0..outcomes.len() {
            let mut dropped = outcomes.clone();
            dropped.remove(index);
            assert!(matches!(
                validate_outcomes(&expected, &dropped),
                Err(PopulationError::MissingOutcome(_))
            ));
            let mut doubled = outcomes.clone();
            doubled.push(outcomes[index].clone());
            assert!(matches!(
                validate_outcomes(&expected, &doubled),
                Err(PopulationError::DuplicateOutcome(_))
            ));
        }
        let mut unexpected = outcomes;
        unexpected.push("foreign".into());
        assert_eq!(
            validate_outcomes(&expected, &unexpected),
            Err(PopulationError::UnexpectedOutcome("foreign".into()))
        );
        assert_eq!(expected_population(&declared, false).unwrap().len(), 5);
        assert!(expected_population(&names(&["space"]), true).is_err());
    }
    #[test]
    fn gid_filter_keeps_results_bound_after_missing_ids() {
        let names = names(&["missing_first", "a", "missing_middle", "b", "missing_last"]);
        let wanted = wanted_gids(&names, |name| match name {
            "a" => Some(7),
            "b" => Some(3),
            _ => None,
        });
        assert_eq!(wanted, vec![("a".into(), 7), ("b".into(), 3)]);
        let mut results =
            bind_readbacks(&wanted, vec![Ok::<_, &str>("outline-a"), Err("b-refused")]).unwrap();
        let mut accounted = Vec::new();
        for name in &names {
            let row = results.remove(name).unwrap_or(Err("missing-gid"));
            match name.as_str() {
                "a" => assert_eq!(row, Ok("outline-a")),
                "b" => assert_eq!(row, Err("b-refused")),
                _ => assert_eq!(row, Err("missing-gid")),
            }
            accounted.push(name.clone());
        }
        assert!(results.is_empty());
        validate_outcomes(&names, &accounted).unwrap();
        assert!(bind_readbacks(&wanted, vec![0]).is_err());
        assert!(bind_readbacks(&[("a".into(), 1), ("a".into(), 2)], vec![0, 1]).is_err());
    }
}

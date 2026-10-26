//! Glyphs-friendly glyph ordering, backed by the official GlyphData
//! (schriftgestalt/GlyphsInfo, vendored compacted at data/glyphdata.tsv).
//! Glyphs' Font View groups glyphs by category/script/subcategory and shows
//! a new heading per contiguous run; emitting in source-gid order interleaves
//! categories and produces repeated headings. Ordering here is deterministic
//! and never invents a category: unknown names sort after known names, by
//! name. `.notdef` is the one explicit exception and always comes first.

use std::collections::BTreeMap;
use std::sync::OnceLock;

/// (category, subCategory, script, row index in the official file) for one
/// known glyph name. The row index is the official GlyphData's own order -
/// used only as a within-subcategory tie-breaker. It is not an assertion
/// that this order is canonical in a particular Glyphs installation.
pub type Entry = (&'static str, &'static str, &'static str, u32);

fn table() -> &'static BTreeMap<&'static str, Entry> {
    static TABLE: OnceLock<BTreeMap<&'static str, Entry>> = OnceLock::new();
    TABLE.get_or_init(|| {
        let mut map = BTreeMap::new();
        for line in include_str!("../data/glyphdata.tsv").lines() {
            if line.starts_with('#') || line.is_empty() {
                continue;
            }
            let mut f = line.split('\t');
            let name = f.next().unwrap_or("");
            let cat = f.next().unwrap_or("");
            let sub = f.next().unwrap_or("");
            let script = f.next().unwrap_or("");
            let idx: u32 = f.next().and_then(|v| v.parse().ok()).unwrap_or(u32::MAX);
            if !name.is_empty() {
                map.insert(name, (cat, sub, script, idx));
            }
        }
        map
    })
}

/// Glyphs Font View group order: Letter, Number, Punctuation, Symbol, Mark,
/// Separator, then anything else. Unknown categories rank last, by name.
fn category_rank(category: &str) -> u8 {
    match category {
        "Letter" => 0,
        "Number" => 1,
        "Punctuation" => 2,
        "Symbol" => 3,
        "Mark" => 4,
        "Separator" => 5,
        _ => 6,
    }
}

/// Sort key: category rank/name, script, actual subcategory, official row
/// index. Subcategories sort lexically (an explicit generator policy, not a
/// claim about canonical Glyphs order); upstream row index breaks ties. Names missing from GlyphData sort after every known name, by name;
/// their order stays deterministic without a guessed category.
pub fn sort_key(name: &str) -> (u8, String, String, String, u32, String) {
    match table().get(name) {
        Some((cat, sub, script, idx)) => (category_rank(cat), (*cat).into(), (*script).into(), (*sub).into(), *idx, name.into()),
        None => (7, String::new(), String::new(), String::new(), u32::MAX, name.into()),
    }
}

/// Stable Glyphs-friendly order: `.notdef` first (explicit exception), then
/// grouped by GlyphData category/script/subcategory, upstream row index within a
/// group (upstream row index). The input multiset is preserved exactly; only positions change.
pub fn ordered<T, F: Fn(&T) -> &str>(mut items: Vec<T>, name_of: F) -> Vec<T> {
    items.sort_by(|a, b| {
        let (a,b) = (name_of(a), name_of(b));
        match (a == ".notdef", b == ".notdef") {
            (true,false) => std::cmp::Ordering::Less,
            (false,true) => std::cmp::Ordering::Greater,
            _ => sort_key(a).cmp(&sort_key(b)),
        }
    });
    items
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn groups_categories_and_notdef_first() {
        let names = vec!["comma", "h", "five", ".notdef", "A", "odieresis"];
        let out = ordered(names, |n| *n);
        assert_eq!(out, vec![".notdef", "h", "odieresis", "A", "five", "comma"]);
    }

    #[test]
    fn unknown_names_last_by_name() {
        let names = vec!["zzz_custom", "A", "aaa_custom"];
        let out = ordered(names, |n| *n);
        assert_eq!(out, vec!["A", "aaa_custom", "zzz_custom"]);
    }
    #[test]
    fn every_actual_subcategory_is_one_contiguous_run() {
        let mut names: Vec<&str> = table().keys().copied().collect();
        names.sort_by_key(|n| sort_key(n));
        let mut finished = std::collections::BTreeSet::new();
        let mut previous = None;
        for name in names {
            let (cat, sub, script, _) = table()[name];
            let group = (cat, script, sub);
            if previous != Some(group) {
                if let Some(p) = previous { finished.insert(p); }
                assert!(!finished.contains(&group), "repeated group {group:?}");
                previous = Some(group);
            }
        }
    }

}

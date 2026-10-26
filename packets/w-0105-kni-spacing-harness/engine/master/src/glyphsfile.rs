//! Strict INSPECTION parser for the `.glyphs` source format (OpenStep
//! property lists), for verification only: the harness reads font info,
//! font-master metrics, glyph unicodes and layer widths out of a `.glyphs`
//! file to compare them against the accompanying OTF. It writes nothing,
//! repairs nothing, and is NOT a conformance validator: full schema
//! validation against the official Glyphs schemas (GlyphsSDK
//! GlyphsFileFormat/Schemas) is out of its scope and is gated separately in
//! the verifier.
//!
//! Strictness (chief review 2026-10-18): duplicate dict keys, missing array
//! commas, comments, non-ASCII whitespace, strings over 1 MiB, inputs over
//! 64 MiB and nesting deeper than 64 are typed errors, never silently
//! accepted. Quoted strings decode as UTF-8 (`\Uxxxx` escapes included).

use std::collections::BTreeMap;

/// Resource guards against hostile input. Guards, not measurements.
const MAX_VALUES: usize = 1 << 22;
const MAX_DEPTH: usize = 64;
const MAX_STRING_BYTES: usize = 1 << 20;
const MAX_INPUT_BYTES: usize = 1 << 26;

#[derive(Debug, Clone, PartialEq)]
pub enum GlyphsError {
    Truncated(&'static str),
    BadSyntax { byte: usize, what: &'static str },
    Budget,
    Missing(&'static str),
}

impl std::fmt::Display for GlyphsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GlyphsError::Truncated(w) => write!(f, "truncated .glyphs: {w}"),
            GlyphsError::BadSyntax { byte, what } => write!(f, ".glyphs byte {byte}: bad syntax: {what}"),
            GlyphsError::Budget => write!(f, ".glyphs resource guard exceeded"),
            GlyphsError::Missing(w) => write!(f, ".glyphs missing {w}"),
        }
    }
}

impl std::error::Error for GlyphsError {}

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Str(String),
    Num(f64),
    /// A number written without a fractional part, kept distinct so
    /// integral-metric checks can flag non-integral values.
    Int(i64),
    Array(Vec<Value>),
    Dict(BTreeMap<String, Value>),
}

impl Value {
    pub fn dict_get<'v>(&'v self, key: &str) -> Option<&'v Value> {
        match self {
            Value::Dict(m) => m.get(key),
            _ => None,
        }
    }
    pub fn as_num(&self) -> Option<f64> {
        match self {
            Value::Num(v) => Some(*v),
            Value::Int(v) => Some(*v as f64),
            _ => None,
        }
    }
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }
    pub fn as_array(&self) -> Option<&[Value]> {
        match self {
            Value::Array(v) => Some(v),
            _ => None,
        }
    }
}

struct P<'a> {
    d: &'a [u8],
    i: usize,
    values: usize,
    depth: usize,
}

impl<'a> P<'a> {
    /// Only the four ASCII whitespace bytes; everything else (including
    /// `//` comments) is rejected so the grammar stays explicit.
    fn ws(&mut self) {
        while self.d.get(self.i).is_some_and(|b| matches!(b, b' ' | b'\t' | b'\r' | b'\n')) {
            self.i += 1;
        }
    }

    fn eat(&mut self, b: u8, what: &'static str) -> Result<(), GlyphsError> {
        self.ws();
        if self.d.get(self.i) == Some(&b) {
            self.i += 1;
            Ok(())
        } else {
            Err(GlyphsError::BadSyntax { byte: self.i, what })
        }
    }

    fn value(&mut self) -> Result<Value, GlyphsError> {
        self.values += 1;
        if self.values > MAX_VALUES || self.depth > MAX_DEPTH {
            return Err(GlyphsError::Budget);
        }
        self.ws();
        match *self.d.get(self.i).ok_or(GlyphsError::Truncated("value"))? {
            b'{' => {
                self.depth += 1;
                let v = self.dict();
                self.depth -= 1;
                v
            }
            b'(' => {
                self.depth += 1;
                let v = self.array();
                self.depth -= 1;
                v
            }
            b'"' => Ok(Value::Str(self.quoted()?)),
            _ => self.atom(),
        }
    }

    fn dict(&mut self) -> Result<Value, GlyphsError> {
        self.eat(b'{', "dict open")?;
        let mut m = BTreeMap::new();
        loop {
            self.ws();
            if self.d.get(self.i) == Some(&b'}') {
                self.i += 1;
                return Ok(Value::Dict(m));
            }
            if self.i >= self.d.len() {
                return Err(GlyphsError::Truncated("dict"));
            }
            let key = match self.d[self.i] {
                b'"' => self.quoted()?,
                _ => self.bare()?,
            };
            self.eat(b'=', "dict '='")?;
            let v = self.value()?;
            self.eat(b';', "dict ';'")?;
            if m.insert(key.clone(), v).is_some() {
                return Err(GlyphsError::BadSyntax { byte: self.i, what: "duplicate dict key" });
            }
        }
    }

    fn array(&mut self) -> Result<Value, GlyphsError> {
        self.eat(b'(', "array open")?;
        let mut v = Vec::new();
        loop {
            self.ws();
            if self.d.get(self.i) == Some(&b')') {
                self.i += 1;
                return Ok(Value::Array(v));
            }
            if self.i >= self.d.len() {
                return Err(GlyphsError::Truncated("array"));
            }
            v.push(self.value()?);
            // A comma is required between values; a bare adjacency is a
            // syntax error, not an implicit separator. A trailing comma
            // before ')' is accepted (Glyphs writes it).
            self.ws();
            if self.d.get(self.i) == Some(&b')') {
                self.i += 1;
                return Ok(Value::Array(v));
            }
            self.eat(b',', "array ','")?;
            self.ws();
        }
    }

    fn quoted(&mut self) -> Result<String, GlyphsError> {
        self.eat(b'"', "quoted string")?;
        let mut s: Vec<u8> = Vec::new();
        loop {
            if s.len() > MAX_STRING_BYTES {
                return Err(GlyphsError::Budget);
            }
            let b = *self.d.get(self.i).ok_or(GlyphsError::Truncated("quoted string"))?;
            self.i += 1;
            match b {
                b'"' => {
                    return String::from_utf8(s)
                        .map_err(|_| GlyphsError::BadSyntax { byte: self.i, what: "string not utf-8" });
                }
                b'\\' => {
                    let e = *self.d.get(self.i).ok_or(GlyphsError::Truncated("escape"))?;
                    self.i += 1;
                    match e {
                        b'n' => s.push(b'\n'),
                        b't' => s.push(b'\t'),
                        b'"' => s.push(b'"'),
                        b'\\' => s.push(b'\\'),
                        b'U' => {
                            let h = self.d.get(self.i..self.i + 4).ok_or(GlyphsError::Truncated("unicode escape"))?;
                            let hex = std::str::from_utf8(h).map_err(|_| GlyphsError::BadSyntax { byte: self.i, what: "unicode escape" })?;
                            let cp = u32::from_str_radix(hex, 16).map_err(|_| GlyphsError::BadSyntax { byte: self.i, what: "unicode escape" })?;
                            self.i += 4;
                            let ch = char::from_u32(cp).ok_or(GlyphsError::BadSyntax { byte: self.i, what: "unicode escape" })?;
                            let mut buf = [0u8; 4];
                            s.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                        }
                        other => s.push(other),
                    }
                }
                _ => s.push(b),
            }
        }
    }

    fn bare(&mut self) -> Result<String, GlyphsError> {
        self.ws();
        let start = self.i;
        while let Some(&b) = self.d.get(self.i) {
            if b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-' | b'+' | b'*') {
                self.i += 1;
            } else {
                break;
            }
        }
        if self.i == start {
            return Err(GlyphsError::BadSyntax { byte: self.i, what: "bare atom" });
        }
        String::from_utf8(self.d[start..self.i].to_vec()).map_err(|_| GlyphsError::BadSyntax { byte: start, what: "atom not utf-8" })
    }

    fn atom(&mut self) -> Result<Value, GlyphsError> {
        let a = self.bare()?;
        if let Ok(v) = a.parse::<i64>() {
            return Ok(Value::Int(v));
        }
        if let Ok(v) = a.parse::<f64>() {
            if v.is_finite() {
                return Ok(Value::Num(v));
            }
        }
        Ok(Value::Str(a))
    }
}

/// Parse a complete `.glyphs` document into its root dict.
pub fn parse(data: &[u8]) -> Result<Value, GlyphsError> {
    if data.len() > MAX_INPUT_BYTES {
        return Err(GlyphsError::Budget);
    }
    let mut p = P { d: data, i: 0, values: 0, depth: 0 };
    let v = p.value()?;
    p.ws();
    if p.i != data.len() {
        return Err(GlyphsError::BadSyntax { byte: p.i, what: "trailing bytes" });
    }
    Ok(v)
}

/// One font master of the source file, both schema generations.
#[derive(Debug, Clone)]
pub struct GlyphsMaster {
    pub id: Option<String>,
    /// Master name. Absent is reported, never invented; empty is a gate
    /// failure in the verifier, not normalized away here.
    pub name: Option<String>,
    /// Legacy scalar metrics (Glyphs 2 schema keys on the master).
    pub ascender: Option<f64>,
    pub descender: Option<f64>,
    pub x_height: Option<f64>,
    pub cap_height: Option<f64>,
    /// Glyphs 3 schema: metric values positional against the font-level
    /// `metrics` registry, as (registry type, pos, over). Slots the file
    /// omits are `None` at their registry position, never reordered; the
    /// type is None when the registry slot itself is invalid.
    pub metric_values: Vec<(Option<String>, Option<f64>, Option<f64>)>,
    /// Indices into `metric_values` whose SOURCE shape was invalid
    /// (non-object element, or metricValues not an array). Their absent
    /// pos/over must NEVER fall back to the metricStore schema default
    /// 0: the schema default applies only to a valid object with an
    /// absent key, not to a malformed slot.
    pub invalid_metric_slots: Vec<usize>,
    /// Whether the file stored a metricValues array on this master at all
    /// (an empty array is not an absent one).
    pub has_metric_values: bool,
    pub has_alignment_zones: bool,
}

/// One glyph layer's advance width record. Neither a missing layer list,
/// nor a missing master binding, nor a missing width is dropped: the
/// verifier decides what each absence means, loudly.
#[derive(Debug, Clone)]
pub struct WidthRecord {
    pub glyph: String,
    /// The layer's `layerId` (its master binding); None when the file
    /// stores no layerId on the layer.
    pub master: Option<String>,
    pub width: Option<f64>,
}

/// One kerning home: a table key (`kerning`, `kerningLTR`, `kerningRTL`,
/// `kerningVertical`) bound to ONE master id. Nothing is flattened across
/// masters or directions.
#[derive(Debug, Clone)]
pub struct KernHome {
    pub table: String,
    pub master: Option<String>,
    pub pairs: Vec<(String, String, f64)>,
}

/// The font-level facts the harness verifies against the OTF.
#[derive(Debug, Clone)]
pub struct GlyphsFontInfo {
    /// `.appVersion` value: the build number the file declares as its
    /// saving app. Reported verbatim; never proof of provenance.
    pub app_version: Option<String>,
    /// `.formatVersion` value; absent means the Glyphs 1/2 schema.
    pub format_version: Option<i64>,
    pub units_per_em: Option<f64>,
    pub family_name: Option<String>,
    pub version: Option<(i64, i64)>,
    pub copyright: Option<String>,
    pub designer: Option<String>,
    pub manufacturer: Option<String>,
    pub license: Option<String>,
    /// The Glyphs 3 metrics registry, in file order; an entry that is not
    /// a dict with a string `type` stays in position as None (positions
    /// define metricValues meaning, so invalid entries are never dropped).
    pub metrics_registry: Vec<Option<String>>,
    pub masters: Vec<GlyphsMaster>,
    /// Every layer of every glyph, with its master binding.
    pub widths: Vec<WidthRecord>,
    /// Glyphs in file order: (name, grouping key "script/category/
    /// subCategory" when the file stores those attributes, else None).
    pub glyph_order: Vec<(String, Option<String>)>,
    /// `unicode` values per glyph, in file order (empty vec when the
    /// glyph stores none).
    pub glyph_unicodes: Vec<(String, Vec<u32>)>,
    /// Glyphs declared non-exporting (`export = 0`; schema
    /// $defs/glyph.export integer enum [0,1], default 1), in file order.
    /// The OTF charset/cmap contains only EXPORTING glyphs, so these are
    /// excluded from population/cmap expectations - never deleted.
    pub nonexporting_glyphs: Vec<String>,
    /// Glyph entries without a usable `glyphname`. Counted, never
    /// silently skipped.
    pub glyphs_unnamed: usize,
    /// Kerning homes, one per (table key, master id) present in the file.
    pub kern_homes: Vec<KernHome>,
    /// Kerning census per table key: (key, total pair count).
    pub kern_tables: Vec<(String, usize)>,
    pub instance_count: usize,
    /// Glyphs 4 info properties (`properties` array), key to first value.
    pub properties: Vec<(String, String)>,
    /// Which of the top-level keys the official schema requires are
    /// physically present in the file (value shape checked separately).
    pub present_keys: Vec<String>,
    /// Present-but-malformed content the extractor refused to interpret
    /// (invalid unicode values, malformed kerning nesting, unbound
    /// localized properties). Every entry kills green; nothing is
    /// dropped silently.
    pub extraction_errors: Vec<String>,
    /// Non-fatal scope notes from extraction (interpretations that had
    /// to be declared, e.g. a legacy hex unicode lexeme).
    pub extraction_notes: Vec<String>,
}

fn int_of(v: Option<&Value>) -> Option<i64> {
    match v {
        Some(Value::Int(i)) => Some(*i),
        Some(Value::Num(n)) if n.fract() == 0.0 => Some(*n as i64),
        _ => None,
    }
}

fn str_of(v: Option<&Value>) -> Option<String> {
    v.and_then(Value::as_str).map(str::to_string)
}

/// Unicode extraction contract, by file format version. Grounding: the
/// official Glyphs 4 schema (`glyphs-4.schema.json`, `$defs/glyph.unicode`)
/// declares the value an INTEGER u32 with decimal examples (`65`,
/// `125184`), `minVersion: 3` — so format-3/4 files are decimal integers,
/// which is also what the slice B/C writers emit (`unicode = 104;` = h).
/// Legacy format-1/2 files carry the historical hex convention: quoted
/// hex strings, and bare digit tokens read as hex text. Anything else is
/// an extraction error, never a guess.
fn unicodes_of(
    g: &Value,
    glyph: &str,
    legacy: bool,
    errs: &mut Vec<String>,
    notes: &mut Vec<String>,
) -> Vec<u32> {
    let one = |v: &Value, errs: &mut Vec<String>, notes: &mut Vec<String>| -> Option<u32> {
        if legacy {
            match v {
                Value::Str(s) => match u32::from_str_radix(s.trim(), 16) {
                    Ok(u) if u <= 0x10FFFF && char::from_u32(u).is_some() => Some(u),
                    _ => {
                        errs.push(format!("glyph '{glyph}': legacy unicode string '{s}' is not a hex scalar value"));
                        None
                    }
                },
                Value::Int(i) if *i >= 0 => {
                    // Bare token: decimal and hex text coincide for pure
                    // digits, so the legacy hex reading is the decimal
                    // TEXT reinterpreted as hex.
                    match u32::from_str_radix(&i.to_string(), 16) {
                        Ok(u) if u <= 0x10FFFF && char::from_u32(u).is_some() => {
                            notes.push(format!("glyph '{glyph}': legacy bare unicode token read as hex ({i} -> U+{u:04X})"));
                            Some(u)
                        }
                        _ => {
                            errs.push(format!("glyph '{glyph}': legacy bare unicode token {i} is not a hex code point"));
                            None
                        }
                    }
                }
                _ => {
                    errs.push(format!("glyph '{glyph}': unicode value has unsupported shape"));
                    None
                }
            }
        } else {
            match v {
                Value::Int(i) if (0..=0x10FFFF).contains(i) && char::from_u32(*i as u32).is_some() => Some(*i as u32),
                Value::Int(i) => {
                    errs.push(format!(
                        "glyph '{glyph}': unicode integer {i} is not a Unicode scalar value (range or surrogate)"
                    ));
                    None
                }
                Value::Num(n) if n.fract() == 0.0 && *n >= 0.0 && *n <= 0x10FFFF as f64 && char::from_u32(*n as u32).is_some() => Some(*n as u32),
                _ => {
                    errs.push(format!(
                        "glyph '{glyph}': unicode value has the wrong type for format >= 3 (schema: decimal integer u32)"
                    ));
                    None
                }
            }
        }
    };
    match g.dict_get("unicode") {
        Some(Value::Array(vs)) => {
            if vs.len() < 2 {
                errs.push(format!("glyph '{glyph}': unicode array must hold at least 2 values (schema minItems 2)"));
            }
            vs.iter().filter_map(|v| one(v, errs, notes)).collect()
        }
        Some(v) => one(v, errs, notes).into_iter().collect(),
        None => Vec::new(),
    }
}

pub fn font_info(root: &Value) -> Result<GlyphsFontInfo, GlyphsError> {
    let app_version = str_of(root.dict_get(".appVersion"));
    let format_version = int_of(root.dict_get(".formatVersion"));
    // Absent `.formatVersion` means the Glyphs 1/2 (legacy) schema.
    let legacy = format_version.unwrap_or(2) < 3;
    let mut extraction_errors: Vec<String> = Vec::new();
    let mut extraction_notes: Vec<String> = Vec::new();
    let present_keys = match root {
        Value::Dict(m) => m.keys().cloned().collect(),
        _ => return Err(GlyphsError::Missing("root dict")),
    };
    let mut properties: Vec<(String, String)> = Vec::new();
    if let Some(pv) = root.dict_get("properties") {
        if !matches!(pv, Value::Array(_)) {
            extraction_errors.push("'properties' is present but not an array".to_string());
        }
    }
    if let Some(ps) = root.dict_get("properties").and_then(Value::as_array) {
        for p in ps {
            let Some(key) = str_of(p.dict_get("key")) else {
                extraction_errors.push("properties entry without a string 'key'".to_string());
                continue;
            };
            let value = if let Some(v) = str_of(p.dict_get("value")) {
                Some(v)
            } else if let Some(vs) = p.dict_get("values").and_then(Value::as_array) {
                // Language binding: the default value is the entry written
                // WITHOUT a language key (Glyphs' writer convention); else
                // the explicit `dflt`; else unbound, which is an error.
                // Shape before binding: a non-object entry, or a present
                // but non-string language key, is an extraction error; a
                // malformed language key must NOT launder the entry into
                // the language-free default slot (chief v5).
                let mut unbound: Vec<&Value> = Vec::new();
                let mut bound: Vec<&Value> = Vec::new();
                for v in vs {
                    if !matches!(v, Value::Dict(_)) {
                        extraction_errors.push(format!(
                            "property '{key}': localized value entry is not an object"
                        ));
                        continue;
                    }
                    match v.dict_get("language") {
                        None => unbound.push(v),
                        Some(l) if l.as_str().is_none() => extraction_errors.push(format!(
                            "property '{key}': 'language' is present but not a string"
                        )),
                        Some(_) => bound.push(v),
                    }
                }
                if unbound.len() > 1 {
                    // Two defaults is typed ambiguity: refusing to pick
                    // beats guessing which language-free value binds.
                    extraction_errors.push(format!(
                        "property '{key}': {} localized values carry no language key (ambiguous default)",
                        unbound.len()
                    ));
                }
                let picked = if !unbound.is_empty() {
                    unbound.remove(0).dict_get("value").and_then(Value::as_str)
                } else {
                    bound
                        .iter()
                        .find(|v| v.dict_get("language").and_then(Value::as_str) == Some("dflt"))
                        .and_then(|v| v.dict_get("value"))
                        .and_then(Value::as_str)
                };
                match picked {
                    Some(v) => Some(v.to_string()),
                    None => {
                        extraction_errors.push(format!(
                            "property '{key}': localized values carry no default (no language-free or dflt entry)"
                        ));
                        None
                    }
                }
            } else {
                extraction_errors.push(format!("property '{key}': no 'value' or 'values'"));
                None
            };
            if let Some(v) = value {
                properties.push((key, v));
            }
        }
    }
    let units_per_em = root.dict_get("unitsPerEm").and_then(Value::as_num);
    let family_name = str_of(root.dict_get("familyName"));
    let version = match (int_of(root.dict_get("versionMajor")), int_of(root.dict_get("versionMinor"))) {
        (Some(a), Some(b)) => Some((a, b)),
        _ => None,
    };
    // Glyphs 3: font-level metrics registry defines the positional meaning
    // of each master's metricValues array. Invalid entries keep their
    // position as None so positions never shift.
    // Registry shape is checked before any per-position default: a
    // present-but-invalid registry, element, or element type is an
    // extraction error, never laundered into an absent type (chief v5).
    let metrics_registry: Vec<Option<String>> = match root.dict_get("metrics") {
        Some(Value::Array(ms)) => ms
            .iter()
            .enumerate()
            .map(|(i, m)| {
                if !matches!(m, Value::Dict(_)) {
                    extraction_errors.push(format!("metrics[{i}] is present but not an object (metric)"));
                    return None;
                }
                match m.dict_get("type") {
                    Some(t) => match t.as_str() {
                        Some(s) => Some(s.to_string()),
                        None => {
                            extraction_errors.push(format!("metrics[{i}].type is present but not a string"));
                            None
                        }
                    },
                    None => None,
                }
            })
            .collect(),
        Some(_) => {
            extraction_errors.push("'metrics' is present but not an array".to_string());
            Vec::new()
        }
        None => Vec::new(),
    };
    let mut masters = Vec::new();
    if let Some(ms) = root.dict_get("fontMaster").and_then(Value::as_array) {
        for m in ms {
            let num = |k: &str| m.dict_get(k).and_then(Value::as_num);
            let mut metric_values = Vec::new();
            let mut invalid_metric_slots = Vec::new();
            let mut has_metric_values = false;
            match m.dict_get("metricValues") {
                Some(Value::Array(vals)) => {
                    has_metric_values = true;
                    for (i, v) in vals.iter().enumerate() {
                        let ty = metrics_registry.get(i).cloned().unwrap_or(None);
                        // A non-object element has no pos/over keys to
                        // default: malformed metricStore shape, an
                        // extraction error, never schema-default 0
                        // (chief v5).
                        if !matches!(v, Value::Dict(_)) {
                            extraction_errors.push(format!(
                                "metricValues[{i}] is present but not an object (metricStore)"
                            ));
                            invalid_metric_slots.push(i);
                            metric_values.push((ty, None, None));
                            continue;
                        }
                        // Absent key = schema default 0; PRESENT but
                        // non-numeric is malformed, never laundered into
                        // the default.
                        for key in ["pos", "over"] {
                            if let Some(raw) = v.dict_get(key) {
                                if raw.as_num().is_none() {
                                    extraction_errors.push(format!(
                                        "metricValues[{i}].{key} is present but not numeric"
                                    ));
                                }
                            }
                        }
                        metric_values.push((ty, num_of(v, "pos"), num_of(v, "over")));
                    }
                }
                Some(_) => {
                    // metricValues present but not an array: extraction
                    // error, and every slot is shape-invalid - never a
                    // schema-default 0.
                    extraction_errors.push("'metricValues' is present but not an array".to_string());
                    has_metric_values = true;
                    for (i, ty) in metrics_registry.iter().enumerate() {
                        invalid_metric_slots.push(i);
                        metric_values.push((ty.clone(), None, None));
                    }
                }
                None => {
                    for ty in &metrics_registry {
                        metric_values.push((ty.clone(), None, None));
                    }
                }
            }
            masters.push(GlyphsMaster {
                id: str_of(m.dict_get("id")),
                name: str_of(m.dict_get("name")),
                ascender: num("ascender"),
                descender: num("descender"),
                x_height: num("xHeight"),
                cap_height: num("capHeight"),
                metric_values,
                invalid_metric_slots,
                has_metric_values,
                has_alignment_zones: m.dict_get("alignmentZones").is_some(),
            });
        }
    }
    let mut widths = Vec::new();
    let mut glyph_order = Vec::new();
    let mut glyph_unicodes = Vec::new();
    let mut nonexporting_glyphs = Vec::new();
    let mut glyphs_unnamed = 0usize;
    if let Some(gs) = root.dict_get("glyphs").and_then(Value::as_array) {
        for g in gs {
            let Some(name) = g.dict_get("glyphname").and_then(Value::as_str) else {
                glyphs_unnamed += 1;
                continue;
            };
            let group = match (g.dict_get("script").and_then(Value::as_str), g.dict_get("category").and_then(Value::as_str)) {
                (None, None) => None,
                (s, c) => Some(format!(
                    "{}/{}/{}",
                    s.unwrap_or(""),
                    c.unwrap_or(""),
                    g.dict_get("subCategory").and_then(Value::as_str).unwrap_or("")
                )),
            };
            // export flag (schema: integer enum [0,1], default 1). A
            // present value of any other shape is an extraction error,
            // never a guessed default.
            match g.dict_get("export") {
                None | Some(Value::Int(1)) => {}
                Some(Value::Int(0)) => nonexporting_glyphs.push(name.to_string()),
                Some(_) => extraction_errors.push(format!(
                    "glyph '{name}': export is present but not 0 or 1 (schema $defs/glyph.export: integer enum [0,1], default 1)"
                )),
            }
            glyph_order.push((name.to_string(), group));
            glyph_unicodes.push((
                name.to_string(),
                unicodes_of(g, name, legacy, &mut extraction_errors, &mut extraction_notes),
            ));
            match g.dict_get("layers").and_then(Value::as_array) {
                Some(layers) => {
                    for l in layers {
                        widths.push(WidthRecord {
                            glyph: name.to_string(),
                            master: str_of(l.dict_get("layerId")),
                            width: l.dict_get("width").and_then(Value::as_num),
                        });
                    }
                }
                None => {
                    widths.push(WidthRecord { glyph: name.to_string(), master: None, width: None });
                }
            }
        }
    }
    let mut kern_homes = Vec::new();
    let mut kern_tables = Vec::new();
    for key in ["kerning", "kerningLTR", "kerningRTL", "kerningVertical"] {
        let Some(kern_value) = root.dict_get(key) else { continue };
        let Value::Dict(by_master) = kern_value else {
            extraction_errors.push(format!("kerning table '{key}' is present but not a dict"));
            continue;
        };
        let mut count = 0usize;
        for (master_id, per_master) in by_master {
            let mut home = KernHome { table: key.to_string(), master: Some(master_id.clone()), pairs: Vec::new() };
            match per_master {
                Value::Dict(by_left) => {
                    for (left, per_left) in by_left {
                        match per_left {
                            Value::Dict(by_right) => {
                                for (right, value) in by_right {
                                    match value.as_num() {
                                        Some(v) => {
                                            home.pairs.push((left.clone(), right.clone(), v));
                                            count += 1;
                                        }
                                        None => extraction_errors.push(format!(
                                            "kerning '{key}'/{master_id}: pair '{left}'/'{right}' has a non-numeric value"
                                        )),
                                    }
                                }
                            }
                            _ => extraction_errors.push(format!(
                                "kerning '{key}'/{master_id}: left entry '{left}' is not a dict of right pairs"
                            )),
                        }
                    }
                }
                _ => extraction_errors.push(format!(
                    "kerning '{key}': master entry '{master_id}' is not a dict of left glyphs"
                )),
            }
            kern_homes.push(home);
        }
        kern_tables.push((key.to_string(), count));
    }
    let instance_count = root.dict_get("instances").and_then(Value::as_array).map_or(0, <[Value]>::len);
    Ok(GlyphsFontInfo {
        app_version,
        format_version,
        units_per_em,
        family_name,
        version,
        copyright: str_of(root.dict_get("copyright")),
        designer: str_of(root.dict_get("designer")),
        manufacturer: str_of(root.dict_get("manufacturer")),
        license: str_of(root.dict_get("license")),
        metrics_registry,
        masters,
        widths,
        glyph_order,
        glyph_unicodes,
        nonexporting_glyphs,
        glyphs_unnamed,
        kern_homes,
        kern_tables,
        instance_count,
        properties,
        present_keys,
        extraction_errors,
        extraction_notes,
    })
}

fn num_of(v: &Value, key: &str) -> Option<f64> {
    v.dict_get(key).and_then(Value::as_num)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_glyph_source_skeleton() {
        let src = br#"{
.formatVersion = 3;
unitsPerEm = 1000;
familyName = "T";
fontMaster = (
{ id = "m01"; ascender = 770; descender = -230; xHeight = 500; capHeight = 700; }
);
glyphs = (
{ glyphname = h; unicode = 104; layers = ( { layerId = "m01"; width = 560; } ); }
);
}
"#;
        let root = parse(src).unwrap();
        let info = font_info(&root).unwrap();
        assert_eq!(info.units_per_em, Some(1000.0));
        assert_eq!(info.masters.len(), 1);
        assert_eq!(info.masters[0].ascender, Some(770.0));
        assert_eq!(info.masters[0].descender, Some(-230.0));
        assert_eq!(info.widths.len(), 1);
        assert_eq!(info.widths[0].glyph, "h");
        assert_eq!(info.widths[0].master.as_deref(), Some("m01"));
        assert_eq!(info.widths[0].width, Some(560.0));
        // Format >= 3 contract (official schema $defs/glyph.unicode:
        // decimal integer u32): 104 == U+0068 == h, exactly what the
        // slice B/C writers emit.
        assert_eq!(info.glyph_unicodes, vec![("h".to_string(), vec![0x68])]);
        assert!(info.extraction_errors.is_empty());
    }

    #[test]
    fn unicode_contract_by_file_version() {
        // Legacy file (no .formatVersion): quoted hex string, and bare
        // digit token read as hex text, both with a declared note.
        let legacy = br#"{ glyphs = ( { glyphname = h; unicode = "0068"; }, { glyphname = A; unicode = 0041; } ); }"#;
        let info = font_info(&parse(legacy).unwrap()).unwrap();
        assert_eq!(info.glyph_unicodes, vec![("h".to_string(), vec![0x68]), ("A".to_string(), vec![0x41])]);
        assert!(info.extraction_errors.is_empty());
        assert!(!info.extraction_notes.is_empty());
        // Format 3: a quoted string is the wrong TYPE (schema: integer),
        // an extraction error, never a hex guess.
        let wrong_type = br#"{ .formatVersion = 3; glyphs = ( { glyphname = h; unicode = "0068"; } ); }"#;
        let info = font_info(&parse(wrong_type).unwrap()).unwrap();
        assert_eq!(info.glyph_unicodes, vec![("h".to_string(), vec![])]);
        assert_eq!(info.extraction_errors.len(), 1);
        // Format 3: out-of-range integer is an extraction error.
        let oor = br#"{ .formatVersion = 3; glyphs = ( { glyphname = h; unicode = 1114112; } ); }"#;
        let info = font_info(&parse(oor).unwrap()).unwrap();
        assert_eq!(info.extraction_errors.len(), 1);
        // Format 3: bare token 0068 parses as decimal 68 (U+0044), which
        // is what the schema's integer type means; no hex reinterpretation.
        let bare = br#"{ .formatVersion = 3; glyphs = ( { glyphname = h; unicode = 0068; } ); }"#;
        let info = font_info(&parse(bare).unwrap()).unwrap();
        assert_eq!(info.glyph_unicodes, vec![("h".to_string(), vec![68])]);
    }

    #[test]
    fn malformed_kerning_is_an_extraction_error() {
        let src = br#"{ .formatVersion = 3; kerning = { m01 = { h = 7; }; }; }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert_eq!(info.extraction_errors.len(), 1);
        assert!(info.extraction_errors[0].contains("not a dict"));
    }

    #[test]
    fn localized_property_language_binding() {
        // Default = entry without a language key; explicit dflt as
        // fallback; no default at all is an extraction error.
        let src = br#"{ .formatVersion = 4; properties = (
{ key = "familyNames"; values = ( { value = "T"; }, { language = DE; value = "T-de"; } ); },
{ key = "designer"; values = ( { language = dflt; value = "D"; } ); },
{ key = "vendor"; values = ( { language = DE; value = "V-de"; } ); }
); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert!(info.properties.contains(&("familyNames".to_string(), "T".to_string())));
        assert!(info.properties.contains(&("designer".to_string(), "D".to_string())));
        assert!(!info.properties.iter().any(|(k, _)| k == "vendor"));
        assert_eq!(info.extraction_errors.len(), 1);
        assert!(info.extraction_errors[0].contains("vendor"));
    }

    #[test]
    fn rejects_trailing_bytes_and_truncation() {
        assert!(matches!(parse(b"{} x"), Err(GlyphsError::BadSyntax { .. })));
        assert!(matches!(parse(b"{ a = (1, 2;"), Err(GlyphsError::BadSyntax { .. })));
        assert!(matches!(parse(b"{ a = \"unterminated"), Err(GlyphsError::Truncated(_))));
    }

    #[test]
    fn strict_grammar_rejections() {
        // duplicate dict key
        assert!(matches!(parse(b"{ a = 1; a = 2; }"), Err(GlyphsError::BadSyntax { .. })));
        // missing comma in array
        assert!(matches!(parse(b"{ a = (1 2); }"), Err(GlyphsError::BadSyntax { .. })));
        // comments are not part of the strict grammar
        assert!(matches!(parse(b"{ a = 1; } // tail"), Err(GlyphsError::BadSyntax { .. })));
        // deep nesting hits the budget guard, not the stack
        let deep = format!("{{ a = {}1{}; }}", "{ x = ".repeat(200), " }".repeat(200));
        assert!(matches!(parse(deep.as_bytes()), Err(GlyphsError::Budget)));
    }

    #[test]
    fn escapes_decode_as_utf8() {
        let src = b"{ a = \"caf\xc3\xa9\"; b = \"\\U00E9\"; }";
        let root = parse(src).unwrap();
        assert_eq!(root.dict_get("a").and_then(Value::as_str), Some("caf\u{00e9}"));
        assert_eq!(root.dict_get("b").and_then(Value::as_str), Some("\u{00e9}"));
        assert!(matches!(parse(b"{ a = \"\xc3\x28\"; }"), Err(GlyphsError::BadSyntax { .. })));
    }
}

#[cfg(test)]
mod v4_tests {
    use super::*;

    #[test]
    fn surrogate_unicode_is_an_extraction_error() {
        let src = br#"{ .formatVersion = 3; glyphs = ( { glyphname = x; unicode = 55296; } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert_eq!(info.glyph_unicodes, vec![("x".to_string(), vec![])]);
        assert_eq!(info.extraction_errors.len(), 1);
        assert!(info.extraction_errors[0].contains("scalar"), "{:?}", info.extraction_errors);
    }

    #[test]
    fn non_numeric_metricvalue_pos_is_invalid_not_default() {
        let src = br#"{ .formatVersion = 3; metrics = ( { type = ascender; } ); fontMaster = ( { id = "m01"; metricValues = ( { pos = "oops"; } ); } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert!(info.extraction_errors.iter().any(|e| e.contains("pos") && e.contains("not numeric")));
    }

    #[test]
    fn ambiguous_language_free_default_is_an_error() {
        let src = br#"{ .formatVersion = 4; properties = ( { key = "familyNames"; values = ( { value = "A"; }, { value = "B"; } ); } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert!(info.extraction_errors.iter().any(|e| e.contains("ambiguous default")), "{:?}", info.extraction_errors);
    }

    #[test]
    fn non_object_metricvalue_element_is_an_extraction_error() {
        // Scalar and string elements at a metric position carry no
        // pos/over keys: malformed metricStore shape, never default 0.
        for frag in ["7", "\"oops\""] {
            let src = format!("{{ .formatVersion = 3; metrics = ( {{ type = ascender; }} ); fontMaster = ( {{ id = \"m01\"; metricValues = ( {frag} ); }} ); }}");
            let info = font_info(&parse(src.as_bytes()).unwrap()).unwrap();
            assert!(
                info.extraction_errors.iter().any(|e| e.contains("metricValues[0]") && e.contains("not an object")),
                "{:?}", info.extraction_errors
            );
        }
    }

    #[test]
    fn scalar_metricvalues_array_slots_are_invalid_not_defaulted() {
        // Glyphs-2-style bare-number metricValues: every element is a
        // shape error and its slot is marked invalid, so the verifier
        // can never fall back to the metricStore schema default 0.
        let src = br#"{ .formatVersion = 3; metrics = ( { type = baseline; }, { type = x-height; } ); fontMaster = ( { id = "m01"; metricValues = ( 0, 500 ); } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert_eq!(info.masters[0].invalid_metric_slots, vec![0, 1]);
        assert_eq!(info.extraction_errors.len(), 2);
        assert!(info.extraction_errors.iter().all(|e| e.contains("not an object")), "{:?}", info.extraction_errors);
        // metricValues present but not an array: all slots invalid.
        let src = br#"{ .formatVersion = 3; metrics = ( { type = baseline; } ); fontMaster = ( { id = "m01"; metricValues = 7; } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert_eq!(info.masters[0].invalid_metric_slots, vec![0]);
        assert!(info.extraction_errors.iter().any(|e| e.contains("'metricValues' is present but not an array")), "{:?}", info.extraction_errors);
        // A VALID object with absent pos is NOT invalid: schema default
        // 0 still applies there.
        let src = br#"{ .formatVersion = 3; metrics = ( { type = baseline; } ); fontMaster = ( { id = "m01"; metricValues = ( { over = 5; } ); } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert!(info.masters[0].invalid_metric_slots.is_empty());
        assert!(info.extraction_errors.is_empty(), "{:?}", info.extraction_errors);
    }

    #[test]
    fn export_flag_parsing() {
        // absent -> exporting (schema default 1); 0 -> non-exporting;
        // any other shape -> extraction error, never a guessed default.
        let src = br#"{ .formatVersion = 3; glyphs = ( { glyphname = a; }, { glyphname = b; export = 0; }, { glyphname = c; export = 1; }, { glyphname = d; export = 2; } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert_eq!(info.nonexporting_glyphs, vec!["b".to_string()]);
        assert_eq!(info.extraction_errors.len(), 1);
        assert!(info.extraction_errors[0].contains("'d'") && info.extraction_errors[0].contains("export"), "{:?}", info.extraction_errors);
    }

    #[test]
    fn lexer_type_parse_lexemes() {
        // Shared B/C/D type-parse fixture lexemes, measured:
        // +1 -> Int(1), .5 -> Num(0.5), +1e3 -> Num(1000).
        let v = parse(b"{ a = ( +1, .5, +1e3 ); }").unwrap();
        let a = v.dict_get("a").and_then(Value::as_array).unwrap();
        assert_eq!(a, &[Value::Int(1), Value::Num(0.5), Value::Num(1000.0)]);
    }

    #[test]
    fn unicode_quoted_and_bare_hex_lexemes() {
        // Quoted "002A" and bare 002A: format >= 3 rejects both as the
        // wrong type (schema: decimal integer u32); legacy reads both as
        // hex U+002A.
        for src in [
            br#"{ .formatVersion = 3; glyphs = ( { glyphname = x; unicode = "002A"; } ); }"#.as_slice(),
            br#"{ .formatVersion = 3; glyphs = ( { glyphname = x; unicode = 002A; } ); }"#.as_slice(),
        ] {
            let info = font_info(&parse(src).unwrap()).unwrap();
            assert_eq!(info.glyph_unicodes, vec![("x".to_string(), vec![])]);
            assert!(info.extraction_errors.iter().any(|e| e.contains("wrong type for format >= 3")), "{:?}", info.extraction_errors);
        }
        for src in [
            br#"{ glyphs = ( { glyphname = x; unicode = "002A"; } ); }"#.as_slice(),
            br#"{ glyphs = ( { glyphname = x; unicode = 002A; } ); }"#.as_slice(),
        ] {
            let info = font_info(&parse(src).unwrap()).unwrap();
            assert_eq!(info.glyph_unicodes, vec![("x".to_string(), vec![0x2A])], "{:?}", info.extraction_errors);
        }
    }

    #[test]
    fn invalid_metrics_registry_shapes_are_extraction_errors() {
        let src = br#"{ .formatVersion = 3; metrics = 7; fontMaster = ( { id = "m01"; } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert!(info.extraction_errors.iter().any(|e| e.contains("'metrics' is present but not an array")), "{:?}", info.extraction_errors);
        let src = br#"{ .formatVersion = 3; metrics = ( 7 ); fontMaster = ( { id = "m01"; } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert!(info.extraction_errors.iter().any(|e| e.contains("metrics[0]") && e.contains("not an object")), "{:?}", info.extraction_errors);
        let src = br#"{ .formatVersion = 3; metrics = ( { type = 7; } ); fontMaster = ( { id = "m01"; } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert!(info.extraction_errors.iter().any(|e| e.contains("metrics[0].type") && e.contains("not a string")), "{:?}", info.extraction_errors);
    }

    #[test]
    fn malformed_language_key_never_becomes_the_default() {
        // language present but not a string: extraction error AND the
        // malformed entry must not occupy the language-free default slot.
        let src = br#"{ .formatVersion = 4; properties = ( { key = "familyNames"; values = ( { language = 7; value = "bad"; }, { value = "T"; } ); } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert!(info.extraction_errors.iter().any(|e| e.contains("language") && e.contains("not a string")), "{:?}", info.extraction_errors);
        assert!(info.properties.contains(&("familyNames".to_string(), "T".to_string())));
        assert!(!info.properties.iter().any(|(_, v)| v == "bad"));
        // A non-object localized entry is an extraction error, never a default.
        let src = br#"{ .formatVersion = 4; properties = ( { key = "familyNames"; values = ( 7, { language = dflt; value = "D"; } ); } ); }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert!(info.extraction_errors.iter().any(|e| e.contains("not an object")), "{:?}", info.extraction_errors);
        assert!(info.properties.contains(&("familyNames".to_string(), "D".to_string())));
    }

    #[test]
    fn properties_wrong_shape_is_an_error() {
        let src = br#"{ .formatVersion = 4; properties = 7; }"#;
        let info = font_info(&parse(src).unwrap()).unwrap();
        assert!(info.extraction_errors.iter().any(|e| e.contains("not an array")));
    }
}

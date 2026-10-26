//! Glyphs (`.glyphs`) master-file serializer for master-mode parts.
//!
//! Writes a master-mode font (structural parts as contours) as a Glyphs
//! file: one shape per structural stroke, overlaps unmerged (the boolean
//! merge stays an export-only step), component references to other glyphs
//! (`ref` plus non-default transform keys, `$defs/component`), one
//! `fontMaster` per master and one layer per glyph per master. The file
//! ships next to the OTF so the parts master opens in Glyphs for review
//! and hand edits.
//!
//! Schema source: the official Glyphs file format documentation
//! (`GlyphsFileFormatv4.md` in schriftgestalt/GlyphsSDK, branch Glyphs4),
//! which covers `.formatVersion` 3 (format 4 gets a typed refusal),
//! cross-checked against glyphsLib 6.16.1 (the Glyphs team's own
//! read/write library). This module emits `.formatVersion = 3`, the format
//! Glyphs 4 itself uses for new documents. Format 3 keeps `familyName`
//! top-level; format 4 moves naming into `properties` and is not emitted.
//!
//! Custody reference: the owner's own Marq Alternate `h` master
//! (Glyphs 4.1 build 4100, `.formatVersion` 4, sha256
//! 4c69d538db9efbad048900920d1139936065eddd59ed2355812b4cbd16353b23)
//! anchors the format decisions measured from a real Glyphs save: smooth
//! nodes (`cs`/`ls` tuple suffixes) in actual drawing, vertical metrics
//! only via `metricValues` (baseline/italic-angle zero values omitted),
//! first path node written as `l`, and a present-but-empty `kerningLTR`
//! container. Format-4-only structure (properties naming, backup layers
//! with `associatedMasterId`, customParameters) stays outside this
//! round-trip reader's subset and gets a typed refusal.
//!
//! Vertical metrics follow the v3/v4 schema: a top-level ordered `metrics`
//! registry and per-master positional `metricValues` (`pos`/`over`). The
//! legacy scalar master fields (`ascender = 850` etc.) are Glyphs 2 format
//! and are never written: Glyphs 3/4 ignores them, which is what produced
//! blank Metrics tabs in earlier deliveries. Overshoots (`over`) are
//! written only when the caller supplies a measured value; an unmeasured
//! overshoot is absent, never a blind zero. The registry is caller data,
//! not a fixed list: a metric with no measured position does not belong in
//! it, so every `pos` in the file is a measured one.
//!
//! `.appVersion` follows the caller's explicit `app_version` choice. The
//! official schema requires the key, so `None` (omit) is a declared
//! schema-NON-conforming generator exception, not a pass; `Some` stamps the
//! given build number, which is honest only for a file Glyphs itself saved.
//! This writer never invents a build number.
//!
//! The reader is a strict round-trip reader for the subset this writer
//! emits, not a general `.glyphs` reader and not a preserving reader for
//! arbitrary Glyphs files. Rereading a written file gives parity on glyph
//! order, contour (part) order, node coordinates and types, widths, cmap,
//! metrics, masters, instances, properties - and parity covers exactly
//! that subset.
//!
//! Strict, not lossy: every key outside the subset is a typed
//! `ParseError::Unsupported`, never silently dropped. That includes
//! semantic fields the schema defines but this subset does not carry:
//! features, classes, featurePrefixes, customParameters, settings, stems,
//! kerning groups, glyph production flags, category/script/
//! subCategory/case/direction, metric and kern bindings (metricLeft,
//! kernRight, ...), userData anywhere other than the one declared layer
//! key below, and unknown keys everywhere. A file containing any of these
//! cannot round-trip through this reader without loss, so it is refused.
//! The only tolerated extras are per-object UI display metadata with no
//! effect on outlines or the built font: DisplayStrings, date, note,
//! gridLength/gridSubDivision, master iconName/visible, glyph color/
//! lastChange/locked/note/tags, layer name/visible/color, instance
//! visible, axis hidden. Glyph sorting metadata (sortName, sortNameKeep,
//! group, groupIdx) is refused: it would reorder the displayed glyph
//! list, and glyph order is caller-owned, so dropping it would silently
//! change what an editor shows. Smooth/tangent node
//! suffixes are refused (the model has no smooth flag), node kinds match
//! exactly, duplicate dictionary keys, missing or doubled commas,
//! non-finite numbers and localized property values are typed errors, and
//! token/recursion/input budgets bound hostile files. These budgets are
//! input-size caps, not a memory or wall-clock proof. All string values
//! are written quoted, so no caller string can ever collide with the
//! lexer's number or comment tokens; dictionary keys stay bare atoms.
//! Instance OS/2 fields (weightClass, widthClass, isBold, isItalic) are
//! carried with parity as optionals: absent means the schema default.
//!
//! Kerning is carried as expanded PAIRS ONLY (kerningLTR/kerningRTL/
//! kerningVertical, nested master -> left -> right -> value in the file,
//! flat ordered lists here): no class kerning, no kernLeft/kernRight
//! group bindings, per the chief ruling that classes are used only on a
//! 1:1 engine-to-GPOS mapping (expanded pairs otherwise). Values must be
//! finite; duplicate pairs and dangling master ids are typed errors.
//! Smooth (G1) node flags are carried per layer in a sidecar
//! (`s`-suffixed tuple kinds in the file); empty sidecar means all
//! corner. Class keys (kernLeft/...) stay refused.
//!
//! The glyph `export` flag is carried (schema enum [0,1], default 1):
//! `export = 0` marks a glyph that must not ship, written and read with
//! parity.
//!
//! Stroke (part) identity is the contour order; stroke names are also
//! recorded in each layer's `userData` under `KNI.strokeNames`, the only
//! userData key this reader accepts. A malformed userData, a malformed or
//! count-mismatched strokeNames list, or any other userData key is a
//! typed error, never a silent name drop.
//!
//! Glyph order is caller data: the serializer never reorders, groups or
//! deduplicates glyphs. Grouping policy (category/script) belongs to the
//! producer, from source-backed metadata only.

use crate::model::{MasterGlyph, Op, Pt, StrokeContour};
use std::fmt;

/// userData key carrying the stroke names, so part names survive a save
/// from Glyphs itself.
pub const STROKE_NAMES_USERDATA_KEY: &str = "KNI.strokeNames";

/// One designspace axis (`axes` entry): user-facing name and OpenType tag.
#[derive(Debug, Clone, PartialEq)]
pub struct GlyphsAxis {
    pub name: String,
    pub tag: String,
}

/// One `metricValues` entry: measured offset from the baseline (`pos`) and,
/// only when measured, the overshoot (`over`).
#[derive(Debug, Clone, PartialEq)]
pub struct MetricValue {
    pub pos: f64,
    pub over: Option<f64>,
}

/// One master: identity, the style name from actual style metadata, the
/// designspace location (one value per font axis) and the vertical metric
/// values in registry order.
#[derive(Debug, Clone, PartialEq)]
pub struct GlyphsMaster {
    pub id: String,
    pub name: String,
    pub axes_values: Vec<f64>,
    pub metrics: Vec<MetricValue>,
}

/// One shape in a layer's ordered `shapes` array: a closed structural
/// stroke contour (the boolean merge stays an export-only step) or a
/// component reference to another glyph. List order is the file's z-order
/// and is preserved exactly.
#[derive(Debug, Clone, PartialEq)]
pub enum GlyphsShape {
    /// A closed path (`closed = 1`, `nodes = (...)`).
    Path(StrokeContour),
    /// A component (`ref` plus its non-default transform keys).
    Component(GlyphsComponent),
}

/// One component: a reference to another glyph's master layer. Only `ref`
/// is required by the schema ($defs/component); every transform key is
/// omitted at its schema default. `masterId` (master-specific derivation),
/// `piece` (Smart Components), `locked`, `orientation`, `keepWeight`,
/// `attr`/`userData` stay outside this subset and are refused on read.
#[derive(Debug, Clone, PartialEq)]
pub struct GlyphsComponent {
    /// Schema `ref`: the referenced glyph's name.
    pub glyph: String,
    /// Translation `(x, y)`; schema default `(0, 0)`.
    pub pos: (f64, f64),
    /// Scale `(sx, sy)`; schema default `(1, 1)`.
    pub scale: (f64, f64),
    /// Rotation in degrees clockwise; schema default `0`.
    pub angle: f64,
    /// Automatic-alignment control; schema default `Default` (key omitted).
    pub alignment: ComponentAlignment,
    /// Attachment anchor name; `None` omits the key.
    pub anchor: Option<String>,
}

/// Schema `alignment` for a component ($defs/component alignment: the enum
/// -1/0/1/3, default 0).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ComponentAlignment {
    /// `0`: alignment follows the normal eligibility rules.
    Default,
    /// `-1`: automatic positioning disabled.
    Disabled,
    /// `1`: alignment forced regardless of context.
    Forced,
    /// `3`: horizontal coordinate only.
    Horizontal,
}

impl ComponentAlignment {
    fn to_i8(self) -> i8 {
        match self {
            ComponentAlignment::Default => 0,
            ComponentAlignment::Disabled => -1,
            ComponentAlignment::Forced => 1,
            ComponentAlignment::Horizontal => 3,
        }
    }
    fn from_i8(v: f64) -> Option<Self> {
        match v {
            0.0 => Some(ComponentAlignment::Default),
            -1.0 => Some(ComponentAlignment::Disabled),
            1.0 => Some(ComponentAlignment::Forced),
            3.0 => Some(ComponentAlignment::Horizontal),
            _ => None,
        }
    }
}

/// One glyph layer: the parts of one glyph under one master. `advance` is
/// the layer width; every shape emits in order, paths unmerged.
#[derive(Debug, Clone)]
pub struct GlyphsLayer {
    pub master_id: String,
    pub advance: f64,
    pub shapes: Vec<GlyphsShape>,
    /// Construction-time provenance: the upm of the master-mode glyph the
    /// layer was built from, checked against the font upm at write time.
    /// Not file data; `None` when built by hand or read back.
    pub source_upm: Option<f64>,
    /// Smooth (G1) node flags: per Path shape (in shape order), per node
    /// tuple. Empty means all-corner (the default); a non-empty sidecar
    /// must match the Path-shape and node counts exactly. Only on-curve
    /// tuples (`l`/`c`) may be flagged; the writer emits the `s` suffix
    /// for them.
    pub smooth: Vec<Vec<bool>>,
}

/// One glyph: name, cmap entries (unicode code points) and its layers.
#[derive(Debug, Clone)]
pub struct GlyphsGlyph {
    pub name: String,
    pub unicode: Vec<u32>,
    pub layers: Vec<GlyphsLayer>,
    /// Schema `export` flag (enum [0,1], default 1): false writes
    /// `export = 0` for glyphs that must not ship (e.g. unshipped
    /// carries). Read and written with parity.
    pub export: bool,
}

/// One instance: style name, designspace location and export flag.
/// The OS/2 class and style-link fields are optional: `None` omits the
/// key, which the schema defines as its documented default (weightClass
/// 400, widthClass 5, isBold/isItalic 0); `Some` writes it, and the value
/// is validated against the schema range/enum on write and on read.
#[derive(Debug, Clone, PartialEq)]
pub struct GlyphsInstance {
    pub name: String,
    pub axes_values: Vec<f64>,
    pub exports: bool,
    /// Schema weightClass, integer 1..=1000.
    pub weight_class: Option<u16>,
    /// Schema widthClass, integer 1..=9.
    pub width_class: Option<u16>,
    /// Schema isBold, enum [0,1].
    pub is_bold: Option<bool>,
    /// Schema isItalic, enum [0,1].
    pub is_italic: Option<bool>,
}

/// One kerning pair for one direction and master. `left`/`right` are glyph
/// names or class names; class names are used only where the caller has a
/// 1:1 class structure (chief ruling), otherwise pairs arrive expanded.
/// File order is caller data and preserved.
#[derive(Debug, Clone, PartialEq)]
pub struct KerningPair {
    pub master_id: String,
    pub left: String,
    pub right: String,
    pub value: f64,
}

/// The three kerning directions the schema carries (kerningLTR,
/// kerningRTL, kerningVertical), each a flat ordered pair list. The file
/// nests them master -> left -> right; the flat list preserves the exact
/// emission order.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct GlyphsKerning {
    pub ltr: Vec<KerningPair>,
    pub rtl: Vec<KerningPair>,
    pub vertical: Vec<KerningPair>,
}

/// One font-info property (`properties` entry). Values come from the source
/// font only; an absent source value is absent here, never invented.
#[derive(Debug, Clone, PartialEq)]
pub struct GlyphsProperty {
    pub key: String,
    pub value: String,
}

/// A `.glyphs` font. All font data comes from the caller (derived from the
/// source font); the serializer invents nothing.
#[derive(Debug, Clone)]
pub struct GlyphsFont {
    pub family_name: String,
    pub upm: u32,
    /// Font version from the source. Required by the schema, so it is a
    /// required field rather than a hardcoded default.
    pub version: (u32, u32),
    /// `.appVersion` policy, caller's explicit choice. The schema marks
    /// the key required and Glyphs records the saving build there, so
    /// `Some` stamps a Glyphs build number (only honest for a file Glyphs
    /// itself saved) and `None` omits a schema-required key (the honest
    /// state for generated files; Glyphs stamps its build on first save).
    /// The two axes - schema conformance vs generator provenance - are the
    /// owner's call; the serializer takes no default.
    pub app_version: Option<String>,
    pub axes: Vec<GlyphsAxis>,
    /// Ordered metrics registry; `type` strings per the schema
    /// (`ascender`, `cap height`, `x-height`, `baseline`, `descender`, ...).
    pub metric_types: Vec<String>,
    pub masters: Vec<GlyphsMaster>,
    pub glyphs: Vec<GlyphsGlyph>,
    pub instances: Vec<GlyphsInstance>,
    pub kerning: GlyphsKerning,
    pub properties: Vec<GlyphsProperty>,
}

impl GlyphsLayer {
    /// A layer view of a master-mode glyph under `master_id`: the advance
    /// becomes the layer width and each structural stroke one shape.
    pub fn from_master_glyph(master_id: &str, glyph: &MasterGlyph) -> Self {
        GlyphsLayer {
            master_id: master_id.to_string(),
            advance: glyph.advance,
            shapes: glyph.contours.iter().cloned().map(GlyphsShape::Path).collect(),
            source_upm: Some(glyph.upm),
            smooth: Vec::new(),
        }
    }
}

/// A write that cannot represent the input faithfully is a typed error,
/// never a silently different file.
#[derive(Debug, Clone, PartialEq)]
pub enum WriteError {
    EmptyGlyphName,
    /// Subset restriction: an instance must have a non-empty style name.
    EmptyInstanceName,
    /// Subset restriction: a property must have a non-empty key.
    EmptyPropertyKey,
    /// The schema requires at least one master (fontMaster minItems 1).
    NoMasters,
    /// Schema range for weightClass is 1..=1000.
    InstanceWeightClassOutOfRange { instance: String, value: u16 },
    /// Schema range for widthClass is 1..=9.
    InstanceWidthClassOutOfRange { instance: String, value: u16 },
    /// Kerning value is not finite.
    NonFiniteKerning { master_id: String, left: String, right: String },
    /// Kerning pair with an empty glyph/class name.
    EmptyKerningName,
    /// The same (master, left, right) pair twice in one direction.
    DuplicateKerningPair { master_id: String, left: String, right: String },
    /// Smooth sidecar does not match Path-shape/node counts, or flags an
    /// off-curve node.
    SmoothSidecarMismatch { glyph: String },
    /// A component with an empty `ref` glyph name.
    EmptyComponentRef { glyph: String },
    /// A component referencing a glyph that is not in the font.
    UnknownComponentRef { glyph: String, target: String },
    /// A component with a non-finite pos/scale/angle value.
    NonFiniteComponentTransform { glyph: String, target: String },
    /// A component with an empty anchor name.
    EmptyComponentAnchor { glyph: String, target: String },
    DuplicateGlyphName(String),
    EmptyMasterName,
    DuplicateMasterId(String),
    /// A layer links to a master that is not in the font.
    UnknownMasterId(String),
    /// A master designspace location does not match the axis count.
    AxesCountMismatch { master: String },
    /// A master metric value count does not match the registry.
    MetricCountMismatch { master: String },
    /// A metric registry entry has no type.
    EmptyMetricType,
    /// A metric value has no measured position: it must not be in the
    /// registry at all, so this is a caller data error.
    NonFiniteMetric { master: String },
    NonFiniteCoordinate { glyph: String, stroke: String },
    EmptyContour { glyph: String, stroke: String },
    MoveNotFirst { glyph: String, stroke: String },
    MultipleMove { glyph: String, stroke: String },
    /// Master mode ships closed contours only; an unclosed contour would
    /// reread differently than it was written.
    OpenContour { glyph: String, stroke: String },
    /// A `Close` anywhere but the final op would silently merge subpaths
    /// on write (nodes carry no close ops).
    CloseNotFinal { glyph: String, stroke: String },
    /// Fewer than three on-curve nodes: a degenerate, area-less contour.
    TooFewSegments { glyph: String, stroke: String },
    NonFiniteAdvance { glyph: String },
    NonFiniteAxisValue { context: String },
    /// Outside the OpenType `unitsPerEm` range 16..=16384.
    UpmOutOfRange { upm: u32 },
    /// Not a Unicode scalar value (above U+10FFFF or a surrogate).
    InvalidCodepoint { glyph: String, value: u32 },
    DuplicateCodepoint { glyph: String, value: u32 },
    /// The same code point assigned to two glyphs.
    CodepointConflict { value: u32, first: String, second: String },
    EmptyMasterId,
    EmptyFamilyName,
    EmptyAxisName,
    EmptyAxisTag,
    DuplicateAxisTag { tag: String },
    /// An instance designspace location does not match the axis count.
    InstanceAxesCountMismatch { instance: String },
    DuplicateLayerForMaster { glyph: String, master_id: String },
    /// A glyph has no layer for a master of the font.
    MissingMasterLayer { glyph: String, master_id: String },
    /// A layer built from a master-mode glyph whose upm differs from the
    /// font's upm: mixed-geometry input, never scaled silently.
    UpmMismatch { glyph: String, layer_upm: f64, font_upm: u32 },
}

impl fmt::Display for WriteError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WriteError::EmptyGlyphName => write!(f, "glyph with empty name"),
            WriteError::EmptyInstanceName => write!(f, "instance with empty name"),
            WriteError::EmptyPropertyKey => write!(f, "property with empty key"),
            WriteError::NoMasters => write!(f, "font has no masters (schema: fontMaster minItems 1)"),
            WriteError::InstanceWeightClassOutOfRange { instance, value } => {
                write!(f, "weightClass {value} out of schema range 1..=1000 in instance {instance}")
            }
            WriteError::InstanceWidthClassOutOfRange { instance, value } => {
                write!(f, "widthClass {value} out of schema range 1..=9 in instance {instance}")
            }
            WriteError::NonFiniteKerning { master_id, left, right } => {
                write!(f, "non-finite kerning value in {master_id}: {left} / {right}")
            }
            WriteError::EmptyKerningName => write!(f, "kerning pair with empty glyph or class name"),
            WriteError::DuplicateKerningPair { master_id, left, right } => {
                write!(f, "duplicate kerning pair in {master_id}: {left} / {right}")
            }
            WriteError::SmoothSidecarMismatch { glyph } => {
                write!(f, "smooth sidecar does not match paths/nodes or flags an off-curve node in {glyph}")
            }
            WriteError::EmptyComponentRef { glyph } => write!(f, "component with empty ref in {glyph}"),
            WriteError::UnknownComponentRef { glyph, target } => {
                write!(f, "component in {glyph} references unknown glyph {target}")
            }
            WriteError::NonFiniteComponentTransform { glyph, target } => {
                write!(f, "non-finite component transform in {glyph} -> {target}")
            }
            WriteError::EmptyComponentAnchor { glyph, target } => {
                write!(f, "component with empty anchor in {glyph} -> {target}")
            }
            WriteError::DuplicateGlyphName(n) => write!(f, "duplicate glyph name {n}"),
            WriteError::EmptyMasterName => write!(f, "master with empty name"),
            WriteError::DuplicateMasterId(id) => write!(f, "duplicate master id {id}"),
            WriteError::UnknownMasterId(id) => write!(f, "layer links to unknown master id {id}"),
            WriteError::AxesCountMismatch { master } => write!(f, "master {master}: axesValues count does not match axes"),
            WriteError::MetricCountMismatch { master } => write!(f, "master {master}: metricValues count does not match metrics registry"),
            WriteError::EmptyMetricType => write!(f, "metrics registry entry with empty type"),
            WriteError::NonFiniteMetric { master } => write!(f, "master {master}: non-finite metric value"),
            WriteError::NonFiniteCoordinate { glyph, stroke } => write!(f, "non-finite coordinate in {glyph}/{stroke}"),
            WriteError::EmptyContour { glyph, stroke } => write!(f, "empty contour in {glyph}/{stroke}"),
            WriteError::MoveNotFirst { glyph, stroke } => write!(f, "contour does not start with a move in {glyph}/{stroke}"),
            WriteError::MultipleMove { glyph, stroke } => write!(f, "contour has more than one move in {glyph}/{stroke}"),
            WriteError::OpenContour { glyph, stroke } => write!(f, "contour is not closed in {glyph}/{stroke}"),
            WriteError::CloseNotFinal { glyph, stroke } => write!(f, "close op before the end of the contour in {glyph}/{stroke}"),
            WriteError::TooFewSegments { glyph, stroke } => write!(f, "fewer than three on-curve nodes in {glyph}/{stroke}"),
            WriteError::NonFiniteAdvance { glyph } => write!(f, "non-finite advance in {glyph}"),
            WriteError::NonFiniteAxisValue { context } => write!(f, "non-finite axis value in {context}"),
            WriteError::UpmOutOfRange { upm } => write!(f, "unitsPerEm {upm} outside 16..=16384"),
            WriteError::InvalidCodepoint { glyph, value } => write!(f, "code point {value} in {glyph} is not a Unicode scalar value"),
            WriteError::DuplicateCodepoint { glyph, value } => write!(f, "duplicate code point {value} in {glyph}"),
            WriteError::CodepointConflict { value, first, second } => write!(f, "code point {value} assigned to both {first} and {second}"),
            WriteError::EmptyMasterId => write!(f, "master with empty id"),
            WriteError::EmptyFamilyName => write!(f, "empty family name"),
            WriteError::EmptyAxisName => write!(f, "axis with empty name"),
            WriteError::EmptyAxisTag => write!(f, "axis with empty tag"),
            WriteError::DuplicateAxisTag { tag } => write!(f, "duplicate axis tag {tag}"),
            WriteError::InstanceAxesCountMismatch { instance } => write!(f, "instance {instance}: axesValues count does not match axes"),
            WriteError::DuplicateLayerForMaster { glyph, master_id } => write!(f, "glyph {glyph} has more than one layer for master {master_id}"),
            WriteError::MissingMasterLayer { glyph, master_id } => write!(f, "glyph {glyph} has no layer for master {master_id}"),
            WriteError::UpmMismatch { glyph, layer_upm, font_upm } => write!(f, "glyph {glyph}: geometry upm {layer_upm} != font upm {font_upm}"),
        }
    }
}

impl std::error::Error for WriteError {}

#[derive(Debug, Clone, PartialEq)]
pub enum ParseError {
    /// Byte position and what went wrong while tokenizing.
    Lex { pos: usize, reason: String },
    /// The plist shape is broken or a required field has the wrong type.
    Structure(String),
    MissingField(&'static str),
    /// A feature outside the emitted subset that would change the outline.
    Unsupported(String),
    /// The file parsed but fails the same semantic validation the writer
    /// enforces (duplicate glyphs, dangling master links, bad cmap, ...).
    Invalid(WriteError),
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ParseError::Lex { pos, reason } => write!(f, "lex error at byte {pos}: {reason}"),
            ParseError::Structure(r) => write!(f, "structure error: {r}"),
            ParseError::MissingField(k) => write!(f, "missing field {k}"),
            ParseError::Unsupported(w) => write!(f, "unsupported: {w}"),
            ParseError::Invalid(w) => write!(f, "invalid font: {w}"),
        }
    }
}

impl std::error::Error for ParseError {}

fn validate(font: &GlyphsFont) -> Result<(), WriteError> {
    // Schema: fontMaster has minItems 1 (glyphs-3.schema.json).
    if font.masters.is_empty() {
        return Err(WriteError::NoMasters);
    }
    if font.family_name.is_empty() {
        return Err(WriteError::EmptyFamilyName);
    }
    if !(16..=16384).contains(&font.upm) {
        return Err(WriteError::UpmOutOfRange { upm: font.upm });
    }
    for t in &font.metric_types {
        if t.is_empty() {
            return Err(WriteError::EmptyMetricType);
        }
    }
    let mut seen_tags = std::collections::HashSet::new();
    for a in &font.axes {
        if a.name.is_empty() {
            return Err(WriteError::EmptyAxisName);
        }
        if a.tag.is_empty() {
            return Err(WriteError::EmptyAxisTag);
        }
        if !seen_tags.insert(a.tag.as_str()) {
            return Err(WriteError::DuplicateAxisTag { tag: a.tag.clone() });
        }
    }
    let mut seen_ids = std::collections::HashSet::new();
    for m in &font.masters {
        if m.id.is_empty() {
            return Err(WriteError::EmptyMasterId);
        }
        if m.name.is_empty() {
            return Err(WriteError::EmptyMasterName);
        }
        if !seen_ids.insert(m.id.as_str()) {
            return Err(WriteError::DuplicateMasterId(m.id.clone()));
        }
        if m.axes_values.len() != font.axes.len() {
            return Err(WriteError::AxesCountMismatch { master: m.name.clone() });
        }
        if m.axes_values.iter().any(|v| !v.is_finite()) {
            return Err(WriteError::NonFiniteAxisValue { context: format!("master {}", m.name) });
        }
        if m.metrics.len() != font.metric_types.len() {
            return Err(WriteError::MetricCountMismatch { master: m.name.clone() });
        }
        for v in &m.metrics {
            if !v.pos.is_finite() || v.over.map(|o| !o.is_finite()).unwrap_or(false) {
                return Err(WriteError::NonFiniteMetric { master: m.name.clone() });
            }
        }
    }
    for inst in &font.instances {
        if inst.name.is_empty() {
            return Err(WriteError::EmptyInstanceName);
        }
        // Schema ranges (glyphs-3.schema.json $defs/instance).
        if let Some(w) = inst.weight_class {
            if !(1..=1000).contains(&w) {
                return Err(WriteError::InstanceWeightClassOutOfRange { instance: inst.name.clone(), value: w });
            }
        }
        if let Some(w) = inst.width_class {
            if !(1..=9).contains(&w) {
                return Err(WriteError::InstanceWidthClassOutOfRange { instance: inst.name.clone(), value: w });
            }
        }
        if inst.axes_values.len() != font.axes.len() {
            return Err(WriteError::InstanceAxesCountMismatch { instance: inst.name.clone() });
        }
        if inst.axes_values.iter().any(|v| !v.is_finite()) {
            return Err(WriteError::NonFiniteAxisValue { context: format!("instance {}", inst.name) });
        }
    }
    for p in &font.properties {
        if p.key.is_empty() {
            return Err(WriteError::EmptyPropertyKey);
        }
    }
    for pairs in [&font.kerning.ltr, &font.kerning.rtl, &font.kerning.vertical] {
        let mut seen = std::collections::HashSet::new();
        for kp in pairs {
            if kp.left.is_empty() || kp.right.is_empty() || kp.master_id.is_empty() {
                return Err(WriteError::EmptyKerningName);
            }
            if !kp.value.is_finite() {
                return Err(WriteError::NonFiniteKerning { master_id: kp.master_id.clone(), left: kp.left.clone(), right: kp.right.clone() });
            }
            if !font.masters.iter().any(|m| m.id == kp.master_id) {
                return Err(WriteError::UnknownMasterId(kp.master_id.clone()));
            }
            if !seen.insert((kp.master_id.as_str(), kp.left.as_str(), kp.right.as_str())) {
                return Err(WriteError::DuplicateKerningPair { master_id: kp.master_id.clone(), left: kp.left.clone(), right: kp.right.clone() });
            }
        }
    }
    // Linear-time dedup/conflict checks (hash sets, not nested scans).
    let mut cmap: std::collections::HashMap<u32, &str> = std::collections::HashMap::new();
    let mut seen_names = std::collections::HashSet::new();
    for g in &font.glyphs {
        if g.name.is_empty() {
            return Err(WriteError::EmptyGlyphName);
        }
        if !seen_names.insert(g.name.as_str()) {
            return Err(WriteError::DuplicateGlyphName(g.name.clone()));
        }
        let mut seen_cps = std::collections::HashSet::new();
        for &cp in &g.unicode {
            if cp > 0x10FFFF || (0xD800..=0xDFFF).contains(&cp) {
                return Err(WriteError::InvalidCodepoint { glyph: g.name.clone(), value: cp });
            }
            if !seen_cps.insert(cp) {
                return Err(WriteError::DuplicateCodepoint { glyph: g.name.clone(), value: cp });
            }
            if let Some(&first) = cmap.get(&cp) {
                return Err(WriteError::CodepointConflict { value: cp, first: first.to_string(), second: g.name.clone() });
            }
            cmap.insert(cp, &g.name);
        }
        let mut layer_masters = std::collections::HashSet::new();
        for l in &g.layers {
            if !layer_masters.insert(l.master_id.as_str()) {
                return Err(WriteError::DuplicateLayerForMaster { glyph: g.name.clone(), master_id: l.master_id.clone() });
            }
        }
        for m in &font.masters {
            if !layer_masters.contains(m.id.as_str()) {
                return Err(WriteError::MissingMasterLayer { glyph: g.name.clone(), master_id: m.id.clone() });
            }
        }
        for l in &g.layers {
            if !font.masters.iter().any(|m| m.id == l.master_id) {
                return Err(WriteError::UnknownMasterId(l.master_id.clone()));
            }
            if !l.advance.is_finite() {
                return Err(WriteError::NonFiniteAdvance { glyph: g.name.clone() });
            }
            if let Some(u) = l.source_upm {
                if u != font.upm as f64 {
                    return Err(WriteError::UpmMismatch { glyph: g.name.clone(), layer_upm: u, font_upm: font.upm });
                }
            }
            let paths: Vec<&StrokeContour> = l
                .shapes
                .iter()
                .filter_map(|s| match s {
                    GlyphsShape::Path(c) => Some(c),
                    GlyphsShape::Component(_) => None,
                })
                .collect();
            if !l.smooth.is_empty() {
                let shape_ok = l.smooth.len() == paths.len()
                    && l.smooth.iter().zip(&paths).all(|(sv, c)| {
                        let kinds = contour_nodes(c);
                        sv.len() == kinds.len()
                            && sv.iter().zip(&kinds).all(|(&f, &(_, _, k))| !f || k != "o")
                    });
                if !shape_ok {
                    return Err(WriteError::SmoothSidecarMismatch { glyph: g.name.clone() });
                }
            }
            for shape in &l.shapes {
                match shape {
                    GlyphsShape::Path(c) => check_contour(&g.name, c)?,
                    GlyphsShape::Component(cp) => {
                        if cp.glyph.is_empty() {
                            return Err(WriteError::EmptyComponentRef { glyph: g.name.clone() });
                        }
                        if !font.glyphs.iter().any(|og| og.name == cp.glyph) {
                            return Err(WriteError::UnknownComponentRef {
                                glyph: g.name.clone(),
                                target: cp.glyph.clone(),
                            });
                        }
                        let vals = [cp.pos.0, cp.pos.1, cp.scale.0, cp.scale.1, cp.angle];
                        if vals.iter().any(|v| !v.is_finite()) {
                            return Err(WriteError::NonFiniteComponentTransform {
                                glyph: g.name.clone(),
                                target: cp.glyph.clone(),
                            });
                        }
                        if let Some(a) = &cp.anchor {
                            if a.is_empty() {
                                return Err(WriteError::EmptyComponentAnchor {
                                    glyph: g.name.clone(),
                                    target: cp.glyph.clone(),
                                });
                            }
                        }
                    }
                }
            }
        }
    }
    Ok(())
}

fn check_contour(glyph: &str, c: &StrokeContour) -> Result<(), WriteError> {
    if c.ops.is_empty() {
        return Err(WriteError::EmptyContour { glyph: glyph.into(), stroke: c.stroke.clone() });
    }
    for op in &c.ops {
        let bad = match op {
            Op::Move(p) | Op::Line(p) => !p.0.is_finite() || !p.1.is_finite(),
            Op::Curve(c1, c2, p) => [c1, c2, p].iter().any(|q| !q.0.is_finite() || !q.1.is_finite()),
            Op::Close => false,
        };
        if bad {
            return Err(WriteError::NonFiniteCoordinate { glyph: glyph.into(), stroke: c.stroke.clone() });
        }
    }
    if !matches!(c.ops[0], Op::Move(_)) {
        return Err(WriteError::MoveNotFirst { glyph: glyph.into(), stroke: c.stroke.clone() });
    }
    if c.ops[1..].iter().any(|op| matches!(op, Op::Move(_))) {
        return Err(WriteError::MultipleMove { glyph: glyph.into(), stroke: c.stroke.clone() });
    }
    // Exactly one Close, at the very end: nodes carry no close ops, so a
    // mid-stream Close would silently merge two subpaths into one polygon.
    let closes = c.ops.iter().filter(|op| matches!(op, Op::Close)).count();
    if !matches!(c.ops.last(), Some(Op::Close)) {
        return Err(WriteError::OpenContour { glyph: glyph.into(), stroke: c.stroke.clone() });
    }
    if closes != 1 {
        return Err(WriteError::CloseNotFinal { glyph: glyph.into(), stroke: c.stroke.clone() });
    }
    let on_curve = c.ops.iter().filter(|op| matches!(op, Op::Move(_) | Op::Line(_) | Op::Curve(..))).count();
    if on_curve < 3 {
        return Err(WriteError::TooFewSegments { glyph: glyph.into(), stroke: c.stroke.clone() });
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// writer
// ---------------------------------------------------------------------------

/// Serialize `font` as a `.formatVersion = 3` Glyphs file. Shapes are
/// written in stroke order with `closed = 1`; no geometry is merged, moved
/// or snapped. Keys are alphabetical inside each dictionary, matching how
/// Glyphs saves.
pub fn write(font: &GlyphsFont) -> Result<String, WriteError> {
    validate(font)?;
    let mut o = String::new();
    o.push_str("{\n");
    if let Some(av) = &font.app_version {
        o.push_str(&format!(".appVersion = {};\n", plist_string(av)));
    }
    o.push_str(".formatVersion = 3;\n");
    if !font.axes.is_empty() {
        o.push_str("axes = (\n");
        for (i, a) in font.axes.iter().enumerate() {
            let comma = if i + 1 < font.axes.len() { "," } else { "" };
            o.push_str("{\n");
            o.push_str(&format!("name = {};\n", plist_string(&a.name)));
            o.push_str(&format!("tag = {};\n", plist_string(&a.tag)));
            o.push_str(&format!("}}{}\n", comma));
        }
        o.push_str(");\n");
    }
    o.push_str(&format!("familyName = {};\n", plist_string(&font.family_name)));
    o.push_str("fontMaster = (\n");
    for (i, m) in font.masters.iter().enumerate() {
        let comma = if i + 1 < font.masters.len() { "," } else { "" };
        o.push_str("{\n");
        if !m.axes_values.is_empty() {
            o.push_str("axesValues = (");
            for (j, v) in m.axes_values.iter().enumerate() {
                let c = if j + 1 < m.axes_values.len() { "," } else { "" };
                o.push_str(&format!("{}{}", fmt_num(*v), c));
            }
            o.push_str(");\n");
        }
        o.push_str(&format!("id = {};\n", plist_string(&m.id)));
        if !m.metrics.is_empty() {
            o.push_str("metricValues = (\n");
            for (j, v) in m.metrics.iter().enumerate() {
                let c = if j + 1 < m.metrics.len() { "," } else { "" };
                o.push_str("{\n");
                if let Some(over) = v.over {
                    o.push_str(&format!("over = {};\n", fmt_num(over)));
                }
                o.push_str(&format!("pos = {};\n", fmt_num(v.pos)));
                o.push_str(&format!("}}{}\n", c));
            }
            o.push_str(");\n");
        }
        o.push_str(&format!("name = {};\n", plist_string(&m.name)));
        o.push_str(&format!("}}{}\n", comma));
    }
    o.push_str(");\n");
    o.push_str("glyphs = (\n");
    for (i, g) in font.glyphs.iter().enumerate() {
        let comma = if i + 1 < font.glyphs.len() { "," } else { "" };
        o.push_str("{\n");
        o.push_str(&format!("glyphname = {};\n", plist_string(&g.name)));
        if !g.layers.is_empty() {
            o.push_str("layers = (\n");
            for (j, l) in g.layers.iter().enumerate() {
                let c = if j + 1 < g.layers.len() { "," } else { "" };
                write_layer(&mut o, l);
                o.push_str(&format!("}}{}\n", c));
            }
            o.push_str(");\n");
        }
        match g.unicode.len() {
            0 => {}
            1 => o.push_str(&format!("unicode = {};\n", g.unicode[0])),
            _ => {
                let u: Vec<String> = g.unicode.iter().map(|c| c.to_string()).collect();
                o.push_str(&format!("unicode = ({});\n", u.join(",")));
            }
        }
        if !g.export {
            o.push_str("export = 0;\n");
        }
        o.push_str(&format!("}}{}\n", comma));
    }
    o.push_str(");\n");
    if !font.instances.is_empty() {
        o.push_str("instances = (\n");
        for (i, inst) in font.instances.iter().enumerate() {
            let comma = if i + 1 < font.instances.len() { "," } else { "" };
            o.push_str("{\n");
            o.push_str("axesValues = (");
            for (j, v) in inst.axes_values.iter().enumerate() {
                let c = if j + 1 < inst.axes_values.len() { "," } else { "" };
                o.push_str(&format!("{}{}", fmt_num(*v), c));
            }
            o.push_str(");\n");
            if !inst.exports {
                o.push_str("exports = 0;\n");
            }
            if let Some(w) = inst.weight_class {
                o.push_str(&format!("weightClass = {};\n", w));
            }
            if let Some(w) = inst.width_class {
                o.push_str(&format!("widthClass = {};\n", w));
            }
            if let Some(b) = inst.is_bold {
                o.push_str(&format!("isBold = {};\n", b as u8));
            }
            if let Some(b) = inst.is_italic {
                o.push_str(&format!("isItalic = {};\n", b as u8));
            }
            o.push_str(&format!("name = {};\n", plist_string(&inst.name)));
            o.push_str(&format!("}}{}\n", comma));
        }
        o.push_str(");\n");
    }
    for (key, pairs) in [("kerningLTR", &font.kerning.ltr), ("kerningRTL", &font.kerning.rtl), ("kerningVertical", &font.kerning.vertical)] {
        if pairs.is_empty() {
            continue;
        }
        // Nest master -> left -> right in first-seen order (file order is
        // caller data). Pairs only: names are production glyph names.
        let mut order: Vec<(&str, Vec<(&str, Vec<(&str, f64)>)>)> = Vec::new();
        for kp in pairs {
            let mi = match order.iter().position(|(id, _)| *id == kp.master_id) {
                Some(i) => i,
                None => {
                    order.push((&kp.master_id, Vec::new()));
                    order.len() - 1
                }
            };
            let lefts = &mut order[mi].1;
            let li = match lefts.iter().position(|(id, _)| *id == kp.left) {
                Some(i) => i,
                None => {
                    lefts.push((&kp.left, Vec::new()));
                    lefts.len() - 1
                }
            };
            lefts[li].1.push((&kp.right, kp.value));
        }
        o.push_str(&format!("{key} = {{\n"));
        for (mid, lefts) in &order {
            o.push_str(&format!("{} = {{\n", plist_string(mid)));
            for (left, rights) in lefts {
                o.push_str(&format!("{} = {{\n", plist_string(left)));
                for (right, value) in rights {
                    o.push_str(&format!("{} = {};\n", plist_string(right), fmt_num(*value)));
                }
                o.push_str("};\n");
            }
            o.push_str("};\n");
        }
        o.push_str("};\n");
    }
    if !font.metric_types.is_empty() {
        o.push_str("metrics = (\n");
        for (i, t) in font.metric_types.iter().enumerate() {
            let comma = if i + 1 < font.metric_types.len() { "," } else { "" };
            o.push_str("{\n");
            o.push_str(&format!("type = {};\n", plist_string(t)));
            o.push_str(&format!("}}{}\n", comma));
        }
        o.push_str(");\n");
    }
    if !font.properties.is_empty() {
        o.push_str("properties = (\n");
        for (i, p) in font.properties.iter().enumerate() {
            let comma = if i + 1 < font.properties.len() { "," } else { "" };
            o.push_str("{\n");
            o.push_str(&format!("key = {};\n", plist_string(&p.key)));
            o.push_str(&format!("value = {};\n", plist_string(&p.value)));
            o.push_str(&format!("}}{}\n", comma));
        }
        o.push_str(");\n");
    }
    o.push_str(&format!("unitsPerEm = {};\n", font.upm));
    o.push_str(&format!("versionMajor = {};\n", font.version.0));
    o.push_str(&format!("versionMinor = {};\n", font.version.1));
    o.push_str("}\n");
    Ok(o)
}

fn write_layer(o: &mut String, l: &GlyphsLayer) {
    o.push_str("{\n");
    o.push_str(&format!("layerId = {};\n", plist_string(&l.master_id)));
    if !l.shapes.is_empty() {
        o.push_str("shapes = (\n");
        let mut path_idx = 0usize;
        for (i, shape) in l.shapes.iter().enumerate() {
            let comma = if i + 1 < l.shapes.len() { "," } else { "" };
            match shape {
                GlyphsShape::Path(c) => {
                    o.push_str("{\n");
                    o.push_str("closed = 1;\n");
                    o.push_str("nodes = (\n");
                    let nodes = contour_nodes(c);
                    let empty: Vec<bool> = Vec::new();
                    let smooth = l.smooth.get(path_idx).unwrap_or(&empty);
                    path_idx += 1;
                    for (j, (x, y, kind)) in nodes.iter().enumerate() {
                        let c2 = if j + 1 < nodes.len() { "," } else { "" };
                        // Smooth on-curve nodes carry the `s` suffix (schema
                        // node kind `ls`/`cs`); off-curve nodes are never
                        // flagged (validated at write).
                        let s = if smooth.get(j).copied().unwrap_or(false) { "s" } else { "" };
                        o.push_str(&format!("({},{},{}{}){}\n", fmt_num(*x), fmt_num(*y), kind, s, c2));
                    }
                    o.push_str(");\n");
                    o.push_str(&format!("}}{}\n", comma));
                }
                GlyphsShape::Component(cp) => {
                    // Schema $defs/component: only `ref` is required; every
                    // transform key is omitted at its schema default.
                    o.push_str("{\n");
                    o.push_str(&format!("ref = {};\n", plist_string(&cp.glyph)));
                    if cp.pos != (0.0, 0.0) {
                        o.push_str(&format!("pos = ({},{});\n", fmt_num(cp.pos.0), fmt_num(cp.pos.1)));
                    }
                    if cp.scale != (1.0, 1.0) {
                        o.push_str(&format!("scale = ({},{});\n", fmt_num(cp.scale.0), fmt_num(cp.scale.1)));
                    }
                    if cp.angle != 0.0 {
                        o.push_str(&format!("angle = {};\n", fmt_num(cp.angle)));
                    }
                    if cp.alignment != ComponentAlignment::Default {
                        o.push_str(&format!("alignment = {};\n", cp.alignment.to_i8()));
                    }
                    if let Some(a) = &cp.anchor {
                        o.push_str(&format!("anchor = {};\n", plist_string(a)));
                    }
                    o.push_str(&format!("}}{}\n", comma));
                }
            }
        }
        o.push_str(");\n");
    }
    o.push_str("userData = {\n");
    o.push_str(&format!("{} = (\n", plist_string(STROKE_NAMES_USERDATA_KEY)));
    let strokes: Vec<&str> = l
        .shapes
        .iter()
        .filter_map(|s| match s {
            GlyphsShape::Path(c) => Some(c.stroke.as_str()),
            GlyphsShape::Component(_) => None,
        })
        .collect();
    for (i, name) in strokes.iter().enumerate() {
        let comma = if i + 1 < strokes.len() { "," } else { "" };
        o.push_str(&format!("{}{}\n", plist_string(name), comma));
    }
    o.push_str(");\n");
    o.push_str("};\n");
    o.push_str(&format!("width = {};\n", fmt_num(l.advance)));
}

/// Flatten one validated contour to Glyphs nodes: the move is the first
/// on-curve node (`l`), a cubic segment is two `o` nodes and a `c` node, a
/// line segment is an `l` node.
fn contour_nodes(c: &StrokeContour) -> Vec<(f64, f64, &'static str)> {
    let mut nodes = Vec::new();
    for op in &c.ops {
        match op {
            Op::Move(p) | Op::Line(p) => nodes.push((p.0, p.1, "l")),
            Op::Curve(c1, c2, p) => {
                nodes.push((c1.0, c1.1, "o"));
                nodes.push((c2.0, c2.1, "o"));
                nodes.push((p.0, p.1, "c"));
            }
            Op::Close => {}
        }
    }
    nodes
}

/// Shortest round-trip spelling: integers without a decimal point,
/// fractions in Rust's shortest round-trip form; `-0` normalized to `0`.
/// (Glyphs itself saves floats with up to five decimals; the file format
/// takes any float literal, and exact round-trip matters here.)
fn fmt_num(v: f64) -> String {
    let v = if v == 0.0 { 0.0 } else { v };
    if v.fract() == 0.0 && v.abs() < 9.0e15 {
        format!("{}", v as i64)
    } else {
        format!("{v}")
    }
}

/// Writes a string always quoted. No caller string can collide with the
/// lexer's number or comment tokens, and escaping is total (`\UXXXX` for
/// controls), so any string round-trips byte-exact.
fn plist_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            '\r' => out.push_str("\\r"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\U{:04X}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}
// ---------------------------------------------------------------------------
// reader
// ---------------------------------------------------------------------------

/// Parse a `.glyphs` file (the subset `write` emits) back into a
/// `GlyphsFont`.
/// Largest input the reader processes (256 MiB).
pub const MAX_INPUT_BYTES: usize = 256 << 20;
/// Token budget for one file.
/// Lexical DoS bound: at most one token per input byte, the grammar's
/// densest legal packing (e.g. `()`), so lexing can never refuse a file
/// the input cap accepted. Allocation scales with input size, never with
/// a fixed token count (absolute memory still depends on host RAM).
/// (A fixed token count would be a size assumption: the writer can emit
/// legitimate files - e.g. CJK-scale fonts - whose token count exceeds
/// any fixed cap.)
/// Deepest dictionary/array nesting accepted.
pub const MAX_DEPTH: usize = 128;

pub fn read(text: &str) -> Result<GlyphsFont, ParseError> {
    if text.len() > MAX_INPUT_BYTES {
        return Err(ParseError::Unsupported(format!("input larger than {MAX_INPUT_BYTES} bytes")));
    }
    let toks = lex(text)?;
    let mut p = Parser { toks: &toks, pos: 0, depth: 0 };
    let v = p.value()?;
    p.finish()?;
    let font = font_from_value(&v)?;
    validate(&font).map_err(ParseError::Invalid)?;
    Ok(font)
}

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    LBrace,
    RBrace,
    LParen,
    RParen,
    Eq,
    Semi,
    Comma,
    Atom(String),
    Str(String),
    Num(f64),
}

fn lex(text: &str) -> Result<Vec<Tok>, ParseError> {
    // The budget is derived from the input: at most one token per input
    // byte, the grammar's densest legal packing (e.g. `()`). Lexing can
    // never refuse a file the input byte cap accepted; allocation scales
    // with input size, never with a fixed token count (absolute memory
    // still depends on host RAM).
    lex_with_budget(text, text.len())
}

fn lex_with_budget(text: &str, max_tokens: usize) -> Result<Vec<Tok>, ParseError> {
    let b = text.as_bytes();
    let mut toks = Vec::new();
    let mut i = 0;
    let err = |pos: usize, reason: &str| ParseError::Lex { pos, reason: reason.to_string() };
    while i < b.len() {
        let c = b[i];
        if toks.len() >= max_tokens {
            return Err(err(i, "token budget exceeded"));
        }
        match c {
            b' ' | b'\t' | b'\n' | b'\r' => i += 1,
            b'/' if b.get(i + 1) == Some(&b'/') => {
                while i < b.len() && b[i] != b'\n' {
                    i += 1;
                }
            }
            b'/' if b.get(i + 1) == Some(&b'*') => {
                let start = i;
                i += 2;
                while i + 1 < b.len() && !(b[i] == b'*' && b[i + 1] == b'/') {
                    i += 1;
                }
                if i + 1 >= b.len() {
                    return Err(err(start, "unterminated block comment"));
                }
                i += 2;
            }
            b'{' => {
                toks.push(Tok::LBrace);
                i += 1;
            }

            b'}' => {
                toks.push(Tok::RBrace);
                i += 1;
            }
            b'(' => {
                toks.push(Tok::LParen);
                i += 1;
            }
            b')' => {
                toks.push(Tok::RParen);
                i += 1;
            }
            b'=' => {
                toks.push(Tok::Eq);
                i += 1;
            }
            b';' => {
                toks.push(Tok::Semi);
                i += 1;
            }
            b',' => {
                toks.push(Tok::Comma);
                i += 1;
            }
            b'"' => {
                let start = i;
                i += 1;
                let mut s = String::new();
                loop {
                    let c = *b.get(i).ok_or_else(|| err(start, "unterminated string"))?;
                    match c {
                        b'"' => {
                            i += 1;
                            break;
                        }
                        b'\\' => {
                            i += 1;
                            let e = *b.get(i).ok_or_else(|| err(start, "unterminated escape"))?;
                            match e {
                                b'"' => s.push('"'),
                                b'\\' => s.push('\\'),
                                b'n' => s.push('\n'),
                                b't' => s.push('\t'),
                                b'r' => s.push('\r'),
                                b'U' => {
                                    let hex = b.get(i + 1..i + 5).ok_or_else(|| err(i, "short \\U escape"))?;
                                    let hex = std::str::from_utf8(hex).map_err(|_| err(i, "bad \\U escape"))?;
                                    let cp = u32::from_str_radix(hex, 16).map_err(|_| err(i, "bad \\U escape"))?;
                                    s.push(char::from_u32(cp).ok_or_else(|| err(i, "bad \\U code point"))?);
                                    i += 4;
                                }
                                _ => return Err(err(i, "unknown escape")),
                            }
                            i += 1;
                        }
                        _ => {
                            let ch_len = utf8_len(c);
                            let end = i + ch_len;
                            let chunk = text.get(i..end).ok_or_else(|| err(i, "bad utf-8"))?;
                            s.push_str(chunk);
                            i = end;
                        }
                    }
                }
                toks.push(Tok::Str(s));
            }
            _ => {
                let start = i;
                while i < b.len() && !matches!(b[i], b' ' | b'\t' | b'\n' | b'\r' | b'{' | b'}' | b'(' | b')' | b'=' | b';' | b',' | b'"') {
                    i += 1;
                }
                let word = &text[start..i];
                // `nan`/`inf` spellings parse as floats but are not numbers
                // in this format: keep them atoms so a numeric context
                // fails with a typed structure error instead of accepting
                // a non-finite coordinate or width.
                match word.parse::<f64>() {
                    Ok(v) if v.is_finite() => toks.push(Tok::Num(v)),
                    _ => toks.push(Tok::Atom(word.to_string())),
                }
            }
        }
    }
    Ok(toks)
}

fn utf8_len(first: u8) -> usize {
    if first < 0x80 {
        1
    } else if first < 0xE0 {
        2
    } else if first < 0xF0 {
        3
    } else {
        4
    }
}

#[derive(Debug, Clone, PartialEq)]
enum Value {
    Dict(Vec<(String, Value)>),
    Array(Vec<Value>),
    Str(String),
    Num(f64),
}

struct Parser<'a> {
    toks: &'a [Tok],
    pos: usize,
    depth: usize,
}

impl<'a> Parser<'a> {
    fn peek(&self) -> Option<&Tok> {
        self.toks.get(self.pos)
    }

    fn next(&mut self) -> Result<Tok, ParseError> {
        let t = self.toks.get(self.pos).cloned().ok_or_else(|| ParseError::Structure("unexpected end of input".into()))?;
        self.pos += 1;
        Ok(t)
    }

    fn expect(&mut self, want: Tok) -> Result<(), ParseError> {
        let got = self.next()?;
        if got == want {
            Ok(())
        } else {
            Err(ParseError::Structure(format!("expected {want:?}, got {got:?}")))
        }
    }

    fn value(&mut self) -> Result<Value, ParseError> {
        match self.next()? {
            Tok::LBrace => {
                self.depth += 1;
                if self.depth > MAX_DEPTH {
                    return Err(ParseError::Structure("nesting deeper than budget".into()));
                }
                let mut entries: Vec<(String, Value)> = Vec::new();
                let mut seen = std::collections::HashSet::new();
                loop {
                    match self.next()? {
                        Tok::RBrace => {
                            self.depth -= 1;
                            return Ok(Value::Dict(entries));
                        }
                        Tok::Atom(k) | Tok::Str(k) => {
                            if !seen.insert(k.clone()) {
                                return Err(ParseError::Structure(format!("duplicate key {k}")));
                            }
                            self.expect(Tok::Eq)?;
                            let v = self.value()?;
                            self.expect(Tok::Semi)?;
                            entries.push((k, v));
                        }
                        t => return Err(ParseError::Structure(format!("expected dict key, got {t:?}"))),
                    }
                }
            }
            Tok::LParen => {
                self.depth += 1;
                if self.depth > MAX_DEPTH {
                    return Err(ParseError::Structure("nesting deeper than budget".into()));
                }
                let mut items = Vec::new();
                // Strict comma separation: a value must be followed by a
                // comma or the closing paren; a trailing comma is allowed
                // once, missing or doubled commas are not.
                loop {
                    match self.peek() {
                        Some(Tok::RParen) => {
                            self.pos += 1;
                            self.depth -= 1;
                            return Ok(Value::Array(items));
                        }
                        Some(_) => {
                            items.push(self.value()?);
                            match self.next()? {
                                Tok::Comma => {
                                    if matches!(self.peek(), Some(Tok::RParen)) {
                                        self.pos += 1;
                                        self.depth -= 1;
                                        return Ok(Value::Array(items));
                                    }
                                }
                                Tok::RParen => {
                                    self.depth -= 1;
                                    return Ok(Value::Array(items));
                                }
                                t => return Err(ParseError::Structure(format!("expected comma or closing paren, got {t:?}"))),
                            }
                        }
                        None => return Err(ParseError::Structure("unexpected end of input in array".into())),
                    }
                }
            }
            Tok::Atom(s) | Tok::Str(s) => Ok(Value::Str(s)),
            Tok::Num(v) => Ok(Value::Num(v)),
            t => Err(ParseError::Structure(format!("unexpected token {t:?}"))),
        }
    }

    fn finish(&self) -> Result<(), ParseError> {
        if self.pos == self.toks.len() {
            Ok(())
        } else {
            Err(ParseError::Structure("trailing tokens after root value".into()))
        }
    }
}

impl Value {
    fn as_dict(&self) -> Result<&[(String, Value)], ParseError> {
        match self {
            Value::Dict(d) => Ok(d),
            _ => Err(ParseError::Structure("expected dict".into())),
        }
    }

    fn as_array(&self) -> Result<&[Value], ParseError> {
        match self {
            Value::Array(a) => Ok(a),
            _ => Err(ParseError::Structure("expected array".into())),
        }
    }

    fn as_str(&self) -> Result<&str, ParseError> {
        match self {
            Value::Str(s) => Ok(s),
            _ => Err(ParseError::Structure("expected string".into())),
        }
    }

    fn as_num(&self) -> Result<f64, ParseError> {
        match self {
            Value::Num(v) => Ok(*v),
            _ => Err(ParseError::Structure("expected number".into())),
        }
    }
}

/// Refuse any key outside the parsed set and the documented tolerated set
/// (inert display/metadata keys Glyphs may add on save). Anything else -
/// anchors, components, shape attributes, transforms, kerning, stems -
/// would change geometry or data this model does not represent, so it is a
/// typed error, never a silent drop.
fn refuse_unknown(dict: &[(String, Value)], ctx: &str, allowed: &[&str], tolerated: &[&str]) -> Result<(), ParseError> {
    for (k, _) in dict {
        if !allowed.contains(&k.as_str()) && !tolerated.contains(&k.as_str()) {
            return Err(ParseError::Unsupported(format!("key {k} in {ctx}")));
        }
    }
    Ok(())
}

// Tolerated extras are per-object UI display metadata only - nothing that
// changes outlines, naming, kerning, exports or variation behavior.
const ROOT_TOLERATED: &[&str] = &[".appVersion", "DisplayStrings", "date", "note", "gridLength", "gridSubDivision"];
const MASTER_TOLERATED: &[&str] = &["iconName", "visible"];
// sortName/sortNameKeep/group/groupIdx would reorder the displayed glyph
// list; with caller-owned order they are refused, not dropped.
const GLYPH_TOLERATED: &[&str] = &["color", "lastChange", "locked", "note", "tags"];
const LAYER_TOLERATED: &[&str] = &["name", "visible", "color"];
const INSTANCE_TOLERATED: &[&str] = &["visible"];

fn field<'a>(dict: &'a [(String, Value)], key: &str) -> Option<&'a Value> {
    dict.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

fn required<'a>(dict: &'a [(String, Value)], key: &'static str) -> Result<&'a Value, ParseError> {
    field(dict, key).ok_or(ParseError::MissingField(key))
}

fn num_to_u32(v: &Value, key: &str) -> Result<u32, ParseError> {
    let n = v.as_num()?;
    if n.fract() != 0.0 || n < 0.0 || n > u32::MAX as f64 {
        return Err(ParseError::Structure(format!("{key} is not a non-negative integer")));
    }
    Ok(n as u32)
}
// ---------------------------------------------------------------------------
// reader: value tree to GlyphsFont
// ---------------------------------------------------------------------------

fn font_from_value(v: &Value) -> Result<GlyphsFont, ParseError> {
    let root = v.as_dict()?;
    refuse_unknown(
        root,
        "font",
        &[".formatVersion", "familyName", "fontMaster", "glyphs", "unitsPerEm", "versionMajor", "versionMinor", "axes", "metrics", "instances", "properties", "kerningLTR", "kerningRTL", "kerningVertical"],
        ROOT_TOLERATED,
    )?;
    match field(root, ".formatVersion") {
        Some(fv) => match fv.as_num()? {
            3.0 => {}
            other => return Err(ParseError::Unsupported(format!(".formatVersion {other}"))),
        },
        None => return Err(ParseError::Unsupported("missing .formatVersion (format 1/2 file)".into())),
    }
    let upm = num_to_u32(required(root, "unitsPerEm")?, "unitsPerEm")?;
    let version = (
        num_to_u32(required(root, "versionMajor")?, "versionMajor")?,
        num_to_u32(required(root, "versionMinor")?, "versionMinor")?,
    );
    let app_version = match field(root, ".appVersion") {
        Some(v) => Some(v.as_str()?.to_string()),
        None => None,
    };
    let family_name = required(root, "familyName")?.as_str()?.to_string();
    let mut axes = Vec::new();
    if let Some(av) = field(root, "axes") {
        for a in av.as_array()? {
            let a = a.as_dict()?;
            refuse_unknown(a, "axis", &["name", "tag"], &["hidden"])?;
            axes.push(GlyphsAxis {
                name: field(a, "name").map(|v| v.as_str()).transpose()?.unwrap_or("").to_string(),
                tag: field(a, "tag").map(|v| v.as_str()).transpose()?.unwrap_or("").to_string(),
            });
        }
    }
    let mut metric_types = Vec::new();
    if let Some(mv) = field(root, "metrics") {
        for m in mv.as_array()? {
            let m = m.as_dict()?;
            refuse_unknown(m, "metric", &["type"], &[])?;
            let t = field(m, "type").map(|v| v.as_str()).transpose()?.unwrap_or("");
            metric_types.push(t.to_string());
        }
    }
    let mut masters = Vec::new();
    for mv in required(root, "fontMaster")?.as_array()? {
        masters.push(master_from_value(mv)?);
    }
    let mut glyphs = Vec::new();
    for gv in required(root, "glyphs")?.as_array()? {
        glyphs.push(glyph_from_value(gv)?);
    }
    let mut instances = Vec::new();
    if let Some(iv) = field(root, "instances") {
        for i in iv.as_array()? {
            let i = i.as_dict()?;
            refuse_unknown(i, "instance", &["name", "axesValues", "exports", "weightClass", "widthClass", "isBold", "isItalic"], INSTANCE_TOLERATED)?;
            instances.push(GlyphsInstance {
                name: field(i, "name").map(|v| v.as_str()).transpose()?.unwrap_or("").to_string(),
                axes_values: match field(i, "axesValues") {
                    Some(v) => v.as_array()?.iter().map(|n| n.as_num()).collect::<Result<Vec<_>, _>>()?,
                    None => Vec::new(),
                },
                exports: match field(i, "exports") {
                    // Schema enum [0,1], default 1.
                    None => true,
                    Some(v) => match v.as_num()? {
                        0.0 => false,
                        1.0 => true,
                        other => return Err(ParseError::Structure(format!("exports must be 0 or 1, got {other}"))),
                    },
                },
                // Schema ranges/enums ($defs/instance): weightClass
                // 1..=1000, widthClass 1..=9, isBold/isItalic enum [0,1].
                weight_class: match field(i, "weightClass") {
                    None => None,
                    Some(v) => {
                        let n = num_to_u32(v, "weightClass")?;
                        if !(1..=1000).contains(&n) {
                            return Err(ParseError::Structure(format!("weightClass {n} out of schema range 1..=1000")));
                        }
                        Some(n as u16)
                    }
                },
                width_class: match field(i, "widthClass") {
                    None => None,
                    Some(v) => {
                        let n = num_to_u32(v, "widthClass")?;
                        if !(1..=9).contains(&n) {
                            return Err(ParseError::Structure(format!("widthClass {n} out of schema range 1..=9")));
                        }
                        Some(n as u16)
                    }
                },
                is_bold: bool01_field(i, "isBold")?,
                is_italic: bool01_field(i, "isItalic")?,
            });
        }
    }
    let mut properties = Vec::new();
    if let Some(pv) = field(root, "properties") {
        for p in pv.as_array()? {
            let p = p.as_dict()?;
            // Schema ($defs/infoProperty): either {key, value} with both
            // required, or {key, values:[{language, value}]} localized.
            refuse_unknown(p, "property", &["key", "value", "values"], &[])?;
            if field(p, "values").is_some() {
                // Localized values are outside the emitted subset: font-info
                // preservation for them is not established, so refuse loudly.
                return Err(ParseError::Unsupported("localized property values".into()));
            }
            let key = required(p, "key")?.as_str()?.to_string();
            let value = required(p, "value")?.as_str()?.to_string();
            properties.push(GlyphsProperty { key, value });
        }
    }
    let kerning = GlyphsKerning {
        ltr: kerning_from_value(field(root, "kerningLTR"))?,
        rtl: kerning_from_value(field(root, "kerningRTL"))?,
        vertical: kerning_from_value(field(root, "kerningVertical"))?,
    };
    Ok(GlyphsFont { family_name, upm, version, app_version, axes, metric_types, masters, glyphs, instances, kerning, properties })
}

fn master_from_value(v: &Value) -> Result<GlyphsMaster, ParseError> {
    let m = v.as_dict()?;
    refuse_unknown(m, "master", &["id", "name", "axesValues", "metricValues"], MASTER_TOLERATED)?;
    let mut axes_values = Vec::new();
    if let Some(av) = field(m, "axesValues") {
        for n in av.as_array()? {
            axes_values.push(n.as_num()?);
        }
    }
    let mut metrics = Vec::new();
    if let Some(mv) = field(m, "metricValues") {
        for e in mv.as_array()? {
            let e = e.as_dict()?;
            refuse_unknown(e, "metricValue", &["pos", "over"], &[])?;
            metrics.push(MetricValue {
                // Schema $defs/metricStore documents default 0 for both pos
                // and over (glyphs-3.schema.json), so an absent pos reads
                // as the schema default, not an invented one.
                pos: match field(e, "pos") {
                    Some(v) => v.as_num()?,
                    None => 0.0,
                },
                over: match field(e, "over") {
                    Some(v) => Some(v.as_num()?),
                    None => None,
                },
            });
        }
    }
    Ok(GlyphsMaster {
        id: required(m, "id")?.as_str()?.to_string(),
        name: field(m, "name").map(|v| v.as_str()).transpose()?.unwrap_or("").to_string(),
        axes_values,
        metrics,
    })
}

fn glyph_from_value(v: &Value) -> Result<GlyphsGlyph, ParseError> {
    let g = v.as_dict()?;
    refuse_unknown(g, "glyph", &["glyphname", "layers", "unicode", "export"], GLYPH_TOLERATED)?;
    let name = required(g, "glyphname")?.as_str()?.to_string();
    let unicode = match field(g, "unicode") {
        None => Vec::new(),
        Some(Value::Num(_)) => vec![num_to_u32(field(g, "unicode").expect("checked"), "unicode")?],
        Some(Value::Array(items)) => {
            let mut out = Vec::new();
            for u in items {
                out.push(num_to_u32(u, "unicode")?);
            }
            out
        }
        Some(_) => return Err(ParseError::Structure("unicode is neither a number nor an array".into())),
    };
    let mut layers = Vec::new();
    if let Some(lv) = field(g, "layers") {
        for l in lv.as_array()? {
            layers.push(layer_from_value(&name, l)?);
        }
    }
    // Schema `export`: integer enum [0,1], default 1.
    let export = match field(g, "export") {
        None => true,
        Some(v) => match v.as_num()? {
            0.0 => false,
            1.0 => true,
            other => return Err(ParseError::Structure(format!("export must be 0 or 1, got {other} in glyph {name}"))),
        },
    };
    Ok(GlyphsGlyph { name, unicode, layers, export })
}

fn layer_from_value(glyph: &str, v: &Value) -> Result<GlyphsLayer, ParseError> {
    let l = v.as_dict()?;
    refuse_unknown(l, "layer", &["layerId", "shapes", "paths", "width", "userData"], LAYER_TOLERATED)?;
    let master_id = required(l, "layerId")?.as_str()?.to_string();
    let advance = required(l, "width")?.as_num()?;
    let mut shapes_out: Vec<GlyphsShape> = Vec::new();
    // `shapes` is the v3/v4 key; `paths` is the v2/legacy key Glyphs still
    // reads. Both keys at once is ambiguous, never a choice. A shape dict
    // with `ref` is a component ($defs/component), otherwise a path.
    let shapes = match (field(l, "shapes"), field(l, "paths")) {
        (Some(_), Some(_)) => return Err(ParseError::Structure(format!("layer has both shapes and paths in glyph {glyph}"))),
        (Some(s), None) => Some(s),
        (None, p) => p,
    };
    let mut smooth_all: Vec<Vec<bool>> = Vec::new();
    if let Some(items) = shapes {
        for pv in items.as_array()? {
            let d = pv.as_dict()?;
            if field(d, "ref").is_some() {
                shapes_out.push(GlyphsShape::Component(component_from_value(glyph, d)?));
            } else {
                let (c, sm) = path_from_value(glyph, d)?;
                shapes_out.push(GlyphsShape::Path(c));
                smooth_all.push(sm);
            }
        }
    }
    // Sidecar convention: empty means all-corner.
    let smooth = if smooth_all.iter().flatten().any(|&f| f) { smooth_all } else { Vec::new() };
    let path_count = shapes_out.iter().filter(|s| matches!(s, GlyphsShape::Path(_))).count();
    if let Some(names) = stroke_names(l)? {
        if names.len() != path_count {
            // A hand edit desynchronized the list: loud, never a silent
            // drop of all part names.
            return Err(ParseError::Structure(format!(
                "{} count {} does not match path count {} in glyph {glyph}",
                STROKE_NAMES_USERDATA_KEY,
                names.len(),
                path_count
            )));
        }
        let mut paths = shapes_out.iter_mut().filter_map(|s| match s {
            GlyphsShape::Path(c) => Some(c),
            GlyphsShape::Component(_) => None,
        });
        for n in names {
            if let Some(c) = paths.next() {
                c.stroke = n;
            }
        }
    }
    Ok(GlyphsLayer { master_id, advance, shapes: shapes_out, source_upm: None, smooth })
}

/// Reads a component shape dict ($defs/component). Only `ref` is required
/// by the schema; transform keys take their schema defaults when absent.
/// Keys outside the subset (attr, keepWeight, locked, masterId,
/// orientation, piece, userData) are a typed refusal.
fn component_from_value(glyph: &str, d: &[(String, Value)]) -> Result<GlyphsComponent, ParseError> {
    refuse_unknown(d, "component", &["ref", "pos", "scale", "angle", "alignment", "anchor"], &[])?;
    let target = required(d, "ref")?.as_str()?.to_string();
    if target.is_empty() {
        return Err(ParseError::Structure(format!("empty component ref in glyph {glyph}")));
    }
    let pair = |key: &str, default: (f64, f64)| -> Result<(f64, f64), ParseError> {
        match field(d, key) {
            None => Ok(default),
            Some(v) => {
                let items = v.as_array()?;
                if items.len() != 2 {
                    return Err(ParseError::Structure(format!(
                        "component {key} must be an array of 2 numbers in glyph {glyph}"
                    )));
                }
                Ok((items[0].as_num()?, items[1].as_num()?))
            }
        }
    };
    let pos = pair("pos", (0.0, 0.0))?;
    let scale = pair("scale", (1.0, 1.0))?;
    let angle = field(d, "angle").map(|v| v.as_num()).transpose()?.unwrap_or(0.0);
    let alignment = match field(d, "alignment") {
        None => ComponentAlignment::Default,
        Some(v) => ComponentAlignment::from_i8(v.as_num()?).ok_or_else(|| {
            ParseError::Structure(format!("component alignment must be one of -1/0/1/3 in glyph {glyph}"))
        })?,
    };
    let anchor = match field(d, "anchor") {
        None => None,
        Some(v) => {
            let a = v.as_str()?.to_string();
            if a.is_empty() {
                return Err(ParseError::Structure(format!("empty component anchor in glyph {glyph}")));
            }
            Some(a)
        }
    };
    Ok(GlyphsComponent { glyph: target, pos, scale, angle, alignment, anchor })
}

/// Reads one schema kerning direction ({ master = { left = { right =
/// value } } }) into a flat ordered pair list; file order is preserved.
/// Every level must be a dictionary and the leaf a number.
fn kerning_from_value(v: Option<&Value>) -> Result<Vec<KerningPair>, ParseError> {
    let mut out = Vec::new();
    let Some(v) = v else { return Ok(out) };
    for (master_id, lefts) in v.as_dict()? {
        for (left, rights) in lefts.as_dict()? {
            for (right, value) in rights.as_dict()? {
                out.push(KerningPair {
                    master_id: master_id.clone(),
                    left: left.clone(),
                    right: right.clone(),
                    value: value.as_num()?,
                });
            }
        }
    }
    Ok(out)
}

/// Reads an optional schema enum-[0,1] integer as a bool; any other value
/// is a schema violation, not "nonzero means true".
fn bool01_field(d: &[(String, Value)], key: &str) -> Result<Option<bool>, ParseError> {
    match field(d, key) {
        None => Ok(None),
        Some(v) => match v.as_num()? {
            0.0 => Ok(Some(false)),
            1.0 => Ok(Some(true)),
            other => Err(ParseError::Structure(format!("{key} must be 0 or 1, got {other}"))),
        },
    }
}

/// Reads the declared layer userData key. Absent userData is fine; a
/// malformed one, a malformed strokeNames list, or any other userData key
/// is a typed error - never a silent drop of part names.
fn stroke_names(l: &[(String, Value)]) -> Result<Option<Vec<String>>, ParseError> {
    let Some(udv) = field(l, "userData") else { return Ok(None) };
    let ud = udv.as_dict().map_err(|_| ParseError::Structure("userData is not a dictionary".into()))?;
    let mut out = None;
    for (k, v) in ud {
        if k != STROKE_NAMES_USERDATA_KEY {
            return Err(ParseError::Unsupported(format!("unknown userData key {k}")));
        }
        let names = v.as_array().map_err(|_| ParseError::Structure(format!("{STROKE_NAMES_USERDATA_KEY} is not an array")))?;
        let mut list = Vec::new();
        for n in names {
            list.push(n.as_str().map_err(|_| ParseError::Structure(format!("{STROKE_NAMES_USERDATA_KEY} has a non-string entry")))?.to_string());
        }
        out = Some(list);
    }
    Ok(out)
}

fn path_from_value(glyph: &str, p: &[(String, Value)]) -> Result<(StrokeContour, Vec<bool>), ParseError> {
    refuse_unknown(p, "path", &["closed", "nodes"], &[])?;
    // `closed` is a required key in the schema (GlyphsFileFormatv4, path);
    // absence is not defaulted here, it is reported.
    // The schema enum is exactly 0 or 1 ($defs/path closed: enum [0,1]);
    // any other number is a schema violation, not "nonzero means true".
    match required(p, "closed")?.as_num()? {
        0.0 => return Err(ParseError::Unsupported(format!("open path in glyph {glyph}"))),
        1.0 => {}
        other => {
            return Err(ParseError::Structure(format!(
                "closed must be 0 or 1, got {other} in glyph {glyph}"
            )))
        }
    }
    let nodes = required(p, "nodes")?.as_array()?;
    if nodes.is_empty() {
        return Err(ParseError::Structure(format!("empty path in glyph {glyph}")));
    }
    let mut ops = Vec::new();
    let mut smooth = Vec::new();
    let mut pending: Vec<Pt> = Vec::new();
    for (i, nv) in nodes.iter().enumerate() {
        let items = nv.as_array()?;
        if items.len() != 3 {
            // Node attributes (4th tuple item) are outside the subset.
            return Err(ParseError::Unsupported(format!("node without exactly 3 items in glyph {glyph}")));
        }
        let pt = (items[0].as_num()?, items[1].as_num()?);
        // Exact kind match: smooth/tangent suffixes and the quadratic,
        // quartic, Hobby and spiral types are all outside the subset.
        let kind = items[2].as_str()?;
        // The `s` suffix marks a smooth (G1) on-curve node, carried in the
        // layer's smooth sidecar. Off-curve nodes are never smooth.
        let (base, flag) = match kind.strip_suffix('s') {
            Some("o") | None if kind == "os" => {
                return Err(ParseError::Unsupported(format!("smooth off-curve node in glyph {glyph}")))
            }
            Some(b) => (b, true),
            None => (kind, false),
        };
        smooth.push(flag);
        match base {
            "l" => {
                if !pending.is_empty() {
                    return Err(ParseError::Structure(format!("dangling off-curve nodes before a line node in glyph {glyph}")));
                }
                ops.push(if i == 0 { Op::Move(pt) } else { Op::Line(pt) });
            }
            "c" => {
                if pending.len() != 2 {
                    return Err(ParseError::Structure(format!("curve node without two off-curve nodes in glyph {glyph}")));
                }
                let (c1, c2) = (pending[0], pending[1]);
                pending.clear();
                if i == 0 {
                    ops.push(Op::Move(pt));
                } else {
                    ops.push(Op::Curve(c1, c2, pt));
                }
            }
            "o" => {
                if i == 0 {
                    return Err(ParseError::Structure(format!("path starts with an off-curve node in glyph {glyph}")));
                }
                pending.push(pt);
            }
            "m" => {
                if i != 0 {
                    return Err(ParseError::Structure(format!("move node mid-path in glyph {glyph}")));
                }
                ops.push(Op::Move(pt));
            }
            other => return Err(ParseError::Unsupported(format!("node type {other} in glyph {glyph}"))),
        }
    }
    if !pending.is_empty() {
        return Err(ParseError::Structure(format!("path ends with dangling off-curve nodes in glyph {glyph}")));
    }
    ops.push(Op::Close);
    Ok((StrokeContour { stroke: String::new(), ops }, smooth))
}

// ---------------------------------------------------------------------------
// parity
// ---------------------------------------------------------------------------

/// Compare a font against its reread twin. Every difference is one
/// human-readable line; an empty result is exact parity: glyph order,
/// contour (part) order, node coordinates and types, widths, cmap,
/// metrics, masters, axes, instances and properties all equal.
pub fn parity_errors(expected: &GlyphsFont, got: &GlyphsFont) -> Vec<String> {
    let mut out = Vec::new();
    if expected.family_name != got.family_name {
        out.push(format!("familyName: {:?} vs {:?}", expected.family_name, got.family_name));
    }
    if expected.upm != got.upm {
        out.push(format!("unitsPerEm: {} vs {}", expected.upm, got.upm));
    }
    if expected.version != got.version {
        out.push(format!("version: {:?} vs {:?}", expected.version, got.version));
    }
    if expected.app_version != got.app_version {
        out.push(format!(".appVersion: {:?} vs {:?}", expected.app_version, got.app_version));
    }
    if expected.axes != got.axes {
        out.push(format!("axes: {:?} vs {:?}", expected.axes, got.axes));
    }
    if expected.metric_types != got.metric_types {
        out.push(format!("metrics registry: {:?} vs {:?}", expected.metric_types, got.metric_types));
    }
    if expected.masters != got.masters {
        out.push(format!("masters: {:?} vs {:?}", expected.masters, got.masters));
    }
    if expected.instances != got.instances {
        out.push(format!("instances: {:?} vs {:?}", expected.instances, got.instances));
    }
    if expected.kerning != got.kerning {
        out.push(format!("kerning: {:?} vs {:?}", expected.kerning, got.kerning));
    }
    if expected.properties != got.properties {
        out.push(format!("properties: {:?} vs {:?}", expected.properties, got.properties));
    }
    if expected.glyphs.len() != got.glyphs.len() {
        out.push(format!("glyphs: {} vs {}", expected.glyphs.len(), got.glyphs.len()));
    }
    for (i, (a, b)) in expected.glyphs.iter().zip(&got.glyphs).enumerate() {
        glyph_parity(i, a, b, &mut out);
    }
    out
}

fn glyph_parity(i: usize, a: &GlyphsGlyph, b: &GlyphsGlyph, out: &mut Vec<String>) {
    if a.name != b.name {
        out.push(format!("glyph {i}: name {:?} vs {:?}", a.name, b.name));
    }
    let (mut ua, mut ub) = (a.unicode.clone(), b.unicode.clone());
    ua.sort_unstable();
    ub.sort_unstable();
    if ua != ub {
        out.push(format!("glyph {}: cmap {:?} vs {:?}", a.name, ua, ub));
    }
    if a.layers.len() != b.layers.len() {
        out.push(format!("glyph {}: layers {} vs {}", a.name, a.layers.len(), b.layers.len()));
    }
    for (j, (la, lb)) in a.layers.iter().zip(&b.layers).enumerate() {
        if la.master_id != lb.master_id {
            out.push(format!("glyph {} layer {j}: master {:?} vs {:?}", a.name, la.master_id, lb.master_id));
        }
        if la.advance != lb.advance {
            out.push(format!("glyph {} layer {j}: width {} vs {}", a.name, la.advance, lb.advance));
        }
        if la.shapes.len() != lb.shapes.len() {
            out.push(format!("glyph {} layer {j}: shapes {} vs {}", a.name, la.shapes.len(), lb.shapes.len()));
        }
        for (k, (sa, sb)) in la.shapes.iter().zip(&lb.shapes).enumerate() {
            match (sa, sb) {
                (GlyphsShape::Path(ca), GlyphsShape::Path(cb)) => {
                    if ca.stroke != cb.stroke {
                        out.push(format!("glyph {} layer {j} shape {k}: stroke {:?} vs {:?}", a.name, ca.stroke, cb.stroke));
                    }
                    if ca.ops != cb.ops {
                        out.push(format!("glyph {} layer {j} shape {k} ({}): ops differ", a.name, ca.stroke));
                    }
                }
                (GlyphsShape::Component(ca), GlyphsShape::Component(cb)) => {
                    if ca != cb {
                        out.push(format!("glyph {} layer {j} shape {k}: component {:?} vs {:?}", a.name, ca, cb));
                    }
                }
                _ => out.push(format!("glyph {} layer {j} shape {k}: kind differs (path vs component)", a.name)),
            }
        }
        // The sidecar's empty-means-all-corner convention compares the
        // effective flags, not the stored vec shape.
        let eff = |l: &GlyphsLayer| -> Vec<Vec<bool>> {
            if l.smooth.is_empty() {
                l.shapes
                    .iter()
                    .filter_map(|s| match s {
                        GlyphsShape::Path(c) => Some(vec![false; contour_nodes(c).len()]),
                        GlyphsShape::Component(_) => None,
                    })
                    .collect()
            } else {
                l.smooth.clone()
            }
        };
        if eff(la) != eff(lb) {
            out.push(format!("glyph {} layer {j}: smooth flags differ", a.name));
        }
    }
}

#[cfg(test)]
mod budget_tests {
    use super::*;

    /// Pins the input-derived token budget convention: the lexer accepts
    /// one token per input byte (the grammar's densest legal packing), so
    /// a large-but-legal file is never refused by a fixed count, and any
    /// budget below the byte length is a typed refusal.
    #[test]
    fn token_budget_scales_with_input_bytes() {
        // `()` is the densest packing: 2 tokens in 2 bytes. A budget equal
        // to the byte length accepts it exactly.
        assert_eq!(lex_with_budget("()", 2).unwrap().len(), 2);
        // Below the byte length: typed refusal, not a silent cap.
        assert!(matches!(lex_with_budget("()", 1), Err(ParseError::Lex { .. })));
        // The convention scales: a long dense input with budget == bytes
        // lexes fully (a fixed cap, e.g. the old 8_000_000, cannot be
        // expressed as a byte-derived budget for small inputs like this).
        let big = "()".repeat(10_000);
        assert_eq!(lex_with_budget(&big, big.len()).unwrap().len(), 20_000);
        assert!(matches!(lex_with_budget(&big, 8_000), Err(ParseError::Lex { .. })));
        // The public reader derives its budget from the input length: a
        // small dense file reads without tripping any fixed count.
        let text = "{
.formatVersion = 3;
familyName = \"t\";
fontMaster = ({
id = \"m01\";
name = \"R\";
metricValues = ();
});
glyphs = ();
unitsPerEm = 1000;
versionMajor = 1;
versionMinor = 0;
}
";
        assert!(read(text).is_ok(), "small dense file reads: {:?}", read(text).err());
    }

    /// N ~ 1M dense pairs lex to exactly 2N tokens under a byte-derived
    /// budget - the convention holds at real scale, not just on toys.
    #[test]
    fn dense_million_pairs_token_count_exact() {
        let big = "()".repeat(1_000_000);
        let toks = lex_with_budget(&big, big.len()).expect("byte-derived budget accepts");
        assert_eq!(toks.len(), 2_000_000, "exactly 2 tokens per () pair");
    }

    /// The byte cap fires before lexing and with its own reason - an
    /// over-cap input is never misreported as a token-budget refusal.
    #[test]
    fn over_byte_cap_refused_with_byte_reason_not_token_reason() {
        let big = "a".repeat(MAX_INPUT_BYTES + 1);
        match read(&big) {
            Err(ParseError::Unsupported(m)) => {
                assert!(m.contains("bytes"), "byte-cap reason: {m}");
                assert!(!m.contains("token"), "never the token reason: {m}");
            }
            other => panic!("expected Unsupported byte-cap refusal, got {:?}", other.map(|f| f.glyphs.len())),
        }
    }
}

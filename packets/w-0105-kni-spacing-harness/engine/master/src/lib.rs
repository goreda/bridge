//! kni-master: master-mode outline model + binding drawing-standard checkers.
//!
//! Reference: the master-mode drawing standard (docs/research), a
//! binding specification for master-mode design work. The master drawing decomposes a glyph into one contour per
//! structural stroke with free overlap; counters travel inside their parent
//! stroke as a band wrap; node architecture/economy is the primary axis:
//! four node roles (extrema, corner, junction, wrap), zero collinear
//! midpoints, zero nodes at covered seams, zero curves in straight strokes,
//! visible geometry identical to the intended export outline.
//!
//! This crate lands the model + the measurable v0.2 rule checkers, locked
//! against the reference R fixture. The export merge (boolean union of the
//! stroke contours) is the next slice; its interface is declared here and
//! intentionally not yet implemented.

pub mod model;
pub mod check;
pub mod compat;
pub mod validate;
pub mod raster;
pub mod fixture;
pub mod vector;
pub mod otf;
pub mod vector_rows;

mod glyf;

pub mod vector_font_rows;

pub mod decompose;
pub mod parts_plug;
pub mod glyphs;
pub mod glyphdata;
pub mod glyphsfile;
pub mod glyphs_file;
pub mod version;

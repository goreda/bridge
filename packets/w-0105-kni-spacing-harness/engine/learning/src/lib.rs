//! Organic learning store: add-only, pinned, schema-checked.
//!
//! The store carries form knowledge (feature key -> outcome distribution), never
//! values, glyph names, coordinates or kern numbers. It is a data artifact that the
//! engine reads; nothing learned is compiled in. If the store is absent, empty or
//! invalid the reader returns `Loaded::Cold` and the engine keeps its current
//! measurement path unchanged.
//!
//! File format (UTF-8 text, one record per line, tab separated):
//!   line 1:  `KNI-LEARN<TAB>schema=<n><TAB>fields=<f1,f2,...>`   (allowed key fields)
//!   record:  `R<TAB>key=<f=v;f=v><TAB>n=<u>,sum=<hexbits>,sumsq=<hexbits><TAB>prov=<...><TAB>chain=<sha256>`
//! `chain` = sha256(previous chain || record body), so any edit or deletion of an
//! earlier line breaks every later link (append-only is verifiable).

pub mod gate;
pub mod prior;
pub mod sha256;
pub mod store;

pub use prior::{leave_font_out, Cell, FontReport, Priors, Unseen};
pub use store::{Loaded, Obs, Provenance, Store, StoreError};

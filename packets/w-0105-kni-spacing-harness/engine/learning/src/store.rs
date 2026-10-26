use crate::sha256::sha256_hex;
use std::collections::BTreeMap;

const MAGIC: &str = "KNI-LEARN";
const GENESIS: &str = "genesis";

#[derive(Debug, Clone, PartialEq)]
pub enum StoreError {
    Io(String),
    Format(String),
    ForbiddenField(String),
    UnknownField(String),
    ChainBroken(usize),
    PinMismatch { expected: String, actual: String },
    Uncertified,
}

/// Where an observation came from. `session_k` and its two inputs are provenance only.
#[derive(Debug, Clone, PartialEq)]
pub struct Provenance {
    pub font_id: String, // opaque hash, never a family name
    pub run_id: String,
    pub receipt_id: String,
    pub tested_sha: String,
    pub declared_cap_u: f64,
    pub measured_cap_px: f64,
    pub certified: bool, // escape_gen PASS tier
}

impl Provenance {
    pub fn session_k(&self) -> f64 {
        self.declared_cap_u / self.measured_cap_px
    }
}

/// One feature observation. `key` is (field, bucket label) pairs; `outcomes` are
/// already font-normalized by the session K (font units, not pixels).
#[derive(Debug, Clone, PartialEq)]
pub struct Obs {
    pub key: Vec<(String, String)>,
    pub n: u64,
    pub sum: f64,
    pub sumsq: f64,
    pub prov: Provenance,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Store {
    pub schema: u32,
    pub allowed_fields: Vec<String>,
    pub records: Vec<Obs>,
    chain: Vec<String>,
}

pub enum Loaded {
    Warm(Store),
    /// Missing, empty or invalid store: engine runs its current path, unchanged.
    Cold(String),
}

/// Field names that may never appear as key fields: the store must not carry glyph
/// identity, coordinates or kern values. Matched as substrings, case-insensitive.
pub fn forbidden(name: &str) -> bool {
    const BANNED: [&str; 6] = ["glyph", "name", "coord", "kern", "unicode", "codepoint"];
    let l = name.to_ascii_lowercase();
    BANNED.iter().any(|b| l.contains(b))
}

fn esc(s: &str) -> String {
    s.replace('%', "%25").replace('\t', "%09").replace('\n', "%0A").replace(';', "%3B").replace('=', "%3D").replace(',', "%2C")
}
fn unesc(s: &str) -> String {
    s.replace("%2C", ",").replace("%3D", "=").replace("%3B", ";").replace("%0A", "\n").replace("%09", "\t").replace("%25", "%")
}
fn hexbits(x: f64) -> String {
    format!("{:016x}", x.to_bits())
}
fn unhex(s: &str) -> Result<f64, StoreError> {
    u64::from_str_radix(s, 16).map(f64::from_bits).map_err(|_| StoreError::Format(format!("bad float bits {s}")))
}

impl Store {
    pub fn new(schema: u32, allowed_fields: &[&str]) -> Result<Store, StoreError> {
        for f in allowed_fields {
            if forbidden(f) {
                return Err(StoreError::ForbiddenField(f.to_string()));
            }
        }
        Ok(Store { schema, allowed_fields: allowed_fields.iter().map(|s| s.to_string()).collect(), records: vec![], chain: vec![] })
    }

    fn header(&self) -> String {
        format!("{MAGIC}\tschema={}\tfields={}", self.schema, self.allowed_fields.join(","))
    }

    fn body(o: &Obs) -> String {
        let key: Vec<String> = o.key.iter().map(|(f, v)| format!("{}={}", esc(f), esc(v))).collect();
        let p = &o.prov;
        let prov = [
            esc(&p.font_id), esc(&p.run_id), esc(&p.receipt_id), esc(&p.tested_sha),
            hexbits(p.declared_cap_u), hexbits(p.measured_cap_px), (p.certified as u8).to_string(),
        ]
        .join(",");
        format!("R\tkey={}\tn={},sum={},sumsq={}\tprov={}", key.join(";"), o.n, hexbits(o.sum), hexbits(o.sumsq), prov)
    }

    fn check(&self, o: &Obs) -> Result<(), StoreError> {
        if !o.prov.certified {
            return Err(StoreError::Uncertified);
        }
        for (f, _) in &o.key {
            if forbidden(f) {
                return Err(StoreError::ForbiddenField(f.clone()));
            }
            if !self.allowed_fields.contains(f) {
                return Err(StoreError::UnknownField(f.clone()));
            }
        }
        Ok(())
    }

    /// Add-only: appends a record. No edit or delete API exists.
    pub fn append(&mut self, o: Obs) -> Result<(), StoreError> {
        self.check(&o)?;
        let prev = self.chain.last().cloned().unwrap_or_else(|| sha256_hex(GENESIS.as_bytes()));
        let link = sha256_hex(format!("{prev}{}", Self::body(&o)).as_bytes());
        self.chain.push(link);
        self.records.push(o);
        Ok(())
    }

    pub fn serialize(&self) -> String {
        let mut s = self.header();
        s.push('\n');
        for (o, c) in self.records.iter().zip(&self.chain) {
            s.push_str(&Self::body(o));
            s.push_str("\tchain=");
            s.push_str(c);
            s.push('\n');
        }
        s
    }

    /// sha256 of the serialized bytes: the pin to record in the receipt.
    pub fn pin(&self) -> (String, usize) {
        let s = self.serialize();
        (sha256_hex(s.as_bytes()), s.len())
    }

    pub fn parse(text: &str) -> Result<Store, StoreError> {
        let mut lines = text.lines();
        let h = lines.next().ok_or_else(|| StoreError::Format("empty".into()))?;
        let hp: Vec<&str> = h.split('\t').collect();
        if hp.len() != 3 || hp[0] != MAGIC {
            return Err(StoreError::Format("bad header".into()));
        }
        let schema = hp[1].strip_prefix("schema=").and_then(|v| v.parse().ok()).ok_or_else(|| StoreError::Format("bad schema".into()))?;
        let fields: Vec<&str> = hp[2].strip_prefix("fields=").ok_or_else(|| StoreError::Format("bad fields".into()))?.split(',').filter(|f| !f.is_empty()).collect();
        let mut st = Store::new(schema, &fields)?;
        for (i, line) in lines.enumerate() {
            let p: Vec<&str> = line.split('\t').collect();
            if p.len() != 5 || p[0] != "R" {
                return Err(StoreError::Format(format!("bad record line {}", i + 2)));
            }
            fn kv<'a>(s: &str, x: &'a str) -> Result<&'a str, StoreError> {
                x.strip_prefix(s).ok_or_else(|| StoreError::Format(format!("missing {s}")))
            }
            let key_s = kv("key=", p[1])?;
            let mut key = vec![];
            for part in key_s.split(';').filter(|x| !x.is_empty()) {
                let (f, v) = part.split_once('=').ok_or_else(|| StoreError::Format("bad key".into()))?;
                key.push((unesc(f), unesc(v)));
            }
            let out: BTreeMap<&str, &str> = p[2].split(',').filter_map(|x| x.split_once('=')).collect();
            let n = out.get("n").and_then(|v| v.parse().ok()).ok_or_else(|| StoreError::Format("bad n".into()))?;
            let sum = unhex(out.get("sum").ok_or_else(|| StoreError::Format("no sum".into()))?)?;
            let sumsq = unhex(out.get("sumsq").ok_or_else(|| StoreError::Format("no sumsq".into()))?)?;
            let pv: Vec<&str> = kv("prov=", p[3])?.split(',').collect();
            if pv.len() != 7 {
                return Err(StoreError::Format("bad prov".into()));
            }
            let prov = Provenance {
                font_id: unesc(pv[0]), run_id: unesc(pv[1]), receipt_id: unesc(pv[2]), tested_sha: unesc(pv[3]),
                declared_cap_u: unhex(pv[4])?, measured_cap_px: unhex(pv[5])?, certified: pv[6] == "1",
            };
            let want = kv("chain=", p[4])?.to_string();
            let o = Obs { key, n, sum, sumsq, prov };
            st.append(o)?;
            if st.chain.last() != Some(&want) {
                return Err(StoreError::ChainBroken(i + 2));
            }
        }
        Ok(st)
    }

    /// Reader: verifies the pin when one is supplied. Any problem yields `Cold`.
    pub fn load(path: &str, pin_sha256: Option<&str>) -> Loaded {
        let bytes = match std::fs::read(path) {
            Ok(b) => b,
            Err(e) => return Loaded::Cold(format!("absent: {e}")),
        };
        if bytes.is_empty() {
            return Loaded::Cold("empty".into());
        }
        if let Some(p) = pin_sha256 {
            let actual = sha256_hex(&bytes);
            if actual != p {
                return Loaded::Cold(format!("{:?}", StoreError::PinMismatch { expected: p.into(), actual }));
            }
        }
        match String::from_utf8(bytes).map_err(|_| StoreError::Format("not utf8".into())).and_then(|t| Store::parse(&t)) {
            Ok(s) if s.records.is_empty() => Loaded::Cold("no records".into()),
            Ok(s) => Loaded::Warm(s),
            Err(e) => Loaded::Cold(format!("{e:?}")),
        }
    }

    pub fn save_new(&self, path: &str) -> Result<(), StoreError> {
        std::fs::write(path, self.serialize()).map_err(|e| StoreError::Io(e.to_string()))
    }

    /// Append-only persistence: refuses unless the file on disk is a strict prefix
    /// of the new serialization.
    pub fn save_append(&self, path: &str) -> Result<(), StoreError> {
        let new = self.serialize();
        if let Ok(old) = std::fs::read_to_string(path) {
            if !new.starts_with(&old) {
                return Err(StoreError::ChainBroken(0));
            }
        }
        std::fs::write(path, new).map_err(|e| StoreError::Io(e.to_string()))
    }
}

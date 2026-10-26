//! OPEN wire-format proposal helpers, not a record codec or canonical preimage.
//! No hash is computed. No record schema, exclusion or freeze is enforced here.

/// Numeric codes proposed in input 54218854; not an adopted domain registry.
#[derive(Clone, Copy, Debug)]
#[repr(u16)]
pub enum ProposedDomain {
    Candidate = 0x0001,
    Assessment = 0x0002,
    CanonicalCore = 0x0003,
    Receipt = 0x0004,
    Evidence = 0x0005,
    RepresentationDecision = 0x0006,
    RuleApplication = 0x0007,
    DraftContour = 0x0008,
    MetricRecord = 0x0009,
    HypothesisSet = 0x000a,
    LossReceipt = 0x000b,
    ReplayRecord = 0x000c,
}

#[derive(Clone, Debug)]
pub enum DraftEncodingError {
    LengthExceedsU32,
}

/// Bytes are experimental fragments, never a canonical record or proof.
#[derive(Clone, Debug)]
pub struct DraftFragment {
    bytes: Vec<u8>,
}

impl DraftFragment {
    pub fn proposed_header(domain: ProposedDomain, version: u16) -> Self {
        let mut bytes = b"KNI1".to_vec();
        bytes.extend_from_slice(&(domain as u16).to_le_bytes());
        bytes.extend_from_slice(&version.to_le_bytes());
        Self { bytes }
    }

    pub fn append_u16(&mut self, value: u16) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    pub fn append_u32(&mut self, value: u32) {
        self.bytes.extend_from_slice(&value.to_le_bytes());
    }

    /// Preserves all original bits, including NaN, infinity and signed zero.
    /// This is raw evidence encoding, NOT accepted finite geometry encoding.
    pub fn append_original_binary64_bits(&mut self, bits: u64) {
        self.bytes.extend_from_slice(&bits.to_le_bytes());
    }

    /// Proposed UTF-8/u32 framing. Rejects length overflow before mutation.
    pub fn append_utf8(&mut self, value: &str) -> Result<(), DraftEncodingError> {
        let length = u32::try_from(value.len())
            .map_err(|_| DraftEncodingError::LengthExceedsU32)?;
        self.append_u32(length);
        self.bytes.extend_from_slice(value.as_bytes());
        Ok(())
    }

    /// A proposed presence marker only, not encoding of an optional payload.
    pub fn append_presence_marker(&mut self, present: bool) {
        self.bytes.push(u8::from(present));
    }

    pub fn as_experimental_bytes(&self) -> &[u8] {
        &self.bytes
    }
}

/// Digest and preimage are distinct storage claims. Neither is verified.
#[derive(Clone, Debug)]
pub struct ClaimedHashMaterial {
    pub algorithm_label: String,
    pub experimental_preimage: Vec<u8>,
    pub claimed_digest: Vec<u8>,
    pub schema_revision_ref: String,
    pub exclusion_rule_ref: String,
}

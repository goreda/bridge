"""Contract stub only; solver must implement BRIEF.md unit. Not a delivered implementation."""
def build(source_sha256, frame, lsb_add, rsb_add, declaration_pin):
    raise NotImplementedError("solver implementation required")

def bind_manifest(text, receipt, expected_source, expected_frame):
    raise NotImplementedError("solver implementation required")

def verify_geometry(before, after, receipt):
    raise NotImplementedError("solver implementation required")


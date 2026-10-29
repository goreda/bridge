"""Solver replaces stub. No receipt/file may supply its own trust.
qualify(prediction, context, trusted_policies) -> {status:'accepted'|'abstained', codepoint:int|None, reason:str}
prediction: {source_sha256,crop_sha256,model_sha256,preprocess_sha256,char,confidence,rejected,pack_refused}
context: {source_sha256,crop_sha256,boundary_qualified:bool,boundary_evidence_pin,policy_pin}
trusted_policies: caller-supplied dict policy_pin->{model_sha256,preprocess_sha256,eligible_classes:list[str],threshold:float}
Only program-supplied trusted_policies can authorize a tier. Threshold is prequalified input, NEVER chosen here.
Malformed input returns typed abstention. No network/files/global trust. No owner data.
"""
def qualify(prediction,context,trusted_policies):
    return dict(status='abstained',codepoint=None,reason='reference_stub_not_implementation')

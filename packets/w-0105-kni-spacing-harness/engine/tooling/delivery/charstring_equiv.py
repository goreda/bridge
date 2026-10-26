"""Compare an audited charstring with the charstring stored in the final font.

The font writer may re-encode numbers (for example a 16-bit integer operand
becomes a one-byte operand) without changing the drawing program. The audit
therefore binds to the decoded program (operators and operands), and the final
charstring byte hash is recorded separately by the callers.
"""
from fontTools.misc.psCharStrings import T2CharString


def decoded_program(data):
    cs = T2CharString(bytecode=bytes(data))
    cs.decompile()
    return list(cs.program)


def same_program(audit_hex, final_bytes):
    try:
        return decoded_program(bytes.fromhex(audit_hex)) == decoded_program(final_bytes)
    except Exception:
        return False

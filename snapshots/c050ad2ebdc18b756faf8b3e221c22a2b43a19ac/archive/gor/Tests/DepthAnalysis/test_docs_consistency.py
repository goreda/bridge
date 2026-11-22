"""Doc consistency pins (R2AH 04:50): CONTRACT-190v.md and CACHE-FORMAT.md must
describe the current Mac depth container (.dzc), legacy HEVC reference format,
10-bit value semantics and current private-owner licence scope.
Grep pins, so a stale edit fails loudly instead of silently drifting."""
import os

DOCS = os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis")


def read(name):
    with open(os.path.join(DOCS, name)) as f:
        return f.read()


def main():
    contract = read("CONTRACT-190v.md")
    fmt = read("CACHE-FORMAT.md")

    # no stale container/format tokens anywhere in either doc
    stale = ["depth_shot_NNNNN.mkv", "depth_shot_{i:05d}.mkv",
             "depth.hevc", "Matroska", "matroska"]
    for tok in stale:
        assert tok not in contract, ("CONTRACT", tok)
        assert tok not in fmt, ("CACHE-FORMAT", tok)

    # fp16 as a DEPTH STORAGE/pixel format stays forbidden (lossy depth);
    # fp16 as CoreML COMPUTE precision is the s13 c1-c3 decision and allowed.
    # Scope the pin to lossy-depth phrasings, not the bare token.
    lossy_fp16 = ["fp16 depth", "fp16-depth", "fp16 luma", "fp16 plane",
                  "fp16 storage", "depth fp16", "fp16 pixel", "fp16 w10",
                  "half-precision depth", "depth in fp16", "depth as fp16"]
    for tok in lossy_fp16:
        assert tok.lower() not in contract.lower(), ("CONTRACT", tok)
        assert tok.lower() not in fmt.lower(), ("CACHE-FORMAT", tok)

    # required format pins in BOTH docs (whitespace-insensitive)
    import re
    squash = lambda t: re.sub(r"\s+", "", t)
    pins = ["depth_shot_NNNNN.mp4", "source_shot_NNNNN.mp4", "yuv420p10le",
            "Main10", "video_full_range_flag", "w10/1023*1024", "source_width",
            "render-ready.json", "depth_ready"]
    for tok in pins:
        assert squash(tok) in squash(contract), ("CONTRACT missing", tok)
        assert squash(tok) in squash(fmt), ("CACHE-FORMAT missing", tok)

    # Licence status: ratified private-owner scope only; NC exclusions intact.
    for doc, name in ((contract, "CONTRACT"), (fmt, "CACHE-FORMAT")):
        assert "owner's private Mac build ONLY" in doc.replace("\n", " "), name
        assert "distribution beyond the owner's Mac" in doc.replace("\n", " "), name
        assert "pending the architect ruling" not in doc.replace("\n", " "), name
        assert "CC-BY-NC" in doc, name
    # Current Mac depth container must not disappear behind the legacy section.
    for doc in (contract,fmt):
        assert '.dzc' in doc and 'GORDZ001' in doc and 'GORDZEND' in doc
        assert 'LZFSE' in doc or 'lzfse' in doc
    # withdrawn exclusion wording must not survive in CACHE-FORMAT
    assert "no redistribution licence" not in fmt, "stale exclusion rationale"
    assert "resolve-iw3 NOTICE" not in fmt, "stale exclusion rationale"

    # the value-mapping sentence is identical in both docs (single semantics)
    mapping = "v=w10/1023*1024"
    assert mapping in squash(contract) and mapping in squash(fmt)
    print("PASS docs consistency: mp4/Main10/full-range pins, no stale tokens, "
          "licence status current")


if __name__ == "__main__":
    main()

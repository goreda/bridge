# GOR-GENERIC-198O-01..04: non-P23 generic research exercises, revision2

Published generic research tasks. These are fresh algorithm/emitter exercises, not P23 stock, not byte-equality against any live/private emitter, not an integration contract. No private code, data, names or links are needed. Lab defines no new template: the exact templates below are frozen inputs. Each emitted file is UTF-8, LF only, no BOM, exactly one final LF. Replace only the bracketed token with its canonical number. Do not include the Markdown fence. Literal ASCII spaces and line breaks are significant.

Common interface: a decimal JSON string parameter, parsed as a base10 decimal, finite and in the stated closed domain. Reject missing, empty, malformed,NaN/infinity and out-of-domain input with typed `invalidParameter`, no GLSL output. Canonical output is decimal fixed6fractional places, round-half-even from the exact decimal string, negative zero normalized to0.000000, ASCII dot. Do not round through binary floating point before canonicalizing. CPU formula tests may use Double with absolute tolerance1e-6. One portable independent reference emitter plus Swift emitter must return equal bytes for each accepted input. An emitter that merely reads the other's output is not independent.

Return form for every exercise: source/reference/test files, exact test command, raw log, source SHA256, expected/actual table, exact byte comparison output and a deliberately mutated literal/template failure. No Mac/native GPU claim. Target branches below are new lab return branches, not delivery refs.

## GOR-GENERIC-198O-01: exposure emitter

Input `g`, domain[0,4]. RGB multiplied by gain; alpha unchanged, no clamp. Exact output template:

```glsl
vec4 generic_exposure(vec4 c) {
    return vec4(c.rgb * [G], c.a);
}
```

Tests:0,1,4,0.125 accepted; -0 canonical0.000000;2.3456785 ->2.345678 and2.3456795 ->2.345680. -1,4.000001,missing,NaN,infinity rejected. RGBA=(0.2,0.4,0.8,0.5),g=2 ->(0.4,0.8,1.6,0.5). Mutate multiplication into addition: formula test must fail; modify one space in one emitter: byte equality must fail.

Target branch: `lab/generic-198o-01`.

## GOR-GENERIC-198O-02: saturation emitter

Input `s`, domain[0,2]. Arithmetic mean gray, not a perceptual luminance claim. No clamp. Exact output template:

```glsl
vec4 generic_saturation(vec4 c) {
    float y = (c.r + c.g + c.b) / 3.0;
    return vec4(vec3(y) + [S] * (c.rgb - vec3(y)), c.a);
}
```

Tests:s=0 on(0.2,0.5,0.8) ->(0.5,0.5,0.5),s=1 identity,s=2 ->(-0.1,0.5,1.1); gray unchanged for0,1,2. Alpha unchanged. Reject negative,>2,missing,NaN,infinity. Half-even vector1.2345685 ->1.234568. Sign-flip mutant must fail the numeric test; whitespace mutant must fail bytes.

Target branch: `lab/generic-198o-02`.

## GOR-GENERIC-198O-03: nearest cross-blur emitter

Input `r`, domain[0,8]. Runtime dimensions must be finite positive integers; the caller supplies an input image and integer output pixel coordinate `p` within its extent. Coordinates are integer texel-center units, not normalized UV. CPU and GLSL helper nearest tie rule: `floor(q+0.5)` per component, then clamp to[0,dimension-1]. Thus exact half-way ties choose the greater coordinate before clamping, including q=-0.5 ->0. RGBA sampled equally. Exact output template:

```glsl
vec4 generic_nearest(sampler2D t, vec2 q, ivec2 n) {
    ivec2 k = ivec2(floor(q + vec2(0.5)));
    return texelFetch(t, clamp(k, ivec2(0), n - ivec2(1)), 0);
}
vec4 generic_cross(sampler2D t, ivec2 p, ivec2 n) {
    vec2 q = vec2(p);
    float r = [R];
    return 0.5 * generic_nearest(t, q, n)
        + 0.125 * generic_nearest(t, q + vec2(r, 0.0), n)
        + 0.125 * generic_nearest(t, q - vec2(r, 0.0), n)
        + 0.125 * generic_nearest(t, q + vec2(0.0, r), n)
        + 0.125 * generic_nearest(t, q - vec2(0.0, r), n);
}
```

Reject invalid dimensions/coordinates before evaluation, independently of source emission. Tests:3x3scalar-valued RGBA image center1,every other texel0 gives center0.5 at r=1; constant0.4 stays0.4 at all valid p; r=0 identity;1x1image stays unchanged. For a3x1scalar image[0,1,2],p=(1,0),r=0.5 ->1.125 (right rounds2,left rounds1,vertical samples1). At p=(0,0),r=1 ->0.125. Explicitly test q=-0.5,0.5,1.5 and edge clamp. Mutate one0.125weight to0.124: constant-image test must fail; same mutation must fail emitter bytes.

Target branch: `lab/generic-198o-03`.

## GOR-GENERIC-198O-04: bounded unsharp emitter

Input `a`, domain[0,2]. C is original RGBA and B is blurred RGBA. No clamp; alpha comes only from C. Exact output template:

```glsl
vec4 generic_unsharp(vec4 c, vec4 b) {
    return vec4(c.rgb + [A] * (c.rgb - b.rgb), c.a);
}
```

Tests:a=0identity; C.rgb=(0.25,0.5,0.75),B.rgb=(0.5,0.5,0.5),a=1 ->(0,0.5,1); C=Bunchanged. Vary B.a while C.a=0.7: output alpha remains0.7. Reject missing,negative,>2,NaN,infinity. Sign-flip mutant fails numeric vector and source bytes.

Target branch: `lab/generic-198o-04`.

## P23 boundary report

No exact live/private emitter family can be accepted for byte-equality from these new interfaces: exact emitted bytes require the actual template, formatting and emitter inputs. That private contract is not authorized for the bridge under the retained generic-only grant. These four exercises deliberately remain non-P23 research. Do not count them toward P23 acceptance or claim that their newly defined templates match a shipped emitter. Internal comparison against private source, if separately assigned, stays in the private repository.

# EGL/llvmpipe real-shader harness setup (VERIFIED working 2026-10-25) — software-render, real GLSL pixels

Complement to P1's RIG-SETUP.md: that rig proves mpv decision/timing
(vo=gpu readback all-black; vo=x11 real pixels but shader/gamma effect
unverified). THIS harness executes the actual photon-grain.glsl in a
standalone surfaceless EGL context and reads back REAL rendered pixels
with positive controls — but it is NOT mpv: no vo=gpu scaler/hook chain,
no mpv uniform binding. Together the two bound the problem; neither is
native (owner Mac) acceptance.

## Components (exact versions in the working environment)

- OS: Linux x86_64 container, no GPU, no DRI
- conda-forge env (/tmp/mamba/envs/mpv): mesa-llvmpipe 26.2.5,
  mesa-libgallium 26.2.5, mesa-lavapipe 26.2.5, mesalib 26.2.5,
  libegl 1.7.0, ffmpeg 9.0.2 (gpl), mpv 0.41.0 (mpv itself unused:
  conda build has NO GPU API compiled in)
- system python3 (/usr/bin/python3): moderngl 5.13.0, numpy, scipy
  (uniform_filter), Pillow (stills)
- Shader: mpv-rig/photon-grain.glsl extracted byte-exact from the
  patched photon-grain.lua's shader block

## Env vars (all four required)

```
LD_LIBRARY_PATH=/tmp/mamba/envs/mpv/lib
EGL_PLATFORM=surfaceless
LIBGL_ALWAYS_SOFTWARE=1
GALLIUM_DRIVER=llvmpipe
```

## Context creation

```
moderngl.create_context(standalone=True, backend="egl")
```

Surfaceless EGL + llvmpipe gives a real GL context with real fragment
shader execution and real readback. NO X server, NO xvfb, NO mpv.

## Harness contract (egl_harness.py, egl_measure.py, egl_measure_accept.py)

1. Parse the mpv-format shader: //!BORDER REPEAT hex noise texture
   (4096 bytes), //!PARAM blocks (name/TYPE/default), //!DESC body.
2. Apply PARAM FILE DEFAULTS as #define/uniform defaults — unset GL
   uniforms are 0, but mpv initializes them to the file defaults;
   skipping this step silently changes the shader.
3. Bindings mirror mpv's pass semantics: hooked texture NEAREST,
   noise texture LINEAR/REPEAT, HOOKED_size/input_size set to the
   render raster. moderngl read() is top-row-first, no flips.
4. POSITIVE CONTROLS before every metric run, on the same frame:
   identity passthrough must equal input exactly (max_abs_diff == 0),
   and a +0.1 shift control must shift. A run without controls passing
   is void.
5. NaN counting per render; the gate-fixed shader
   (smoothstep(0.0, 1e-30, var), NOT 1e-66 — 0/0 float32 underflow UB)
   renders 0 NaN; the pre-fix shader corrupts 91.5% of pixels under
   llvmpipe. Claim scope llvmpipe-only, Metal unknown.
6. Frames: ffmpeg ground-truth extraction (-ss t -frames:v 1 rawvideo
   rgb24), zero clocks; ffmpeg lanczos upscale for window-size rows.

## VERIFIED LIMITATIONS (do not claim beyond these)

- NOT mpv: no vo=gpu hook chain, no mpv scaler, no mpv PARAM transport.
  mpv-side uniform binding semantics are mirrored by hand.
- llvmpipe sampling/filtering behavior (e.g. sub-pixel cell attenuation)
  may differ from Metal — the 68(f) floor measurement showed the d^2
  smearing model overestimates attenuation on this stack.
- llvmpipe-only float behavior; the smoothstep gate fix is
  contract-tested here but unverified on Metal.
- Visual acceptance still needs the owner Mac or a fixed mpv readback
  stack; this harness is bounded distinct evidence, not acceptance.

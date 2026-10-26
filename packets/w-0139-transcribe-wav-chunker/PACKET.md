# G-T3 WAV chunker (generic, ohal transcribe line)
One pure function + tests, <2h. Replaces the multipart-assembler proposal (ownership of that group unverified - do not duplicate).

## Interface
```js
wavChunks(pcm: Uint8Array, { sampleRate = 16000, channels = 1, bytesPerSample = 2, partSeconds = 5 })
// -> Uint8Array[] each a COMPLETE valid RIFF/WAVE file (header + data), PCM data split on frame boundaries
```
## Synthetic fixture
Generated PCM: sine wave or ramp bytes, deterministic (no audio files, no captures).
## Must-pass tests
1. Header validity: every chunk starts 'RIFF'....'WAVE', fmt chunk declares PCM, sizes consistent with data length.
2. Duration math: concat of chunk data == input PCM exactly (byte equality).
3. Boundary exact: input length an exact multiple of one part -> no trailing empty chunk.
4. 1 byte shorter than one frame -> typed error, no silent truncation.
5. Empty input -> zero chunks (not one header-only chunk).
Run: `node test/gt3-wav-chunker.test.mjs`.
## Bounds
Pure bytes math; no real audio, no streaming, no upload logic.
## Target
Integrator ports into the transcribe line branch (assigned on return).

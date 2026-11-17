# Ops-authored mirror: grain variance-removal adversarial review

This is Ops-authored, not lab-authored. Live bridge fetch on November 17 at 22:43 Europe/Istanbul found no lab output after fb828d2. Reviewed the supplied 629d4fb grain diff and current delivered c736 grain source. The source export lacks the licensed embedded texture; this document exports no texture bytes.

## Confirmed non-clipped failures

Independent c736 Linux mpv0.41 GPU-next/Xvfb/Mesa execution found zero ON/OFF delta on three flat midgray 256x144 fixtures: explicit strength zero, all three zone sensitivities zero, and 48 amount fine-down callbacks. The 9 default low/mid/high flat/near-flat/gradient cases pass. Candidate053d7d6dd adds a conditional one-code-step RGB floor only when all RGB components are strictly inside0..1 and amplitude is nonpositive. It passes12 cases; nine default ON files are byte-identical to baseline. These are measurements of one software rendering path, not proof about every frame.

## Remaining adversarial fixtures

- Pure black and white: solid0/255 images, then an interior black/white patch surrounded by midgray. Test border-connected pure-black rows/columns separately from enclosed black patches. Clipped samples are outside the owner's non-clipped condition; distinguish intentional black border suppression from interior behavior. R2 does not floor a pixel with any RGB component at0 or1.
- HDR highlights: float linear ramps through.99,1,1.01,2 and mixed-channel colors; verify tone-mapped output and delta. R2's strict RGB0..1 gate excludes above-one highlights and colors with one clipped component. Whether that is expected under the owner's frame-level wording remains open; no HDR PASS.
- Film-frame bucket edges: sample immediately before/after bucket boundaries during still/24/60fps and seek backward; compare ON/OFF delta and temporal correlation. A frame bucket is intended to stabilize grain, not remove it. Numerical hash/precision degenerate realizations were not exhaustively tested.
- Very small crops:1x1,1xN,2x2,8x8 and16x16 interior crops including letterbox masking at either edge. Positive contribution does not guarantee positive sigma on a single sample or constant-sign tiny field; a separate nonzero absolute-delta assertion is needed. Current test256x144 does not cover this.
- Tiny positive amplitude: strength values approaching zero but greater than zero, very small positive zone sensitivity and fine amount immediately before zero. R2 activates only at amp<=0; quantization can still remove a positive sub-code-step effect. Test8/10/16-bit outputs independently. No universal no-zero guarantee is claimed.
- OFF: remove shader via the real target-enabled receiver; pixels must equal the reference OFF image. A floor must never turn OFF into ON. Current R2 cases verify real shader removal and OFF/OFF stability.

## Delivery effect

Lua-only candidate remains Class S. These additional runtime fixtures do not become invented preconditions without working prerequisites under owner198u/v. Report native pixel capability honestly as NOT_RUN when absent. Confirmed current non-clipped P0 cases are fixed by the candidate, but the untested regimes above remain unverified, not PASS.

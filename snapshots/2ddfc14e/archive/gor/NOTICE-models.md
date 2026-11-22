# gor 3D models: licences and pins

Weights are downloaded at build time by `tools/gor-fetch-models.sh` from the pinned revisions in `models/models.lock.tsv`
and kept only when the sha256 matches. They are never committed. Non-commercial or unverified-licence weights never enter the build.

| model | licence | source (pinned revision) | sha256 |
|---|---|---|---|
| Video Depth Anything Small `video_depth_anything_vits.pth` | Apache-2.0 | huggingface.co/depth-anything/Video-Depth-Anything-Small @ 256875362cff76724b920335dfb4b29dd611f66e | 13379300b739e659f076a59d52e9801bd8d38c541a7e71f73bbca4dcfb013609 |
| VDA Small streaming ONNX (bootstrap, encoder, stream; fixed 154x266, reference only) | Apache-2.0 | huggingface.co/EmreGneri/video-depth-anything-small-stream @ 56ff0a88aaf2262d50d5d82d69b47e9d40e1c991 | see models.lock.tsv |
| Depth Anything V2 Small CoreML F16 `DepthAnythingV2SmallF16.mlpackage` (model.mlmodel + weight.bin + Manifest.json) | Apache-2.0 | huggingface.co/apple/coreml-depth-anything-v2-small @ cfef6f6f2a70783dedc0bfae40cecbc2052285d3 | see models.lock.tsv (3 rows) |
| MoGe-2 ViT-S normal `model.pt` | MIT | huggingface.co/Ruicheng/moge-2-vits-normal @ 26b477f41595707c5db6770294c0d1721e8ed4ed | 79a16621928c2bf0ed04659218c55c01075e950507f40bb3332fb4c873d3e1dc |

The CoreML kits (release assets of github.com/goreda/gorav, pinned by tag + sha256: `vda-coreml-kit`, `vda-windowed-coreml-kit` and `moge2-coreml-kit`) are fp16/fp32 conversions of the rows above under the same terms: MoGe-2 code and weights MIT (microsoft/MoGe), DINOv2-small backbone Apache-2.0 (facebookresearch/dinov2). MoGe-2 cleared by the owner's 190w W1 (2026-11-09).

Code references (not bundled): iw3 / nunif (MIT, github.com/nagadomi/nunif), resolve-iw3 (MIT, github.com/enoky/resolve-iw3).

Excluded: Video Depth Anything Base/Large and Depth-Anything-V2 Base/Large/Metric (CC-BY-NC-4.0); MoGe-3 (needs Triton, not macOS);
Apple Depth Pro (research-only licence, never used); Depth Anything 3 (fallback, not pinned).
iw3 row_flow_v3 / mlbw / inpaint weights: approved for the owner's private Mac build only (190w ruling below); the licence
of the weights is not stated and only row_flow_v2 has a recorded author confirmation (resolve-iw3 NOTICE), so they stay
out of any distributed build.

## 190w licence rulings (architect, 2026-11-09 13:52, relayed by Main)

- MoGe-2 ViT-S normal weights APPROVED: MIT (backbone dinov2-small Apache-2.0). Unlocks the `moge2-coreml-kit` row in
  `models/models.lock.tsv` (github.com/goreda/gorav private release gor-kit-2026-11-09, asset `gor-kit-moge-46d0ef03.tar`,
  sha256 79e8ebbd...3c989; owner gh login, weights never in git). The `vda-coreml-kit` row fetches from the same goreda/gorav release.
- nunif / iw3 `row_flow_v3`, `mlbw_l2_inpaint`, `mlbw_l2_inpaint_video` weights APPROVED for the owner's private Mac
  build ONLY. nunif code is MIT (github.com/nagadomi/nunif), but the iw3 training code uses an Apple Depth Pro fork, so
  the weights' training-data provenance is unconfirmed. Any distribution beyond the owner's Mac is a go-live gate.
  Lock row `iw3-nunif-weights-kit` (private gorav release asset gor-kit-nunif-v2.tar, sha256 0dbfb58d0a9c1e646578451b9f7197c6243d92866bc03945258289a269d1efe0, 19,804,160 B; replaces the v1 asset, which lacked the T1/T2 weights) is `usable` for the owner's Mac build only; never ship it in a distributed build.
- Lock row `iw3-nunif-coreml` (gorav release gor-kit-2026-11-09, gor-kit-nunif-coreml.tar, sha256 ef67c393...fd218, 149,964,800 B): CoreML fp16 conversions of the same nunif weights, same terms and the same
  owner-private-Mac-build-only caveat (training-data provenance unconfirmed; any distribution is a go-live gate). Unpacked to <models>/nunif-coreml; the id deliberately lacks "coreml-kit" so it does not gate the 3D-ready state. No runner loads it yet.

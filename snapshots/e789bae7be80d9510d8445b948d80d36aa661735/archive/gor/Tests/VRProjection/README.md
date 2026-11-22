# Projection metadata parser characterization

Runs the actual current production parser on six JSON cases, without ffprobe, camera, AppKit or media capture. This records current behavior, not acceptance of its recognition policy and not proof about the owner's files. In particular, layout-only metadata is recognized as stereo but supplies no projection; full equirectangular is not silently called VR180. No production behavior is changed by these tests.

Run `sh Tests/VRProjection/run.sh` with Swift available. `SWIFTC` can name a compiler.

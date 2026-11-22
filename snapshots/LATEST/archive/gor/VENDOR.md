# Frozen vendor inventory

2026-09-26 freeze remains. No vendor code/style changes in M1. Directory hashes
are SHA256 of sorted relative-path + NUL + file SHA256 records (no symlinks).
Versions below are source labels, not independently verified upstream releases.

| Name | Version/source label | Tree/file SHA256 | Update trigger | Owner |
| --- | --- | --- | --- | --- |
| wt_server | reviewed bounded-tail v22.21 snapshot | b87f730e93733c15fb408c44aa76d61f6191f4c6b57617ba388ece9eaad32235 | explicit reviewed vendor update; separate ADR for module rules | unassigned |
| magnet_search | frozen source snapshot | df014b869554946fe18ecb504bbe0ed19da2c70327471942aa00cb079c15a2e7 | explicit reviewed vendor update; separate ADR for module rules | unassigned |
| mega_relay | frozen source snapshot | 301e54ccd8f3d08a5ae4d80e3d97a26506f3398fc9825c8bd93ffaf743e9890f | explicit reviewed vendor update; separate ADR for module rules | unassigned |
| mus2 | frozen source snapshot | d4e36bd6f2dfd603a6081d468492fdc8402d52b1ff1103d223c6794ccc366344 | explicit reviewed vendor update; separate ADR for module rules | unassigned |
| webtorrent-cli | 6.0.0 | 7668086ceab95746042a0be5e948ed75d522b621d0865fb9ba8361ee3ae4a27b | explicit reviewed vendor update; separate ADR for module rules | unassigned |
| update-chromium.py | frozen source snapshot | 236e4f359bfb481eb8f0c9b0c87cfcd1ae76c907d92d09b4fc2ad5650ea09612 | explicit reviewed vendor update; separate ADR for module rules | unassigned |

Product photon-*.lua, vr180-look.lua and clip.lua are GorMPVBackend runtime assets,
not frozen third-party exemptions. Engine pin/FFmpeg provider lock stays separate;
M1 does not assert that an unmeasured binary or upstream version is verified.

# Public-domain fixture provenance

NASA SVS release12034 explicitly presents the4K release in the public domain: https://svs.gsfc.nasa.gov/12034 . NASA SVS policy https://svs.gsfc.nasa.gov/help/ says content is public domain unless otherwise noted; some music is licensed and visualizations may be used without its audio. No audio is present in these fixtures.

Item: Arctic B-roll in4K, Ice Edge. Credit NASA's Goddard Space Flight Center. Actual file URL observed in release HTML: https://svs.gsfc.nasa.gov/vis/a010000/a012000/a012034/Ice_Edge_UHD_YouTube.mp4 . Extract starts around10seconds and lasts10seconds with keyframe boundary allowance. Source3840x2160H264 yuv420p. All packet files are derived/reencoded, not native independent480/1080/2160captures. Commands:
ffmpeg -ss10 -i SOURCE_URL -t10 -map0:v:0 -an -c:v copy source-4k-excerpt.mp4
ffmpeg -i source-4k-excerpt.mp4 -an -vf scale=854:480 -c:v libx264 -preset fast -crf20 -threads2 480p.mp4
ffmpeg -i source-4k-excerpt.mp4 -an -vf scale=1920:1080 -c:v libx264 -preset fast -crf20 -threads2 1080p.mp4
ffmpeg -i source-4k-excerpt.mp4 -an -c:v libx264 -preset fast -crf26 -threads2 2160p.mp4
Space-separated flags in reproducible script BUILD-MEDIA.sh are authoritative.

Limit: flowing meltwater and ice texture,8-bitSDR. Not a representative film-grain/compression-noise corpus; no10-bit/HDR/static-flat coverage claimed. Reviewer adds those explicit failure cases before seeing solver fix. Hashes/dimensions in manifest, no original licensed third-party bytes or audio.

# DR-PHOTON-ADAPTIVE-V4 lab corpus request (queue table)

Requester: goreda. Relayed by Instinct via bridge, 2026-11-21, Europe/Istanbul.
Labs: 1nstinct and in2tinct (both). Claim and return per GROUP-GUIDE v14.

## Task

Produce corpus packets for SEVEN source classes:

1. 480p DVD film
2. 720p
3. Grainy 1080p Blu-ray
4. Clean 1080p digital
5. 4K HDR
6. Animation
7. S/B (black-and-white)

Output heights: picture_out_h in {1080, 1440, 2160}.
Pipeline: Linux egl_harness line.
Declare the class x height coverage of each packet explicitly in its report.

## Measurements (per packet)

- Grain sigma per luma bin.
- Normalized autocorrelation width at the output pixel.

## Fixture rules

Synthetic or public fixtures only. No licensed captures or specimens.
Bridge rules apply; secret-scan on every post.

## Required packet contents (every packet)

- Real source (fixture identity and origin)
- Command line(s)
- Environment (OS, GPU/driver, harness version, build sha)
- Exit code
- Log (raw)
- Hash (sha256 of artifacts)

## Routing note

The first landed packet will be escalated immediately: Ops carries the
sigma_t(Y) knot table and k(cell_out_px) values into photon lane patch B2.

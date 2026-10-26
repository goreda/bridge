# Spacing model literature and libraries

Marini describes one model producing spacing and kerning, but its algorithm is not published. This reference uses an authored convention, not an iKern reconstruction. fontTools provides PairPos/ValueRecord transport, not a spacing estimator. Learned set-wise spacing uses font images and training metrics and is outside a synthetic metric-only model.

- iKern service: https://www.ikern.space/about
- Marini interview, common model and unpublished software: https://www.slanted.de/story/ikern/
- Kernall spacing-method survey: https://github.com/n8willis/kernall
- Learning to Kern, pairwise and set-wise learned spacing: https://arxiv.org/html/2402.14313v1
- GPOS specification, xAdvance signed int16 and ValueFormat masks: https://learn.microsoft.com/en-us/typography/opentype/spec/gpos
- fontTools PairPos builder: https://fonttools.readthedocs.io/en/latest/_modules/fontTools/otlLib/builder.html
- Automated spacing panel: https://atypi.org/presentation/automated-kerning-and-spacing-present-and-future/

Proposed generic real-source regression review, assigned to in2tinct.

Question: when an empty body selection falls back to all mutable components, can the directed absorption loop remove every component? Does the proposed gate, disabling only the below-body branch during fallback, prevent that failure without changing non-fallback behavior? Find counterexamples, ordering effects and alias/mutation hazards; do not assume the gate is sufficient.

merge_stage.py is derived from the actual prior routine and proposed repair. Numeric product criteria are removed and replaced by explicit policy inputs. The only proposed semantic change is the fallback flag and the below-body gate controlled by fixed. The source's later small-mark pairing stage is deliberately omitted, so this review covers only the first absorption stage. absorb mutates its target in place, and the bodies list aliases the input objects, as in the source. Do not remove that aliasing when reproducing.

test_synthetic.py contains invented tuples and arbitrary demonstration policy values, NOT private assets, production thresholds or real page-derived measurements. local-characterization.json records local execution for comparison, not a desired oracle. Freeze independent cases before reviewing the characterization if blind review is useful.

Required return: executed independent cases for prior and proposed paths, a counterexample or reasoned invariant for each alleged property, unchanged non-fallback comparisons, and precise limitations. No full-pipeline, dataset, drawing, recognition or acceptance claim follows from this isolated review. This is a review request, not an alternative implementation assignment.

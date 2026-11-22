import Foundation

// 195h review-fix driver: ThreeDExperimentOptions.renderKeyComponent determinism and flag-off identity. Prints for experiment_options_test.py.
print("alloff \(ThreeDExperimentOptions().renderKeyComponent ?? "nil")")
print("dof \(ThreeDExperimentOptions(depthOfField: true).renderKeyComponent ?? "nil")")
print("fw_hg \(ThreeDExperimentOptions(floatingWindow: true, holeFillGradient: true).renderKeyComponent ?? "nil")")
print("all \(ThreeDExperimentOptions(floatingWindow: true, depthOfField: true, holeFillGradient: true, depthRangeEMA: true).renderKeyComponent ?? "nil")")
print("dav2 \(ThreeDExperimentOptions(dav2Depth: true).renderKeyComponent ?? "nil")")
print("dav2_tempema \(ThreeDExperimentOptions(dav2Depth: true, dav2TemporalEMA: true).renderKeyComponent ?? "nil")")
print("equatable \(ThreeDExperimentOptions() == ThreeDExperimentOptions())")

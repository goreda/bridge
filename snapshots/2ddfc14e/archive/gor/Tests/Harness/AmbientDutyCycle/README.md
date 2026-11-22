# Ambient camera duty-cycle ownership

Run `bash gor/Tests/Harness/AmbientDutyCycle/run.sh`. Python 3 only, current PPController_Features.swift required. No snapshot fallback, camera, timers, Dispatch scheduling, Swift/hardware/privacy/UI or thermal execution. Separate from HeadTracker camera lifecycle and dimming numeric policy.

Six controls preserve start idempotence, checkpoint/runtime gates, first/normal source ceilings, retry availability and normal stop under successful pending-work cancellation. Three source mutations fail. Characterizations: old retained frame callback can close a replacement window because close has no window identity; an already-begun first/retry callback can open after stop because open itself lacks active/runtime/generation gate; seek over several checkpoints drains one overdue checkpoint per call. The harness does not claim a canceled pending DispatchWorkItem runs. Native cancellation/frame ordering and intended seek policy remain unverified.

PASS is clock-free state consistency, not camera/privacy/thermal correctness. Validate retained callback/replacement ordering natively before a fix. Preserve settling/consumer balance and designed checkpoint/ceiling behavior. No production patch included.

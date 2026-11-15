```packet-json
{
  "code_owner": "gdb gor-structure consuming Camera owner",
  "product_repo": "goreda/instinct",
  "product_sha": "4579f080d624a30bf3a87e9a4b1e718136380ed6",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Camera/Runtime.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "archive/gor/Sources/gor/Camera/Sensing.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "stopSessionLocked(generation: UInt64, after: (() -> Void)? = nil) -> Void; cameraHelper.stopSession(generation: UInt64, completion: @escaping (Bool) -> Void)",
    "types": "UInt64 generation; Bool running/stopped; CameraHelperIPC.Event(ev,state,generation,running); synthetic fixture labels and text rows",
    "ownership_lifetime": "Helper owns AVCaptureSession; serialized sessionQueue orders stop/configure. Parent owns child process and stop completion. Synthetic fixtures own copied strings only.",
    "caller": "CameraHelperEngine.apply stop/shutdown command; HeadTracker zero-consumer stop request",
    "callee": "AVCaptureSession.stopRunning; CameraHelperSink.send; parent CameraHelperClient child-exit completion"
  },
  "test": {
    "command": "python3 stop_model.py",
    "expected": "S1..S5 PASS with classifications returned/self_exit/parent_kill/incomplete/unattributed_completion; CAUGHT stale generation; PASS 5 synthetic stop paths; no hardware claim; exit 0",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/gdb-native87-full-app-gate",
    "paths": [
      "archive/gor/Tests/Harness/ScreenCamera/stop_sequence_test.py"
    ],
    "return_form": "full-files"
  }
}
```

# W-gdb-gor-2: synthetic camera stop-sequence model, r3

## Task
Build a small parser and state-machine test for helper/parent stop paths.
All five fixtures below are invented. No recordings, personal context,
private capture filenames, device details, or user activity are included.

## Pinned product excerpts
Source pin: `4579f080d624a30bf3a87e9a4b1e718136380ed6`.
These minimal exact excerpts are enough to inspect the stop call and the
success emitters. No private checkout or network access is needed.

`Camera/Runtime.swift`, helper stop method:

```swift id=source1
    private func stopSessionLocked(generation: UInt64, after: (() -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        headWorker.stop();blinkWorker.stop();ambientWorker.stop()
        mediaLog("HEAD-CAPTURE event=delegate generation=\(generation) attached=false")
        session.stopRunning()
        let running = session.isRunning
        mediaLog("HEAD-CAPTURE event=hardware-stopped running=\(running) generation=\(generation)")
        sink.send(CameraHelperIPC.Event(ev: "state", state: "stopped", generation: generation, running: running))
        after?()
    }

```

`Camera/Sensing.swift`, parent completion emitter:

```swift id=source2
            Diag.mediaRecord("HEAD-CAPTURE event=hardware-stopped running=\(!stopped) generation=\(generation)")
```

Important correction: BOTH success strings have `running=... generation=...`
order at this source pin. Token order does not identify the emitter. Any
parser claiming otherwise must fail review. Synthetic origin labels below
are fixture metadata, not fields available in production log lines.

## Measurement boundary
A delegate-detached log with no helper-success log is consistent with an
incomplete stop, lost/unobserved output, process exit, or a blocked call.
Absence alone does not prove the exact blocked instruction. A stack sample,
additional bounded instrumentation or independent completion evidence is
needed to distinguish these cases. This exercise does not establish a
hardware stop, current device state, or a root cause.

## Interface and expected paths
Save the Python block as `stop_model.py`; run `python3 stop_model.py`.
The code includes all input bytes, lexicon, generation checks and expected
paths. No external files are required.

| Fixture | Synthetic generations | Expected classification |
|---|---|---|
| S1 | 101 -> 102 | returned |
| S2 | 103 -> 104 | self_exit |
| S3 | 105 -> 106 | parent_kill |
| S4 | 107 -> 108 | incomplete |
| S5 | 109 -> 110 | unattributed_completion |

`self_timeout`, `child_exit` and origin labels model a possible bounded
recovery. They are not claims about the pinned implementation. The pinned
helper currently calls stopRunning synchronously. For bounded recovery,
require an explicit deadline below the parent's deadline, distinguish a
returned stop from process exit, and reject claims of hardware success
based only on a missing log. Preserve serialized generation handling.

## Passing tests
All five classifications must match the table. A mismatched generation
must be rejected. A missing success line must remain incomplete, not turn
into a proven call-site diagnosis. Ambiguous success without origin data
must remain unattributed. Add negative tests for stale events, repeated
stop, late completion, process-exit-before-stop and a configure queued
behind a stop. No hardware or native-compile acceptance is implied.

## Target branch and return
Target: `lane/gdb-native87-full-app-gate`, output path
`archive/gor/Tests/Harness/ScreenCamera/stop_sequence_test.py`. No push is requested. Return a unified patch against the complete
Python block, or full replacement files plus stdout and interpreter
version. No product edits, owner refs, native runs or real capture data.

## Complete runnable synthetic fixture and model

```python id=fixtures1
import re
# ALL sequences below are invented, not recordings of any person or device.
FIXTURES = [
 ("S1",101,102,"delegate helper_success parent_success", "returned"),
 ("S2",103,104,"delegate self_timeout child_exit parent_success", "self_exit"),
 ("S3",105,106,"delegate parent_timeout helper_kill child_exit parent_success", "parent_kill"),
 ("S4",107,108,"delegate", "incomplete"),
 ("S5",109,110,"delegate parent_success", "unattributed_completion"),
]
LEXICON = {
 "delegate": "HEAD-CAPTURE event=delegate generation={g} attached=false",
 "helper_success": "HEAD-CAPTURE event=hardware-stopped running=false generation={g}",
 "parent_success": "HEAD-CAPTURE event=hardware-stopped running=false generation={g}",
 "self_timeout": "HEAD-CAPTURE event=hardware-stop-timeout generation={g} recovery=bounded-self-exit",
 "child_exit": "SYNTHETIC event=child-exit generation={g}",
 "parent_timeout": "HEAD-CAPTURE event=stop-pending generation={g} elapsed_s=2",
 "helper_kill": "SYNTHETIC event=helper-kill generation={g}",
}
EXPECTED = {
 "delegate helper_success parent_success":"returned",
 "delegate self_timeout child_exit parent_success":"self_exit",
 "delegate parent_timeout helper_kill child_exit parent_success":"parent_kill",
 "delegate":"incomplete",
 "delegate parent_success":"unattributed_completion",
}
def classify(rows):
    # Synthetic origin labels are supplied as fixture truth, NOT inferred
    # from event token order. Product helper/parent success strings collide.
    labels=[]
    for label,text,generation in rows:
        m=re.search(r"generation=(\d+)",text)
        assert m and int(m.group(1)) == generation, "generation mismatch"
        assert text == LEXICON[label].format(g=generation), "lexicon mismatch"
        labels.append(label)
    return EXPECTED.get(" ".join(labels),"invalid")
for name,old,new,events,want in FIXTURES:
    rows=[(label,LEXICON[label].format(g=new),new) for label in events.split()]
    got=classify(rows)
    assert got==want,(name,got,want)
    print(name,old,"->",new,got,"PASS")
# Missing success cannot establish the internal blocking location.
assert classify([("delegate",LEXICON["delegate"].format(g=112),112)])=="incomplete"
try: classify([("delegate",LEXICON["delegate"].format(g=113),114)])
except AssertionError: print("CAUGHT stale generation")
else: raise RuntimeError("stale generation accepted")
print("PASS 5 synthetic stop paths; no hardware claim")
```

## Scope of source excerpts

The source excerpts define the actual consuming seam, not files the lab should edit. Return the full synthetic parser/test at the target path. The source pin is pre-C5; a subsequent bounded-stop candidate exists separately and is not accepted by this packet. Dependency roles: session is an AVCaptureSession; videoOutput is AVCaptureVideoDataOutput; worker.stop() retires its child; mediaLog writes a bounded log; sink.send writes an IPC event. None is invoked by the portable fixture. Helper/parent emitter identity is intentionally not recoverable from these strings alone.

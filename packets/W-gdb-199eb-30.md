# W-gdb-199eb-30: arch-export-stop
Team: in2tinct. State: WAIT_STATION_REPIN. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-30, lane lane/in2tinct/arch-export-stop; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Player/ExportRunComposition.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: c261a9392e5f9a5cadb863902cc3a1d06124c68e
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Make stopping an export terminal before permitting a successor, without blocking playback.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Existing export target is being consolidated by the single station writer. Wait for its verified destination@SHA, then repin this same packet. No parallel satellite edit.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
179:         if d == .started { launch() }
180:         return d
181:     }
182: 
183:     public func cancel() {
184:         lock.lock()
185:         switch phase {
186:         case .idle, .tearingDown: lock.unlock()
187:         case .starting: cancelLatched = true; lock.unlock()
188:         case .running:
189:             let b = current; lock.unlock()
190:             b?.runner.stop(.cancelled)
191:             b?.source.cancel()
192:         }
193:     }
194: 
195:     /// Teardown debt, read WITHOUT holding the internal lock (the closures are external code and may read isInFlight): the admission scope, the bound source's release debt, and
196:     /// the backend this operation created (its own native close may outlive close(); a refusal or a pre-run discard takes no admission, so only this covers it).
197:     private func pending(_ b: ExportRunComposition.BoundRun?, _ backend: ExportRGBA64Backend?) -> Bool {
198:         if scopeBusy() { return true }
199:         if backend?.closePending == true { return true }
200:         if let b { return teardownPending(b) }
201:         return false
202:     }
203: 
204:     /// Terminal delivery + phase release. The phase is published as .tearingDown BEFORE the debt is read (no start can slip in between); the debt is checked outside the lock.
205:     /// Clear debt: idle first, then the callback (a reentrant start is accepted). Pending debt: the callback fires in .tearingDown and the phase turns idle only after it clears.
206:     /// `backend` stays strongly held here until the drain ends (a closed-but-pending backend object is not freed under its own native close).
```

Secret scan: clean.

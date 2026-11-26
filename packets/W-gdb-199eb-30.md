# W-gdb-199eb-30: arch-export-stop
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/arch-export-stop.
Source: archive/gor/Sources/gor/Player/ExportRunComposition.swift, lines 179-206.

## Product change
Make stopping an export terminal before permitting a successor, without blocking playback.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Stop/start race and backend error preserve run identity and finish exactly once.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.

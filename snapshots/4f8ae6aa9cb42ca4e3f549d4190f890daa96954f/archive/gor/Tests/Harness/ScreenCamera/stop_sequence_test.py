# stop_sequence_test.py - W-gdb-gor-2 synthetic camera stop-sequence model
# Target path: archive/gor/Tests/Harness/ScreenCamera/stop_sequence_test.py
# Scope: full synthetic parser/test ONLY. No product edit, no native run,
# no hardware claim. All sequences below are invented, not recordings of
# any person or device.
#
# Run as: python3 stop_model.py (this file is the stop_model.py content).
#
# Synthetic origin labels are fixture truth, NOT inferred from event token
# order. At pin 4579f080d624a30bf3a87e9a4b1e718136380ed6 both the helper
# (Runtime.swift stopSessionLocked) and parent (Sensing.swift) success
# strings are identical:
#   "HEAD-CAPTURE event=hardware-stopped running=false generation={g}"
# so a success line alone cannot be attributed to an emitter.

import re

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
 # Extra label used only by the negative tests below: a configure command
 # queued on the serialized sessionQueue behind a stop.
 "configure": "HEAD-CAPTURE event=configure generation={g}",
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
    # One stop sequence spans exactly one generation: any event carrying a
    # different generation is stale and the whole sequence is rejected.
    labels=[]
    generations=set()
    for label,text,generation in rows:
        m=re.search(r"generation=(\d+)",text)
        assert m and int(m.group(1)) == generation, "generation mismatch"
        assert text == LEXICON[label].format(g=generation), "lexicon mismatch"
        labels.append(label)
        generations.add(generation)
    assert len(generations)<=1, "mixed generations in sequence"
    return EXPECTED.get(" ".join(labels),"invalid")

def rows_for(events, gen):
    return [(label,LEXICON[label].format(g=gen),gen) for label in events.split()]

# --- Positive paths S1..S5 ---
for name,old,new,events,want in FIXTURES:
    got=classify(rows_for(events,new))
    assert got==want,(name,got,want)
    print(name,old,"->",new,got,"PASS")

# Missing success cannot establish the internal blocking location.
assert classify(rows_for("delegate",112))=="incomplete"
try: classify([("delegate",LEXICON["delegate"].format(g=113),114)])
except AssertionError: print("CAUGHT stale generation")
else: raise RuntimeError("stale generation accepted")

# --- Required negative tests ---

# N1 stale events: a success event still carrying the OLD generation must
# be rejected by the parser, not folded into the new generation's sequence.
# Exercised through classify() itself, which enforces one generation per
# sequence.
try:
    rows=rows_for("delegate",120)
    rows.append(("helper_success",LEXICON["helper_success"].format(g=119),119))
    rows.append(("parent_success",LEXICON["parent_success"].format(g=120),120))
    got=classify(rows)
    raise RuntimeError("stale event accepted: "+got)
except AssertionError:
    print("CAUGHT N1 stale event generation")

# N2 repeated stop: a second stop completion for the same generation must
# not extend or re-classify the completed returned path.
assert classify(rows_for("delegate helper_success parent_success helper_success parent_success",121))=="invalid"
print("CAUGHT N2 repeated stop")

# N3 late completion: a helper success arriving after a bounded self-exit
# has already been classified must not upgrade or alter self_exit.
assert classify(rows_for("delegate self_timeout child_exit parent_success helper_success",122))=="invalid"
print("CAUGHT N3 late completion after exit")

# N4 process-exit-before-stop: child exit with no stop completion is not a
# self_exit, and a later success line does not repair it.
assert classify(rows_for("delegate child_exit",123))=="invalid"
assert classify(rows_for("delegate child_exit parent_success",123))=="invalid"
print("CAUGHT N4 process-exit-before-stop")

# N5 configure queued behind a stop: the serialized sessionQueue means a
# configure may follow a stop, but it must not be reordered ahead of the
# stop, and it must not change an accepted classification or mask an
# incomplete one.
assert classify(rows_for("delegate configure parent_success",124))=="invalid"
assert classify(rows_for("configure delegate helper_success parent_success",124))=="invalid"
assert classify(rows_for("delegate helper_success parent_success configure",124))=="invalid"
print("CAUGHT N5 configure queued behind stop")

print("PASS 5 synthetic stop paths; no hardware claim")

import json,sys
d=json.load(open(sys.argv[1]))
ids=[c["id"] for c in d["cases"]]
assert len(ids)==len(set(ids))
for c in d["cases"]: assert c["id"] and c["class"] and c.get("expect")
need={"seek","pause_resume","drop_burst","clock_jump","extreme_pts","negative_control","regression"}
assert need<={c["class"] for c in d["cases"]}
print("ok",len(ids),"cases (parser selftest only)")

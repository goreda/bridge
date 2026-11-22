#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
source="$root/Sources/gor/App/IndependentDocumentRouter.swift"
swiftc "$source" "$root/Tests/IndependentDocuments/main.swift" -o "$tmp/fence"
"$tmp/fence"
for mutant in receiver count rate; do
 python3 - "$source" "$tmp/$mutant.swift" "$mutant" <<'PY'
import sys
s=open(sys.argv[1]).read();name=sys.argv[3]
if name=='receiver':s=s.replace('if receiverInitial {','if false {')
elif name=='count':s=s.replace('if runningCount >= 6 {','if false {')
else:s=s.replace('if recentSpawnTimes.filter({ now - $0 < 10 && now >= $0 }).count >= 2 {','if false {')
open(sys.argv[2],'w').write(s)
PY
 swiftc "$tmp/$mutant.swift" "$root/Tests/IndependentDocuments/main.swift" -o "$tmp/mutant"
 if "$tmp/mutant" >"$tmp/$mutant.log" 2>&1; then echo "MUTANT SURVIVED $mutant"; exit 1; fi
 echo "MUTANT RED $mutant"
done

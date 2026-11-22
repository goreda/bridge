"""arch196g: inventory must not act as a file/line target."""
from pathlib import Path
import importlib.util
r=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('inventory',r/'tools/structure-freeze.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
a={'Sources/gor/App/AppDelegate.swift':(100,'a')}
b={**a,'Sources/gor/New.swift':(5000,'b')};b['Sources/gor/App/AppDelegate.swift']=(10000,'c')
assert m.failures(a,b)==[]
print('PASS retired count/hub/line/path-placement gates do not block source; ownership is a separate contract')

spec=importlib.util.spec_from_file_location('architecture',r/'tools/architecture.py');a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
source=(r/'tools/architecture.py').read_text();body=source[source.index('def violations('):source.index('def ',source.index('def violations(')+5)]
assert "'ceiling'" not in body and "'small-file'" not in body
print('PASS architecture report cannot revive retired ceiling/small-file acceptance gates')

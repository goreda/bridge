#!/usr/bin/env python3
"""Exact source initializer-access regression. Not a Swift compiler substitute."""
import pathlib,re
root=pathlib.Path(__file__).resolve().parents[2]
s=(root/'Sources/gor/Engine/MPVCommand.swift').read_text()
def valid(text):
 body=text.split('struct IPCResponseCounter {',1)[1].split('// Crop samples',1)[0]
 return 'private var buffer=Data()' in body and re.search(r'^    init\(expected:Int\) \{ self.expected=expected \}$',body,re.M) is not None
assert valid(s)
assert not valid(s.replace('    init(expected:Int) { self.expected=expected }\n',''))
assert not valid(s.replace('    init(expected:Int)', '    private init(expected:Int)'))
assert 'IPCResponseCounter(expected:payload.split(separator:"\\n").count)' in s
print('PASS actual constructor source and missing/private-init negative controls; Swift compile NOT_RUN')

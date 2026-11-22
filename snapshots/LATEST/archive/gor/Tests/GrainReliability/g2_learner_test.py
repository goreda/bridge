#!/usr/bin/env python3
"""G2 manual-learner vectors run on the real production Lua module.
Not shader/pixel proof. JSON codec is a reversible Lua-table test seam here;
the independent real-mpv relaunch test covers production JSON persistence.
"""
import argparse,pathlib,tempfile,json,hashlib
from ug3_test import execute
p=argparse.ArgumentParser();p.add_argument('--scripts',type=pathlib.Path);a=p.parse_args();s=(a.scripts or pathlib.Path(__file__).resolve().parents[2]/'Resources/vendor/mpv/scripts').resolve()
code=r'''
local M=require('photon-look-learning')
local function serialize(v)
 if type(v)=='string'then return string.format('%q',v)end
 if type(v)~='table'then return tostring(v)end
 local out={'{'};for k,x in pairs(v)do out[#out+1]='['..serialize(k)..']='..serialize(x)..','end;out[#out+1]='}';return table.concat(out)
end
local utils={format_json=serialize,parse_json=function(bytes)return assert(loadstring('return '..bytes))()end}
local counter=0
local function fresh()counter=counter+1;return M.new(utils,root..'/look'..counter)end
local function near(x,y)assert(math.abs(x-y)<1e-9,tostring(x)..' != '..tostring(y))end
local learn=fresh()
assert(learn:record('A','amount','e1',.5,'on'));assert(learn:record('A','amount','e2',.7,'on'));assert(learn:record('A','amount','e3',.6,'off'))
near(learn:target('A','amount'),.6);near(learn:solve('A','amount',1),.8)
assert(learn:record('A','amount','e4',.9,'on'));near(learn:target('A','amount'),.65);near(learn:solve('A','amount',1),.825)
local learn9=fresh();for i=1,10 do assert(learn9:record('A','strength','s'..i,i,'on'))end
near(learn9:target('A','strength'),6);near(learn9:solve('A','strength',1),3.5)
local learn2=fresh();assert(learn2:record('A','amount','a',.5,'on'));assert(learn2:record('A','amount','b',.9,'on'))
near(learn2:solve('A','amount',1),1);near(learn2:solve('A','amount',0),0)
for _,case in ipairs{{'amount','c',0,'on'},{'amount','c',65,'on'},{'amount','c',.5,'sideways'},{'bogus','c',.5,'on'},{'amount','a',.4,'on'}}do assert(not learn2:record('A',unpack(case)))end
-- Twin omits this rule, production properly rejects it. Not a supplied negative vector.
assert(not learn2:record('A','amount','../bad',.4,'on'))
'''
with tempfile.TemporaryDirectory(prefix='g2-learner-')as temp:
 f=pathlib.Path(temp)/'g2.lua';f.write_text('local root='+json.dumps(temp)+'\npackage.path='+json.dumps(str(s)+'/?.lua;')+'..package.path\n'+code);rc,msg=execute(f)
print(json.dumps({'result':'PASS'if rc==0 else 'FAIL','exit':rc,'scope':'actual module learner equivalence, JSON codec test seam, not pixel proof','source_sha256':hashlib.sha256((s/'photon-look-learning.lua').read_bytes()).hexdigest(),'cases':['median3','median4-even','last9-of10','under3','automatic0','reject0','reject65','bad-mode','bad-parameter','duplicate-id','additional-invalid-id'],'detail':msg,'G2_flat_sigma_numeric_comparison':'NOT_APPLICABLE: supplied sigma function is amplitude model, not pixel residual sigma','U_G3_ratio_vectors_in_G2':'NONE'},indent=2));raise SystemExit(rc)

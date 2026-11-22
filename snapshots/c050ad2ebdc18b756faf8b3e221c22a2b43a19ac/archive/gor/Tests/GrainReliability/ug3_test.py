#!/usr/bin/env python3
"""U-G3 product Lua regression tests. No GPU or app acceptance claim.
Runs the complete grain source with test mp/common I/O seams, then exercises its
actual locals and callbacks. Recovery renderer is inert; common raster math is real.
"""
import argparse,ctypes,ctypes.util,hashlib,json,os,pathlib,shutil,subprocess,tempfile

def execute(path):
    binary=os.environ.get('GRAIN_RELIABILITY_LUA') or shutil.which('lua5.1') or shutil.which('luajit')
    if binary:
        p=subprocess.run([binary,str(path)],capture_output=True,text=True,timeout=15)
        return p.returncode,p.stdout+p.stderr
    name=ctypes.util.find_library('lua5.1') or ctypes.util.find_library('luajit-5.1')
    if not name:return 2,'NOT_RUN: Lua5.1/LuaJIT library or interpreter required'
    lib=ctypes.CDLL(name,mode=ctypes.RTLD_GLOBAL)
    lib.luaL_newstate.restype=ctypes.c_void_p;L=lib.luaL_newstate()
    lib.luaL_openlibs.argtypes=[ctypes.c_void_p];lib.luaL_loadfile.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
    lib.lua_pcall.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
    lib.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lib.lua_tolstring.restype=ctypes.c_char_p
    lib.lua_close.argtypes=[ctypes.c_void_p];lib.luaL_openlibs(L)
    rc=lib.luaL_loadfile(L,str(path).encode())
    if not rc:rc=lib.lua_pcall(L,0,0,0)
    message=lib.lua_tolstring(L,-1,None).decode() if rc else 'PASS all U-G3 source/callback assertions'
    lib.lua_close(L);return (1 if rc else 0),message

def run(scripts):
    grain=(scripts/'photon-grain.lua').read_text();master=(scripts/'photon.lua').read_text()
    report={'source_sha256':{n:hashlib.sha256((scripts/n).read_bytes()).hexdigest() for n in ['photon-grain.lua','photon-common.lua','photon.lua']},'scope':'complete product Lua with deterministic host seams; NOT pixel/native-app proof','Darwin':'NOT_RUN'}
    with tempfile.TemporaryDirectory(prefix='ug3-test-') as temp:
        root=pathlib.Path(temp);(root/'shader').mkdir();results=root/'results.tsv'
        head=r'''
local root=__ROOT__
package.path=__SCRIPTS__..'/?.lua;'..package.path
local callbacks,events,observers={}, {}, {}
local props={['config-dir']=root,['glsl-shaders']={}}
local no=function()end
mp={msg={info=no,warn=no,error=no,verbose=no,debug=no},get_opt=function()return nil end,
 get_time=function()return 100 end, get_script_name=function()return 'ug3-test' end,
 get_property=function(k)return props[k]end,
 get_property_number=function(k,default)return props[k] or default end,
 get_property_bool=function(k,default)return props[k] or default end,
 get_property_native=function(k)return props[k]end,
 register_script_message=function(k,f)callbacks[k]=f end,
 register_event=function(k,f)events[k]=events[k]or{};table.insert(events[k],f)end,
 observe_property=function(k,_,f)observers[k]=observers[k]or{};table.insert(observers[k],f)end,
 add_timeout=function()return{kill=no,resume=no}end,
 add_periodic_timer=function()return{kill=no,resume=no}end,
 add_key_binding=no,commandv=no,command_native_async=function(_,f)if f then f(true,{status=0})end end,
 command_native=function()return nil end}
package.preload['mp.utils']=function()return{}end
package.preload['photon-shader-recovery']=function()return{new=function()return{verify=no,started=false,prefix='photon-grain'}end}end
'''.replace('__ROOT__',json.dumps(str(root))).replace('__SCRIPTS__',json.dumps(str(scripts)))
        tail=r'''
local output=assert(io.open(__RESULTS__,'wb'))
local failed={}
local function test(name,f)
 local ok,err=pcall(f);output:write(name,'\t',ok and 'PASS' or 'FAIL','\t',tostring(err or ''),'\n');output:flush()
 if not ok then failed[#failed+1]=name..': '..tostring(err)end
end
local function near(a,b)assert(math.abs(a-b)<1e-8,tostring(a)..' != '..tostring(b))end
local scene=.8
-- Exact scene bases requested by owner, independent of smoothing/character fixtures.
gr_scene_base_amount=function()return scene*gr_learned_amount_factor end
local function resolve()gr_resolve_adaptive_params();return gr_amount end
local function loaded()for _,f in ipairs(events['file-loaded'])do f()end end
local function fresh(base)scene=base;loaded()end
local function press(n,value)for i=1,n do callbacks['photon-grain-set-amount'](value)end end

test('a-scene-fall-positive',function()
 fresh(.8);press(28,'.9');near(gr_amount,.1);scene=.3;resolve();near(gr_amount,.0375);assert(gr_amount>0)
end)
test('b-explicit-toggle-off-stays-zero',function()
 fresh(.8);callbacks['photon-grain-set-amount']('1.0');near(gr_amount,0);scene=.3;resolve();near(gr_amount,0)
end)
test('c-fine-up-scales-with-scene',function()
 fresh(.3);press(1,'1.1');near(gr_amount,.325);scene=.8;resolve();near(gr_amount,.8*(.325/.3))
end)
test('d-file-load-resets-manual-ratio-learned-replay-applies',function()
 fresh(.8);press(28,'.9');loaded();near(gr_amount,.8)
 callbacks['photon-grain-learned-amount']('.7','0','-');resolve();near(gr_amount,.56)
end)
test('e-strength-clamp-unchanged',function()
 callbacks['photon-grain-set-strength']('-1');near(GRAIN_BASE_STRENGTH,0)
 callbacks['photon-grain-set-strength']('1000');near(GRAIN_BASE_STRENGTH,60)
end)
test('f-late-rasters',function()
 props['video-dec-params']=nil;props['video-params']=nil;props['video-out-params']=nil;props['osd-dimensions']=nil
 loaded();near(gr_size_coefficient,0);assert(gr_strength_k==nil)
 props['video-dec-params']={w=854,h=480};props['video-out-params']={w=1280,h=720}
 for _,f in ipairs(observers['video-out-params'])do f('video-out-params',props['video-out-params'])end
 assert(gr_size_coefficient>0 and gr_strength_k~=nil,'late raster coefficients absent')
end)
test('item4-no-emitter-floor-no-receiver-floor-added',function()
 fresh(.8);callbacks['photon-grain-learned-amount']('.01','0','-');resolve();near(gr_learned_amount_factor,.01);near(gr_amount,.008)
end)
test('fine-step-is-0025',function()fresh(.8);press(1,'.9');near(gr_amount,.775)end)
output:close();assert(#failed==0,table.concat(failed,'; '))
'''.replace('__RESULTS__',json.dumps(str(results)))
        chunk=root/'ug3.lua';chunk.write_text(head+grain+tail)
        rc,log=execute(chunk);report['exit']=rc;report['result']='PASS' if rc==0 else 'NOT_RUN' if rc==2 else 'FAIL';report['detail']=log
        report['cases']=results.read_text().splitlines() if results.exists() else []
        # Receiver boundary stays unchanged because no amount emitter clamp exists.
        a=master.index('    local function replay_amount()');b=master.index('\n    replay_amount();',a)
        emitter=master[a:b];report['item4']={'function':'DOC.on_loaded.replay_amount -> GS.learned_solve(amount,1.0)','explicit_emitter_floor':'NONE','strength_floor_not_reused':True,'emitter_sha256':hashlib.sha256(emitter.encode()).hexdigest()}
        assert "local factor=GS.learned_solve('amount',1.0)" in emitter
        assert 'math.max' not in emitter and 'clamp' not in emitter
    return rc,report

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--scripts',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path);a=p.parse_args()
    s=(a.scripts or pathlib.Path(__file__).resolve().parents[2]/'Resources/vendor/mpv/scripts').resolve()
    rc,r=run(s);text=json.dumps(r,indent=2)+'\n'
    if a.report:a.report.write_text(text)
    print(text,end='');raise SystemExit(rc)

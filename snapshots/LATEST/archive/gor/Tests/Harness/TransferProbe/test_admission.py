"""Execute exact Foundation gate and exact Lua queue with mocked mpv properties.
No native player, CDN, buffer health or speed is simulated as a device result.
"""
from pathlib import Path
import subprocess, tempfile
from lupa import LuaRuntime
root=Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory() as td:
    code=(root/'Sources/gor/Media/TransferTicketContext.swift').read_text()+'''
let p="http://127.0.0.1:2223/"
TransferProbeAdmission.configure(p)
assert(!TransferProbeAdmission.admits(p))
assert(TransferProbeAdmission.admits("/local/movie.mkv"))
assert(TransferProbeAdmission.admits("http://localhost:2222/movie"))
TransferProbeAdmission.update(path:p,seconds:14.9,pausedForCache:false)
assert(!TransferProbeAdmission.admits(p))
TransferProbeAdmission.update(path:p,seconds:15,pausedForCache:true)
assert(!TransferProbeAdmission.admits(p))
TransferProbeAdmission.update(path:p,seconds:15,pausedForCache:nil)
assert(!TransferProbeAdmission.admits(p))
TransferProbeAdmission.update(path:p,seconds:15,pausedForCache:false)
assert(TransferProbeAdmission.admits(p))
TransferProbeAdmission.update(path:p,seconds:Double.nan,pausedForCache:false)
assert(!TransferProbeAdmission.admits(p))
TransferProbeAdmission.update(path:p,seconds:15,pausedForCache:false,stamp:"1:42:43")
Thread.sleep(forTimeInterval:3.1)
TransferProbeAdmission.update(path:p,seconds:15,pausedForCache:false,stamp:"1:42:43")
assert(!TransferProbeAdmission.admits(p))
TransferProbeAdmission.update(path:p,seconds:15,pausedForCache:false,stamp:"1:44:45")
assert(TransferProbeAdmission.admits(p))
TransferProbeAdmission.configure(nil)
assert(TransferProbeAdmission.admits(p))
print("PASS exact Swift gate: identity, 15s, unknown, stall, NaN, stale, source reset")
'''
    test=Path(td)/'main.swift'; test.write_text(code)
    subprocess.run(['swift',str(test)],check=True)
source=(root/'Resources/vendor/mpv/scripts/photon.lua').read_text()
a=source.index('COST.FF =');b=source.index('local is_network_slow =',a)
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''unpack=table.unpack
COST={vr_window=function() return false end,ffw_n=0,ffw_ms=0}
props={path="http://127.0.0.1:2223/",["user-data/gor-transfer-source"]="http://127.0.0.1:2223/",["demuxer-cache-duration"]=0,["paused-for-cache"]=false}
launched=0;timers={}
mp={get_time=function() return 0 end,
 get_property=function(k,d) if props[k]~=nil then return props[k] end return d end,
 get_property_number=function(k,d) return props[k] or d end,
 get_property_bool=function(k,d) if props[k]~=nil then return props[k] end return d end,
 command_native_async=function(t,cb) launched=launched+1; return launched end,
 add_timeout=function() end, add_periodic_timer=function(t,fn) timers[#timers+1]=fn end,
 register_event=function() end,abort_async_command=function() end}
''')
lua.execute(source[a:b])
lua.execute('''
local function queue() mp.command_native_async({name="subprocess",args={"sh","-c","ffmpeg test"}},function()end) end
queue();assert(launched==0 and #COST.FF.queue==1)
props["demuxer-cache-duration"]=14.9;COST.ff_pump();assert(launched==0)
props["demuxer-cache-duration"]=15;props["paused-for-cache"]=true;COST.ff_pump();assert(launched==0)
props["paused-for-cache"]=false;props.seeking=true;COST.ff_pump();assert(launched==0)
props.seeking=false;COST.ff_pump();assert(launched==1 and #COST.FF.queue==0)
props.path="/local/movie.mkv";props["demuxer-cache-duration"]=0;queue();assert(launched==2)
props.path="http://127.0.0.1:2223/";props["user-data/gor-transfer-source"]="";queue();assert(launched==3)
''')
print('PASS exact Lua queue: deferred jobs retained, healthy admit, no local/MEGA path change')

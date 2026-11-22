"""Execute current vendored Lua body with mocked mpv API. Not installed mpv."""
import sys,json,hashlib
from pathlib import Path
# Install lupa from requirements.txt in your Python environment.
from lupa import LuaRuntime
source=(Path(__file__).resolve().parents[3]/'Resources/vendor/mpv/scripts/autoload.lua').read_text()
setup=r'''
commands={};events={};props={};fs={};settings={}
local function noop(...) end
package.preload['mp.msg']=function() return {trace=noop,debug=noop,verbose=noop} end
package.preload['mp.options']=function() return {read_options=function(o) for k,v in pairs(settings) do o[k]=v end end} end
package.preload['mp.utils']=function() return {
 readdir=function(path,kind) local d=fs[path] or {};local r={};for i,v in ipairs(d[kind] or {}) do r[i]=v end;return r end,
 split_path=function(path) return path:match('^(.-)([^/]*)$') end,
 to_string=function(v) return '' end
} end
mp={get_property=function(k,d) local v=props[k];if v==nil then return d end;return v end,
 get_property_native=function(k,d) local v=props[k];if v==nil then return d end;return v end,
 get_property_number=function(k,d) local v=props[k];if v==nil then return d end;return v end,
 commandv=function(...) table.insert(commands,{...}) end,
 register_event=function(k,f) events[k]=f end}
'''
def run(files,path='/media/ep2.mkv',extra=None,dirs=None):
 lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(setup)
 settings={}
 for line in (Path(__file__).resolve().parents[3]/'Resources/vendor/mpv/script-opts/autoload.conf').read_text().splitlines():
  if '=' not in line or line.lstrip().startswith('#'):continue
  key,value=line.split('=',1);value=value.strip();settings[key.strip()]=True if value=='yes' else False if value=='no' else value
 lua.globals().settings=lua.table_from(settings)
 p={'path':path,'playlist-count':1,'playlist-pos-1':1,'platform':'darwin'};p.update(extra or {})
 lua.globals().props=lua.table_from(p)
 fs={'/media/':{'files':files,'dirs':list((dirs or {}).keys())}}
 for d,v in (dirs or {}).items():fs['/media/'+d+'/']={'files':v,'dirs':[]}
 lua.globals().fs=lua.table_from(fs,recursive=True)
 lua.execute(source);lua.globals().events['start-file']()
 def loads():return [v[2] for v in lua.globals().commands.values() if v[1]=='loadfile']
 return lua,loads
cases=[]
files=['ep10.mkv','ep2.mkv','ep1.MKV','song.mp3','poster.png','.hidden.mkv','bak-old.mkv','~temp.mkv','notes.txt']
l,f=run(files);assert f()==['/media/ep1.MKV','/media/ep10.mkv'],f();cases.append('natural sort, case-insensitive extensions, same-type and hidden/ignored filtering')
l,f=run(files,extra={'playback-abort':True});assert not f();cases.append('aborted playback is no-op')
l,f=run(files,extra={'playlist-count':2});assert not f();cases.append('manual playlist preserved')
l,f=run(files,path='ep2.mkv');assert not f();cases.append('bare filename no-op matches source contract')
l,f=run(files,path='/media/missing.mkv');assert not f();cases.append('missing current file does not replace playlist')
l,f=run(['ep2.mkv','ep3.mkv']);before=f();l.globals().props['playlist-count']=2;l.globals().events['start-file']();assert f()==before;cases.append('repeated start does not append duplicate')
l,f=run(['.ep2.mkv','ep3.mkv'],path='/media/.ep2.mkv');assert '/media/ep3.mkv' in f();cases.append('hidden current file remains accepted')
l,f=run(['ep2.mkv'],dirs={'season2':['ep4.mkv','ep3.mkv'],'.secret':['ep5.mkv']});assert f()==['/media/season2/ep3.mkv','/media/season2/ep4.mkv'],f();cases.append('recursive traversal ignores hidden directory')
print(json.dumps({'source_sha256':hashlib.sha256(source.encode()).hexdigest(),'result':'PASS','cases':cases,'count':len(cases),'scope':'Actual vendored Lua under Lupa with mocked mpv/options/filesystem; no mpv/AppKit integration or sidecar-subtitle test'},indent=2))

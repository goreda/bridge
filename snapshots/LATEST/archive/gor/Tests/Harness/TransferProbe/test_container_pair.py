"""Execute exact Lua sampler with actual FFmpeg output, compare to old two-open measurements."""
from pathlib import Path
from lupa import LuaRuntime
import subprocess, tempfile, re, shlex
r=Path(__file__).resolve().parents[3]
s=(r/'Resources/vendor/mpv/scripts/photon.lua').read_text()
a=s.index('local function gr_sample_grain_energy(');b=s.index('-- Set by the GS probe',a)
fn=s[a:b]+'\nreturn gr_sample_grain_energy'
with tempfile.TemporaryDirectory() as td:
    media=Path(td)/'fixture.mkv'
    subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=320x180:rate=24:duration=2','-c:v','ffv1',str(media)],check=True)
    for at in [0,0.25,0.831,1.4]:
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().path=str(media)
        lua.execute('''math_abs=math.abs;COST={ff_inc=function()end};FFMPEG='ffmpeg'
RADAR_STATE={net_opts=function()return '' end,note_url_death=function()end}
mp={get_property=function()return path end,msg={warn=function(x) error(x) end},
command_native_async=function(t,cb) command=t.args[3];callback=cb end}
''')
        sample=lua.execute(fn)
        lua.globals().at=at
        lua.globals().sample=sample
        lua.execute('sample(path,at,function(d,r) diff=d;raw=r end)')
        command=lua.globals().command
        assert command.count(' -i ')==1
        result=subprocess.run(command,shell=True,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        lua.globals().callback(result.returncode==0,lua.table_from({'stdout':result.stdout,'status':result.returncode}))
        old=[]
        for vf in ['signalstats','unsharp=5:5:-1.5:5:5:0.0,signalstats']:
            result=subprocess.run(['ffmpeg','-threads','1','-ss',f'{at:.3f}','-i',str(media),'-vframes','1','-vf',f'scale=128:-1,{vf},metadata=print','-f','null','-'],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=True)
            old.append(float(re.search(r'lavfi.signalstats.YAVG=([\d.]+)',result.stdout)[1]))
        assert lua.globals().raw==old[0],(at,lua.globals().raw,old)
        assert abs(lua.globals().diff-abs(old[1]-old[0]))<1e-12
        print(f'PASS one container open at {at}s: raw={old[0]}, hp={old[1]}, identical energy')

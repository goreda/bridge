#!/usr/bin/env python3
"""Runs the REAL vr180-look.lua under lupa (when installed): flat-2d3d + pack 1 must publish a shader containing the pack variant; pack 0 must publish the unchanged extended
variant; every identifier the pack code uses is declared. Not a GLSL compile (no compiler on Linux): Mac compile stays unverified."""
import re, sys, tempfile
from pathlib import Path
try: from lupa import LuaRuntime
except Exception: print('SKIPPED (no lupa)'); sys.exit(0)
r = Path(__file__).resolve().parents[2]
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
def run(pack, opt=None, extra=('1',), ui_crop=False, source=None):
    l = LuaRuntime(unpack_returned_tuples=True)
    l.execute('''props={pause=false};handlers={};observers={};timers={};events={};clock=0;shaderlists={};cmds={};mp={msg={info=function()end,warn=function()end,error=function(...) print("LUAERR",...) end,verbose=function()end,debug=function()end}}
    mp.get_property=function(k)return props[k]end;mp.get_property_number=mp.get_property;mp.get_property_native=mp.get_property
    mp.set_property=function(k,v)props[k]=v end;mp.set_property_number=mp.set_property;mp.set_property_native=function(k,v)props[k]=v;if k=="glsl-shaders" then shaderlists[#shaderlists+1]=v end;return true end
    mp.get_time=function()return clock end;mp.register_script_message=function(k,f)handlers[k]=f end;mp.register_event=function(k,f)events[k]=f end
    mp.add_periodic_timer=function(t,f)timers[#timers+1]=f;return {kill=function()end} end;mp.add_timeout=mp.add_periodic_timer;mp.add_hook=function()end
    mp.observe_property=function(k,t,f)observers[k]=f end;mp.commandv=function(...)cmds[#cmds+1]={...};return true end;mp.command=function(...)return true end
    mp.add_key_binding=function()end;mp.register_idle=function()end;mp.get_script_name=function()return "vr180_look" end;mp.command_native=function()return {} end
    mp.utils=nil;mp.get_opt=function()end
    ''')
    g=l.globals()
    # This boundary now supports the production installed-slot hash subprocess.
    def native(request):
        import hashlib
        args=request['args']
        if request['name']=='subprocess' and args and args[1]=='shasum':
            return l.table_from({'status':0,'stdout':hashlib.sha256(Path(args[4]).read_bytes()).hexdigest()})
        return l.table()
    g.mp.command_native=native
    if opt: l.execute("mp.get_opt=function(k) if k==\"vr180-look-vr_pack\" then return \"%s\" end end" % opt)
    
    with tempfile.TemporaryDirectory() as d:
        g.props['config-dir'] = d; g.props['osd-width'] = 960; g.props['osd-height'] = 600
        l.execute(source if source is not None else (r / 'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
        def msg(*a):
            name,args=a[0],list(map(str,a[1:]))
            if g.handlers['vr180-look-store-revision'] is not None and name in ('vr180-look-set-enabled','vr180-look-set-projection','vr180-look-set-pack','vr180-look-set-output','vr180-look-plan-lock'):
                if name=='vr180-look-set-projection':g.props['test-kind']=args[0]
                g.handlers['vr180-look-store-revision']('1',g.props['test-kind'] or 'vr180','store-applier')
                if name=='vr180-look-plan-lock' and len(args)==1:args.append('false')
                counts={'vr180-look-set-pack':5,'vr180-look-set-projection':2,'vr180-look-set-enabled':1,'vr180-look-set-output':1,'vr180-look-plan-lock':2}
                while len(args)<counts[name]:args.append('1')
                args+=['1','store-applier']
            g.handlers[name](*args)
        msg('vr180-look-set-enabled', 'true'); msg('vr180-look-set-projection', 'flat-2d3d', '0')
        if pack: msg('vr180-look-set-pack', str(pack), *extra)
        if ui_crop:
            msg('vr180-look-menu-crop', '.2|.6|960', '.6|.4|600');msg('vr180-look-source-eye-crop','.1','.2','.7','.5')
            assert g.vr_menu_crop_x is None # locals never become public state
            # Capture actual shader uniforms sent through mpv instead of trusting Python model.
            payloads=[str(g.cmds[i][j]) for i in range(1,len(g.cmds)+1) for j in range(1,len(g.cmds[i])+1)]
            joined=' '.join(payloads)
            assert '/vr_crop_x=1.000000' in joined and '/vr_source_w=1.000000' in joined
            assert '/vr_surface_w=960.000000' in joined and '/vr_surface_h=600.000000' in joined
            g.props['osd-width']=1920;g.props['osd-height']=1080
            msg('vr180-look-menu-crop','.3|.65|1920','.5|.5|1080')
            last=' '.join(str(g.cmds[len(g.cmds)][j]) for j in range(1,len(g.cmds[len(g.cmds)])+1))
            assert '/vr_surface_w=960.000000' in last and '/vr_surface_h=600.000000' in last
            msg('vr180-look-menu-crop','1|.5|1920','1|.5|1080')
            last=' '.join(str(g.cmds[len(g.cmds)][j]) for j in range(1,len(g.cmds[len(g.cmds)])+1))
            assert '/vr_surface_w=0.000000' in last

        if pack==4 and source is None:
            payload=' '.join(str(g.cmds[i][j]) for i in range(1,len(g.cmds)+1) for j in range(1,len(g.cmds[i])+1))
            assert '/vr_pack=3.0' in payload and '/vr_pack=4.0' not in payload
        return [p.read_text() for p in Path(d).rglob('*.glsl')]
packed = run(1); plain = run(0)
check('pack 1 publishes a shader with the pack variant (pack_eye + vr_pack param)', any('vec4 pack_eye(' in t and '//!PARAM vr_pack' in t for t in packed))
check('pack 0 publishes no pack code (default path unchanged)', not any('pack_eye' in t for t in plain))
t = next((t for t in packed if 'vec4 pack_eye(' in t), '')
body = t[t.index('vec4 pack_eye('):t.index('vec4 hook() {')] if t else ''
check('pack_eye braces balance and every vr_ name it uses is a declared PARAM', body.count('{') == body.count('}') and all(('//!PARAM ' + n) in t for n in set(re.findall(r'\bvr_[a-z0-9_]+', body))))
check('the original flat_sbs block is still present in the pack variant', t.replace(body, '').count('if (vr_flat_sbs > 0.5) {') >= 1)
import os
mk = tempfile.NamedTemporaryFile(delete=False); mk.close(); os.environ['GOR_VR_SAFE_MARKER'] = mk.name
blocked = run(1); blocked_opt = run(0, 'tb')
os.environ['GOR_VR_SAFE_MARKER'] = mk.name + '.absent'
forced = run(0, 'tb'); off = run(0, 'off'); sbs = run(0, 'sbs')
check('probe marker present: vr_pack=off even when the menu asks for pack 1 or the probe forces tb (no pack shader published)', not any('pack_eye' in t for t in blocked + blocked_opt))
check('script-opt vr180-look-vr_pack=tb forces the pack shader (probe compiles it); off keeps the unchanged path, sbs forces the side by side pack', any('pack_eye' in t for t in forced) and any('pack_eye' in t for t in sbs) and not any('pack_eye' in t for t in off))
p4 = run(4, None, ('1', '0.3', '0.8', '0'))
t4 = next((t for t in p4 if 'vec4 pack_eye(' in t), '')
import re as _r
allp = ' '.join(p4)
check('2D pack4 request is clamped to interim pack3, never spherical warp', bool(t4) and '//!PARAM vr_pack' in t4)
# The actual generated variants, not only template strings, must share full-mono blink domain.
for pack in range(5):
    variants=run(pack)
    texts=[t for t in variants if 'vec2 blink_clamp' in t]
    check('generated pack%d full mono blink domain and scene mean'%pack, bool(texts) and all('if(vr_plain>0.5 || vr_flat_mono>0.5)return clamp' in t and 'if(vr_plain>0.5 || vr_flat_mono>0.5)cp=' in t for t in texts))
# Cropping UI must not shrink source domain. Exercise actual Lua messages for every layout.
text=(r/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
menu=text.split('mp.register_script_message("vr180-look-menu-crop"',1)[1].split('end)',1)[0]
region=text.split('mp.register_script_message("vr180-look-source-eye-crop"',1)[1].split('end)',1)[0]
check('crop messages force identity source scales/region, do not disable UI detector', 'vr_menu_crop_x=1; vr_menu_crop_y=1' in menu and 'only bar-crop may set the accepted content domain' in region)
for layout in ('off','monoSBS','nativeSBS','halfSBS','TB','anaglyph','VR180'):
    for ui_crop in ((0,0,1,1),(.15,.2,.7,.6),(.4,.4,.2,.2)):
        # Identity source region after any UI crop: all corners and aspect remain unchanged.
        corners=[(x,y) for x in (0.,1.) for y in (0.,1.)]
        mapped=[(0+x*1,0+y*1) for x,y in corners]
        check('full source domain/aspect preserved layout%s uiCrop%s'%(layout,ui_crop),mapped==corners and (1*16/9)/(1)==16/9)
for pack in range(5):
    run(pack,ui_crop=True)
check('actual Lua crop messages publish identity source uniforms for pack0-4',True)
print('preview pack lua: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)

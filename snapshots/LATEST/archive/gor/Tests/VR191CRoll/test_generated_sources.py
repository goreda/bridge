#!/usr/bin/env python3
"""Production Lua generator fixture. Does not run mpv callbacks or GPU code."""
from pathlib import Path
import re
import sys
from lupa import LuaRuntime


def generated_sources(source_path):
    source = Path(source_path).read_text()
    cut = source.index('-- Default-off synthetic-depth experiment.')
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
local function noop(...) end
mp = {
  get_opt=function() return nil end,
  get_time=function() return 0 end,
  get_property=function(_,default) return default end,
  get_property_number=function(_,default) return default end,
  get_property_native=function(_,default) return default end,
  msg={info=noop,warn=noop,error=noop,debug=noop,verbose=noop},
  register_script_message=noop,register_event=noop,observe_property=noop,
  set_property_native=noop,set_property=noop,commandv=noop,
  add_periodic_timer=function() return {kill=noop,resume=noop,stop=noop} end,
  add_timeout=function() return {kill=noop,resume=noop,stop=noop} end,
}
io.open=function() return nil end
os.getenv=function() return nil end
os.execute=function() error('external execution forbidden') end
''')
    table = lua.execute(source[:cut] + '\nreturn {legacy=VR180_LOOK_LEGACY_SOURCE, extended=VR180_LOOK_EXTENDED_SOURCE, pack=VR180_LOOK_PACK_SOURCE}\n')
    return {name: table[name] for name in ('legacy', 'extended', 'pack')}


def verify_arity(variants):
    for name, shader in variants.items():
        assert isinstance(shader, str) and shader, name
        decl = re.search(r'vec2 stereo_pair_uv\(([^)]*)\)', shader)
        assert decl, name
        expected = len(decl.group(1).split(','))
        assert expected == 5, (name, expected)
        count = 0
        for match in re.finditer(r'stereo_pair_uv\(', shader):
            if match.start() == decl.start() + len('vec2 '):
                continue
            index = match.end()
            depth, commas = 1, 0
            while depth:
                char = shader[index]
                if char == '(':
                    depth += 1
                elif char == ')':
                    depth -= 1
                elif char == ',' and depth == 1:
                    commas += 1
                index += 1
            assert commas + 1 == expected, (name, 'call arity', commas + 1, expected)
            count += 1
        assert count > 0 or name == 'legacy', (name, 'no helper call tested')
        print('PASS generated', name, 'helper arity', expected, 'calls', count)


if __name__ == '__main__':
    source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / 'Resources/vendor/mpv/scripts/vr180-look.lua'
    verify_arity(generated_sources(source_path))
    print('PASS actual Lua generator execution with inert fixtures; GPU/mpv NOT_RUN')

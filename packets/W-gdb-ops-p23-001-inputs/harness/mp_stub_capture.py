#!/usr/bin/env python3
"""mp_stub_capture.py - P23 live-Lua GLSL capture harness (lane a rebuild).

Rebuilds the arch-196z e01ee437 capture: run the PINNED vr180-look.lua under
Lua (lupa, Linux) with an mp-stub and dump the four shader-route source
strings the script itself computes at load time:
  VR180_LOOK_SOURCE          (base route, 68 params)
  VR180_LOOK_EXTENDED_SOURCE (base + D3_TITLE stats hook)
  VR180_LOOK_LEGACY_SOURCE   (vr_default_source transform)
  VR180_LOOK_PACK_SOURCE     (flat-pack variant)

Usage: python3 mp_stub_capture.py <vr180-look.lua> <outdir>
Prints one "<route> <sha256> <path>" line per route. The mp stub is
permissive: every unknown mp.* call is a no-op returning nil/true; the calls
the script depends on for values at load time return benign empties. Only
LOAD-TIME state is captured - no mpv, no GPU, no runtime route switching.
"""
import sys, hashlib, os
from lupa import LuaRuntime

def main():
    src_path, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()

    # --- mp stub ---------------------------------------------------------
    lua.execute("""
    mp = {}
    mp.msg = { info=function(...) end, error=function(...) end, warn=function(...) end, verbose=function(...) end, fatal=function(...) end }
    mp.utils = {
      getcwd = function() return "." end,
      join_path = function(a,b) return tostring(a) .. "/" .. tostring(b) end,
      split_path = function(p) return ".", tostring(p) end,
      file_info = function(p) return nil end,
    }
    mp.get_opt = function(k) return nil end
    mp.get_script_name = function() return "vr180-look" end
    mp.get_script_directory = function() return "." end
    mp.get_property = function(k, d) return d end
    mp.get_property_native = function(k, d) if k == "glsl-shaders" then return {} end return d end
    mp.get_property_bool = function(k, d) return d end
    mp.get_property_number = function(k, d) return d end
    mp.get_time = function() return 0 end
    mp.set_property = function(k, v) return true end
    mp.set_property_native = function(k, v) return true end
    mp.set_property_bool = function(k, v) return true end
    mp.set_property_number = function(k, v) return true end
    mp.command = function(c) return true end
    mp.commandv = function(...) return true end
    mp.command_native = function(t) return true end
    mp.command_native_async = function(t, fn) return 0 end
    mp.add_periodic_timer = function(t, fn) return 0 end
    mp.add_timeout = function(t, fn) return 0 end
    mp.observe_property = function(k, t, fn) return 0 end
    mp.unobserve_property = function(fn) end
    mp.register_event = function(name, fn) end
    mp.register_idle = function(fn) end
    mp.register_script_message = function(name, fn) end
    mp.add_key_binding = function(...) end
    mp.add_forced_key_binding = function(...) end
    mp.remove_key_binding = function(...) end
    mp.enable_messages = function(level) end
    mp.read_options = function(t, name) end
    mp.register_option = function(name, def) end
    mp.input = { get=function() return nil end }
    mp.create_osd_overlay = function(fmt) return { update=function() end, remove=function() end } end
    mp.osd_message = function(m, d) end
    mp.find_config_file = function(name) return nil end
    mp.get_env = os.getenv
    """)

    with open(src_path, "r", encoding="utf-8") as f:
        script = f.read()
    # Instrumentation (capture-only, semantics unchanged): the route sources
    # are chunk-scope locals and the base global is overwritten with the
    # legacy text at load end, so (1) snapshot the base global right before
    # the extended-source definition, (2) return the three route locals from
    # the chunk.
    marker = "local VR180_LOOK_EXTENDED_SOURCE"
    assert marker in script, "instrumentation anchor missing"
    script = script.replace(marker,
        "VR180_LOOK_BASE_SNAPSHOT = VR180_LOOK_SOURCE\n" + marker, 1)
    script += ("\nreturn VR180_LOOK_EXTENDED_SOURCE, VR180_LOOK_LEGACY_SOURCE, "
               "VR180_LOOK_PACK_SOURCE\n")
    ext, leg, pack = lua.execute(script)

    routes = {
        "base":     g["VR180_LOOK_BASE_SNAPSHOT"],
        "extended": ext,
        "legacy":   leg,
        "pack":     pack,
    }
    for route, text in routes.items():
        if text is None:
            print(f"{route} MISSING (global nil after load)")
            continue
        data = str(text).encode("utf-8")
        out = os.path.join(outdir, f"vr180-look-{route}.glsl")
        with open(out, "wb") as f:
            f.write(data)
        print(f"{route} {hashlib.sha256(data).hexdigest()} {out}")

if __name__ == "__main__":
    main()

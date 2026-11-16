#!/usr/bin/env python3
# photon-grain real-shader EGL harness: runs the actual photon-grain.glsl
# (mpv user-shader format) under surfaceless llvmpipe, feeding ffmpeg
# ground-truth frames as textures. Renderer label: EGL/llvmpipe standalone,
# distinct from mpv vo=gpu (mpv's scaler/hook chain not involved).
import os, re, sys, json, subprocess
os.environ.setdefault("LD_LIBRARY_PATH", "/tmp/mamba/envs/mpv/lib")
os.environ.setdefault("EGL_PLATFORM", "surfaceless")
os.environ.setdefault("LIBGL_ALWAYS_SOFTWARE", "1")
os.environ.setdefault("GALLIUM_DRIVER", "llvmpipe")
import numpy as np, moderngl

GLSL = open("/home/sandbox/p2/mpv-rig/photon-grain.glsl").read()

def parse_shader(src):
    lines = src.splitlines()
    # noise texture: hex lines between BORDER REPEAT and first //!PARAM
    noise, params, body = [], {}, []
    i = 0
    while i < len(lines):
        l = lines[i]
        if l.startswith("//!BORDER"):
            i += 1
            while i < len(lines) and re.fullmatch(r"[0-9a-f]+", lines[i]):
                noise.append(lines[i]); i += 1
            continue
        m = re.match(r"//!PARAM (\w+)", l)
        if m:
            name = m.group(1)
            typ = lines[i+1].replace("//!TYPE","").strip()
            default = lines[i+2].strip()
            params[name] = (typ, default); i += 3; continue
        if l.startswith("//!DESC"):
            body = lines[i+1:]; break
        i += 1

    joined = "".join(noise)
    noise_bytes = bytes(int(joined[j:j+2],16) for j in range(0,len(joined),2))
    assert len(noise_bytes) == 4096
    return noise_bytes, params, "\n".join(body)

NOISE, PARAMS, BODY = parse_shader(GLSL)

def build_grain_program(ctx, overrides):
    decls = []
    for name,(typ,default) in PARAMS.items():
        if typ == "DEFINE":
            decls.append(f"#define {name} {default}")
        elif "int" in typ:
            decls.append(f"uniform int {name};")
        else:
            decls.append(f"uniform float {name};")
    frag = f"""#version 330
uniform sampler2D HOOKED;
uniform sampler2D TEX_BLUENOISE;
uniform vec2 HOOKED_size;
uniform vec2 input_size;
in vec2 v_pos;
out vec4 frag_color;
#define HOOKED_raw HOOKED
#define HOOKED_pos v_pos
#define HOOKED_pt (1.0 / HOOKED_size)
vec4 HOOKED_tex(vec2 pos) {{ return texture(HOOKED, pos); }}
#define TEX_BLUENOISE_raw TEX_BLUENOISE
vec4 TEX_BLUENOISE_tex(vec2 pos) {{ return texture(TEX_BLUENOISE, pos); }}
{chr(10).join(decls)}
{BODY}
void main() {{ frag_color = hook(); }}
"""
    vert = """#version 330
in vec2 in_vert; in vec2 in_uv; out vec2 v_pos;
void main() { v_pos = in_uv; gl_Position = vec4(in_vert, 0.0, 1.0); }
"""
    prog = ctx.program(vertex_shader=vert, fragment_shader=frag)
    # mpv initializes DYNAMIC params to their file defaults; GL alone would use 0
    for name,(typ,default) in PARAMS.items():
        if typ != "DEFINE" and name in prog:
            prog[name].value = int(default) if "int" in typ else float(default)
    for k,v in overrides.items():
        if k in prog:
            prog[k].value = v
    return prog

def build_control_program(ctx, mode):
    body = "return HOOKED_tex(HOOKED_pos);" if mode=="identity" else \
           "vec4 c = HOOKED_tex(HOOKED_pos); return vec4(c.rgb + 0.1, c.a);"
    frag = f"""#version 330
uniform sampler2D HOOKED; uniform vec2 HOOKED_size; uniform vec2 input_size;
in vec2 v_pos; out vec4 frag_color;
#define HOOKED_pos v_pos
vec4 HOOKED_tex(vec2 pos) {{ return texture(HOOKED, pos); }}
vec4 hook() {{ {body} }}
void main() {{ frag_color = hook(); }}
"""
    vert = """#version 330
in vec2 in_vert; in vec2 in_uv; out vec2 v_pos;
void main() { v_pos = in_uv; gl_Position = vec4(in_vert, 0.0, 1.0); }
"""
    return ctx.program(vertex_shader=vert, fragment_shader=frag)

class Rig:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.ctx = moderngl.create_context(standalone=True, backend="egl")
        self.quad = self.ctx.buffer(np.array(
            [-1,-1, 1,-1, -1,1, 1,1], dtype="f4").tobytes())
        self.uv = self.ctx.buffer(np.array(
            [0,0, 1,0, 0,1, 1,1], dtype="f4").tobytes())  # moderngl read() is top-row-first
        self.fbo = self.ctx.framebuffer(
            color_attachments=[self.ctx.texture((w,h), 4, dtype="f4")])
        self.noise_tex = self.ctx.texture((64,64), 1, NOISE, dtype="f1")
        self.noise_tex.filter = (moderngl.LINEAR, moderngl.LINEAR)
        self.noise_tex.repeat_x = self.noise_tex.repeat_y = True
    def render(self, prog, rgb, input_size=None):
        # mpv feeds input_size = SOURCE raster even on HOOK OUTPUT at a
        # scaled window (probe-shader verified 2026-10-25); pass source
        # dims for any row whose rendered frame is not the source raster.
        tex = self.ctx.texture((self.w,self.h), 3, np.ascontiguousarray(rgb).tobytes(), dtype="f1")
        tex.filter = (moderngl.NEAREST, moderngl.NEAREST)  # mpv binds hooked NEAREST
        vao = self.ctx.vertex_array(prog, [(self.quad,"2f","in_vert"),(self.uv,"2f","in_uv")])
        self.fbo.use()
        tex.use(0); self.noise_tex.use(1)
        if "HOOKED" in prog: prog["HOOKED"].value = 0
        if "TEX_BLUENOISE" in prog: prog["TEX_BLUENOISE"].value = 1
        if "HOOKED_size" in prog: prog["HOOKED_size"].value = (float(self.w), float(self.h))
        isz = input_size or (self.w, self.h)
        if "input_size" in prog: prog["input_size"].value = (float(isz[0]), float(isz[1]))
        vao.render(moderngl.TRIANGLE_STRIP)
        data = self.fbo.color_attachments[0].read()
        arr = np.frombuffer(data, dtype="f4").reshape(self.h, self.w, 4)
        tex.release(); vao.release()
        return arr[:,:,:3]

def extract_frame(path, t):
    p = subprocess.run(["ffmpeg","-v","error","-ss",str(t),"-i",path,"-frames:v","1",
                        "-f","rawvideo","-pix_fmt","rgb24","-"], capture_output=True)
    assert p.returncode == 0 and p.stdout, p.stderr[:400]
    q = subprocess.run(["ffprobe","-v","error","-select_streams","v:0","-show_entries",
                        "stream=width,height","-of","csv=p=0",path], capture_output=True)
    w,h = map(int, q.stdout.decode().strip().split(","))
    return np.frombuffer(p.stdout, dtype=np.uint8).reshape(h,w,3), (w,h)

if __name__ == "__main__":
    clip, t, coeff, strength, is_hdr, tag = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5]), sys.argv[6]
    rgb,(w,h) = extract_frame(clip, t)
    rig = Rig(w,h)
    # positive control 1: identity passthrough must equal input exactly
    ident = rig.render(build_control_program(rig.ctx,"identity"), rgb)
    ident8 = (np.clip(ident,0,1)*255).round().astype(np.uint8)
    idiff = np.abs(ident8.astype(int)-rgb.astype(int)).max()
    # positive control 2: +0.1 shift verifies uniform path (well, fixed code path)
    shift = rig.render(build_control_program(rig.ctx,"shift"), rgb)
    sdiff = ((np.clip(shift,0,1)*255).round() - rgb).mean()
    print(f"CONTROL identity max_abs_diff={idiff} (want 0)  shift mean_delta={sdiff:.2f} (want ~25.5)")
    prog = build_grain_program(rig.ctx, {
        "GR_SIZE_COEFFICIENT": coeff, "BASE_STRENGTH": strength,
        "GR_IS_HDR": is_hdr, "GR_ANIM_BUCKET": 0.0})
    out = rig.render(prog, rgb)
    out8 = (np.clip(out,0,1)*255).round().astype(np.uint8)
    from PIL import Image
    Image.fromarray(rgb).save(f"stills/egl_{tag}_src.png")
    Image.fromarray(out8).save(f"stills/egl_{tag}_grain.png")
    print(f"RENDER {tag} {w}x{h} coeff={coeff} strength={strength} hdr={is_hdr} -> stills/egl_{tag}_grain.png")

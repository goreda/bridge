"""W-0249 execution fixture builder. Deterministic synthetic glyph collections.
Pure stdlib; every byte synthetic; no licensed fonts, no real captures."""
import hashlib, json, os, pathlib, shutil, struct, zlib

OUT = pathlib.Path('/tmp/w249fix/out')

def png_gray(width, height, pixel_fn):
    """Minimal deterministic 8-bit grayscale PNG."""
    raw = b''.join(b'\x00' + bytes(pixel_fn(x, y) for x in range(width)) for y in range(height))
    def chunk(tag, data):
        c = tag + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 0, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def glyph_px(seed_byte):
    def fn(x, y):
        # deterministic glyph-ish ink pattern varying by seed
        v = (x * 31 + y * 17 + seed_byte) % 97
        ink = (10 <= x <= 53) and (8 <= y <= 55) and ((x - seed_byte) % 11 < 6 or (y + seed_byte) % 13 < 7)
        return 0 if ink else 255 if v else 255
    return fn

def build_collection(root, seed_base, styles):
    for style, glyphs in styles.items():
        d = root / style
        d.mkdir(parents=True)
        for i, g in enumerate(glyphs):
            (d / ('glyph_%s.png' % g)).write_bytes(png_gray(64, 64, glyph_px(seed_base + i * 7 + ord(g))))

def source_set_sha(paths):
    return hashlib.sha256(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '\n' for p in paths).encode()).hexdigest()

def walk_collection(root):
    out = []
    for base, dirs, files in os.walk(root):
        dirs.sort(); files.sort()
        out.extend(pathlib.Path(base) / n for n in files if pathlib.Path(n).suffix.lower() in {'.png','.jpg','.jpeg','.tif','.tiff','.bmp','.webp'})
    return [p.resolve() for p in out]

FRAME = 'image_series_whole_canvas_pixels_y_down'

def env_json(source_sha, *, post=None, levels=None, pin='00' * 32, origin='fixture-baked declaration, not automatic measurement'):
    sb = {'source': 'engine_derived', 'operation': 'engine_derived', 'post_offsets': None, 'declaration_pin': None}
    if post is not None:
        sb = {'source': 'manual_add', 'operation': 'add_to_engine_derived', 'post_offsets': post, 'declaration_pin': pin}
    rec = {'schema': 'kni-composition-settings-v1', 'source_sha256': source_sha, 'coordinate_frame': FRAME,
           'sidebearings': sb, 'vertical_metrics': 'separate_evidence_consumer', 'quality_approved': False,
           'declared_levels': levels or {}, 'levels_declaration_pin': (pin if levels else None),
           'settings_origin': origin}
    return json.dumps(rec, indent=2, sort_keys=True) + '\n'

def main():
    shutil.rmtree(OUT, ignore_errors=True)
    fa = OUT / 'fixtures' / 'collection-a'
    fb = OUT / 'fixtures' / 'collection-b'
    fe = OUT / 'fixtures' / 'collection-empty'
    fe.mkdir(parents=True)
    build_collection(fa, 3, {'styleone': ['A', 'B', 'C'], 'styletwo': ['D', 'E']})
    build_collection(fb, 41, {'styleone': ['A', 'X'], 'stylethree': ['Q']})
    sa = source_set_sha(walk_collection(fa))
    sb_ = source_set_sha(walk_collection(fb))
    pins = {str(p.relative_to(OUT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.rglob('*')) if p.is_file()}
    env = OUT / 'env'
    env.mkdir()
    good_post = {'lsb_add': '5', 'rsb_add': '-3', 'post_scope': 'base', 'post_scope_label': 'fixture-shared-sb'}
    (env / 'valid-a.json').write_text(env_json(sa, post=good_post, levels={'baseline': 149.0}))
    (env / 'valid-a-noenv-decision.json').write_text(env_json(sa))
    # T-10 battery implants (each baked for A's exact source sha unless the case IS the mismatch)
    (env / 'bad-unknown-key.json').write_text(env_json(sa, post={'lsb_add': '5', 'rsb_add': '-3', 'post_scope': 'base', 'post_scope_label': 'fixture-shared-sb', 'lsb_ad': '5'}))
    (env / 'bad-noninteger.json').write_text(env_json(sa, post={'lsb_add': '5.5', 'rsb_add': '-3', 'post_scope': 'base', 'post_scope_label': 'fixture-shared-sb'}))
    (env / 'bad-out-of-range.json').write_text(env_json(sa, post={'lsb_add': '40000', 'rsb_add': '-3', 'post_scope': 'base', 'post_scope_label': 'fixture-shared-sb'}))
    (env / 'bad-scope-token.json').write_text(env_json(sa, post={'lsb_add': '5', 'rsb_add': '-3', 'post_scope': 'nope', 'post_scope_label': 'fixture-shared-sb'}))
    (env / 'bad-source-mismatch.json').write_text(env_json(sb_, post=good_post))  # baked for B, run on A
    (env / 'bad-malformed-json.json').write_text('{"schema": "kni-composition-settings-v1", "source_sha256": ')  # truncated
    (env / 'bad-label-token.json').write_text(env_json(sa, post={'lsb_add': '5', 'rsb_add': '-3', 'post_scope': 'base', 'post_scope_label': 'bad label with spaces'}))
    meta = {'frame': FRAME, 'collection_a_source_sha256': sa, 'collection_b_source_sha256': sb_,
            'fixture_files': pins}
    (OUT / 'fixtures' / 'FIXTURES.json').write_text(json.dumps(meta, indent=1, sort_keys=True) + '\n')
    print('A source:', sa[:24], '... | B source:', sb_[:24], '...')
    print('files:', len(pins))

main()

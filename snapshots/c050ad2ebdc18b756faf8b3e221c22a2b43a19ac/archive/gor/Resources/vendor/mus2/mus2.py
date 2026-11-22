#!/usr/bin/env python3
"""
mus2 - local spotify backend.

COMMAND PROTOCOL (stdin → stdout JSON):
  search <q>              → results
  browse <idx>            → tracks (inside zip/rar or bandcamp songs)
  info <idx>              → info text (nfo/txt or bandcamp description)
  play_track <idx> <n>    → play track n of the album
  play <idx>              → play the album
  pause / next / prev     → transport
  vol <delta>             → volume ±delta
  status                  → mpv status
  menu                    → menu (playlists + library count)
  pl_new <name>           → new playlist
  pl_add <pl_id> <idx>    → add album to playlist
  pl_remove <pl_id> <i>   → remove from playlist
  pl_play <pl_id>         → load playlist into queue and play
  pl_list                 → all playlists
  q_add <idx>             → add album to queue
  q_add_track <idx> <n>   → add track to queue
  q_clear                 → clear queue
  q_list                  → queue contents
  q_next                  → next in queue
  refresh                 → refresh the archive
  quit                    → quit
"""
import sys, json, os, urllib.request, urllib.parse, re, pickle, time, html as htmlmod, uuid
import zipfile, io, struct as st, concurrent.futures

SOCKET = None

# ═══════════════════════════════════════════════════════════════════
# MPV IPC
# ═══════════════════════════════════════════════════════════════════

def mpv_raw(cmd):
    import subprocess
    if not SOCKET or not os.path.exists(SOCKET):
        log("err", f"mpv_raw: no SOCKET: {SOCKET}")
        return ""
    try:
        r = subprocess.run(["nc", "-U", SOCKET], input=cmd + "\n",
                           capture_output=True, text=True, timeout=3)
        log("info", f"mpv_raw cmd={cmd[:50]} result={r.stdout.strip()[:50]}")
        return r.stdout.strip()
    except Exception as e:
        log("err", f"mpv_raw exception: {e}")
        return ""

def mpv_prop(prop):
    raw = mpv_raw(f'{{"command":["get_property","{prop}"]}}')
    if raw and '"data":' in raw:
        m = re.search(r'"data":([^,}\n]+)', raw)
        if m: return m.group(1).strip().strip('"')
    return None

def mpv_cmd(cmd_str):
    mpv_raw(cmd_str)

def mpv_play(url, cover_path=None):
    if cover_path:
        cmd_json = json.dumps({"command": ["loadfile", url, "replace", 0, f"cover-art-file={cover_path}"]})
    else:
        cmd_json = json.dumps({"command": ["loadfile", url, "replace"]})
    mpv_cmd(cmd_json)
    time.sleep(0.3)
    if mpv_prop("pause") == "true":
        mpv_cmd('{"command":["set","pause","no"]}')
    log("info", f"Playing: {url[:100]}..." + (" [cover]" if cover_path else ""))

def mpv_pause():
    mpv_cmd('{"command":["cycle","pause"]}')

def mpv_next():
    mpv_cmd('{"command":["playlist-next"]}')

def mpv_prev():
    mpv_cmd('{"command":["playlist-prev"]}')

def mpv_vol(v):
    mpv_cmd(f'{{"command":["add","volume","{v}"]}}')

# ═══════════════════════════════════════════════════════════════════
# CONFIG & CACHE
# ═══════════════════════════════════════════════════════════════════

CONFIG_DIR = os.path.expanduser("~/.config/mus2")
CACHE_FILE = os.path.join(CONFIG_DIR, "archive_cache.pkl")
PL_FILE    = os.path.join(CONFIG_DIR, "playlists.json")
COVER_DIR  = os.path.join(CONFIG_DIR, "covers")
os.makedirs(CONFIG_DIR, exist_ok=True)
os.makedirs(COVER_DIR,  exist_ok=True)

DATA_MODE = ""

ARCHIVE_COLLECTIONS = ["jillem-full-archive", "jillem-full-archive_2"]
AUDIO_TAGS = ["320kb","flac","vbr","aac","alac","wav","mp3","256kb","192kb","128kb","v0","v2"]
AUDIO_EXTS = {".mp3",".flac",".ogg",".aac",".wav",".m4a",".opus",".wma",".aiff",".ape",".wv"}
INFO_EXTS  = {".nfo",".txt",".md",".log"}
INFO_NAMES = {"nfo","readme","info","about","description","release","notes"}

# ═══════════════════════════════════════════════════════════════════
# O(1) CACHE INDEX
# ═══════════════════════════════════════════════════════════════════

_cache_index = {}
_url_cache   = {}

def build_cache_index(cache):
    global _cache_index
    _cache_index = {id(item): idx for idx, item in enumerate(cache)}

# ═══════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════

def log(level, msg):
    print(json.dumps({"cmd":"log","level":level,"msg":msg}), flush=True)

CHUNK_SIZE = 32000

def emit(obj):
    line = json.dumps(obj, ensure_ascii=False)
    if len(line) > CHUNK_SIZE:
        chunks = [line[i:i+CHUNK_SIZE] for i in range(0, len(line), CHUNK_SIZE)]
        for idx, chunk in enumerate(chunks):
            sys.stdout.write(json.dumps({
                "cmd": "chunk",
                "total": len(chunks),
                "index": idx,
                "data": chunk
            }) + "\n")
            sys.stdout.flush()
    else:
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

def is_music(name):
    l = name.lower().strip()
    m = re.search(r'\(([^)]+)\)\s*$', l)
    if m:
        last = m.group(1); parts = re.split(r'[+,&/]', last)
        ha = any(t in p for t in AUDIO_TAGS for p in parts)
        hb = any(e in p for e in ["epub","pdf","txt","jpg","png","gif","log","nfo","sfv"] for p in parts)
        if hb and not ha: return False
    return any(t in l for t in AUDIO_TAGS)

def fmt_duration(secs):
    try:
        s = int(float(secs)); return f"{s//60}:{s%60:02d}"
    except: return ""

# ═══════════════════════════════════════════════════════════════════
# COVER
# ═══════════════════════════════════════════════════════════════════

def download_cover(cover_url):
    if not cover_url: return None
    fname = os.path.join(COVER_DIR, str(abs(hash(cover_url))) + ".jpg")
    if os.path.exists(fname): return fname
    try:
        req = urllib.request.Request(cover_url)
        req.add_header('User-Agent', 'Mozilla/5.0')
        with urllib.request.urlopen(req, timeout=8) as r:
            data = r.read()
        with open(fname, "wb") as f: f.write(data)
        return fname
    except Exception as e:
        log("err", f"Cover: {e}"); return None

# ═══════════════════════════════════════════════════════════════════
# ARCHIVE.ORG
# ═══════════════════════════════════════════════════════════════════

def fetch_archive_parallel(collections):
    """Fetch all collections in parallel."""
    albums = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = {executor.submit(fetch_archive, col): col for col in collections}
        for future in concurrent.futures.as_completed(futures):
            try:
                albums.extend(future.result())
            except Exception as e:
                log("err", f"Parallel fetch: {e}")
    return albums

def fetch_archive(col):
    url = f"https://archive.org/metadata/{col}"
    albums = []
    try:
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'Mozilla/5.0')
        req.add_header('Accept-Encoding', 'gzip')
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
        if raw[:2] == b'\x1f\x8b':
            import gzip
            raw = gzip.decompress(raw)
        data = json.loads(raw.decode("utf-8"))
        _url_cache[f"_server_{col}"] = data.get("server", "")
        _url_cache[f"_dir_{col}"]    = data.get("dir", "")
        files_map = {f.get("name",""): f for f in data.get("files",[])}
        
        for f in data.get("files", []):
            n = f.get("name","")
            if not (n.endswith(".zip") or n.endswith(".rar")): continue
            if not is_music(n): continue
            ext = ".zip" if n.endswith(".zip") else ".rar"
            base = re.sub(r'\.(zip|rar)$','', n)
            cover = None
            for img_ext in ['.jpg','.jpeg','.png']:
                test = base + img_ext
                if test in files_map:
                    cover = f"https://archive.org/download/{col}/{urllib.parse.quote(test)}"
                    break
            albums.append({
                "id": str(uuid.uuid4()),
                "title": base,
                "source": "archive",
                "collection": col,
                "ext": ext,
                "cover": cover,
                "tracks": None,
            })
    except Exception as e:
        log("err", str(e))
    return albums

def archive_url(alb):
    key = (alb["collection"], alb["title"], alb.get("ext", ".zip"))
    if key not in _url_cache:
        q = urllib.parse.quote(alb["title"], safe="")
        _url_cache[key] = f"https://archive.org/download/{alb['collection']}/{q}{alb.get('ext','.zip')}"
    return _url_cache[key]

def browse_archive(alb):
    """ZIP/RAR file list - only the header is downloaded."""
    if alb.get("ext") == ".rar":
        return browse_rar_archive(alb)

    col = alb["collection"]
    zip_name = alb["title"] + alb.get("ext", ".zip")
    url = archive_url(alb)
    tracks = []

    try:
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'Mozilla/5.0')
        req.add_header('Range', 'bytes=-65536')

        with urllib.request.urlopen(req, timeout=20) as r:
            tail = r.read()
            cr = r.headers.get('Content-Range', '')
            file_size = int(cr.split('/')[-1]) if cr else len(tail)

        eocd = tail.rfind(b'PK\x05\x06')
        if eocd >= 0:
            cd_off = st.unpack('<I', tail[eocd+16:eocd+20])[0]
            cd_sz  = st.unpack('<I', tail[eocd+12:eocd+16])[0]
            tail_start = file_size - len(tail)
            cd_pos = cd_off - tail_start

            if 0 <= cd_pos and cd_pos + cd_sz <= len(tail):
                cd = tail[cd_pos:cd_pos + cd_sz]
            else:
                req2 = urllib.request.Request(url)
                req2.add_header('User-Agent', 'Mozilla/5.0')
                req2.add_header('Range', f'bytes={cd_off}-{cd_off + cd_sz - 1}')
                with urllib.request.urlopen(req2, timeout=10) as r2:
                    cd = r2.read()

            pos = 0; i = 0
            while pos < len(cd) - 46:
                if cd[pos:pos+4] != b'PK\x01\x02':
                    pos += 1; continue
                nlen = st.unpack('<H', cd[pos+28:pos+30])[0]
                elen = st.unpack('<H', cd[pos+30:pos+32])[0]
                clen = st.unpack('<H', cd[pos+32:pos+34])[0]
                name = cd[pos+46:pos+46+nlen].decode('utf-8', errors='ignore')
                ext = os.path.splitext(name.lower())[1]
                if ext in AUDIO_EXTS:
                    bn = os.path.basename(name)
                    bn_clean = re.sub(r'^[\d\s\-_.]+', '', os.path.splitext(bn)[0]).strip()
                    stream_url = f"https://archive.org/download/{col}/{urllib.parse.quote(zip_name)}/{urllib.parse.quote(name)}"
                    tracks.append({
                        "n": i,
                        "title": bn_clean or bn,
                        "file": name,
                        "duration": "",
                        "stream_url": stream_url
                    })
                    i += 1
                pos += 46 + nlen + elen + clen

    except Exception as e:
        log("err", f"browse_archive: {e}")

    return tracks, None

def browse_rar_archive(alb):
    col = alb["collection"]
    rar_name = alb["title"] + ".rar"
    tracks = []

    try:
        server = _url_cache.get(f"_server_{col}", "")
        directory = _url_cache.get(f"_dir_{col}", "")
        if not server or not directory:
            meta_url = f"https://archive.org/metadata/{col}"
            req = urllib.request.Request(meta_url)
            req.add_header('User-Agent', 'Mozilla/5.0')
            with urllib.request.urlopen(req, timeout=15) as r:
                meta = json.loads(r.read().decode('utf-8'))
            server = meta.get("server", "")
            directory = meta.get("dir", "")
            _url_cache[f"_server_{col}"] = server
            _url_cache[f"_dir_{col}"]    = directory

        view_url = (
            f"https://{server}/view_archive.php"
            f"?archive={directory}/{urllib.parse.quote(rar_name)}"
        )
        log("info", f"browse_rar: view_url={view_url}")
        
        req2 = urllib.request.Request(view_url)
        req2.add_header('User-Agent', 'Mozilla/5.0')
        with urllib.request.urlopen(req2, timeout=20) as r:
            html = r.read().decode('utf-8', errors='ignore')

        seen = []
        for m in re.finditer(r'href="(//[^"]+)"', html):
            url = "https:" + m.group(1)
            ext = os.path.splitext(urllib.parse.urlparse(url).path.lower())[1]
            if ext in AUDIO_EXTS and url not in seen:
                seen.append(url)

        log("info", f"browse_rar first url: {seen[0] if seen else 'empty'}")
        
        for i, stream_url in enumerate(seen):
            decoded = urllib.parse.unquote(stream_url)
            raw_name = decoded.split("/")[-1]  # split after unquote
            bn_clean = re.sub(r'^[\d\s\-_.]+', '', os.path.splitext(raw_name)[0]).strip()
            tracks.append({
                "n": i,
                "title": bn_clean or raw_name,
                "file": raw_name,
                "duration": "",
                "stream_url": stream_url
            })

    except Exception as e:
        log("err", f"browse_rar: {e}")

    return tracks, None

def play_archive_track(alb, track_n):
    tracks = alb.get("tracks") or []
    cover = download_cover(alb.get("cover"))

    if not tracks:
        mpv_play(archive_url(alb), cover)
        emit({"cmd": "np", "title": alb["title"], "source": "archive"})
        return

    if DATA_MODE == "wf":
        # WIFI: load all tracks
        mpv_cmd('{"command":["playlist-clear"]}')
        time.sleep(0.05)
        for i, t in enumerate(tracks):
            if t.get("stream_url"):
                if i == track_n:
                    mpv_play(t["stream_url"], cover)
                else:
                    mpv_cmd(f'{{"command":["loadfile","{t["stream_url"]}","append"]}}')
    else:
        # DATA: only the requested track
        t = tracks[track_n]
        if t.get("stream_url"):
            mpv_play(t["stream_url"], cover)

    emit({"cmd": "np", "title": f"{alb['title']} — {tracks[track_n]['title']}", "source": "archive"})

# ═══════════════════════════════════════════════════════════════════
# BANDCAMP
# ═══════════════════════════════════════════════════════════════════

def search_bc_artist(q):
    q2 = q.lower().replace(" ","")
    try:
        urllib.request.urlopen(f"https://{q2}.bandcamp.com/music", timeout=5)
        return f"https://{q2}.bandcamp.com"
    except: return None

def fetch_bc_artist(artist_url):
    if not artist_url.startswith("http"):
        artist_url = f"https://{artist_url}.bandcamp.com"
    domain = re.search(r'https?://([^/]+)', artist_url).group(1)
    albums = []
    req = urllib.request.Request(artist_url.rstrip("/") + "/music")
    req.add_header('User-Agent','Mozilla/5.0')
    with urllib.request.urlopen(req, timeout=10) as r:
        html = r.read().decode("utf-8", errors="ignore")
    m = re.search(r'data-band-id="(\d+)"', html)
    if not m: return albums
    api_req = urllib.request.Request(f"https://{domain}/api/mobile/24/band_details?band_id={m.group(1)}")
    api_req.add_header('User-Agent','Mozilla/5.0')
    with urllib.request.urlopen(api_req, timeout=10) as r:
        data = json.loads(r.read().decode("utf-8"))
    for item in data.get("discography",[]):
        if item.get("item_type") not in ["album","track"]: continue
        album_title = item.get("title","")
        artist = item.get("artist_name","")
        display_title = f"{artist} - {album_title}" if artist and artist != item.get("band_name","") else album_title
        slug = re.sub(r'[^a-z0-9]+','-', album_title.lower()).strip('-')[:100]
        url_path = f"/album/{slug}" if item.get("item_type")=="album" else f"/track/{slug}"
        raw_art_id = str(item.get("art_id",""))
        padded = raw_art_id.zfill(10) if raw_art_id else ""
        cover_url = f"https://f4.bcbits.com/img/a{padded}_16.jpg" if padded else None
        albums.append({
            "id": str(uuid.uuid4()),
            "title": display_title,
            "source": "bandcamp",
            "domain": domain,
            "url": f"https://{domain}{url_path}",
            "artist": domain.split(".")[0],
            "cover": cover_url,
            "tracks": None,
            "stream_url": None,
            "description": None,
        })
    log("info", f"Bandcamp: {len(albums)} albums")
    return albums

def fetch_bc_tracks(alb):
    tracks = []; description = None
    try:
        req = urllib.request.Request(alb["url"])
        req.add_header('User-Agent','Mozilla/5.0')
        with urllib.request.urlopen(req, timeout=10) as r:
            h = r.read().decode("utf-8", errors="ignore")
        dm = re.search(r'class="tralbum-about[^"]*"[^>]*>(.*?)</p>', h, re.DOTALL)
        if dm:
            description = htmlmod.unescape(re.sub(r'<[^>]+>','', dm.group(1))).strip()
        if not description:
            dm2 = re.search(r'<meta name="description" content="([^"]*)"', h)
            if dm2: description = htmlmod.unescape(dm2.group(1)).strip()
        m2 = re.search(r'data-tralbum="({[^"]+})"', h)
        if m2:
            raw = htmlmod.unescape(m2.group(1))
            data = json.loads(raw)
            for i, t in enumerate(data.get("trackinfo",[])):
                stream = None
                if t.get("file"): stream = t["file"].get("mp3-128")
                tracks.append({"n":i,"title":t.get("title",""),
                                "duration":fmt_duration(t.get("duration","")),
                                "stream_url":stream})
        alb["tracks"] = tracks
        alb["description"] = description
    except Exception as e:
        log("err", f"fetch_bc_tracks: {e}")
    return tracks, description

def play_bc_album(alb, start_n, cache):
    tracks = alb.get("tracks") or []
    if not tracks:
        tracks, _ = fetch_bc_tracks(alb)
    if not tracks:
        log("err", "No tracks found")
        return

    cover_path = download_cover(alb.get("cover"))
    
    if DATA_MODE == "wf":
        # WIFI: load the whole album into the playlist, then jump to the selected track
        mpv_cmd('{"command":["playlist-clear"]}')
        time.sleep(0.05)
        first = True
        for i, t in enumerate(tracks):
            if t.get("stream_url"):
                if first:
                    mpv_cmd(f'{{"command":["loadfile","{t["stream_url"]}","append"]}}')
                    first = False
                else:
                    mpv_cmd(f'{{"command":["loadfile","{t["stream_url"]}","append"]}}')
        time.sleep(0.3)
        mpv_cmd(f'{{"command":["set","playlist-pos","{track_n}"]}}')
        if cover:
            mpv_cmd(f'{{"command":["set_property","cover-art-file","{cover}"]}}')
    else:
        # DATA: only the requested track
        target_track = tracks[start_n]
        if target_track.get("stream_url"):
            mpv_play(target_track["stream_url"], cover_path)

    emit({"cmd":"np","title":alb["title"],"source":"bandcamp"})

# ═══════════════════════════════════════════════════════════════════
# PERSISTENCE
# ═══════════════════════════════════════════════════════════════════

def load_cache():
    global _cache_index
    try:
        with open(CACHE_FILE,"rb") as f:
            data = pickle.load(f)
        build_cache_index(data)
        return data
    except:
        _cache_index = {}
        return []

def save_cache(data):
    build_cache_index(data)
    with open(CACHE_FILE,"wb") as f: pickle.dump(data, f)

def ensure_archive_cache(cache):
    if _cache_index:
        return cache
    if any(a.get("source")=="archive" for a in cache):
        build_cache_index(cache)
        return cache
    new_albums = fetch_archive_parallel(ARCHIVE_COLLECTIONS)
    new_albums.sort(key=lambda x: x["title"].lower())
    cache.extend(new_albums)
    save_cache(cache)
    return cache

def items_with_idx(items_list, cache):
    result = []
    for item in items_list:
        idx = _cache_index.get(id(item), -1)
        result.append({**item, "cache_idx": idx})
    return result

# ═══════════════════════════════════════════════════════════════════
# PLAYLISTS
# ═══════════════════════════════════════════════════════════════════

def _atomic_write_json(path, obj):
    """Serialize first, write to a temp file in the same dir, flush+fsync, then os.replace.
    On any failure the previous file is untouched and the temp file is removed."""
    data = json.dumps(obj, indent=2)          # serialization errors surface before any file I/O
    d = os.path.dirname(path) or "."
    tmp = os.path.join(d, "." + os.path.basename(path) + ".tmp-" + str(os.getpid()))
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try: os.unlink(tmp)
        except OSError: pass
        raise
    try:                                       # best effort: persist the rename itself
        dfd = os.open(d, os.O_RDONLY)
        try: os.fsync(dfd)
        finally: os.close(dfd)
    except OSError:
        pass

def _load_json_list(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return []                              # first run: genuinely empty
    except (ValueError, OSError) as e:        # corrupt or unreadable: do NOT treat as empty silently
        bad = path + ".corrupt-" + time.strftime("%Y%m%d-%H%M%S")
        try: os.replace(path, bad)             # quarantine so the next save cannot overwrite it
        except OSError: bad = "(could not quarantine)"
        log("err", "unreadable " + os.path.basename(path) + " (" + type(e).__name__ + "); kept as " + bad)
        return []
    if not isinstance(data, list):
        bad = path + ".corrupt-" + time.strftime("%Y%m%d-%H%M%S")
        try: os.replace(path, bad)
        except OSError: bad = "(could not quarantine)"
        log("err", os.path.basename(path) + " is not a list; kept as " + bad)
        return []
    return data

def _save_json(path, obj):
    """Returns True on success. On failure logs a visible error and returns False;
    the previous file stays byte-identical."""
    try:
        _atomic_write_json(path, obj)
        return True
    except Exception as e:
        log("err", "save failed for " + os.path.basename(path) + ": " + type(e).__name__ + ": " + str(e))
        return False

def load_playlists():            return _load_json_list(PL_FILE)
def save_playlists(pls):         return _save_json(PL_FILE, pls)

def pl_find(pls, pl_id):
    for pl in pls:
        if pl["id"] == pl_id: return pl
    return None

# ═══════════════════════════════════════════════════════════════════
# QUEUE
# ═══════════════════════════════════════════════════════════════════

_queue = []
_queue_pos = -1

def q_emit():
    emit({"cmd":"queue","items":_queue,"current":_queue_pos})

def q_clear_all():
    global _queue, _queue_pos
    _queue = []; _queue_pos = -1
    mpv_cmd('{"command":["playlist-clear"]}')
    q_emit()

def q_play_pos(n):
    global _queue_pos
    if n < 0 or n >= len(_queue): return
    _queue_pos = n
    it = _queue[n]
    cover_path = download_cover(it.get("cover_url"))
    mpv_play(it["url"], cover_path)
    emit({"cmd":"np","title":it["title"],"source":it.get("source","")})

def build_queue_from_album(alb, cache_idx):
    if alb["source"] == "archive":
        _queue.append({"title":alb["title"],"url":archive_url(alb),
                        "cover_url":alb.get("cover"),"source":"archive","cache_idx":cache_idx})
    elif alb["source"] == "bandcamp":
        tracks = alb.get("tracks") or []
        if not tracks: tracks, _ = fetch_bc_tracks(alb)
        for t in tracks:
            if t.get("stream_url"):
                _queue.append({"title":f"{alb['title']} — {t['title']}",
                                "url":t["stream_url"],"cover_url":alb.get("cover"),
                                "source":"bandcamp","cache_idx":cache_idx,"track_n":t["n"]})
    q_emit()

# ═══════════════════════════════════════════════════════════════════
# LOCAL LIBRARY
# ═══════════════════════════════════════════════════════════════════

LOCAL_LIBRARIES_FILE = os.path.join(CONFIG_DIR, "local_libraries.json")

def load_local_libraries():      return _load_json_list(LOCAL_LIBRARIES_FILE)
def save_local_libraries(libs):  return _save_json(LOCAL_LIBRARIES_FILE, libs)

def scan_local_path(root_path):
    log("info", f"scan_local_path: {root_path}")
    """Recursive folder scan. Each folder is evaluated independently."""
    items = []
    if not os.path.isdir(root_path):
        return items
    
    try:
        entries = sorted(os.listdir(root_path))
    except PermissionError:
        return items
    
    for entry in entries:
        full = os.path.join(root_path, entry)
        if not os.path.isdir(full) or entry.startswith("."):
            continue
        
        # Does this folder directly contain audio files?
        direct_audio, subdirs = classify_contents(full)
        
        if direct_audio:
            # Album: has direct audio files
            tracks = []
            for i, af in enumerate(sorted(direct_audio)):
                bn = os.path.splitext(os.path.basename(af))[0]
                bn_clean = re.sub(r'^[\d\s\-_.]+', '', bn).strip()
                tracks.append({
                    "n": i,
                    "title": bn_clean or bn,
                    "file": af,
                    "duration": "",
                    "stream_url": None,
                    "local_path": af
                })
            items.append({
                "type": "album",
                "name": entry,
                "path": full,
                "cover": None,
                "tracks": tracks
            })
        elif subdirs:
            # No direct audio but has subfolder → folder (scanned again when entered)
            items.append({
                "type": "folder",
                "name": entry,
                "path": full,
                "has_subdirs": True
            })
        # else: empty folder, skip
    
    return items

def classify_contents(path):
    """Classify a folder's direct contents: audio files and subfolders."""
    direct_audio = []
    subdirs = []
    try:
        for entry in sorted(os.listdir(path)):
            full = os.path.join(path, entry)
            if os.path.isfile(full) and os.path.splitext(entry.lower())[1] in AUDIO_EXTS:
                direct_audio.append(full)
            elif os.path.isdir(full) and not entry.startswith("."):
                subdirs.append(full)
    except PermissionError:
        pass
    return direct_audio, subdirs

# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════

def main():
    global SOCKET
    if len(sys.argv) < 2:
        log("err","usage: mus2.py <socket-path>"); return
    SOCKET = sys.argv[1]
    import threading

    # watch mpv playlist position - emit np when the track changes
    _last_playlist_pos = [-1]

    def mpv_watcher():
        while True:
            time.sleep(1.0)
            if not SOCKET or not os.path.exists(SOCKET):
                continue
            try:
                pos_raw = mpv_prop("playlist-pos")
                log("info", f"watcher: pos={pos_raw}")  # ← add
                if pos_raw is None:
                    continue
                pos = int(pos_raw)
                if pos != _last_playlist_pos[0] and pos >= 0:
                    _last_playlist_pos[0] = pos
                    title = mpv_prop("media-title") or ""
                    emit({"cmd": "np", "title": title, "source": "archive", "track_n": pos})
            except Exception:
                pass

    threading.Thread(target=mpv_watcher, daemon=True).start()
    cache = load_cache()
    playlists = load_playlists()

    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        parts = line.split(" ", 2)
        cmd = parts[0]
        arg  = parts[1] if len(parts) > 1 else ""
        arg2 = parts[2] if len(parts) > 2 else ""

        if cmd == "search":
            query = line[len(cmd):].lstrip(" ")
            cache = ensure_archive_cache(cache)
            ar = [a for a in cache if a.get("source")=="archive" and query.lower() in a["title"].lower()]
            bc = []
            bc_url = search_bc_artist(query)
            if bc_url:
                try:
                    domain = re.search(r'https?://([^/]+)', bc_url).group(1)
                    new = fetch_bc_artist(bc_url)
                    if new:
                        cache = [a for a in cache if a.get("domain") != domain]
                        cache.extend(new); save_cache(cache); bc = new
                except Exception as e: log("err",f"bc: {e}")
            emit({"cmd":"results","items":items_with_idx(ar+bc, cache)})

        elif cmd == "browse":
            try:
                idx = int(arg)
                if idx < len(cache):
                    alb = cache[idx]
                    if alb["source"] == "archive":
                        tracks, _ = browse_archive(alb)
                        alb["tracks"] = tracks; save_cache(cache)
                        emit({"cmd":"tracks","album_idx":idx,"source":"archive",
                              "title":alb["title"],"cover":alb.get("cover"),"items":tracks})
                    elif alb["source"] == "bandcamp":
                        tracks, _ = fetch_bc_tracks(alb)
                        save_cache(cache)
                        emit({"cmd":"tracks","album_idx":idx,"source":"bandcamp",
                              "title":alb["title"],"cover":alb.get("cover"),"items":tracks})
            except Exception as e: log("err",f"browse: {e}")

        elif cmd == "info":
            try:
                idx = int(arg)
                if idx < len(cache):
                    alb = cache[idx]
                    if alb["source"] == "archive":
                        _, text = browse_archive(alb)
                        text = text or "(no info file found)"
                    else:
                        desc = alb.get("description")
                        if not desc: _, desc = fetch_bc_tracks(alb); save_cache(cache)
                        text = desc or "(no description found)"
                    emit({"cmd":"info","album_idx":idx,"title":alb["title"],"text":text})
            except Exception as e: log("err",f"info: {e}")

        elif cmd == "play_track":
            try:
                idx = int(arg); track_n = int(arg2)
                if idx < len(cache):
                    alb = cache[idx]
                    if alb["source"] == "archive":
                        play_archive_track(alb, track_n)
                    elif alb["source"] == "bandcamp":
                        play_bc_album(alb, track_n, cache); save_cache(cache)
            except Exception as e: log("err",f"play_track: {e}")

        elif cmd == "play_local":
            filepath = line[len("play_local "):].strip()
            mpv_play(filepath, None)
            emit({"cmd": "np", "title": os.path.basename(filepath), "source": "local"})

        elif cmd == "queue_local":
            filepath = line[len("queue_local "):].strip()
            if os.path.exists(filepath):
                mpv_cmd(json.dumps({"command": ["loadfile", filepath, "append"]}))
            
        elif cmd == "play":
            try:
                idx = int(arg)
                if idx < len(cache):
                    alb = cache[idx]
                    if alb["source"] == "archive":
                        play_archive_track(alb, 0)
                    elif alb["source"] == "bandcamp":
                        play_bc_album(alb, 0, cache); save_cache(cache)
            except Exception as e: log("err",f"play: {e}")

        elif cmd == "play_stream":
            url = arg
            mpv_play(url, None)
            log("info", "play_stream called")
            
        elif cmd == "set_mode":
            global DATA_MODE
            DATA_MODE = arg
            log("info", f"Data mode: {DATA_MODE}")

        elif cmd == "pause": mpv_pause()
        elif cmd == "next":  mpv_next()
        elif cmd == "prev":  mpv_prev()
        elif cmd == "vol":
            try: mpv_vol(int(arg))
            except: pass

        elif cmd == "status":
            t = mpv_prop("media-title") or ""
            emit({"cmd":"status","title":t,
                  "pos":mpv_prop("time-pos") or "0",
                  "dur":mpv_prop("duration") or "0",
                  "paused":mpv_prop("pause")=="true",
                  "vol":mpv_prop("volume") or "80"})

        elif cmd == "menu":
            cache = ensure_archive_cache(cache)
            archive_count = sum(1 for a in cache if a.get("source") == "archive")
            emit({"cmd": "menu", "playlists": playlists,
                  "library_count": archive_count, "library_title": "jillem full discography",
                  "data_mode": DATA_MODE})
            if archive_count > 0:
                archive_items = [a for a in cache if a.get("source") == "archive"]
                emit({"cmd": "results", "items": items_with_idx(archive_items, cache)})

        elif cmd == "pl_new":
            name = line[len("pl_new "):].strip() or f"playlist {len(playlists)+1}"
            pl = {"id":str(uuid.uuid4()),"name":name,"items":[]}
            playlists.append(pl); save_playlists(playlists)
            emit({"cmd":"playlists","playlists":playlists})

        elif cmd == "pl_add":
            pl = pl_find(playlists, arg)
            if pl:
                try:
                    idx = int(arg2)
                    if idx < len(cache):
                        alb = cache[idx]
                        pl["items"].append({"cache_idx":idx,"title":alb["title"],
                                            "source":alb["source"],"cover":alb.get("cover")})
                        save_playlists(playlists)
                        emit({"cmd":"playlists","playlists":playlists})
                        log("info",f"Added {alb['title']} to {pl['name']}")
                except Exception as e: log("err",f"pl_add: {e}")

        elif cmd == "pl_remove":
            pl = pl_find(playlists, arg)
            if pl:
                try:
                    i = int(arg2)
                    if 0 <= i < len(pl["items"]):
                        pl["items"].pop(i); save_playlists(playlists)
                        emit({"cmd":"playlists","playlists":playlists})
                except: pass

        elif cmd == "pl_play":
            pl = pl_find(playlists, arg)
            if pl:
                q_clear_all()
                for entry in pl["items"]:
                    idx = entry.get("cache_idx",-1)
                    if 0 <= idx < len(cache):
                        build_queue_from_album(cache[idx], idx)
                if _queue: q_play_pos(0)
        
        elif cmd == "pl_delete":
            playlists = [pl for pl in playlists if pl["id"] != arg]
            save_playlists(playlists)
            emit({"cmd":"playlists","playlists":playlists})
        
        elif cmd == "pl_list":
            emit({"cmd":"playlists","playlists":playlists})

        elif cmd == "q_add":
            try:
                idx = int(arg)
                if idx < len(cache): build_queue_from_album(cache[idx], idx)
            except Exception as e: log("err",f"q_add: {e}")

        elif cmd == "q_add_track":
            try:
                idx = int(arg); track_n = int(arg2)
                if idx < len(cache):
                    alb = cache[idx]
                    if alb["source"] == "bandcamp":
                        tracks = alb.get("tracks") or []
                        if not tracks: tracks, _ = fetch_bc_tracks(alb)
                        if track_n < len(tracks) and tracks[track_n].get("stream_url"):
                            t = tracks[track_n]
                            _queue.append({"title":f"{alb['title']} — {t['title']}",
                                           "url":t["stream_url"],"cover_url":alb.get("cover"),
                                           "source":"bandcamp","cache_idx":idx,"track_n":track_n})
                            save_cache(cache); q_emit()
                    elif alb["source"] == "archive":
                        _queue.append({"title":alb["title"],"url":archive_url(alb),
                                       "cover_url":alb.get("cover"),"source":"archive",
                                       "cache_idx":idx,"track_n":track_n})
                        q_emit()
            except Exception as e: log("err",f"q_add_track: {e}")

        elif cmd == "q_clear":  q_clear_all()
        elif cmd == "q_list":   q_emit()
        elif cmd == "q_add_local":
            filepath = line[len("q_add_local "):].strip()
            _queue.append({"title": os.path.basename(filepath), "url": filepath, "cover_url": None, "source": "local", "cache_idx": -1})
            mpv_cmd(f'{{"command":["loadfile","{filepath}","append"]}}')
            q_emit()
        elif cmd == "q_next":   q_play_pos(_queue_pos + 1)
        
        elif cmd == "local_add":
            filepath = line[len("local_add "):].strip()
            libs = load_local_libraries()
            if not any(l["path"] == filepath for l in libs):
                libs.append({"path": filepath, "name": os.path.basename(filepath) or filepath})
                save_local_libraries(libs)
            emit({"cmd": "local_libraries", "libraries": libs})
        
        elif cmd == "local_remove":
            # Local library sil
            libs = load_local_libraries()
            libs = [l for l in libs if l["path"] != arg]
            save_local_libraries(libs)
            emit({"cmd": "local_libraries", "libraries": libs})
        
        elif cmd == "local_list":
            # List all local libraries
            libs = load_local_libraries()
            emit({"cmd": "local_libraries", "libraries": libs})
        
        elif cmd == "local_browse":
            filepath = line[len("local_browse "):].strip()
            items = scan_local_path(filepath)
            emit({"cmd": "local_items", "path": filepath, "name": os.path.basename(filepath) or filepath, "items": items})

        elif cmd == "refresh":
            cache = []
            for col in ARCHIVE_COLLECTIONS:
                try: cache.extend(fetch_archive(col))
                except: pass
            cache.sort(key=lambda x: x["title"].lower())
            save_cache(cache)
            emit({"cmd":"results","items":items_with_idx(cache, cache)})

        elif cmd == "quit":
            break

        sys.stdout.flush()

if __name__ == "__main__":
    main()

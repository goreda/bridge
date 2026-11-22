"""Production Lua with real headless mpv IPC. No native macOS/UI acceptance."""
from pathlib import Path
import json
import os
import socket
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    path = str(base / 'ipc.sock')
    fixture = base / 'video.mkv'
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'color=black:size=1280x720:rate=2', '-t', '1', '-c:v', 'libx264', '-y', str(fixture)], check=True)
    log = (base / 'mpv.log').open('w')
    process = subprocess.Popen([os.environ['MPV'], '--no-config', '--idle=yes', '--vo=null', '--ao=null', '--pause=yes', '--keep-open=yes', '--input-ipc-server=' + path, '--script=' + str(root / 'Resources/vendor/mpv/scripts/gor-fit.lua')], stdout=log, stderr=log)
    try:
        for _ in range(200):
            try:
                client = socket.socket(socket.AF_UNIX)
                client.connect(path)
                break
            except OSError:
                client.close()
                time.sleep(0.02)
        stream = client.makefile('rwb', buffering=0)
        def ipc(*args):
            stream.write((json.dumps({'command': args, 'request_id': 42}) + '\n').encode())
            while True:
                row = json.loads(stream.readline())
                if row.get('request_id') == 42:
                    assert row['error'] == 'success', (args, row)
                    return row.get('data')
        def mode(value):
            ipc('script-message-to', 'gor_fit', 'pip-mode', value)
            time.sleep(0.1)
        ipc('loadfile', str(fixture))
        for _ in range(100):
            if ipc('get_property', 'path') == str(fixture):
                break
            time.sleep(0.02)
        time.sleep(0.2)
        for zoom in [-0.8, -0.2, 0, 0.5]:
            ipc('set_property', 'video-zoom', zoom)
            mode('yes')
            assert abs(ipc('get_property', 'video-zoom') - max(0, zoom)) < 1e-8
            mode('yes')
            mode('no')
            assert abs(ipc('get_property', 'video-zoom') - zoom) < 1e-8
        ipc('set_property', 'video-zoom', -0.6)
        mode('yes')
        ipc('script-message-to', 'gor_fit', 'reset')
        time.sleep(0.2)
        mode('no')
        assert ipc('get_property', 'video-zoom') == 0
        ipc('set_property', 'video-zoom', -0.4)
        mode('yes')
        ipc('loadfile', str(fixture), 'replace')
        time.sleep(0.4)
        mode('no')
        assert ipc('get_property', 'video-zoom') == 0
        print('PASS real mpv +production Lua: negative/zero/positive mode round trips, duplicate receipt, PiP reset clears suspended zoom, new playback clears preceding zoom; no native UI/pixels claim')
        ipc('quit')
    finally:
        process.terminate()
        process.wait(timeout=10)
        log.close()

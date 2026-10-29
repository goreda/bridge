"""Entry-level adapter: invoke the INSTALLED 151c ocr_images.py bytes directly
(no launcher, no runtime venv - refusal paths die before the engine is needed)."""
import json, os, pathlib, subprocess, sys, shutil

KIT_SRC = pathlib.Path('/tmp/kni-src/custody/2026-10-29-kni-151c/current-kit')
TOOLS = ['ocr_images.py', 'ocr_series_identity.py', 'composition_settings_consumer.py',
         'composition_settings_prompt.py', 'input_path.py']

def make_scratch(dst):
    dst = pathlib.Path(dst)
    shutil.rmtree(dst, ignore_errors=True)
    (dst / 'kni' / 'tools').mkdir(parents=True)
    for t in TOOLS:
        shutil.copyfile(KIT_SRC / 'kni' / 'tools' / t, dst / 'kni' / 'tools' / t)
    (dst / 'out').mkdir()
    return dst

def run(kit, args, env_extra=None, stdin_tty=False):
    env = dict(os.environ)
    env.pop('KNI_COMPOSITION_SETTINGS', None); env.pop('KNI_TERMINAL_APP', None)
    if env_extra: env.update(env_extra)
    p = subprocess.run([sys.executable, '-B', str(kit / 'kni' / 'tools' / 'ocr_images.py'), str(kit)] + args,
                       capture_output=True, text=True, env=env, timeout=120)
    return p.returncode, p.stdout, p.stderr

if __name__ == '__main__':
    kit = make_scratch(sys.argv[1])
    print('scratch kit:', kit)

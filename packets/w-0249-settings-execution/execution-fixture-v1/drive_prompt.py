"""Drive a settings-prompt module's ask() with scripted answers; capture prompt order + payload."""
import importlib.util, io, json, sys
from contextlib import redirect_stdout

def drive(module_path, answers):
    spec = importlib.util.spec_from_file_location('promptmod', module_path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    prompts = []
    it = iter(answers)
    def input_fn(text):
        prompts.append(text)
        return next(it, '')
    buf = io.StringIO()
    try:
        with redirect_stdout(buf):
            out = m.ask('a' * 64, 'image_series_whole_canvas_pixels_y_down', input_fn=input_fn)
        return {'result': out, 'prompts': prompts, 'screen_tail': buf.getvalue()[-400:]}
    except m.Cancelled as e:
        return {'cancelled': str(e), 'prompts': prompts}

if __name__ == '__main__':
    out = drive(sys.argv[1], sys.argv[2].split('|') if len(sys.argv) > 2 else [''])
    print(json.dumps(out, indent=1, sort_keys=True, default=str))

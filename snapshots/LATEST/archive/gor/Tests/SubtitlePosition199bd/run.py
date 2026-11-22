from pathlib import Path
import subprocess,tempfile,os,shutil,sys
here=Path(__file__).resolve().parent;root=here.parents[1]
with tempfile.TemporaryDirectory(prefix='subtitle199bd-') as d:
 p=Path(d)
 for n in ['run_geometry.py','run_layout.py','run_route.py','run_consumer.py']:shutil.copy(here/n,p/n)
 env=dict(os.environ,SOURCE_DIR=str(root))
 for n in ['run_geometry.py','run_layout.py','run_route.py','run_consumer.py']:subprocess.run([sys.executable,str(p/n)],env=env,check=True)

"""Create a disposable production copy, run HTTP acceptance checks, stop it.

python3 script/readiness_server.py tmp/readiness/http-fixed.json
No access to the workspace databases or uploads. Uses localhost:18018 only.
"""
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
output = (root / sys.argv[1]).resolve()
output.parent.mkdir(parents=True, exist_ok=True)
with socket.socket() as probe:
    if probe.connect_ex(('127.0.0.1', 18018)) == 0:
        raise SystemExit('Port 18018 is occupied; refusing to test an unknown server')
stage = Path(tempfile.mkdtemp(prefix='attrfill-acceptance-', dir='/private/tmp'))
shutil.copytree(root, stage, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns('.git', '.idea', '.env', 'storage', 'tmp', 'log',
                                              'docs', '__pycache__', 'master.key'))
for name in ['storage', 'tmp', 'log']:
    (stage / name).mkdir()
(stage / '.env').write_text('PORT=18018\nTAILWIND=prebuilt\nLLM_MODE=off\nACCEPTANCE_MODE=strict\n')
context = {'stage': str(stage), 'port': 18018}
result_code = 1
with output.with_suffix('.server.log').open('w') as server_log:
    process = subprocess.Popen(['bin/demo'], cwd=stage, stdout=server_log, stderr=subprocess.STDOUT,
                               start_new_session=True)
    context['pid'] = process.pid
    try:
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError('Demo exited before readiness; see server log')
            try:
                with urllib.request.urlopen('http://127.0.0.1:18018/up', timeout=2) as response:
                    if response.status == 200:
                        break
            except OSError:
                time.sleep(0.25)
        else:
            raise RuntimeError('Demo did not become ready within 120 seconds')
        result = subprocess.run([sys.executable, str(root / 'script/readiness_http.py'),
                                 'http://127.0.0.1:18018', str(output)], cwd=root)
        result_code = result.returncode
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        context['server_stopped'] = process.poll() is not None
        output.with_suffix('.context.json').write_text(json.dumps(context, indent=2))
raise SystemExit(result_code)

#!/usr/bin/env python3
"""Cold-import and runtime tests on the selected installed Godot, with no network."""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ENGINE = str(Path(sys.argv[1]).resolve())
MARKER = 'PASS: Godot GDScript SDK addon; native StreamPeerTCP; local lifecycle'
version = subprocess.check_output([ENGINE, '--version'], text=True, timeout=10).strip()
print('Godot:', version, flush=True)
assert version.startswith('4.'), 'Godot 4 required'


def run(project, args, expected=0):
    result = subprocess.run([ENGINE, '--headless', '--path', str(project),
                             '--log-file', str(project.parent / 'engine.log'), *args],
                            env={**os.environ, 'XDG_DATA_HOME': str(project.parent / 'userdata'), 'XDG_CONFIG_HOME': str(project.parent / 'config'), 'XDG_CACHE_HOME': str(project.parent / 'cache')},
                            capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    print(output, end='', flush=True)
    assert result.returncode == expected, (args, result.returncode, expected)
    if expected == 0:
        assert 'SCRIPT ERROR:' not in output and 'ERROR:' not in output, 'Godot error in successful run'
    return output


with tempfile.TemporaryDirectory(prefix='godot-sdk-smoke-') as tmp:
    work = Path(tmp)
    for attempt in range(3):
        project = work / f'cold-{attempt}' / 'project'
        shutil.copytree(HERE / 'project', project)
        shutil.copytree(ROOT / 'addons/mmo_sdk', project / 'addons/mmo_sdk')
        run(project, ['--import'])
        output = run(project, ['--script', 'res://smoke.gd'])
        assert MARKER in output, 'missing actual runtime PASS marker'
        print(f'PASS: fresh SDK import + runtime {attempt + 1}/3, exit 0', flush=True)
    client = project / 'addons/mmo_sdk/client.gd'
    original = client.read_text()
    for label, bad_source in [
        ('API mismatch', original.replace('API_VERSION: int = 1', 'API_VERSION: int = 2')),
        ('wrong nonce', original.replace('"nonce": nonce,', '"nonce": 17,')),
    ]:
        client.write_text(bad_source)
        output = run(project, ['--script', 'res://smoke.gd'], expected=1)
        assert MARKER not in output and 'FAIL:' in output
        print(f'PASS: {label} fails smoke with exit 1', flush=True)
    client.write_text(original)
    shutil.rmtree(project / 'addons')
    output = run(project, ['--script', 'res://smoke.gd'], expected=1)
    assert MARKER not in output and 'SCRIPT ERROR:' in output
    print('PASS: missing addon fails with exit 1', flush=True)
assert not Path(tmp).exists()
print('PASS: temporary projects and caches removed', flush=True)

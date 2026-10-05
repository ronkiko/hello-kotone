#!/usr/bin/env python3
"""Parser/contract checks; no raster runtime dependency."""
import hashlib
import json
import sys
import tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import frame_tools as frames
import character_assets as packages
checks=0
failures=[]
def check(ok,label):
    global checks
    checks+=1
    if not ok: failures.append(label)
def rejects(fn,label):
    try: fn()
    except frames.ToolError: check(True,label)
    else: check(False,label)
spec={'schema':1,'canvas_px':[320,240],'pivot_px':[71,201],'ground_y_px':210,'physical_height_cm':180,'pixels_per_cm':0.75}
check(frames.frame_spec(spec)==spec,'arbitrary frame size/ground/pivot/projection accepted')
for change in ({'schema':True},{'physical_height_cm':0},{'pixels_per_cm':float('nan')},{'pivot_px':[400,0]},{'canvas_px':[True,256]},{'ground_y_px':241},{'target_body_height_px':172}):
    rejects(lambda: frames.frame_spec({**spec,**change}),'invalid prepared frame rejected')
plan={'schema':1,'source_root_px':[128.5,460],'source_body_height_px':400,'analysis':{'method':'llm','confidence':.8}}
check(frames.placement_plan(plan)==plan,'reviewed single pose plan accepted')
for change in ({'source_root_px':[0,float('inf')]},{'source_body_height_px':True},{'analysis':{'method':'script_heuristic','confidence':.3}},{'scale':.5},{'character_model_id':'kotone'}):
    rejects(lambda: frames.placement_plan({**plan,**change}),'invalid or unreviewed placement rejected')
contract=packages.load_contract()
check(contract.target_height_px('kotone')==172 and contract.target_height_px('yuna')==155,'MMO projection is a separate consumer')

recipe=packages.REPO_ROOT/'godot/tools/character_recipes/locomotion_v1/commands.json'
manifest=json.loads(recipe.read_text())
check(manifest.get('schema')==1 and len(manifest.get('sources',[]))==5,'locomotion recipe manifest loads')
for source_entry in manifest['sources']:
    source_path=packages._repo_relative_path(source_entry['path'],'source path')
    check(source_path.is_file(),source_entry['id']+' source is committed')
    check(hashlib.sha256(source_path.read_bytes()).hexdigest()==source_entry['sha256'],source_entry['id']+' source checksum')
check(all(not item['path'].startswith('godot/assets/') for item in manifest['sources']),'raw locomotion sources live outside Godot runtime assets')
check(not list((packages.GODOT_ROOT/'assets').glob('kotone_v2_*.png')) and not list((packages.GODOT_ROOT/'assets').glob('yuna_v1_*.png')),'legacy raw sheets absent from Godot assets')
check(packages._expand_recipe_command(['place','--source','{repo}/references/a.png'],{'{repo}':'/repo'})==['place','--source','/repo/references/a.png'],'recipe placeholders expand deterministically')
rejects(lambda:packages._expand_recipe_command(['place','--source','{mystery}/a.png'],{}),'unknown recipe placeholder rejected')
rejects(lambda:packages._repo_relative_path('../outside.png','source path'),'recipe source traversal rejected')
with tempfile.TemporaryDirectory() as temp:
    p=Path(temp);source=p/'source.png';source.write_bytes(b'source')
    rejects(lambda:frames.output_file(source,[source],True),'force cannot mutate source')
    d=p/'frames';d.mkdir();(d/'000.png').touch();(d/'002.png').touch()
    rejects(lambda:packages.frame_files(d),'package frame gap rejected')
print(json.dumps({'suite':'character-assets-tool','checks':checks,'failures':failures,'result':'FAIL' if failures else 'PASS'}))
raise SystemExit(bool(failures))

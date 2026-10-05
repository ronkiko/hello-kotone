#!/usr/bin/env python3
"""Parser/contract checks; no raster runtime dependency."""
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
with tempfile.TemporaryDirectory() as temp:
    p=Path(temp);source=p/'source.png';source.write_bytes(b'source')
    rejects(lambda:frames.output_file(source,[source],True),'force cannot mutate source')
    d=p/'frames';d.mkdir();(d/'000.png').touch();(d/'002.png').touch()
    rejects(lambda:packages.frame_files(d),'package frame gap rejected')
print(json.dumps({'suite':'character-assets-tool','checks':checks,'failures':failures,'result':'FAIL' if failures else 'PASS'}))
raise SystemExit(bool(failures))

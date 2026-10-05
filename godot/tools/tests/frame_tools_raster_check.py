#!/usr/bin/env python3
"""Real raster invariants: independent canvas, source immutability, SRT and metadata."""
import contextlib,hashlib,io,json,sys,tempfile,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import frame_tools as f
checks=0;failures=[]
def check(ok,label):
    global checks
    checks+=1
    if not ok:failures.append(label)
def pixels(im,path):return f.run((*im.convert,path,'-format','%[pixel:p{80,100}]','info:'),capture=True)
im=f.find_imagemagick()
with tempfile.TemporaryDirectory(prefix='frame-tools-check-') as temp:
    root=Path(temp);source=root/'pose.png'
    f.run((*im.convert,'-size','512x512','xc:none','-fill','#0000ff','-draw','rectangle 240,70 272,469','-fill','#00ff00','-draw','rectangle 253,467 259,473',f'PNG32:{source}'))
    before=hashlib.sha256(source.read_bytes()).hexdigest()
    spec={'schema':1,'canvas_px':[160,128],'pivot_px':[80,100],'ground_y_px':100,'physical_height_cm':100,'pixels_per_cm':.5}
    plan={'schema':1,'source_root_px':[256,470],'source_body_height_px':400,'analysis':{'method':'llm','confidence':.9}}
    result=f.place_pose(source,root/'placed.png',spec,plan)
    check(result['uniform_scale']==.125,'scale uses cm and projection')
    check(f.png_geometry(root/'placed.png')==(160,128,8,6),'arbitrary canvas RGBA output')
    green=f.run((*im.convert,root/'placed.png','-format','%[fx:p{80,100}.g]','info:'),capture=True)
    check(float(green)>.3,'source root maps to explicit target pivot')
    bbox=f.alpha_bbox(im,root/'placed.png')
    crown=f.run((*im.convert,root/'placed.png','-format','%[fx:p{80,50}.a] %[fx:p{80,40}.a]','info:'),capture=True).split()
    check(float(crown[0])>.4 and float(crown[1])==0,'anatomical crown projected to height 50 px')
    f.place_pose(source,root/'repeat.png',spec,plan)
    check(subprocess.check_output([*im.convert,str(root/'placed.png'),'RGBA:-'])==subprocess.check_output([*im.convert,str(root/'repeat.png'),'RGBA:-']),'repeat placement has identical pixels')
    check(before==hashlib.sha256(source.read_bytes()).hexdigest(),'source unchanged')
    f.extract_pose(source,root/'crop.png',[224,50,64,440])
    check(f.png_geometry(root/'crop.png')[:2]==(64,440),'single pose extraction supports explicit rectangle')
    check(f.alpha_bbox(im,root/'crop.png')[:2]==(16,20),'alpha diagnostics preserve trim offsets')
    empty=root/'empty.png';f.run((*im.convert,'-size','37x51','xc:none',f'PNG32:{empty}'))
    check(f.alpha_bbox(im,empty) is None,'transparent pose not a fake silhouette')
    # Source geometry is 1024x512 but stale virtual canvas metadata says 512x512.
    sheet=root/'sheet.png';f.run((*im.convert,source,source,'+append','-set','page','512x512+0+0',f'PNG32:{sheet}'))
    with contextlib.redirect_stdout(io.StringIO()):
        code=f.main(['split-grid','--source',str(sheet),'--columns','2','--rows','1','--output',str(root/'split')])
    check(code==0 and len(list((root/'split').glob('*.png')))==2,'grid ignores stale PNG page metadata')
    check(f.png_geometry(root/'split/001.png')[:2]==(512,512),'512 frame remains unscaled after split')
    matte=root/'matte.png';f.run((*im.convert,'-size','32x32','xc:#466F4B','-fill','red','-draw','rectangle 10,10 20,20',f'PNG32:{matte}'))
    f.clean_pose(matte,root/'clean.png',matte='#466F4B')
    check(f.alpha_bbox(im,root/'clean.png')==(10,10,11,11),'matte cleanup is separate offline operation')
    with contextlib.redirect_stdout(io.StringIO()):
        code=f.main(['resize','--source',str(source),'--factor','.5','--output',str(root/'small.png')])
    check(code==0 and f.png_geometry(root/'small.png')[:2]==(256,256),'explicit independent uniform resize')
    suggestion=f.heuristic_pose(source)
    try:f.placement_plan({k:v for k,v in suggestion.items() if k!='alpha_bbox_diagnostic'})
    except f.ToolError: check(True,'heuristic cannot apply itself')
    else:check(False,'heuristic cannot apply itself')
    target_spec = root/'target-spec.json'
    pose_plan = root/'pose-plan.json'
    target_spec.write_text(json.dumps(spec))
    pose_plan.write_text(json.dumps(plan))
    with contextlib.redirect_stderr(io.StringIO()):
        code=f.main(['place','--source',str(source),'--frame-spec',str(target_spec),'--plan',str(pose_plan),'--output',str(target_spec),'--force'])
    check(code==1 and json.loads(target_spec.read_text())==spec,'place force cannot overwrite prepared specification')
    f.prepare_frame(root/'prepared.json',spec)
    check(f.png_geometry(root/'prepared.png')[:2]==(160,128),'prepare emits independent blank canvas')
print(json.dumps({'suite':'frame-tools-raster','checks':checks,'failures':failures,'result':'FAIL' if failures else 'PASS'}))
raise SystemExit(bool(failures))

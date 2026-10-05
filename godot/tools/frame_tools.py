#!/usr/bin/env python3
"""Atomic raster operations. An agent chooses the flow and all semantic points.

No Godot, model ids, package layout, frame sizes or character heights are assumed.
Every operation preserves its inputs and writes only explicit outputs.
"""
from __future__ import annotations
import argparse
import json
import math
import re
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
BBOX_RE = re.compile(r"^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)$")

class ToolError(RuntimeError):
    pass

@dataclass(frozen=True)
class ImageMagick:
    convert: tuple[str, ...]
    identify: tuple[str, ...]
    montage: tuple[str, ...]
    label: str

def run(command: Iterable[str], *, capture: bool = False) -> str:
    args = [str(part) for part in command]
    result = subprocess.run(
        args,
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    if result.returncode:
        detail = (result.stderr or result.stdout or "").strip()
        raise ToolError(f"command failed ({result.returncode}): {' '.join(args)}\n{detail}")
    return (result.stdout or "").strip()


def find_imagemagick() -> ImageMagick:
    magick = shutil.which("magick")
    if magick:
        return ImageMagick(
            convert=(magick,),
            identify=(magick, "identify"),
            montage=(magick, "montage"),
            label="ImageMagick 7",
        )
    convert = shutil.which("convert")
    identify = shutil.which("identify")
    montage = shutil.which("montage")
    if convert and identify and montage:
        return ImageMagick(
            convert=(convert,),
            identify=(identify,),
            montage=(montage,),
            label="ImageMagick 6",
        )
    raise ToolError(
        "ImageMagick not found; install ImageMagick 7 (magick) or "
        "ImageMagick 6 (convert + identify + montage)"
    )


def png_geometry(path: Path) -> tuple[int, int, int, int]:
    with path.open("rb") as stream:
        header = stream.read(33)
    if len(header) < 33 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ToolError(f"{path}: not a PNG with IHDR")
    width, height, bit_depth, color_type = struct.unpack(">IIBB", header[16:26])
    return width, height, bit_depth, color_type


def identify_geometry(im: ImageMagick, path: Path) -> tuple[int, int]:
    text = run((*im.identify, "-format", "%w %h", path), capture=True)
    try:
        width, height = (int(part) for part in text.split())
    except ValueError as exc:
        raise ToolError(f"{path}: unexpected identify output: {text!r}") from exc
    return width, height


def alpha_bbox(im: ImageMagick, path: Path) -> tuple[int, int, int, int] | None:
    extrema = run((*im.convert, path, "+repage", "-alpha", "extract", "-format", "%[fx:maxima]", "info:"), capture=True)
    if float(extrema) <= 0:
        return None
    text = run(
        (
            *im.convert,
            path,
            "+repage",
            "-alpha",
            "extract",
            "-threshold",
            "0",
            "-trim",
            "-format",
            "%wx%h%O",
            "info:",
        ),
        capture=True,
    )
    match = BBOX_RE.fullmatch(text.strip())
    if not match:
        return None
    width, height, x, y = (int(value) for value in match.groups())
    if width <= 0 or height <= 0:
        return None
    return x, y, width, height



def finite(value, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ToolError(f"{label} must be finite")
    return float(value)


def frame_spec(value: dict) -> dict:
    keys = {"schema", "canvas_px", "pivot_px", "ground_y_px", "physical_height_cm", "pixels_per_cm"}
    if not isinstance(value, dict) or set(value) != keys or type(value["schema"]) is not int or value["schema"] != 1:
        raise ToolError("invalid frame specification")
    size, pivot = value["canvas_px"], value["pivot_px"]
    if not isinstance(size, list) or len(size) != 2 or any(type(n) is not int or not 1 <= n <= 8192 for n in size):
        raise ToolError("canvas must contain two integers in [1,8192]")
    if not isinstance(pivot, list) or len(pivot) != 2:
        raise ToolError("pivot must contain two coordinates")
    x, y = [finite(n, "pivot") for n in pivot]
    if not 0 <= x < size[0] or not 0 <= y < size[1]:
        raise ToolError("pivot outside canvas")
    if not 0 <= finite(value["ground_y_px"], "ground") < size[1]:
        raise ToolError("ground outside canvas")
    if finite(value["physical_height_cm"], "physical height") <= 0 or finite(value["pixels_per_cm"], "projection") <= 0:
        raise ToolError("physical height and pixels_per_cm must be positive")
    return value


def placement_plan(value: dict) -> dict:
    if not isinstance(value, dict) or set(value) != {"schema", "source_root_px", "source_body_height_px", "analysis"} or type(value["schema"]) is not int or value["schema"] != 1:
        raise ToolError("invalid single-pose placement plan")
    point = value["source_root_px"]
    if not isinstance(point, list) or len(point) != 2:
        raise ToolError("source_root_px must have two coordinates")
    for n in point:
        finite(n, "source root")
    if finite(value["source_body_height_px"], "source body height") <= 0:
        raise ToolError("source body height must be positive")
    analysis = value["analysis"]
    if not isinstance(analysis, dict) or set(analysis) - {"method", "confidence", "notes", "author"}:
        raise ToolError("invalid analysis")
    if analysis.get("method") not in {"llm", "human", "llm_reviewed_heuristic", "human_reviewed_heuristic"}:
        raise ToolError("placement requires explicit reviewed coordinates; script_heuristic is a suggestion only")
    if not 0 <= finite(analysis.get("confidence"), "confidence") <= 1:
        raise ToolError("confidence must be in [0,1]")
    return value


def output_file(path: Path, sources=(), force: bool = False) -> Path:
    path = path.resolve()
    if path in {Path(source).resolve() for source in sources}:
        raise ToolError("output must not overwrite an input")
    if path.exists() and not force:
        raise ToolError(f"{path}: already exists; use --force")
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def source_command(im: ImageMagick, source: Path) -> list:
    if not source.is_file():
        raise ToolError(f"{source}: missing source")
    return [*im.convert, source, "+repage", "-alpha", "on"]


def extract_pose(source: Path, output: Path, region: list[int] | None = None, *, force=False) -> dict:
    im = find_imagemagick()
    width, height = identify_geometry(im, source)
    x, y, w, h = region or [0, 0, width, height]
    if any(type(n) is not int for n in (x, y, w, h)) or min(x,y) < 0 or min(w,h) <= 0 or x+w > width or y+h > height:
        raise ToolError("extraction region outside source pixels")
    output = output_file(output, [source], force)
    run((*source_command(im, source), "-crop", f"{w}x{h}+{x}+{y}", "+repage", "-strip", f"PNG32:{output}"))
    return {"result": "PASS", "source_size_px": [width, height], "source_region_px": [x,y,w,h], "output": str(output)}


def prepare_frame(output: Path, spec: dict, *, force=False) -> dict:
    spec = frame_spec(spec)
    output = output_file(output, force=force)
    canvas = output_file(output.with_suffix(".png"), [output], force)
    im = find_imagemagick()
    width, height = spec["canvas_px"]
    run((*im.convert, "-size", f"{width}x{height}", "xc:none", "-strip", f"PNG32:{canvas}"))
    output.write_text(json.dumps(spec, indent=2) + "\n")
    return {"result": "PASS", "frame_spec": str(output), "canvas": str(canvas)}


def clean_pose(source: Path, output: Path, *, matte=None, fuzz=0.0, alpha_floor=0.0, force=False) -> dict:
    im = find_imagemagick()
    if matte is not None and re.fullmatch(r"#[0-9a-fA-F]{6}", matte) is None:
        raise ToolError("matte must be #RRGGBB")
    if not 0 <= finite(fuzz, "fuzz") <= 25 or fuzz and not matte:
        raise ToolError("fuzz requires matte and must be in [0,25]")
    if not 0 <= finite(alpha_floor, "alpha floor") <= 1:
        raise ToolError("alpha floor must be in [0,1]")
    output = output_file(output, [source], force)
    command = source_command(im, source)
    if matte:
        command += ["-fuzz", f"{fuzz:.12g}%", "-transparent", matte]
    if alpha_floor:
        command += ["-channel", "A", "-fx", f"u>{alpha_floor:.12g} ? u : 0", "+channel"]
    run((*command, "-strip", f"PNG32:{output}"))
    return {"result": "PASS", "matte": matte, "fuzz_percent": fuzz, "alpha_floor": alpha_floor, "output": str(output)}


def place_pose(source: Path, output: Path, spec: dict, plan: dict, *, force=False) -> dict:
    """One uniform SRT, one source pose. No cleanup, heuristic or package selection."""
    spec, plan = frame_spec(spec), placement_plan(plan)
    im = find_imagemagick()
    width, height = identify_geometry(im, source)
    x, y = plan["source_root_px"]
    if not 0 <= x < width or not 0 <= y < height:
        raise ToolError("source root outside source")
    output = output_file(output, [source], force)
    scale = spec["physical_height_cm"] * spec["pixels_per_cm"] / plan["source_body_height_px"]
    if not math.isfinite(scale) or scale <= 0:
        raise ToolError("computed uniform scale must be finite and positive")
    px, py = spec["pivot_px"]
    w, h = spec["canvas_px"]
    run((*source_command(im, source), "-background", "none", "-virtual-pixel", "transparent", "-filter", "Lanczos",
         "-set", "option:distort:viewport", f"{w}x{h}+0+0", "-distort", "SRT", f"{x:.12g},{y:.12g} {scale:.12g} 0 {px:.12g},{py:.12g}", "+repage", "-strip", f"PNG32:{output}"))
    bbox = alpha_bbox(im, output)
    clipped = bbox is not None and (bbox[0] <= 0 or bbox[1] <= 0 or bbox[0]+bbox[2] >= w or bbox[1]+bbox[3] >= h)
    return {"result": "PASS_WITH_WARNINGS" if clipped else "PASS", "uniform_scale": scale,
            "source_root_px": [x,y], "target_root_px": [px,py], "physical_height_cm": spec["physical_height_cm"], "pixels_per_cm": spec["pixels_per_cm"], "target_body_height_px": spec["physical_height_cm"] * spec["pixels_per_cm"],
            "alpha_bbox_diagnostic": bbox, "edge_touch_warning": clipped, "output": str(output)}


def inspect_pose(source: Path, output: Path, *, grid_step=32, force=False) -> dict:
    im = find_imagemagick()
    width, height = identify_geometry(im, source)
    if grid_step <= 0:
        raise ToolError("grid step must be positive")
    output = output_file(output, [source], force)
    packet = output_file(output.with_suffix(".json"), [source, output], force)
    lines = [f"line {x},0 {x},{height-1}" for x in range(grid_step,width,grid_step)]
    lines += [f"line 0,{y} {width-1},{y}" for y in range(grid_step,height,grid_step)]
    command = source_command(im, source) + ["-stroke", "#00FFFF66", "-strokewidth", "1", "-fill", "none"]
    if lines:
        command += ["-draw", " ".join(lines)]
    run((*command, "-strip", f"PNG32:{output}"))
    result = {"result": "PASS", "source_size_px": [width,height], "alpha_bbox_diagnostic": alpha_bbox(im, source),
              "grid_step_px": grid_step, "origin": "top-left; pixel-center coordinates", "source": str(source),
              "instructions": "LLM chooses anatomical height/root. Alpha bbox is diagnostics only. Uniform scale across related poses.",
              "overlay": str(output)}
    packet.write_text(json.dumps(result,indent=2)+'\n')
    return result


def heuristic_pose(source: Path) -> dict:
    im = find_imagemagick()
    bbox = alpha_bbox(im, source)
    if bbox is None:
        raise ToolError("source is transparent")
    x,y,w,h = bbox
    return {"schema": 1, "source_root_px": [x+w/2, y+h-1], "source_body_height_px": h,
            "analysis": {"method": "script_heuristic", "confidence": 0.3,
                         "notes": "Silhouette midpoint/bottom and height only. Ignores anatomical body axis, hair, foot pose and artifacts. Review required."},
            "alpha_bbox_diagnostic": bbox}


OPERATIONS = {"extract", "split-grid", "prepare", "clean", "resize", "mirror", "inspect", "heuristic", "place", "render"}

def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in sorted(OPERATIONS):
        p = sub.add_parser(name)
        if name != "prepare":
            p.add_argument("--source", type=Path, required=True)
        if name != "heuristic":
            p.add_argument("--output", type=Path, required=True)
            p.add_argument("--force", action="store_true")
        if name == "extract":
            p.add_argument("--region", type=int, nargs=4)
        elif name == "split-grid":
            p.add_argument("--columns", type=int, required=True)
            p.add_argument("--rows", type=int, required=True)
        elif name == "prepare":
            p.add_argument("--canvas", type=int, nargs=2, required=True)
            p.add_argument("--pivot", type=float, nargs=2, required=True)
            p.add_argument("--ground-y", type=float, required=True)
            p.add_argument("--height-cm", type=float, required=True)
            p.add_argument("--pixels-per-cm", type=float, required=True)
        elif name == "clean":
            p.add_argument("--matte")
            p.add_argument("--fuzz", type=float, default=0)
            p.add_argument("--alpha-floor", type=float, default=0)
        elif name == "resize":
            p.add_argument("--factor", type=float, required=True)
        elif name == "inspect":
            p.add_argument("--grid-step", type=int, default=32)
        elif name == "place":
            p.add_argument("--frame-spec", type=Path, required=True)
            p.add_argument("--plan", type=Path, required=True)
        elif name == "render":
            p.add_argument("--background", default="#404040")
    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)
    try:
        match args.command:
            case "extract": result = extract_pose(args.source,args.output,args.region,force=args.force)
            case "prepare": result = prepare_frame(args.output,{"schema":1,"canvas_px":args.canvas,"pivot_px":args.pivot,"ground_y_px":args.ground_y,"physical_height_cm":args.height_cm,"pixels_per_cm":args.pixels_per_cm},force=args.force)
            case "clean": result = clean_pose(args.source,args.output,matte=args.matte,fuzz=args.fuzz,alpha_floor=args.alpha_floor,force=args.force)
            case "inspect": result = inspect_pose(args.source,args.output,grid_step=args.grid_step,force=args.force)
            case "heuristic": result = heuristic_pose(args.source)
            case "place":
                output_file(args.output, [args.source, args.frame_spec, args.plan], args.force)
                result = place_pose(args.source, args.output, json.loads(args.frame_spec.read_text()), json.loads(args.plan.read_text()), force=args.force)
            case "split-grid":
                if args.columns <= 0 or args.rows <= 0 or args.columns*args.rows > 1000:
                    raise ToolError("grid must contain 1..1000 cells")
                im = find_imagemagick()
                width,height = identify_geometry(im,args.source)
                w,h = math.ceil(width/args.columns),math.ceil(height/args.rows)
                output = args.output.resolve()
                if output == args.source.resolve() or output in args.source.resolve().parents:
                    raise ToolError("output directory contains source")
                if output.exists() and any(output.iterdir()):
                    raise ToolError("split-grid requires an empty output directory")
                output.mkdir(parents=True,exist_ok=True)
                run((*source_command(im,args.source),"-background","none","-gravity","northwest","-extent",f"{w*args.columns}x{h*args.rows}","-crop",f"{w}x{h}","+repage",f"PNG32:{output / '%03d.png'}"))
                result = {"result":"PASS","cell_size_px":[w,h],"grid":[args.columns,args.rows],"frames":args.columns*args.rows,"output":str(output)}
            case "resize" | "mirror" | "render":
                im = find_imagemagick()
                command = source_command(im,args.source)
                output = output_file(args.output,[args.source],args.force)
                if args.command == "resize":
                    if not 0 < finite(args.factor,"factor") <= 100:
                        raise ToolError("factor must be in (0,100]")
                    command += ["-filter","Lanczos","-resize",f"{args.factor*100:.12g}%"]
                elif args.command == "mirror": command += ["-flop"]
                else: command += ["-background",args.background,"-alpha","remove","-alpha","off"]
                run((*command,"-strip", f"PNG32:{output}"))
                result = {"result":"PASS","output":str(output),"size_px":identify_geometry(im,output)}
        print(json.dumps(result,indent=2))
        return 0
    except (OSError,ValueError,KeyError,TypeError,ToolError,subprocess.SubprocessError) as exc:
        print(f"FAIL {exc}",file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

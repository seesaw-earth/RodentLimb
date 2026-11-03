#!/usr/bin/env python3
"""Install or update the pose models of the RodentLimb iPhone/iPad Xcode project.

The app ships two models (Pose/PoseModels.swift):
  --fp16  CylinderPose7_FP16_640      visible light, 7 keypoints (default)
  --nir   PalmReaderPose8_640_W8A16   near-infrared dark box, 8 keypoints

Usage (from the RodentLimb-iOS folder):
  python3 Tools/install_model.py --fp16 ~/Downloads/CylinderPose7_FP16_640.mlpackage.zip
  python3 Tools/install_model.py --nir ~/Downloads/PalmReaderPose8_640_W8A16.mlpackage.zip
Accepts either the .mlpackage.zip exported from Colab or an unpacked .mlpackage folder.

CylinderMousePoseV2 (full precision, 38 MB) is no longer part of the app: videos tracked with it keep
their results, and tracking them again uses CylinderPose7 FP16 (the same network). This script
removes a leftover CylinderMousePoseV2.mlpackage from the Models folder.

The Xcode project uses a synchronized folder, so the package is picked up automatically;
do not drag it into Xcode again.
"""
import argparse, pathlib, shutil, sys, tempfile, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEST = ROOT / 'RodentLimb' / 'Models'
FP16_NAME = 'CylinderPose7_FP16_640.mlpackage'
NIR_NAME = 'PalmReaderPose8_640_W8A16.mlpackage'
REMOVED = 'CylinderMousePoseV2.mlpackage'


def locate(path, work):
    src = pathlib.Path(path).expanduser().resolve()
    if not src.exists():
        raise ValueError(f'Not found / 找不到: {src}')
    if src.is_dir() and src.suffix == '.mlpackage':
        pkg = src
    elif src.is_file() and src.suffix.lower() == '.zip':
        with zipfile.ZipFile(src) as z:
            for item in z.infolist():
                out = (work / item.filename).resolve()
                if not str(out).startswith(str(work.resolve())):
                    raise ValueError('Unsafe path in ZIP / ZIP 包含不安全路径')
            z.extractall(work)
        found = [p for p in work.rglob('*.mlpackage') if '__MACOSX' not in p.parts]
        if len(found) != 1:
            raise ValueError(f'Expected exactly one .mlpackage in the ZIP, found {len(found)}')
        pkg = found[0]
    else:
        raise ValueError(f'Use a .mlpackage folder or a .zip containing one: {src}')
    if not (pkg / 'Manifest.json').exists():
        raise ValueError(f'{pkg} has no Manifest.json — incomplete Core ML package')
    return pkg


def install(src, name, tmp):
    tmp = pathlib.Path(tmp)
    tmp.mkdir(parents=True, exist_ok=True)
    pkg = locate(src, tmp)
    target = DEST / name
    staging = DEST / (name + '.installing')
    if staging.exists():
        shutil.rmtree(staging)
    shutil.copytree(pkg, staging)
    if target.exists():
        shutil.rmtree(target)
    staging.rename(target)
    size = sum(f.stat().st_size for f in target.rglob('*') if f.is_file()) / 1e6
    print(f'OK: {target} ({size:.1f} MB)')


def main():
    ap = argparse.ArgumentParser(description='Install the pose models into RodentLimb (iPhone/iPad)')
    ap.add_argument('--fp16', help='CylinderPose7_FP16_640 .mlpackage or .zip (visible light, default)')
    ap.add_argument('--nir', help='PalmReaderPose8_640_W8A16 .mlpackage or .zip (near-infrared dark box)')
    args = ap.parse_args()
    if not args.fp16 and not args.nir:
        ap.error('give --fp16 and/or --nir')
    DEST.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        if args.fp16:
            install(args.fp16, FP16_NAME, pathlib.Path(tmp) / 'fp16')
        if args.nir:
            install(args.nir, NIR_NAME, pathlib.Path(tmp) / 'nir')
    old = DEST / REMOVED
    if old.exists():
        shutil.rmtree(old)
        print(f'Removed {old} (no longer part of the app / 已不再包含在 App 中)')
    print('Open RodentLimb.xcodeproj, Product > Clean Build Folder, then Run on your iPhone.')
    print('打开 RodentLimb.xcodeproj，Product > Clean Build Folder，然后在 iPhone 上运行。')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('ERROR:', exc, file=sys.stderr)
        sys.exit(1)

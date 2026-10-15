#!/usr/bin/env python3
"""Install CylinderMousePoseV2 into the RodentLimb Xcode project.

Usage (from the RodentLimb folder):
  python3 Tools/install_model.py --v2 ~/Downloads/CylinderMousePoseV2.mlpackage.zip
Accepts either the .mlpackage.zip exported from Colab or an unpacked .mlpackage folder.
You can also point it at the copy already installed in CylinderPose:
  python3 Tools/install_model.py --v2 ~/Downloads/CylinderPose_DualModel_AB/CylinderPose/CylinderPose/Models/CylinderMousePoseV2.mlpackage

The Xcode project uses a synchronized folder, so the package is picked up automatically —
do not drag it into Xcode again.
"""
import argparse, pathlib, shutil, sys, tempfile, zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEST = ROOT / 'RodentLimb' / 'Models'
NAME = 'CylinderMousePoseV2.mlpackage'


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


def main():
    ap = argparse.ArgumentParser(description='Install CylinderMousePoseV2 into RodentLimb')
    ap.add_argument('--v2', required=True, help='CylinderMousePoseV2 .mlpackage or .zip')
    args = ap.parse_args()
    DEST.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        pkg = locate(args.v2, pathlib.Path(tmp))
        target = DEST / NAME
        staging = DEST / (NAME + '.installing')
        if staging.exists():
            shutil.rmtree(staging)
        shutil.copytree(pkg, staging)
        if target.exists():
            shutil.rmtree(target)
        staging.rename(target)
        size = sum(f.stat().st_size for f in target.rglob('*') if f.is_file()) / 1e6
        print(f'OK: {target} ({size:.1f} MB)')
    print('Open RodentLimb.xcodeproj, Product > Clean Build Folder, then Run on your iPhone.')
    print('打开 RodentLimb.xcodeproj，Product > Clean Build Folder，然后在 iPhone 上运行。')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print('ERROR:', exc, file=sys.stderr)
        sys.exit(1)

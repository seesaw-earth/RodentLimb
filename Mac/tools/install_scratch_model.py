#!/usr/bin/env python3
"""Install the trained scratch detector exported by the Colab notebook into the app.

The notebook (RodentLimb_PublicDatasets_Behavior, section 9) writes a compact JSON file,
`compact_scratch_model.json`: feature names, gradient-boosted trees, the tuned post-processing
and test vectors. This script checks that file the same way the app does (every test vector
must be reproduced to < 1e-6) and copies it to macOS/RodentLimbMac/Models/ScratchModel.json. Rebuild
the app afterwards; the Itch assay then uses the model ("Trained model if installed").

Usage:
    python3 Tools/install_scratch_model.py ~/Downloads/compact_scratch_model.json
    python3 Tools/install_scratch_model.py --remove      # go back to the keypoint rules
"""
import argparse
import json
import math
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "macOS" / "RodentLimbMac" / "Models" / "ScratchModel.json"
# Features the app cannot compute from keypoints alone (the detector box is not stored).
UNSUPPORTED = ("box", "area")


def score(model, x):
    z = model["baseline"]
    for t in model["trees"]:
        i = 0
        for _ in range(4096):
            f = t["feature"][i]
            if f < 0:
                break
            v = x[f]
            if v is None or (isinstance(v, float) and math.isnan(v)):
                i = t["left"][i] if t["missing_left"][i] == 1 else t["right"][i]
            else:
                i = t["left"][i] if v <= t["threshold"][i] else t["right"][i]
        z += t["value"][i]
    return 1.0 / (1.0 + math.exp(-z))


def check(path):
    model = json.loads(Path(path).read_text())
    for key in ("features", "baseline", "trees", "postprocess"):
        if key not in model:
            sys.exit(f"Not a RodentLimb scratch model: '{key}' is missing.")
    names = [f["name"] for f in sorted(model["features"], key=lambda f: f["index"])]
    for t in model["trees"]:
        n = len(t["feature"])
        if n == 0 or any(len(t[k]) != n for k in ("threshold", "missing_left", "left", "right", "value")):
            sys.exit("Malformed tree in the model file.")
        if any(f >= len(names) for f in t["feature"]):
            sys.exit("A tree refers to a feature index that does not exist.")
    bad = [n for n in names if any(u in n for u in UNSUPPORTED)]
    if bad:
        sys.exit("The model uses features the app cannot compute: " + ", ".join(bad) +
                 "\nRetrain it in the notebook without detector-box features.")
    vectors = model.get("test_vectors") or []
    err = max((abs(score(model, v["x"]) - v["p"]) for v in vectors), default=0.0)
    if err >= 1e-6:
        sys.exit(f"Test vectors are not reproduced (max error {err:.2e}); the file is damaged or from another format.")
    pp = model["postprocess"]
    f1 = (model.get("metrics_official_test") or [{}])[0].get("frame_F1")
    print(f"OK: {len(model['trees'])} trees, {len(names)} features, {len(vectors)} test vectors reproduced (max error {err:.1e}).")
    print(f"    post-processing: smooth {pp['smooth_s']} s, threshold {pp['thr']}, gap {pp['gap_s']} s, minimum {pp['min_s']} s")
    if f1 is not None:
        print(f"    held-out frame F1 reported by the notebook: {f1:.3f}")
    return model


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model", nargs="?", help="compact_scratch_model.json from the notebook")
    ap.add_argument("--remove", action="store_true", help="remove the installed model")
    a = ap.parse_args()
    if a.remove:
        if DEST.exists():
            DEST.unlink()
            print(f"Removed {DEST}. Rebuild the app; the Itch assay uses the keypoint rules.")
        else:
            print("No model installed.")
        return
    if not a.model:
        ap.error("give the path to compact_scratch_model.json, or --remove")
    check(a.model)
    DEST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(a.model, DEST)
    print(f"Installed to {DEST}. Rebuild the app in Xcode.")


if __name__ == "__main__":
    main()

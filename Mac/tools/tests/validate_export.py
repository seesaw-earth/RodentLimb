"""Checks an export written by the core tests: every table loads with pandas, identification
columns are consistent, segments / bins / frame labels / DLC pose / BORIS have the expected layout.
Usage: python3 tools/tests/validate_export.py <folder containing the export folder>"""
import sys, os, glob, json
import pandas as pd

root = sys.argv[1]
folders = sorted(glob.glob(os.path.join(root, "RodentLimb_*")))
assert folders, "no export folder"
ex = folders[-1]
fails = 0
def check(ok, what):
    global fails
    print(("  ok    " if ok else "  FAIL  ") + what)
    if not ok: fails += 1

print("Export (pandas)")
ID = ["analysis_id","study","animal_id","blind_code","sex","group","timepoint","trial","video","included"]
qc = pd.read_csv(os.path.join(ex, "qc_videos.csv"), encoding="utf-8-sig")
check(len(qc) == 6 and "mouse_tracked_pct" in qc and "decision" in qc, f"qc_videos.csv: {len(qc)} videos")
task = glob.glob(os.path.join(ex, "GROOM_*"))[0]
summ = pd.read_csv(os.path.join(task, "GROOM_summary.csv"), encoding="utf-8-sig")
check(len(summ) >= 4 and "qc_verdict" in summ.columns, f"summary: {len(summ)} analyses, {summ.shape[1]} columns")
seg = pd.read_csv(os.path.join(task, "GROOM_segments.csv"), encoding="utf-8-sig", dtype={"analysis_id": str})
check(list(seg.columns[:10]) == ID and {"onset_s","offset_s","duration_s","final_label"} <= set(seg.columns), f"segments: id columns + {len(seg)} events")
if len(seg):
    check(((seg.offset_s - seg.onset_s - seg.duration_s).abs() < 0.002).all(), "segments: duration = offset − onset")
bins = pd.read_csv(os.path.join(task, "GROOM_time_bins.csv"), encoding="utf-8-sig")
check({"bin","measure","value"} <= set(bins.columns), f"time bins long format: {len(bins)} rows")
etho = pd.read_csv(os.path.join(task, "GROOM_ethogram.csv"), encoding="utf-8-sig")
check({"behavior","start_s","end_s"} <= set(etho.columns), f"ethogram: {len(etho)} intervals")
fl = glob.glob(os.path.join(task, "frame_labels", "*_labels.csv"))
check(len(fl) >= 4, f"frame labels: {len(fl)} files")
if fl:
    lab = pd.read_csv(fl[0], index_col=0)
    check(lab.columns[0] == "background" and set(lab.values.flatten()) <= {0, 1}, f"frame labels 0/1 with background ({len(lab)} frames, {lab.shape[1]} columns)")
    check(((lab.iloc[:, 1:].sum(axis=1) == 0) == (lab.background == 1)).all(), "background = 1 exactly when no behavior is scored")
dlc = glob.glob(os.path.join(ex, "pose_dlc", "*_DLC.csv"))
check(len(dlc) >= 4, f"DeepLabCut pose files: {len(dlc)}")
if dlc:
    d = pd.read_csv(dlc[0], header=[0,1,2], index_col=0)
    check(d.columns.nlevels == 3 and d.shape[1] == 21 and set(d.columns.get_level_values(2)) == {"x","y","likelihood"}, f"DLC layout: {d.shape[0]} frames × 7 body parts × (x, y, likelihood)")
pose = glob.glob(os.path.join(ex, "pose", "*_pose.csv"))
if pose:
    pz = pd.read_csv(pose[0], encoding="utf-8-sig")
    check("nose_x" in pz.columns and len(pz) == len(d), "RodentLimb pose CSV matches the DLC file frame count")
man = json.load(open(os.path.join(ex, "export_manifest.json")))
check(len(man["analyses"]) == len(summ) and "parameters" in man["analyses"][0], "manifest lists every analysis with parameters")
pv = glob.glob(os.path.join(task, "per_video", "*", "*_summary.csv"))
check(len(pv) >= 4, f"per-video folders: {len(pv)}")
readme = open(os.path.join(ex, "README.txt"), encoding="utf-8-sig").read()
check("IDENTIFICATION COLUMNS" in readme and "GROOM_segments.csv" in readme, "README data dictionary")
print("\nEXPORT CHECKS PASSED" if fails == 0 else f"\n{fails} EXPORT CHECK(S) FAILED")
sys.exit(1 if fails else 0)

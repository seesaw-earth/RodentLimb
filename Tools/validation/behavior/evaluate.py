"""Score the Swift analyzers' output against the simulator's ground truth."""
import json, sys
import numpy as np

d = sys.argv[1]


def load(name):
    return json.load(open(f'{d}/{name}_truth.json')), json.load(open(f'{d}/{name}_swift.json'))


def overlap(a, b):
    return max(0.0, min(a[1], b[1]) - max(a[0], b[0]))


def match(truth_iv, det_iv, min_frac=0.3):
    """Event-level recall/precision: a truth event is found if a detection overlaps ≥ min_frac of it (or contains its onset for brief events)."""
    hit_t = [any(overlap(t, x) >= min_frac * max(t[1] - t[0], 1e-9) or (x[0] - 0.15 <= t[0] <= x[1] + 0.15) for x in det_iv) for t in truth_iv]
    hit_d = [any(overlap(t, x) > 0 or (x[0] - 0.15 <= t[0] <= x[1] + 0.15) for t in truth_iv) for x in det_iv]
    return (sum(hit_t), len(truth_iv), sum(hit_d), len(det_iv))


def show(title, r):
    tp, nt, dp, nd = r
    print(f'  {title:34s} recall {tp}/{nt}  precision {dp}/{nd}')


def ev(sw, label, counted=True):
    return [(float(e['onset']), float(e['offset'])) for e in sw['events'] if e['label'] == label and (not counted or e['counted'] == '1')]


def notes(sw):
    for n in sw['notes']:
        print('   ', n[:150])


print('== ITCH (rules)')
truth, sw = load('itch')
tr = [(t['start'], t['end']) for t in truth['truth'] if t['kind'] == 'scratch']
show('scratch bouts', match(tr, ev(sw, 'scratch')))
m = sw['metrics']
print(f"  scratching time {m['scratch_time_s']:.1f} s (truth {sum(b - a for a, b in tr):.1f}); bouts {m['scratch_bouts_n']:.0f} (truth {len(tr)}); "
      f"L/R {m['left_bouts_n']:.0f}/{m['right_bouts_n']:.0f} (truth {sum(t['side'] == 'L' for t in truth['truth'] if t['kind'] == 'scratch')}/"
      f"{sum(t['side'] == 'R' for t in truth['truth'] if t['kind'] == 'scratch')})")
fg = [(t['start'], t['end']) for t in truth['truth'] if t['kind'] == 'groom_face']
print(f"  face-grooming segments mistaken for scratching: {match(fg, ev(sw, 'scratch'))[0]}/{len(fg)}")
notes(sw)
try:
    _, swm = load('itch_model') if False else (None, json.load(open(f'{d}/itch_model_swift.json')))
    print(f"  (model path ran: bouts {swm['metrics']['scratch_bouts_n']:.0f}; note: {swm['notes'][0][:110]})")
except FileNotFoundError:
    pass
_, swe = (None, json.load(open(f'{d}/itch_edit_swift.json')))
print(f"  after ignoring the first bout: bouts {swe['metrics']['scratch_bouts_n']:.0f}, edited {swe['metrics']['edited_n']:.0f}")

print('== ITCH, cheek model (scratch = itch, unilateral forepaw wipe = pain)')
truth, sw = load('cheek')
m = sw['metrics']
for kind in ['scratch', 'wipe']:
    tr = [(t['start'], t['end']) for t in truth['truth'] if t['kind'] == kind]
    show(kind + ' bouts', match(tr, ev(sw, kind)))
fg = [(t['start'], t['end']) for t in truth['truth'] if t['kind'] == 'groom_face']
print(f"  face grooming counted as wipe: {match(fg, ev(sw, 'wipe'))[0]}/{len(fg)}; as scratch: {match(fg, ev(sw, 'scratch'))[0]}/{len(fg)}")
wt = [t for t in truth['truth'] if t['kind'] == 'wipe']
print(f"  wipe L/R {m['wipe_left_n']:.0f}/{m['wipe_right_n']:.0f} (truth {sum(t['side'] == 'L' for t in wt)}/{sum(t['side'] == 'R' for t in wt)}); "
      f"wipe time {m['wipe_time_s']:.1f} s (truth {sum(t['end'] - t['start'] for t in wt):.1f}); trains {m['trains_n']:.0f}")

print('== PAIN (formalin-like, compressed phases I 0–120 s, II 180–480 s)')
truth, sw = load('pain')
lick = [(t['start'], t['end']) for t in truth['truth'] if t['kind'] == 'lick' and t['paw'] == 'R_hind_paw']
lickc = [(t['start'], t['end']) for t in truth['truth'] if t['kind'] == 'lick' and t['paw'] == 'L_hind_paw']
fl = [(t['start'], t['end']) for t in truth['truth'] if t['kind'] == 'flinch']
show('licking injected paw', match(lick, ev(sw, 'lick')))
show('licking other paw', match(lickc, ev(sw, 'lick_contra')))
show('flinches', match(fl, ev(sw, 'flinch')))
m = sw['metrics']
def secs(iv, a, b): return sum(overlap(x, (a, b)) for x in iv)
print(f"  licking phase I {m['lick_phase1_s']:.1f} s (truth {secs(lick, 0, 120):.1f}); phase II {m['lick_phase2_s']:.1f} s (truth {secs(lick, 180, 480):.1f})")
print(f"  flinches {m['flinch_n']:.0f} (truth {len(fl)}); phase I {m['flinch_phase1_n']:.0f} (truth {sum(1 for a, _ in fl if a < 120)}); "
      f"phase II {m['flinch_phase2_n']:.0f} (truth {sum(1 for a, _ in fl if 180 <= a < 480)})")
print(f"  contra licking {m['lick_contra_s']:.1f} s (truth {sum(b - a for a, b in lickc):.1f}); bins lick_s {[round(v, 1) for v in sw['bins']['lick_s']]}")
notes(sw)

print('== GROOMING')
truth, sw = load('groom')
m = sw['metrics']
for reg, key in [('groom_face', 'face'), ('groom_body', 'body'), ('groom_leg', 'leg'), ('groom_tail', 'tail')]:
    iv = [(t['start'], t['end']) for t in truth['truth'] if t['kind'] == reg]
    det = [tuple(x) for x in sw['tracks'][key]]
    tot = sum(b - a for a, b in iv)
    agree = sum(overlap(x, y) for x in iv for y in det)
    print(f"  {key:5s}: detected {m[key + '_s']:.1f} s, truth {tot:.1f} s, correctly placed {agree:.1f} s")
allg = [(t['start'], t['end']) for t in truth['truth'] if t['kind'].startswith('groom')]
print(f"  total {m['groom_time_s']:.1f} s (truth {sum(b - a for a, b in allg):.1f}); bouts {m['groom_bouts_n']:.0f} (truth 6); "
      f"interrupted {m['interrupted_pct']:.0f}% (truth 1/6 = 17%); incorrect transitions {m['incorrect_transitions_pct']:.0f}% (truth 0%)")
for e in sw['events']: print('   bout', e['onset'], e['offset'], e['info'])
notes(sw)

print('== SEIZURE (injection at 60 s)')
truth, sw = load('seizure')
m = sw['metrics']
want = {'arrest': 'arrest', 'jerk': 'jerk', 'clonic': 'clonic', 'tonic_clonic': 'tonic_clonic', 'running': 'running', 'tonic': 'tonic'}
for k, lab in want.items():
    tv = [(t['start'], t['end']) for t in truth['truth'] if t['kind'] == k]
    show(k, match(tv, ev(sw, lab)))
first = lambda k: min(t['start'] for t in truth['truth'] if t['kind'] == k) - 60
print(f"  max stage {m['max_stage']:.0f} (truth 7); latency jerk {m['latency_jerk_s']} (truth {first('jerk'):.1f}); "
      f"latency generalized {m['latency_generalized_s']} (truth {first('clonic'):.1f}); latency tonic {m['latency_tonic_s']} (truth {first('tonic'):.1f})")
print(f"  baseline detections (before injection): {m['baseline_events_n']}; jerks {m['jerks_n']:.0f} (truth 5)")
for e in sw['events']: print('   ', e['label'], e['onset'], e['offset'], e['counted'], e['info'])
notes(sw)

print('== SEIZURE, modified Racine scale for kainate')
truth, sw = load('seizure')
_, ka = json.load(open(f'{d}/seizure_truth.json')), json.load(open(f'{d}/seizure_ka_swift.json'))
mk = ka['metrics']
print(f"  max stage {mk['max_stage']:.0f} (expected 5); latency generalized {mk['latency_generalized_s']} (expected first clonic); death flag {mk['death_suspected']:.0f}")
print('  stages:', sorted({(e['label'], ) for e in ka['events']}))

print('== NEGATIVE CONTROL (exploration, rest, face/body grooming; 300 s)')
t = json.load(open(f'{d}/control_truth.json'))['truth']
g = sum(x['end'] - x['start'] for x in t if x['kind'].startswith('groom'))
def evs(n): return [e for e in json.load(open(f'{d}/control_{n}_swift.json'))['events'] if e['counted'] == '1']
from collections import Counter
for n in ['itch', 'cheek', 'pain', 'seizure']:
    c = Counter(e['label'] for e in evs(n))
    print(f'  {n:8s} false detections: {dict(c) or 0}')
gm = json.load(open(f'{d}/control_groom_swift.json'))['metrics']
print(f"  grooming {gm['groom_time_s']:.1f} s (truth {g:.1f})")

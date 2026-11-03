import json, subprocess, os, sys, itertools
from collections import Counter
import numpy as np
sys.path.insert(0, '.')
env = dict(os.environ)
def ov(a, b): return max(0.0, min(a[1], b[1]) - max(a[0], b[0]))
def match(tr, det, frac=0.3):
    ht = sum(any(ov(t, x) >= frac * max(t[1] - t[0], 1e-9) or (x[0] - 0.15 <= t[0] <= x[1] + 0.15) for x in det) for t in tr)
    hd = sum(any(ov(t, x) > 0 or (x[0] - 0.15 <= t[0] <= x[1] + 0.15) for t in tr) for x in det)
    return ht, len(tr), hd, len(det)
rows = []
for seed, noise, fps in itertools.product(range(1, 6), [0.008, 0.015], [30.0, 60.0]):
    d = f'sweep/s{seed}_n{noise}_f{int(fps)}'; os.makedirs(d, exist_ok=True)
    subprocess.run(['python3', 'behavior_sim.py', d, str(seed), str(noise), str(fps)], check=True, capture_output=True)
    subprocess.run(['./run', d], check=True, capture_output=True, env=env)
    def L(n): return json.load(open(f'{d}/{n}_truth.json'))['truth'], json.load(open(f'{d}/{n}_swift.json'))
    def ev(sw, lab): return [(float(e['onset']), float(e['offset'])) for e in sw['events'] if e['label'] == lab and e['counted'] == '1']
    r = dict(seed=seed, noise=noise, fps=fps)
    t, sw = L('itch'); r['scratch'] = match([(x['start'], x['end']) for x in t if x['kind'] == 'scratch'], ev(sw, 'scratch'))
    t, sw = L('cheek')
    r['cheek_scratch'] = match([(x['start'], x['end']) for x in t if x['kind'] == 'scratch'], ev(sw, 'scratch'))
    r['wipe'] = match([(x['start'], x['end']) for x in t if x['kind'] == 'wipe'], ev(sw, 'wipe'))
    t, sw = L('pain')
    r['lick'] = match([(x['start'], x['end']) for x in t if x['kind'] == 'lick' and x['paw'] == 'R_hind_paw'], ev(sw, 'lick'))
    r['flinch'] = match([(x['start'], x['end']) for x in t if x['kind'] == 'flinch'], ev(sw, 'flinch'))
    t, sw = L('groom'); m = sw['metrics']
    tot = sum(x['end'] - x['start'] for x in t if x['kind'].startswith('groom'))
    r['groom_time_err_pct'] = round((m['groom_time_s'] - tot) / tot * 100, 1)
    r['groom_bouts'] = (m['groom_bouts_n'], 6)
    t, sw = L('seizure'); m = sw['metrics']
    r['jerk'] = match([(x['start'], x['end']) for x in t if x['kind'] == 'jerk'], ev(sw, 'jerk'))
    r['sz_stage'] = m['max_stage']; r['sz_baseline_fp'] = m['baseline_events_n']
    for k in ['clonic', 'tonic_clonic', 'running', 'tonic']:
        r[k] = match([(x['start'], x['end']) for x in t if x['kind'] == k], ev(sw, k))[0]
    from collections import Counter
    fp = Counter()
    for nm in ['itch', 'cheek', 'pain', 'seizure']:
        for e in json.load(open(f'{d}/control_{nm}_swift.json'))['events']:
            if e['counted'] == '1': fp[nm + ':' + e['label']] += 1
    r['control_fp'] = dict(fp)
    t, sw = L('seizure')
    r['arrest'] = match([(x['start'], x['end']) for x in t if x['kind'] == 'arrest'][:1], ev(sw, 'arrest'))
    rows.append(r)
def agg(key):
    a = np.array([r[key] for r in rows]); return f'recall {a[:,0].sum()}/{a[:,1].sum()}  precision {a[:,2].sum()}/{a[:,3].sum()}'
print(f'{len(rows)} simulated runs (5 seeds × noise 0.8%/1.5% BL × 30/60 fps)')
for k in ['scratch', 'cheek_scratch', 'wipe', 'lick', 'flinch', 'jerk']: print(f'  {k:8s}', agg(k))
for nz in [0.008, 0.015]:
    for fps in [30.0, 60.0]:
        sub = [r for r in rows if r['noise'] == nz and r['fps'] == fps]
        w = np.array([r['wipe'] for r in sub]); g = [r['groom_time_err_pct'] for r in sub]
        print(f'  noise {nz} fps {fps:.0f}: wipe {w[:,0].sum()}/{w[:,1].sum()} prec {w[:,2].sum()}/{w[:,3].sum()} | grooming time err {g}')
        f = np.array([r['flinch'] for r in sub]); s = np.array([r['scratch'] for r in sub]); j = np.array([r['jerk'] for r in sub])
        print(f'  noise {nz} fps {fps:.0f}: scratch {s[:,0].sum()}/{s[:,1].sum()} prec {s[:,2].sum()}/{s[:,3].sum()} | flinch {f[:,0].sum()}/{f[:,1].sum()} prec {f[:,2].sum()}/{f[:,3].sum()} | jerk {j[:,0].sum()}/{j[:,1].sum()} prec {j[:,2].sum()}/{j[:,3].sum()}')
print('  grooming time error %:', [r['groom_time_err_pct'] for r in rows])
print('  grooming bouts:', [int(r['groom_bouts'][0]) for r in rows])
print('  seizure max stage:', [int(r['sz_stage']) for r in rows], ' baseline FPs:', [r['sz_baseline_fp'] for r in rows])
print('  clonic/tonic-clonic/running/tonic found:', [ (r['clonic'], r['tonic_clonic'], r['running'], r['tonic']) for r in rows])
print('  first (pre-ictal) arrest found:', sum(r['arrest'][0] for r in rows), '/', len(rows), '; arrest detections', sum(r['arrest'][3] for r in rows))
tot = Counter()
for r in rows: tot.update(r['control_fp'])
print('  negative-control false detections over', len(rows), 'runs × 300 s:', dict(tot))

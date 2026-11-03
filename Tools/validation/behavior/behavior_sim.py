"""Keypoint-level simulator of bottom-view mouse behavior with ground truth, for validating the
RodentLimb behavior analyzers. Writes app-format pose CSVs (frame,time_s,box_confidence,<kp>_x,_y,_confidence)
and a truth JSON per scenario. Not a substitute for real data: it checks that the detection logic, bout
bookkeeping, windows, bins and stage mapping do what they claim on clean, known behavior.

Body model: ego coordinates in body lengths (BL), x from the tail base toward the nose, y lateral.
"""
import json, math, sys
import numpy as np

KP = ['L_fore_paw', 'L_hind_paw', 'R_fore_paw', 'R_hind_paw', 'tail_base', 'nose', 'mouth']
LF, LH, RF, RH, TB, NO, MO = range(7)
TEMPLATE = np.array([[0.62, 0.16], [0.18, 0.20], [0.62, -0.16], [0.18, -0.20], [0.0, 0.0], [1.0, 0.0], [0.90, 0.0]])


CFG = dict(seed=0, noise=None, fps=None)      # command-line overrides for robustness sweeps


class Sim:
    def __init__(self, fps=30.0, bl_px=80.0, W=640, H=480, seed=0, noise=0.008):
        fps = CFG['fps'] or fps
        self.fps, self.bl, self.W, self.H = fps, bl_px, W, H
        self.rng = np.random.default_rng(seed + 100 * CFG['seed'])
        self.noise = CFG['noise'] or noise
        self.pos = np.array([W / 2, H / 2])     # tail base, px
        self.th = 0.3
        self.frames = []                          # (ego (7,2) BL, conf (7,), tail px, heading)
        self.truth = []

    @property
    def t(self):
        return len(self.frames) / self.fps

    def _emit(self, ego, conf=None, pos=None, th=None):
        c = np.full(7, 0.9) if conf is None else conf
        self.frames.append((ego.copy(), c.copy(), (self.pos if pos is None else pos).copy(), self.th if th is None else th))

    def _mark(self, kind, t0, **kw):
        self.truth.append(dict(kind=kind, start=t0, end=self.t, **kw))

    def _keep_in(self):
        m = 1.5 * self.bl
        if not (m < self.pos[0] < self.W - m and m < self.pos[1] < self.H - m):
            self.th += math.pi * 0.9
            self.pos = np.clip(self.pos, m, [self.W - m, self.H - m])

    # ── behaviors ──
    def rest(self, sec):
        for _ in range(int(sec * self.fps)):
            ego = TEMPLATE.copy()
            ego[NO, 1] += 0.01 * math.sin(2 * math.pi * 0.3 * self.t)       # slow sniffing drift
            self._emit(ego)

    def walk(self, sec, speed=3.0, turn=0.0):
        t0 = self.t
        for i in range(int(sec * self.fps)):
            self.th += turn / self.fps + self.rng.normal(0, 0.01)
            self.pos = self.pos + np.array([math.cos(self.th), math.sin(self.th)]) * speed * self.bl / self.fps
            self._keep_in()
            ph = 2 * math.pi * 4.0 * self.t
            ego = TEMPLATE.copy()
            ego[[LF, RH], 0] += 0.08 * math.sin(ph)
            ego[[RF, LH], 0] += 0.08 * math.sin(ph + math.pi)
            self._emit(ego)
        self._mark('walk', t0)

    def scratch(self, sec, side='L', hz=20.0, amp=0.06):
        t0 = self.t
        k = LH if side == 'L' else RH
        s = 1 if side == 'L' else -1
        for _ in range(int(sec * self.fps)):
            ph = 2 * math.pi * hz * self.t
            ego = TEMPLATE.copy()
            ego[k] = [0.74 + amp * math.sin(ph), s * (0.30 + amp * math.cos(ph))]
            ego[NO, 0] = 0.92; ego[MO, 0] = 0.83
            conf = np.full(7, 0.9); conf[k] = self.rng.uniform(0.45, 0.85)
            self._emit(ego, conf)
        self._mark('scratch', t0, side=side)

    def lick_paw(self, sec, k):
        t0 = self.t
        for _ in range(int(sec * self.fps)):
            ego = TEMPLATE.copy()
            side = 1 if k in (LF, LH) else -1
            paw = np.array([0.55, side * 0.12]) if k in (LH, RH) else np.array([0.80, side * 0.06])
            ego[k] = paw + self.rng.normal(0, 0.01, 2)
            ego[MO] = paw + [0.04, 0.0] + self.rng.normal(0, 0.01, 2)
            ego[NO] = paw + [0.12, 0.0]
            ego[k] += 0.015 * math.sin(2 * math.pi * 7 * self.t)
            self._emit(ego)
        self._mark('lick', t0, paw=KP[k])

    def flinch(self, k, dur=0.10, amp=0.3):
        """One flinch: the paw jerks `amp` BL out and back within `dur` s (same physical speed at any fps)."""
        t0 = self.t
        side = 1 if k in (LF, LH) else -1
        m = max(1, int(round(dur * self.fps)))
        for j in range(m):
            d = amp * math.sin(math.pi * (j + 1) / (m + 1))
            ego = TEMPLATE.copy()
            ego[k] = ego[k] + [-0.1 * d / 0.3, side * d]
            self._emit(ego)
        self._mark('flinch', t0, paw=KP[k])

    def face_groom(self, sec):
        t0 = self.t
        for _ in range(int(sec * self.fps)):
            ph = 2 * math.pi * 6.0 * self.t
            ego = TEMPLATE.copy()
            ego[NO, 0] = 0.95; ego[MO, 0] = 0.86
            ego[LF] = [0.84 + 0.06 * math.sin(ph), 0.05]
            ego[RF] = [0.84 + 0.06 * math.sin(ph), -0.05]
            ego[NO, 1] += 0.02 * math.sin(ph)
            self._emit(ego)
        self._mark('groom_face', t0)

    def wipe(self, sec, side='L', hz=5.0):
        """Unilateral forepaw wipe of the cheek (cheek model, pain-like): one forepaw strokes the
        ipsilateral cheek, the other stays on the floor."""
        t0 = self.t
        k = LF if side == 'L' else RF
        s = 1 if side == 'L' else -1
        for _ in range(int(sec * self.fps)):
            ph = 2 * math.pi * hz * self.t
            ego = TEMPLATE.copy()
            ego[NO, 0] = 0.95; ego[MO, 0] = 0.86
            ego[k] = [0.84 + 0.07 * math.sin(ph), s * (0.09 + 0.03 * math.cos(ph))]
            ego[NO, 1] -= s * 0.02
            self._emit(ego)
        self._mark('wipe', t0, side=side)

    def body_groom(self, sec, side='L'):
        t0 = self.t
        s = 1 if side == 'L' else -1
        for _ in range(int(sec * self.fps)):
            ph = 2 * math.pi * 5.0 * self.t
            ego = TEMPLATE.copy()
            sh = (TEMPLATE[LF] + TEMPLATE[RF]) / 2
            ang = s * math.radians(80)
            head = np.array([math.cos(ang), math.sin(ang)]) * 0.36
            ego[NO] = sh + head + [0.02 * math.sin(ph), 0.02 * math.cos(ph)]
            ego[MO] = sh + head * 0.75
            self._emit(ego)
        self._mark('groom_body', t0)

    def leg_groom(self, sec, k=LH):
        t0 = self.t
        self.lick_paw(sec, k)
        self.truth.pop()
        self._mark('groom_leg', t0)

    def tail_groom(self, sec):
        t0 = self.t
        for _ in range(int(sec * self.fps)):
            ego = TEMPLATE.copy()
            ego[NO] = [0.18 + 0.02 * math.sin(2 * math.pi * 4 * self.t), 0.22]
            ego[MO] = [0.14, 0.18]
            ego[LF] = [0.45, 0.25]; ego[RF] = [0.50, 0.05]
            self._emit(ego)
        self._mark('groom_tail', t0)

    def jerk(self):
        t0 = self.t
        for d in [0.10, 0.25, 0.12]:
            ego = TEMPLATE.copy()
            ego[:, 0] += d * 0.3
            ego[:, 1] *= 1 + d
            ego[[LF, RF, NO, MO], 0] += d * 0.4
            pos = self.pos + np.array([-math.sin(self.th), math.cos(self.th)]) * d * self.bl
            self._emit(ego, pos=pos)
        self._mark('jerk', t0)

    def clonic(self, sec, hz=5.0, amp=0.09, side_lying=False):
        t0 = self.t
        for _ in range(int(sec * self.fps)):
            ph = 2 * math.pi * hz * self.t
            ego = TEMPLATE.copy()
            if side_lying:
                ego[[LF, RF], 1] = [0.30, 0.18]
                ego[[LH, RH], 1] = [0.28, 0.16]
            for k, phase in [(LF, 0), (RF, 0.4), (LH, 1.1), (RH, 1.5), (NO, 0.2), (MO, 0.2)]:
                ego[k, 0] += amp * math.sin(ph + phase)
                ego[k, 1] += amp * 0.6 * math.cos(ph + phase)
            self._emit(ego)
        self._mark('tonic_clonic' if side_lying else 'clonic', t0)

    def running(self, sec, speed=11.0):
        t0 = self.t
        self.walk(sec, speed=speed, turn=1.5)
        self.truth.pop()
        self._mark('running', t0)

    def tonic(self, sec):
        t0 = self.t
        for _ in range(int(sec * self.fps)):
            ego = TEMPLATE.copy()
            ego[LH] = [-0.22, 0.14]; ego[RH] = [-0.22, -0.14]
            ego[LF] = [0.92, 0.18]; ego[RF] = [0.92, -0.18]
            self._emit(ego)
        self._mark('tonic', t0)

    def arrest(self, sec):
        t0 = self.t
        for _ in range(int(sec * self.fps)):
            self._emit(TEMPLATE.copy())
        self._mark('arrest', t0)

    # ── output ──
    def write(self, stem):
        n = len(self.frames)
        rows = ['frame,time_s,box_confidence,' + ','.join(f'{k}_x,{k}_y,{k}_confidence' for k in KP)]
        for i, (ego, conf, pos, th) in enumerate(self.frames):
            u = np.array([math.cos(th), math.sin(th)]); nv = np.array([-u[1], u[0]])
            pts = pos + self.bl * (ego[:, :1] * u + ego[:, 1:] * nv)
            pts = pts + self.rng.normal(0, self.noise * self.bl, pts.shape)
            c = np.clip(conf + self.rng.normal(0, 0.03, 7), 0, 1)
            drop = self.rng.random(7) < 0.03
            c[drop] = self.rng.uniform(0.0, 0.25, drop.sum())
            f = [str(i), f'{i / self.fps:.6f}', '0.9']
            for k in range(7):
                f += [f'{pts[k, 0]:.4f}', f'{pts[k, 1]:.4f}', f'{c[k]:.4f}']
            rows.append(','.join(f))
        open(stem + '_pose.csv', 'w').write('\n'.join(rows) + '\n')
        json.dump(dict(fps=self.fps, duration=n / self.fps, bl_px=self.bl, truth=self.truth), open(stem + '_truth.json', 'w'), indent=1)


def scenario_itch(out, fps=60.0, seed=1):
    s = Sim(fps=fps, seed=seed)
    s.rest(5); s.walk(4)
    for i in range(12):
        s.scratch(s.rng.uniform(1.0, 4.0), side='L' if i % 3 else 'R')
        s.rest(s.rng.uniform(3, 8))
        if i % 4 == 0: s.walk(3)
        if i % 5 == 0: s.face_groom(3); s.rest(2)
    s.write(out)


def scenario_cheek(out, fps=60.0, seed=5):
    """Cheek model (Shimada & LaMotte 2008): hind-paw scratching of the cheek = itch, unilateral
    forepaw wiping = pain; bilateral face grooming must count as neither."""
    s = Sim(fps=fps, seed=seed)
    s.rest(5); s.walk(4)
    for i in range(8):
        s.scratch(s.rng.uniform(1.0, 3.0), side='L' if i % 2 else 'R'); s.rest(s.rng.uniform(3, 6))
        s.wipe(s.rng.uniform(1.0, 2.5), side='R' if i % 2 else 'L'); s.rest(s.rng.uniform(3, 6))
        if i % 3 == 0: s.face_groom(3); s.rest(3)
        if i % 2 == 0: s.walk(3); s.rest(2)
    s.write(out)


def scenario_control(out, fps=30.0, seed=6):
    """Negative control: exploration, resting and ordinary face/body grooming only. Itch, pain and
    seizure analyzers should find (almost) nothing here."""
    s = Sim(fps=fps, seed=seed)
    while s.t < 300:
        s.walk(s.rng.uniform(2, 6), speed=s.rng.uniform(1.5, 4.5), turn=s.rng.uniform(-1.5, 1.5)); s.rest(s.rng.uniform(1, 6))
        r = s.rng.random()
        if r < 0.25: s.face_groom(s.rng.uniform(2, 5)); s.rest(1)
        elif r < 0.35: s.body_groom(s.rng.uniform(2, 4), 'L' if s.rng.random() < 0.5 else 'R'); s.rest(1)
    s.write(out)


def scenario_pain(out, fps=60.0, seed=2):
    s = Sim(fps=fps, seed=seed)
    # phase I (0-600 s compressed: we use phase1End=120, phase2Start=180, phase2End=480 in the test)
    for i in range(6):
        s.lick_paw(s.rng.uniform(3, 8), RH); s.rest(2)
        s.flinch(RH); s.rest(1.5); s.flinch(RH); s.rest(3)
        s.walk(2); s.rest(3)
    s.rest(60)                                    # interphase
    s.walk(5)
    while s.t < 180: s.rest(2); s.walk(2)
    for i in range(10):
        s.lick_paw(s.rng.uniform(4, 10), RH); s.rest(3)
        s.flinch(RH); s.rest(4)
        if i % 3 == 0: s.lick_paw(3, LH); s.rest(3)       # contralateral licking (control)
        s.walk(3); s.rest(5)
    while s.t < 480: s.rest(3); s.walk(2)
    s.write(out)


def scenario_groom(out, fps=30.0, seed=3):
    s = Sim(fps=fps, seed=seed)
    s.walk(10); s.rest(5)
    for i in range(5):
        s.face_groom(s.rng.uniform(3, 6)); s.body_groom(s.rng.uniform(2, 4), 'L' if i % 2 else 'R')
        s.leg_groom(s.rng.uniform(2, 3), LH if i % 2 else RH); s.tail_groom(s.rng.uniform(1.5, 3))
        s.rest(s.rng.uniform(8, 12)); s.walk(4); s.rest(5)
    # one interrupted bout: face, 2-s pause, face again
    s.face_groom(4); s.rest(2); s.face_groom(3); s.rest(10)
    s.write(out)


def scenario_seizure(out, fps=30.0, seed=4, injection=60.0):
    s = Sim(fps=fps, seed=seed)
    while s.t < injection:                        # baseline exploration
        s.walk(s.rng.uniform(2, 5), turn=s.rng.uniform(-1, 1)); s.rest(s.rng.uniform(2, 5))
    s.walk(3); s.arrest(8)                        # stage 1 after injection
    s.walk(3); s.rest(4)
    for _ in range(5):                            # myoclonic jerks
        s.jerk(); s.rest(s.rng.uniform(3, 6))
    s.clonic(6); s.rest(10)                       # stage 4
    s.clonic(5, side_lying=True); s.rest(4)       # stage 6
    s.running(1.2); s.rest(6)                     # stage 6
    s.tonic(6)                                    # stage 7
    s.arrest(70)                                  # no movement afterwards
    s.write(out)


if __name__ == '__main__':
    d = sys.argv[1]
    CFG['seed'] = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    CFG['noise'] = float(sys.argv[3]) if len(sys.argv) > 3 else None
    CFG['fps'] = float(sys.argv[4]) if len(sys.argv) > 4 else None
    scenario_itch(d + '/itch')
    scenario_cheek(d + '/cheek')
    scenario_control(d + '/control')
    scenario_pain(d + '/pain')
    scenario_groom(d + '/groom')
    scenario_seizure(d + '/seizure')
    print('ok')

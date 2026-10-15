# Python mirror of the upgraded Swift GaitAnalyzer (v2): turning filter, run-end trimming,
# reference-speed values, CV, step length, gait pattern, nose/tail lateral displacement.
import math, numpy as np
from port import *

def gait2(s, ratio=0.8, floor=0.8, minphase=0.03, minbody=1.0, maxstride=1.0, maxturn=30.0, trim=True, refspeed=2.0):
    n=s.n; bl=s.bl
    cx=[NAN]*n; cy=[NAN]*n
    for i in range(n):
        a=s.p(NOSE,i); b=s.p(TAIL,i)
        if a and b: cx[i]=(a[0]+b[0])/2; cy[i]=(a[1]+b[1])/2
    sw=s.samples(0.15); cx=smooth(cx,sw); cy=smooth(cy,sw)
    vx=deriv(cx,s.t); vy=deriv(cy,s.t); body=[math.hypot(a,b) for a,b in zip(vx,vy)]
    # heading angle (unwrapped) and angular velocity
    ang=[NAN]*n
    for i in range(n):
        if isf(body[i]) and body[i]>0.2*bl: ang[i]=math.atan2(vy[i],vx[i])
        else:
            a=s.p(NOSE,i); b=s.p(TAIL,i)
            if a and b: ang[i]=math.atan2(a[1]-b[1],a[0]-b[0])
    unw=list(ang); prev=None
    for i in range(n):
        if not isf(unw[i]): continue
        if prev is not None:
            d=unw[i]-unw[prev]
            while d>math.pi: unw[i]-=2*math.pi; d-=2*math.pi
            while d<-math.pi: unw[i]+=2*math.pi; d+=2*math.pi
        prev=i
    angv=[abs(x)*180/math.pi if isf(x) else NAN for x in deriv(smooth(unw,s.samples(0.2)),s.t)]
    stances={}; mp=s.samples(minphase)
    for paw in PAWS:
        sp=s.step_speed(paw); st=[-1]*n
        for i in range(n):
            if isf(sp[i]):
                th=max(floor*bl,ratio*(body[i] if isf(body[i]) else 0)); st[i]=1 if sp[i]<th else 0
        changed=True;g=0
        while changed and g<4:
            changed=False;g+=1;i=0
            while i<n:
                j=i
                while j<n and st[j]==st[i]: j+=1
                if st[i]>=0 and i>0 and j<n and j-i<mp and st[i-1]==st[j] and st[j]>=0:
                    for k in range(i,j): st[k]=st[j]
                    changed=True
                i=j
        lst=[];i=0
        while i<n:
            j=i
            while j<n and st[j]==st[i]: j+=1
            if st[i]==1 and i>0 and j<n and st[i-1]==0 and st[j]==0:
                pts=[s.p(paw,q) for q in range(i,j) if s.p(paw,q)]
                lst.append(dict(r=(i,j),iv=s.interval((i,j)),pr=(sum(p[0] for p in pts)/len(pts),sum(p[1] for p in pts)/len(pts))))
            i=j
        stances[paw]=lst
    def mean_over(arr,a,b): return mean([arr[i] for i in s.idx(a,b)])
    strides=[]
    for paw in PAWS:
        l=stances[paw]; cand=[]
        for k in range(len(l)-1):
            a,b=l[k],l[k+1]; dur=b['iv'][0]-a['iv'][0]
            v=mean_over(body,a['iv'][0],b['iv'][0]); w=mean_over(angv,a['iv'][0],b['iv'][0])
            ok = dur>0 and dur<=maxstride and v is not None and v>=minbody*bl and (w is None or w<=maxturn)
            stance=a['iv'][1]-a['iv'][0]; swing=dur-stance
            if swing<=0: ok=False
            cand.append(dict(paw=paw,start=a['iv'][0],end=b['iv'][0],dur=dur,stance=stance,swing=swing,duty=stance/dur if dur>0 else 0,
                             length=math.dist(a['pr'],b['pr']),speed=v,ok=ok,a=a,b=b))
        # trim run ends
        i=0
        while i<len(cand):
            if not cand[i]['ok']: i+=1; continue
            j=i
            while j+1<len(cand) and cand[j+1]['ok'] and abs(cand[j+1]['start']-cand[j]['end'])<1e-9: j+=1
            run=cand[i:j+1]
            if trim and len(run)>=3: run=run[1:-1]
            elif trim: run=[]
            strides+=run; i=j+1
    hind=[x for x in strides if x['paw'] in (LH,RH)]
    # reference-speed values
    def at_ref(key):
        xs=np.array([x['speed']/bl for x in hind]); ys=np.array([x[key] for x in hind])
        if len(xs)<8 or xs.std()<0.1: return None
        if not (xs.min()*0.75<=refspeed<=xs.max()*1.25): return None
        b,a=np.polyfit(xs,ys,1); return a+b*refspeed
    # CV
    def cv(key):
        v=[x[key] for x in hind]; return np.std(v,ddof=1)/np.mean(v)*100 if len(v)>2 else None
    # step length LH->RH along heading
    steps=[]
    for a in stances[LH]:
        nxt=[b for b in stances[RH] if b['iv'][0]>a['iv'][0] and b['iv'][0]-a['iv'][0]<maxstride]
        if not nxt: continue
        b=nxt[0]; mid=(a['r'][0]+a['r'][1])//2
        if not isf(ang[mid]): continue
        h=(math.cos(ang[mid]),math.sin(ang[mid])); d=(b['pr'][0]-a['pr'][0],b['pr'][1]-a['pr'][1])
        steps.append(abs(h[0]*d[0]+h[1]*d[1]))
    # phases per LH stride & pattern
    def phase_in(st,tgt):
        t=next((x['iv'][0] for x in stances[tgt] if st['start']<=x['iv'][0]<st['end']),None)
        return None if t is None else (t-st['start'])/st['dur']
    pats={'walk':0,'trot':0,'gallop':0,'bound':0}
    for st in [x for x in strides if x['paw']==LH]:
        ph=phase_in(st,RH); dg=phase_in(st,RF)
        if ph is None: continue
        if abs(ph-0.5)<=0.15:
            if dg is not None and min(dg,1-dg)<=0.15: pats['trot']+=1
            else: pats['walk']+=1
        elif min(ph,1-ph)<=0.15: pats['bound']+=1
        else: pats['gallop']+=1
    # lateral displacement of nose & tail base per LH stride
    def lat(k):
        amps=[];phs=[]
        for st in [x for x in strides if x['paw']==LH]:
            r=s.idx(st['start'],st['end'])
            if len(r)<4: continue
            p0=(cx[r[0]],cy[r[0]]); p1=(cx[r[-1]],cy[r[-1]])
            if not all(map(isf,p0+p1)): continue
            d=(p1[0]-p0[0],p1[1]-p0[1]); L=math.hypot(*d)
            if L<1e-6: continue
            u=(d[0]/L,d[1]/L); offs=[]
            for i in r:
                p=s.p(k,i)
                if p: offs.append((u[0]*(p[1]-p0[1])-u[1]*(p[0]-p0[0]), (i-r[0])/len(r)))
            if len(offs)<len(r)*0.7: continue
            v=[o[0] for o in offs]; amps.append((max(v)-min(v))/bl); phs.append(offs[int(np.argmax(v))][1])
        return (np.mean(amps) if amps else None), circular(phs)
    return dict(strides=strides,hind=hind,ref={k:at_ref(k) for k in ('length','dur','duty','stance','swing')},
                cv_len=cv('length'),cv_dur=cv('dur'),step=mean(steps),pats=pats,nose=lat(NOSE),tail=lat(TAIL),bl=bl)

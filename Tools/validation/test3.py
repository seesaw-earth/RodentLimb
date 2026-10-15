import math, numpy as np, sys
sys.path.insert(0,'.')
from port import *; from gait2 import gait2
rng=np.random.default_rng(3)
def make(fps=100,T=8.0,segments=((0,8,200.0,4.0,0.6),),noise=1.0,wobble=6.0,turn=0.0):
    n=int(T*fps); t=[i/fps for i in range(n)]
    X=[[0.0]*n for _ in range(7)];Y=[[0.0]*n for _ in range(7)];C=[[0.9]*n for _ in range(7)]
    phase={LF:0.0,RH:0.0,RF:0.5,LH:0.5}; lat={LF:-12,RF:12,LH:-15,RH:15}; ax={LF:30,RF:30,LH:-30,RH:-30}
    # integrate a variable-speed body; footprints from body position at mid-stance
    for p in PAWS:
        pass
    x=100.0; xs=[]; cyc=0.0; cycs=[]
    for ti in t:
        seg=[s for s in segments if s[0]<=ti<s[1]][0]; v,f,duty=seg[2],seg[3],seg[4]
        xs.append(x); cycs.append(cyc); x+=v/fps; cyc+=f/fps
    for i,ti in enumerate(t):
        seg=[s for s in segments if s[0]<=ti<s[1]][0]; duty=seg[4]
        bx=xs[i]; th=turn*ti
        def W(px,py): # rotate about origin (100,300) by th
            dx,dy=px-100,py-300; return 100+dx*math.cos(th)-dy*math.sin(th), 300+dx*math.sin(th)+dy*math.cos(th)
        wob=wobble*math.sin(2*math.pi*cycs[i])
        X[NOSE][i],Y[NOSE][i]=W(bx+45,300+wob); X[TAIL][i],Y[TAIL][i]=W(bx-45,300-wob); X[MOUTH][i],Y[MOUTH][i]=X[NOSE][i],Y[NOSE][i]
        for p in PAWS:
            c=cycs[i]+phase[p]; k=math.floor(c); u=c-k
            # footprint k at body position when cycle == k+duty/2 - phase
            def fp(kk):
                target=kk+duty/2-phase[p]; j=min(range(len(cycs)),key=lambda q: abs(cycs[q]-target)) if 0<=target<=cycs[-1] else None
                return (xs[j] if j is not None else xs[0]+(target)*(xs[1]-xs[0])/(cycs[1]-cycs[0]+1e-9))+ax[p]
            if u<duty: px=fp(k)
            else: px=fp(k)+(u-duty)/(1-duty)*(fp(k+1)-fp(k))
            X[p][i],Y[p][i]=W(px,300+lat[p]); X[p][i]+=rng.normal(0,noise); Y[p][i]+=rng.normal(0,noise)
    return Series(t,X,Y,C,sm=0.03)
# A: steady trot, 20cm/s (10px/cm), BL=90
s=make(); r=gait2(s)
print("A steady  strides",len(r['strides']),"pats",r['pats'],"stepLen %.1f px (truth 25)"%r['step'])
print("   noseAmp %.3f BL (truth %.3f)  tailAmp %.3f"%(r['nose'][0],12/90,r['tail'][0]), "CVlen %.1f%%"%r['cv_len'])
# B: speed varies: 1.5 -> 3 BL/s with stride freq rising; ref values at 2 BL/s
seg=((0,4,135.0,3.0,0.68),(4,8,270.0,4.5,0.55))
s=make(T=8,segments=seg); r=gait2(s)
sp=sorted(set(round(x['speed']/s.bl,2) for x in r['hind']))
print("B mixed   speeds BL/s",sp[0],"-",sp[-1]," ref@2.0:",{k:(round(v,3) if v else v) for k,v in r['ref'].items()})
print("   expected length@2.0 by linear interp ~", round(45+(60-45)*(2.0-1.5)/(3-1.5),1),"px")
# C: turning 40 deg/s -> strides rejected
s=make(turn=math.radians(40)); r=gait2(s); print("C turning 40°/s strides kept:",len(r['strides']))
# D: walk pattern (lateral-sequence walk: LH 0, LF 0.25, RH 0.5, RF 0.75) -> diag phase LH->RF 0.25

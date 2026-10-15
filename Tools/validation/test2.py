import math, numpy as np, sys
sys.path.insert(0,'.')
from port import *
rng=np.random.default_rng(2)
def blank(n): return [[0.0]*n for _ in range(7)],[[0.0]*n for _ in range(7)],[[0.9]*n for _ in range(7)]

# ---------- TST: 6 min @30 fps, hanging head-down. Ground-truth immobile intervals.
fps=30; n=360*fps; t=[i/fps for i in range(n)]
X,Y,C=blank(n)
truth=[]; tt=0.0; mobile=True
while tt<360:
    d=rng.uniform(4,10) if mobile else rng.uniform(2,25)
    if not mobile: truth.append((tt,min(360,tt+d)))
    tt+=d; mobile=not mobile
def imm(ti): return any(a<=ti<b for a,b in truth)
ph=0
for i,ti in enumerate(t):
    still=imm(ti)
    amp=0.4 if still else 18   # breathing vs struggling (px)
    sw=amp*math.sin(2*math.pi*(0.8 if still else 3.0)*ti)
    X[TAIL][i]=500;Y[TAIL][i]=100
    X[NOSE][i]=500+0.3*sw;Y[NOSE][i]=280
    X[MOUTH][i]=500;Y[MOUTH][i]=275
    for k,(dx,dy) in {LF:(-40,240),RF:(40,240),LH:(-60,130),RH:(60,130)}.items():
        X[k][i]=500+dx+sw*(1 if k in (LF,LH) else -1)+rng.normal(0,0.8)
        Y[k][i]=100+dy+0.5*sw+rng.normal(0,0.8)
s=Series(t,X,Y,C)
imm_s,lat,nb,motion=tst(s)
true_imm=sum(max(0,min(b,360)-max(a,120)) for a,b in truth if b-a>=1.0)
print("TST  BL=%.0f px  immobility 120-360 s: %.1f s (truth %.1f)  latency %.1f (truth %.1f)"%(s.bl,imm_s,true_imm,lat,[a for a,b in truth if b-a>=1][0]))
# frame-level agreement
mask_true=[imm(ti) for ti in t]
still_pred=[isf(m) and m<0.25 for m in motion]
agree=np.mean([a==b for a,b in zip(mask_true,still_pred)])
print("     frame agreement %.1f%%"%(agree*100))

# ---------- Cylinder bottom view: circle (500,500) r=400; scripted rears
fps=30; T=60; n=T*fps; t=[i/fps for i in range(n)]
X,Y,C=blank(n)
script=[(3,'left'),(9,'right'),(15,'both'),(21,'left'),(27,'left'),(33,'both'),(39,'right'),(45,'left'),(51,'right')]
cx,cy,r=500,500,400
def paw_pos(ti,side,angle):
    # default: under body near center; during rear: on rim at angle
    for t0,lab in script:
        lead = (lab=='both') or (lab==side)
        on = t0 + (0 if lead else 0.5)          # trailing paw arrives 0.5 s later
        if on<=ti<t0+2.0:
            a=0.3*t0+(0.12 if side=="right" else -0.12)
            return cx+r*0.99*math.cos(a), cy+r*0.99*math.sin(a)
        if t0-0.4<=ti<on:   # reaching movement
            a=0.3*t0+(0.12 if side=="right" else -0.12); f=(ti-(t0-0.4))/(on-(t0-0.4))
            return cx+(0.2+0.79*f)*r*math.cos(a), cy+(0.2+0.79*f)*r*math.sin(a)
    return None
for i,ti in enumerate(t):
    ang=0.3*ti
    hx,hy=cx+0.2*r*math.cos(ang), cy+0.2*r*math.sin(ang)
    X[TAIL][i]=hx-60*math.cos(ang);Y[TAIL][i]=hy-60*math.sin(ang)
    X[NOSE][i]=hx+60*math.cos(ang);Y[NOSE][i]=hy+60*math.sin(ang)
    X[MOUTH][i]=X[NOSE][i];Y[MOUTH][i]=Y[NOSE][i]
    for k,side in ((LF,'left'),(RF,'right')):
        p=paw_pos(ti,side,ang)
        if p is None: p=(hx+20*math.cos(ang)+(-15 if side=='left' else 15)*math.sin(ang), hy+20*math.sin(ang))
        X[k][i]=p[0]+rng.normal(0,1);Y[k][i]=p[1]+rng.normal(0,1)
    for k in (LH,RH): X[k][i]=hx;Y[k][i]=hy
s=Series(t,X,Y,C)
ev,rears=cylinder(s,(cx,cy,r))
print("CYL  detected:",ev)
print("     truth:   ",[l for _,l in script])

import math, numpy as np, sys
sys.path.insert(0,'.')
from port import *
rng=np.random.default_rng(1)

def blank(n): return [[0.0]*n for _ in range(7)],[[0.0]*n for _ in range(7)],[[0.9]*n for _ in range(7)]

# ---------- GAIT: trot, 20 cm/s, 10 px/cm, 4 Hz, duty 0.6, BoS hind 3 cm
fps=100; T=4.0; n=int(T*fps); t=[i/fps for i in range(n)]
X,Y,C=blank(n); v=200.0; f=4.0; P=1/f; duty=0.6; L=v*P
phase={LF:0.0,RH:0.0,RF:0.5,LH:0.5}
lat={LF:-12,RF:12,LH:-15,RH:15}; ax={LF:30,RF:30,LH:-30,RH:-30}
for i,ti in enumerate(t):
    bx=100+v*ti
    X[NOSE][i]=bx+45;Y[NOSE][i]=300;X[TAIL][i]=bx-45;Y[TAIL][i]=300;X[MOUTH][i]=bx+40;Y[MOUTH][i]=300
    for p in PAWS:
        c=(ti/P+phase[p]); k=math.floor(c); u=c-k
        # stance during u in [0,duty): fixed at footprint k; swing moves to footprint k+1
        foot=lambda kk: 100+ax[p]+ (kk - phase[p] + duty/2)*L
        if u<duty: x=foot(k)
        else: x=foot(k)+(u-duty)/(1-duty)*L
        X[p][i]=x+rng.normal(0,0.7); Y[p][i]=300+lat[p]+rng.normal(0,0.7)
s=Series(t,X,Y,C)
strides,ph,bos,st=gait(s)
pxcm=10
def m(key,paws): 
    v=[x[key] for x in strides if x['paw'] in paws]; return sum(v)/len(v) if v else None
print("GAIT  BL=%.1f px  strides=%d"%(s.bl,len(strides)))
print("  stride length hind %.2f cm (truth %.2f)"%(m('length',[LH,RH])/pxcm, L/pxcm))
print("  stride freq %.2f Hz (truth %.2f)"%(1/m('dur',[LH,RH]),f))
print("  duty hind %.2f (truth %.2f)  stance %.3f s (truth %.3f)"%(m('duty',[LH,RH]),duty,m('stance',[LH,RH]),duty*P))
print("  speed %.1f cm/s (truth 20)"%(m('speed',PAWS)/pxcm))
print("  BoS hind %.2f cm (truth 3.0)"%(bos/pxcm))
for k,vv in ph.items(): print("  phase",k,"mean %.2f R %.2f"%vv)

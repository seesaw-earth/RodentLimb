# Line-for-line Python mirror of RodentLimb's Swift analyzers (PoseSeries, TST, Cylinder, Gait).
import math, numpy as np
NAN=float('nan')
LF,LH,RF,RH,TAIL,NOSE,MOUTH=range(7)
PAWS=[LF,RF,LH,RH]
def isf(v): return v==v and math.isfinite(v)
def fill_gaps(v,maxgap):
    out=list(v); n=len(v); i=0
    if maxgap<=0 or n<=2: return out
    while i<n:
        if not isf(out[i]):
            j=i
            while j<n and not isf(out[j]): j+=1
            gap=j-i
            if i>0 and j<n and gap<=maxgap:
                a,b=out[i-1],out[j]
                for k in range(i,j): out[k]=a+(b-a)*(k-i+1)/(gap+1)
            i=j
        else: i+=1
    return out
def median3(v):
    out=list(v)
    for i in range(1,len(v)-1):
        a,b,c=v[i-1],v[i],v[i+1]
        if isf(a) and isf(b) and isf(c): out[i]=max(min(a,b),min(max(a,b),c))
    return out
def smooth(v,window):
    w=max(1,window|1)
    if w<=1 or len(v)<=2: return list(v)
    h=w//2;n=len(v);out=list(v)
    for i in range(n):
        if not isf(v[i]): continue
        seg=[x for x in v[max(0,i-h):min(n,i+h+1)] if isf(x)]
        out[i]=sum(seg)/len(seg)
    return out
def deriv(v,t):
    n=len(v);out=[NAN]*n
    for i in range(n):
        a=max(0,i-1);b=min(n-1,i+1);dt=t[b]-t[a]
        if dt>0 and isf(v[a]) and isf(v[b]): out[i]=(v[b]-v[a])/dt
    return out
def runs(mask):
    out=[];s=None
    for i,m in enumerate(mask):
        if m and s is None: s=i
        if not m and s is not None: out.append((s,i));s=None
    if s is not None: out.append((s,len(mask)))
    return out
def mean(v):
    f=[x for x in v if isf(x)]; return sum(f)/len(f) if f else None
def circular(ph):
    f=[p for p in ph if isf(p)]
    if not f: return None
    s=sum(math.sin(2*math.pi*p) for p in f)/len(f); c=sum(math.cos(2*math.pi*p) for p in f)/len(f)
    m=math.atan2(s,c)/(2*math.pi); m+= 1 if m<0 else 0
    return m,math.hypot(s,c)

class Series:
    def __init__(s,t,X,Y,C,thr=0.3,maxgap=0.25,sm=0.10):
        s.n=len(t);s.t=t
        dt=float(np.median(np.diff(t[:600])));s.dt=dt;s.fps=1/dt
        gap=int(round(maxgap/dt));win=int(round(sm/dt))
        s.x=[];s.y=[];s.vis=[]
        for k in range(7):
            vx=[X[k][i] if C[k][i]>=thr and X[k][i]>=0 else NAN for i in range(s.n)]
            vy=[Y[k][i] if C[k][i]>=thr and Y[k][i]>=0 else NAN for i in range(s.n)]
            s.vis.append(sum(isf(a) for a in vx)/s.n)
            s.x.append(smooth(median3(fill_gaps(vx,gap)),win)); s.y.append(smooth(median3(fill_gaps(vy,gap)),win))
        L=[math.hypot(s.x[NOSE][i]-s.x[TAIL][i],s.y[NOSE][i]-s.y[TAIL][i]) for i in range(s.n) if isf(s.x[NOSE][i]) and isf(s.x[TAIL][i])]
        s.bl=float(np.median(L))
    def p(s,k,i):
        return (s.x[k][i],s.y[k][i]) if isf(s.x[k][i]) and isf(s.y[k][i]) else None
    def speed(s,k):
        vx=deriv(s.x[k],s.t);vy=deriv(s.y[k],s.t); return [math.hypot(a,b) for a,b in zip(vx,vy)]
    def step_speed(s,k):
        out=[NAN]*s.n
        for i in range(s.n):
            c=[]
            for j in (i-1,i+1):
                if 0<=j<s.n and isf(s.x[k][i]) and isf(s.x[k][j]):
                    c.append(math.hypot(s.x[k][j]-s.x[k][i],s.y[k][j]-s.y[k][i])/abs(s.t[j]-s.t[i]))
            if c: out[i]=min(c)
        return out
    def samples(s,sec): return max(1,int(round(sec/s.dt)))
    def interval(s,r): return (s.t[r[0]], s.t[r[1]-1]+s.dt)
    def idx(s,a,b):
        lo=next((i for i,x in enumerate(s.t) if x>=a),s.n); hi=next((i for i,x in enumerate(s.t) if x>=b),s.n); return range(lo,max(lo,hi))

def tst(s,thr=0.25,minbout=1.0,msm=0.25,w0=120,w1=360):
    speeds=[s.speed(k) for k in [LF,RF,LH,RH,NOSE]]
    motion=[NAN]*s.n
    for i in range(s.n):
        vals=[min(sp[i]/s.bl,5) for sp in speeds if isf(sp[i])]
        if len(vals)>=2: motion[i]=sum(vals)/len(vals)
    motion=smooth(motion,s.samples(msm))
    still=[isf(m) and m<thr for m in motion]
    mask=[False]*s.n; bouts=[]
    for r in runs(still):
        iv=s.interval(r)
        if iv[1]-iv[0]>=minbout-1e-9:
            bouts.append(iv)
            for i in range(*r): mask[i]=True
    win=s.idx(w0,w1)
    imm=sum(s.dt for i in win if mask[i])
    return imm, bouts[0][0] if bouts else None, len([b for b in bouts if b[1]>w0 and b[0]<w1]), motion

def cylinder(s,circle,margin=0.15,still=0.8,minc=0.10,simul=0.2,reargap=0.5):
    cx,cy,r=circle
    def mask(k):
        sp=s.speed(k);m=[False]*s.n
        for i in range(s.n):
            pt=s.p(k,i)
            if pt is None or not isf(sp[i]) or sp[i]/s.bl>=still: continue
            if math.hypot(pt[0]-cx,pt[1]-cy)>=r*(1-margin): m[i]=True
        bridge=max(2,s.samples(0.06));i=0
        while i<s.n:
            if not m[i]:
                j=i
                while j<s.n and not m[j]: j+=1
                if i>0 and j<s.n and j-i<=bridge:
                    for q in range(i,j): m[q]=True
                i=j
            else: i+=1
        return m
    def contacts(m): return [(r_,s.interval(r_)) for r_ in runs(m) if s.interval(r_)[1]-s.interval(r_)[0]>=minc-1e-9]
    L=contacts(mask(LF)); R=contacts(mask(RF))
    allc=sorted([c[1] for c in L+R]); rears=[]
    for c in allc:
        if rears and c[0]-rears[-1][1]<reargap: rears[-1]=(rears[-1][0],max(rears[-1][1],c[1]))
        else: rears.append(c)
    on=sorted([(c[1][0],True) for c in L]+[(c[1][0],False) for c in R])
    ev=[]
    for rear in rears:
        inr=[o for o in on if rear[0]-1e-9<=o[0]<=rear[1]+1e-9]
        if not inr: continue
        f=inr[0]; other=[o for o in inr if o[1]!=f[1] and o[0]-f[0]<=simul]
        ev.append('both' if other else ('left' if f[1] else 'right'))
    return ev,rears

def gait(s,ratio=0.5,floor=0.8,minphase=0.03,minbody=1.0,maxstride=1.0):
    n=s.n;bl=s.bl
    cx=[NAN]*n;cy=[NAN]*n
    for i in range(n):
        a=s.p(NOSE,i);b=s.p(TAIL,i)
        if a and b: cx[i]=(a[0]+b[0])/2;cy[i]=(a[1]+b[1])/2
    sw=s.samples(0.15);cx=smooth(cx,sw);cy=smooth(cy,sw)
    vx=deriv(cx,s.t);vy=deriv(cy,s.t);body=[math.hypot(a,b) for a,b in zip(vx,vy)]
    stances={};mp=s.samples(minphase)
    for paw in PAWS:
        sp=s.step_speed(paw);st=[-1]*n
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
                lst.append(((i,j),s.interval((i,j)),(sum(p[0] for p in pts)/len(pts),sum(p[1] for p in pts)/len(pts))))
            i=j
        stances[paw]=lst
    def mbs(a,b): return mean([body[i] for i in s.idx(a,b)])
    strides=[];starts={}
    for paw in PAWS:
        l=stances[paw]
        for k in range(len(l)-1):
            a,b=l[k],l[k+1];dur=b[1][0]-a[1][0];v=mbs(a[1][0],b[1][0])
            if dur<=0 or dur>maxstride or v is None or v<minbody*bl: continue
            stance=a[1][1]-a[1][0];swing=dur-stance
            if swing<=0: continue
            strides.append(dict(paw=paw,dur=dur,stance=stance,swing=swing,duty=stance/dur,length=math.dist(a[2],b[2]),speed=v))
            starts.setdefault(paw,[]).append((a[1][0],b[1][0]))
    def phases(ref,tgt):
        tg=[x[1][0] for x in stances[tgt]];out=[]
        for a,b in starts.get(ref,[]):
            t=next((x for x in tg if a<=x<b),None)
            if t is not None: out.append((t-a)/(b-a))
        return out
    # base of support hind
    bos=[]
    for a in stances[LH]:
        best=None;bs=-1e9
        for b in stances[RH]:
            ov=min(a[1][1],b[1][1])-max(a[1][0],b[1][0]); sc=ov if ov>0 else -abs(b[1][0]-a[1][0])
            if sc>bs and (ov>0 or abs(b[1][0]-a[1][0])<maxstride/2): bs=sc;best=b
        if best:
            mid=(a[0][0]+a[0][1])//2; h=(vx[mid],vy[mid]); L=math.hypot(*h); h=(h[0]/L,h[1]/L)
            d=(best[2][0]-a[2][0],best[2][1]-a[2][1]); bos.append(abs(h[0]*d[1]-h[1]*d[0]))
    return strides,{k:circular(phases(*k)) for k in [(LH,RH),(LF,RF),(LH,LF),(LH,RF)]},mean(bos),stances

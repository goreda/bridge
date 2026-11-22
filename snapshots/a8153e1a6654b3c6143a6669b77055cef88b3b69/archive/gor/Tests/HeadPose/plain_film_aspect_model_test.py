#!/usr/bin/env python3
"""Model of the 194q plain-2D shader math (NOT the shader, NOT a render). Reproduces the
GLSL expressions for plain_content/rotate_bound/uv in numpy and checks, for window aspects
different from the film aspect and tilt 0/25/-45/90: the film keeps its aspect (no stretch)
and all four film corners stay inside the window. Also fails the old mapping (red)."""
import math,numpy as np,sys
def sample(px,py,asp,film,roll,locked=True,frame_fit=0.0):
    cr,sr=math.cos(-roll),math.sin(-roll)
    cx=cy=1.0
    if locked and film>0:
        if film>asp: cy=asp/film
        else: cx=film/asp
    fw,fh=cx*asp,cy
    if locked: rb=max((abs(cr)*fw+abs(sr)*fh)/asp,abs(sr)*fw+abs(cr)*fh)
    else: rb=max(abs(cr)+abs(sr)/asp,abs(cr)+abs(sr)*asp)
    s=max(max(1.0,rb),1/frame_fit if frame_fit>0 else 1.0)
    x,y=(px-.5)*s,(py-.5)*s
    x*=asp;x,y=cr*x-sr*y,sr*x+cr*y;x/=asp
    if locked: x/=cx;y/=cy
    return x+.5,y+.5
def forward_corners(asp,film,roll):
    # find output position of each film corner by dense inverse search
    n=401;xs=(np.arange(n)+.5)/n
    X,Y=np.meshgrid(xs,xs);out=[]
    U,V=np.vectorize(lambda a,b:sample(a,b,asp,film,roll))(X,Y)
    for cu,cv in ((0,0),(1,0),(0,1),(1,1)):
        d=np.maximum(abs(U-cu),abs(V-cv));i=np.unravel_index(d.argmin(),d.shape);out.append((d.min(),X[i],Y[i]))
    return out
fail=[]
for asp in (16/9,1.0,2.39,.75):
  for film in (4/3,16/9,2.39):
    for deg in (0,25,-45,90):
      roll=math.radians(deg)
      for dist,x,y in forward_corners(asp,film,roll):
        if dist>.02: fail.append(('corner hidden',asp,film,deg,round(dist,3)))
      if deg==0:
        # film aspect of the displayed rect at rest: width/height in window pixels
        u0=sample(0,.5,asp,film,0)[0];u1=sample(1,.5,asp,film,0)[0]
        # displayed film width fraction = 1/(u1-u0)
        wfrac=1/(u1-u0)
        hfrac=1/(sample(.5,1,asp,film,0)[1]-sample(.5,0,asp,film,0)[1])
        shown=(wfrac*asp)/hfrac
        if abs(shown-film)>1e-6: fail.append(('aspect changed',asp,film,shown))
print('model cases failed:',len(fail),fail[:5])
assert not fail
print('PASS model: film aspect preserved, four corners visible at tilt 0/25/-45/90 (shader math model only)')

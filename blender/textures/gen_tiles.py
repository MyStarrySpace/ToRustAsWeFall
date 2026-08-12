from PIL import Image
import random, os, zlib

T = 32          # 32 px / meter
VARS = 4
def q(c): return tuple(max(0,min(255,int(round(v)))) for v in c[:3]) + (255,)
def sh(b,f): return q((b[0]*f,b[1]*f,b[2]*f))
def lerp(a,b,t): return q((a[0]+(b[0]-a[0])*t, a[1]+(b[1]-a[1])*t, a[2]+(b[2]-a[2])*t))

# ordered 4x4 Bayer for subtle pixel-art dithering (deterministic, not noise)
BAYER=[[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]]
def dith(px,x,y,dark,light,t):  # t in 0..1 chooses light prob via bayer
    px[x,y]= light if (t*16) > BAYER[y%4][x%4] else dark

def fill(px,c,W=T):
    for y in range(W):
        for x in range(W): px[x,y]=c

def speck(px,rng,base,dark,light,d,W=T):
    n=int(W*W*d)
    for _ in range(n):
        x,y=rng.randrange(W),rng.randrange(W)
        px[x,y]= dark if rng.random()<0.5 else light

# --- industrial facility wall metal: brushed verticals + panel seam + rivets ---
def m_metal(px,rng):
    dk=(70,74,82); base=(98,103,112); lt=(122,127,137)
    for y in range(T):
        for x in range(T):
            # faint vertical brushed streaks
            f = 1.0 + 0.05*((x*5+ (x//3))%3 -1)
            px[x,y]= sh(base,f)
    for x in range(T): px[x,0]=dk; px[x,T-1]=sh(base,0.82)        # top seam + bottom edge (wraps)
    for y in range(T):
        if rng.random()<0.10: px[rng.randrange(T),y]=sh(base,1.12)
    for (cx,cy) in [(2,2),(29,2),(2,29),(29,29),(15,15)]:          # rivets
        px[cx,cy]=lt; px[cx,(cy+1)%T]=dk

# --- dark diamond-plate floor: raised diamonds on 8px grid ---
def m_deck(px,rng):
    base=(50,53,60); hi=(66,70,78); shd=(40,42,48)   # calmed: the old 2x pop strobed as noise at gameplay distance
    fill(px,base)
    for gy in range(0,T,8):
        for gx in range(0,T,8):
            for (dx,dy) in [(2,1),(3,2),(2,3),(1,2)]:             # diamond body
                px[(gx+dx)%T,(gy+dy)%T]=hi
            for (dx,dy) in [(3,3),(2,4),(4,2)]:                   # shadow side
                px[(gx+dx)%T,(gy+dy)%T]=shd

# --- elevator paneled wall: vertical panels w/ seams + bolts + soft shading ---
def m_panel(px,rng):
    base=(110,103,95); dk=(74,69,63); lt=(132,124,114)
    for y in range(T):
        for x in range(T):
            col = x//16
            f = 1.0 + (0.06 if (x%16) in (6,7,8) else 0.0) - (0.05 if (x%16)>13 else 0.0)
            px[x,y]= sh(base,f)
    for x in (0,16):                                              # seams
        for y in range(T): px[x,y]=dk
    for (cx,cy) in [(2,2),(2,29),(18,2),(18,29),(13,15),(29,15)]: # bolts
        px[cx,cy]=lt; px[(cx+1)%T,cy]=dk

# --- distress companions: per-cell wear at the SAME contrast scale as each painter's own
# features (a variation-atlas cell must read distinct at gameplay distance — 1px scratches
# vanish under minification; swapped plates, missing rivets and discolored panels do not) ---
def d_deck(px,rng):
    base=(50,53,60); hi=(66,70,78); shd=(40,42,48)   # calmed: the old 2x pop strobed as noise at gameplay distance
    def diamonds(gx,gy,h,s):
        for (dx,dy) in [(2,1),(3,2),(2,3),(1,2)]: px[(gx+dx)%T,(gy+dy)%T]=h
        for (dx,dy) in [(3,3),(2,4),(4,2)]:       px[(gx+dx)%T,(gy+dy)%T]=s
    if rng.random()<0.35:                                        # replaced plate patch
        f=rng.choice([0.8,1.16]); gx0,gy0=rng.randrange(0,T,8),rng.randrange(0,T,8)
        w=rng.choice([8,16]); h=rng.choice([8,16])
        for y in range(gy0,min(gy0+h,T)):
            for x in range(gx0,min(gx0+w,T)): px[x,y]=sh(base,f)
        for gy in range(gy0,min(gy0+h,T),8):
            for gx in range(gx0,min(gx0+w,T),8): diamonds(gx,gy,sh(hi,f),sh(shd,f))
    for _ in range(rng.randint(0,3)):                            # missing rivet cluster
        gx,gy=rng.randrange(0,T,8),rng.randrange(0,T,8)
        for (dx,dy) in [(2,1),(3,2),(2,3),(1,2),(3,3),(2,4),(4,2)]: px[(gx+dx)%T,(gy+dy)%T]=base
    for _ in range(rng.randint(0,2)):                            # worn-shiny rivet
        gx,gy=rng.randrange(0,T,8),rng.randrange(0,T,8)
        diamonds(gx,gy,sh(hi,1.3),sh(hi,0.9))
    if rng.random()<0.35:                                        # wide grime smear
        x0,y0=rng.randrange(0,T-9),rng.randrange(0,T-14)
        for y in range(y0,y0+rng.randint(6,14)):
            for x in range(x0,x0+rng.randint(4,9)): px[x,y]=sh(px[x,y],0.86)

def d_panel(px,rng):
    base=(110,103,95); dk=(74,69,63)
    if rng.random()<0.4:                                         # discolored replaced panel
        f=rng.choice([0.86,1.1]); x0=rng.choice([1,17])
        for y in range(T):
            for x in range(x0,x0+15): px[x,y]=sh(px[x,y],f)
    if rng.random()<0.45:                                        # drip streak from a bolt
        cx,cy=rng.choice([(2,2),(18,2),(13,15),(29,15)])
        for y in range(cy,min(cy+rng.randint(6,16),T)):
            for x in (cx,cx+1):
                if x<T: px[x,y]=sh(px[x,y],0.84)
    if rng.random()<0.3:                                         # missing bolt
        cx,cy=rng.choice([(2,2),(2,29),(18,2),(18,29),(13,15),(29,15)])
        px[cx,cy]=base; px[(cx+1)%T,cy]=base
    for _ in range(rng.randint(0,2)):                            # scratch
        x,y=rng.randint(2,T-8),rng.randint(2,T-8); dx,dy=rng.choice([(1,0),(0,1),(1,1)])
        f=rng.choice([0.75,1.2])
        for i in range(rng.randint(3,6)): px[x+dx*i,y+dy*i]=sh(px[x+dx*i,y+dy*i],f)

# --- catwalk grate: metallic bars, dark holes with depth ---
def m_grate(px,rng):
    hole=(16,17,22); bar=(92,95,103); barhi=(126,130,140); bardk=(60,62,70)
    for y in range(T):
        for x in range(T):
            on = (x%8<2) or (y%8<2)
            if on:
                top = (x%8==0) or (y%8==0)
                px[x,y]= barhi if top else bar
            else:
                # subtle depth in the hole
                px[x,y]= hole if ((x%8) in (4,5) and (y%8) in (4,5)) else sh(hole,1.25)
    # cross-joint accents
    for gy in range(0,T,8):
        for gx in range(0,T,8): px[gx,gy]=bardk

# --- rust on iron (the red chasm): metal base + rust blotches + pitting ---
# W lets the painter cover a whole W x W variation-atlas canvas in ONE pass: features wrap
# at W (the REPEAT seam), so blotches flow across metre-cell boundaries instead of being
# torus-wrapped inside a single 32px cell (which clips them dead straight at every cell edge).
def m_rust(px,rng,W=T):
    A=(W//T)*(W//T)
    metal=(96,82,74); rust=(150,74,38); rustlt=(186,104,52); pit=(64,32,20)
    fill(px,metal,W)
    speck(px,rng,metal,sh(metal,0.8),sh(metal,1.12),0.18,W)
    # Corrosion grows in CLUMPS: a few nuclei each sprouting a cluster of blotches,
    # with clean metal between — uniform random blotches read as leopard camo.
    for _ in range(3*A):
        ncx,ncy=rng.randrange(W),rng.randrange(W)
        for _b in range(rng.randint(2,4)):
            cx,cy=(ncx+rng.randint(-9,9))%W,(ncy+rng.randint(-9,9))%W
            r=rng.randint(3,6)
            for y in range(-r,r+1):
                for x in range(-r,r+1):
                    if x*x+y*y<=r*r:
                        xx,yy=(cx+x)%W,(cy+y)%W
                        d=(x*x+y*y)/(r*r+0.1)
                        px[xx,yy]= lerp(rustlt,rust,d) if rng.random()>0.18 else pit
    for _ in range(14*A): px[rng.randrange(W),rng.randrange(W)]=rustlt   # bright flecks

# --- cave rock: warm facets, cracks, mineral specks ---
def m_rock(px,rng,W=T):
    A=(W//T)*(W//T)
    base=(138,104,78)
    fill(px,base,W)
    for _ in range(10*A):                                        # facet patches
        cx,cy=rng.randrange(W),rng.randrange(W); r=rng.randint(3,7); f=rng.uniform(0.78,1.2)
        for y in range(-r,r+1):
            for x in range(-r,r+1):
                if x*x+y*y<=r*r: px[(cx+x)%W,(cy+y)%W]=sh(base,f)
    for _ in range(7*A):                                         # cracks (kept short, away from wrap seams)
        x,y=rng.randint(3,W-4),rng.randint(3,W-4); L=rng.randint(4,9)
        dx,dy=rng.choice([(1,1),(1,0),(0,1),(1,-1)])
        for i in range(L):
            xx,yy=x+dx*i,y+dy*i
            if 0<=xx<W and 0<=yy<W: px[xx,yy]=sh(base,0.55)
    for _ in range(10*A): px[rng.randrange(W),rng.randrange(W)]=q((196,156,104))   # minerals

# --- cave sand floor: fine speckle, ripples, pebbles ---
def m_sand(px,rng):
    base=(174,142,108)
    fill(px,base); speck(px,rng,base,sh(base,0.86),sh(base,1.1),0.28)
    for y in range(T):                                           # gentle ripples
        for x in range(T):
            if (x+y*2)%7<2: px[x,y]=sh(px[x,y],0.93)
    for _ in range(6):                                           # pebbles
        cx,cy=rng.randrange(T),rng.randrange(T)
        px[cx,cy]=sh(base,0.7); px[(cx+1)%T,cy]=sh(base,1.15)

# --- bioluminescent: dark substrate + teal glow clusters w/ bright cores ---
def m_biolum(px,rng):
    base=(14,24,22); glow=(60,220,165); core=(170,255,225)
    fill(px,base)
    for _ in range(5):
        cx,cy=rng.randrange(5,27),rng.randrange(5,27); r=rng.randint(3,5)
        for y in range(-r,r+1):
            for x in range(-r,r+1):
                if x*x+y*y<=r*r:
                    d=(x*x+y*y)/(r*r+0.1)
                    px[(cx+x)%T,(cy+y)%T]=lerp(glow,base,d)
        px[cx,cy]=core

MATS=[("rock",m_rock),("sand",m_sand),("facility_metal",m_metal),("grate",m_grate),
      ("rust_iron",m_rust),("biolum_teal",m_biolum),("deck_metal",m_deck),("wall_panel",m_panel)]

# The painters above are a shared library (gen_variation_atlases.py composes them into
# per-surface variation atlases) — the shipped-tile build below only runs standalone.
# Seeds are crc32 (deterministic across runs); note the currently SHIPPED tiles predate
# this and came from a salted-hash seed, so the first re-run still repaints them once.
if __name__=="__main__":
    ROOT="C:/Users/quest/Programming/Games/ToRustAsWeFall"
    SRC=ROOT+"/blender/textures/tiles"
    RES=ROOT+"/to-rust-as-we-fall/resources/models/elevator/tiles"
    W=T*VARS; H=T*len(MATS)
    atlas=Image.new("RGBA",(W,H),(0,0,0,255))
    for row,(name,fn) in enumerate(MATS):
        for col in range(VARS):
            tile=Image.new("RGBA",(T,T),(0,0,0,255)); tp=tile.load()
            fn(tp, random.Random(zlib.crc32(("%s:%d"%(name,col)).encode())))
            atlas.paste(tile,(col*T,row*T))
            if col==0:   # variation 0 -> the shipped individual tile
                tile.save(SRC+"/%s.png"%name)
                tile.save(RES+"/%s.png"%name)
    atlas.save(ROOT+"/blender/textures/tile_atlas_32.png")
    atlas.resize((W*10,H*10),Image.NEAREST).save("C:/tmp/tile_atlas_preview.png")
    print("wrote atlas %dx%d + individual tiles to:\n  %s\n  %s"%(W,H,SRC,RES))

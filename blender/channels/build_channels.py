import bpy, math, mathutils, sys, importlib

# --- load the spatial grammar (relational placement, not raw coords) ---
BL = r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender"
if BL not in sys.path: sys.path.insert(0, BL)
import spatial_grammar; importlib.reload(spatial_grammar)
from spatial_grammar import Grammar

bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene

def mat(name,color,emis=None,es=0.0,rough=0.8,metal=0.0):
    m=bpy.data.materials.new(name); m.use_nodes=True
    b=m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value=(*color,1); b.inputs["Roughness"].default_value=rough; b.inputs["Metallic"].default_value=metal
    if emis: b.inputs["Emission Color"].default_value=(*emis,1); b.inputs["Emission Strength"].default_value=es
    return m
M_WALL =mat("Wall",(0.10,0.10,0.12),rough=0.75,metal=0.25)
M_MID  =mat("Mid",(0.17,0.16,0.18),rough=0.6,metal=0.4)
M_DECK =mat("Deck",(0.13,0.13,0.15),rough=0.7,metal=0.3)
M_GRATE=mat("Grate",(0.07,0.07,0.085),rough=0.7,metal=0.3)
M_RUST =mat("Rust",(0.24,0.11,0.06),rough=0.85)
M_RED  =mat("Red",(0.9,0.12,0.07),emis=(1.0,0.12,0.05),es=12.0,rough=0.5)
M_REDM =mat("RedDim",(0.7,0.10,0.06),emis=(1.0,0.10,0.04),es=4.0,rough=0.6)
M_PANEL=mat("Panel",(0.9,0.45,0.12),emis=(1.0,0.55,0.18),es=3.0,rough=0.4)
M_SIGN =mat("Sign",(0.5,0.12,0.07),emis=(0.9,0.18,0.08),es=2.0,rough=0.6)
M_WATER=mat("Water",(0.015,0.03,0.045),rough=0.06,metal=0.0)
M_PIPE =mat("Pipe",(0.20,0.19,0.18),rough=0.55,metal=0.55)
M_CABLE=mat("Cable",(0.035,0.035,0.045),rough=0.9)
M_HAZ  =mat("Hazard",(0.8,0.6,0.05),rough=0.7)

g=Grammar()
LZ0,LZ1=-4.0,3.2; CHX=[14.6,20.68,26.76]; CHW=1.6; WTOP=-0.35; WFLOOR=-3.6

# ===== FLOORS (slabs filling footprints; abutting -> no gaps) =====
g.slab_xz("Floor_south", -7,51, -17,LZ0, 0,0.3, M_DECK)                       # branch/hide/south
segs=[(-7,CHX[0]-CHW/2),(CHX[0]+CHW/2,CHX[1]-CHW/2),(CHX[1]+CHW/2,CHX[2]-CHW/2),(CHX[2]+CHW/2,51)]
decks=[g.slab_xz("Deck_%d"%i,x0,x1,LZ0,LZ1,0,0.3,M_DECK) for i,(x0,x1) in enumerate(segs)]
for i,d in enumerate(decks):
    g.box("Grate_%d"%i, d.x0+0.2,d.x1-0.2, 0.0,0.05, LZ0+0.3,LZ1-0.3, M_GRATE,"floor")
g.slab_xz("WaterFloor", -7,51, LZ1,17, WFLOOR,0.3, M_WALL, tag="floor")
for i,cx in enumerate(CHX):
    g.slab_xz("ChanFloor_%d"%i, cx-CHW/2,cx+CHW/2, LZ0,LZ1, WFLOOR,0.3, M_WALL, tag="floor")
# water surfaces (tag 'water': NOT a floor -> a prop placed over it is flagged)
g.box("Water_main", -6.7,50.7, WTOP-0.04,WTOP, LZ1+0.1,16.9, M_WATER,"water")
for i,cx in enumerate(CHX):
    g.box("Water_ch_%d"%i, cx-CHW/2+0.06,cx+CHW/2-0.06, WTOP-0.16,WTOP-0.12, LZ0+0.1,LZ1, M_WATER,"water")

# ===== WALLS (stand on edges) =====
wall_N=g.wall("WallN",'x',17,-7,51,0,6,0.6,M_WALL,side=+1)
g.wall("WallS",'x',-17,-7,51,0,6,0.4,M_WALL,side=-1)
g.wall("WallW",'z',-7,-17,17,0,6,0.4,M_WALL,side=-1)
g.wall("WallE",'z',51,-17,17,0,6,0.4,M_WALL,side=+1)
back_W=g.wall("BackW",'x',LZ0,-7,7.2,0,6,0.4,M_WALL,side=-1)    # west of branch opening
back_E=g.wall("BackE",'x',LZ0,23.2,40,0,6,0.4,M_WALL,side=-1)   # east of branch opening

# ===== ACCESS door — recess() splits back_W into L/R/lintel (no gap) + alcove =====
door=g.recess(back_W, 2.0,4.0, 2.6)
op=door["opening"]
g.box("DoorAlcove", op.x0,op.x1, 0,op.y1, op.z0-0.7,op.z0, M_WALL,"structure")
g.box("DoorThresh", op.x0,op.x1, 0,0.12, op.z0,op.z0+0.9, M_RUST,"structure")
g.box("DoorStripL", op.x0,op.x0+0.08, 0.15,op.y1-0.2, op.z0-0.66,op.z0, M_RED,"structure")
g.box("DoorStripR", op.x1-0.08,op.x1, 0.15,op.y1-0.2, op.z0-0.66,op.z0, M_RED,"structure")
g.on_wall("Sgn_access", door["lintel"], '+z', 0.5, 0.15, 1.7,0.4, 0.06, M_SIGN)

# ===== DECORATIONS — on_wall() so they're attached to a real wall (never floating / over a gap) =====
def pipe_run(host, face, vs):
    L=(host.x1-host.x0) if face in('+z','-z') else (host.z1-host.z0)
    for v,r in vs:
        g.on_wall("Pipe_%s_%d"%(host.name,int(v*100)), host, face, 0.5, v, L*0.92, r*2, r*2, M_PIPE)
pipe_run(back_E,'+z',[(0.55,0.12),(0.62,0.10),(0.69,0.14)])
pipe_run(wall_N,'-z',[(0.72,0.12),(0.80,0.10)])
g.on_wall("Pipe_R", door["R"], '+z', 0.5, 0.62, (door["R"].x1-door["R"].x0)*0.8, 0.2,0.2, M_PIPE)
# vents on the east back wall
for u in (0.32,0.58,0.84):
    g.on_wall("VentH_%d"%int(u*100), back_E, '+z', u, 0.4, 1.4,1.4, 0.18, M_MID)
    g.on_wall("VentG_%d"%int(u*100), back_E, '+z', u, 0.4, 1.15,1.15, 0.06, M_GRATE)
# cable bundles (attached to back walls) + drops
for v in (0.86,0.9,0.82):
    g.on_wall("Cable_E_%d"%int(v*100), back_E, '+z', 0.5, v, (back_E.x1-back_E.x0)*0.95, 0.05,0.05, M_CABLE)
    g.on_wall("Cable_L_%d"%int(v*100), door["L"], '+z', 0.5, v, (door["L"].x1-door["L"].x0)*0.9, 0.05,0.05, M_CABLE)
# wall panels + signs
g.on_wall("Panel_channels", door["L"], '+z', 0.62, 0.62, 4.2,2.0, 0.08, M_PANEL)
g.on_wall("Sign_sector12", back_E, '+z', 0.5, 0.78, 3.6,1.4, 0.06, M_SIGN)
g.on_wall("Panel_gatectrl", wall_N, '-z', 0.78, 0.6, 3.2,1.8, 0.08, M_PANEL)

# ===== sluice gate (slatted, on the north water wall) =====
g.on_wall("Sluice_recess", wall_N, '-z', 0.9, 0.18, 3.4,2.8, 0.5, M_WALL)
for i in range(5):
    g.on_wall("Sluice_slat_%d"%i, wall_N, '-z', 0.9, 0.04+i*0.052, 3.0,0.22, 0.6, M_MID)
g.on_wall("Sluice_glow", wall_N, '-z', 0.9, 0.18, 3.0,2.4, 0.55, M_REDM)

# ===== railing along the water edge (posts on the deck, rails spanning) =====
def post(i,p):
    x=p[0]
    if any(abs(x-cx)<CHW for cx in CHX): return None
    return g.box("Rpost_%d"%i, x-0.05,x+0.05, 0,1.05, LZ1-0.18,LZ1-0.06, M_MID, "prop")
g.row("Rpost",(5,0,LZ1),(37,0,LZ1),2.2,post)
for nm,y0,y1,m in [("lo",0.43,0.49,M_MID),("hi",0.76,0.82,M_MID),("top",0.98,1.06,M_RUST)]:
    g.box("Rrail_%s"%nm, 5,37, y0,y1, LZ1-0.15,LZ1-0.09, m, "structure")

# ===== ladder down into the water (rails + rungs), attached to the deck edge =====
g.box("LadL", 33.66,33.74, WFLOOR,0.3, LZ1-0.02,LZ1+0.14, M_MID,"structure")
g.box("LadR", 34.26,34.34, WFLOOR,0.3, LZ1-0.02,LZ1+0.14, M_MID,"structure")
for i in range(8):
    g.box("Lad_%d"%i, 33.7,34.3, WFLOOR+0.2+i*0.5,WFLOOR+0.26+i*0.5, LZ1-0.0,LZ1+0.12, M_MID,"structure")

# ===== crates (ON floors) =====
g.on("Crate1", decks[3], 0.18,0.45, 1.3,1.3, 1.3, M_RUST)
g.on("Crate2", decks[3], 0.28,0.5,  1.0,1.0, 1.0, M_RUST)
c3=g.on("Crate3", decks[3], 0.18,0.45, 1.0,1.0, 1.0, M_RUST); g.stack("Crate3b",c3,0.9,0.9,0.9,M_RUST)
g.on("Crate4", decks[0], 0.78,0.45, 1.1,1.1, 1.1, M_RUST)
fs=g.regions  # branch crates on the south floor
g.box("Crate5", 15,16.2, 0,1.2, -6.6,-5.4, M_RUST,"prop")     # on south floor (z<-4)
g.box("Crate6", 13.9,15.0, 0,1.1, -12.6,-11.5, M_RUST,"prop") # near hide corridor
g.on("Sgn_d512", decks[3], 0.18,0.45, 0.85,0.1, 0.6, M_SIGN)  # placard leaning on Crate1 area

# ===== hazard stripes + signs (flat, ON the deck / on walls) =====
for i,d in enumerate(decks):
    g.box("Haz_edge_%d"%i, d.x0+0.2,d.x1-0.2, 0,0.04, LZ1-0.28,LZ1-0.12, M_HAZ,"prop")
for cx in CHX:
    g.box("Haz_chW_%d"%int(cx*10), cx-CHW/2-0.2,cx-CHW/2-0.04, 0,0.04, LZ0+0.3,LZ1-0.3, M_HAZ,"prop")
    g.box("Haz_chE_%d"%int(cx*10), cx+CHW/2+0.04,cx+CHW/2+0.2, 0,0.04, LZ0+0.3,LZ1-0.3, M_HAZ,"prop")
g.on_wall("Sgn_waterdepth", back_E, '+z', 0.12, 0.32, 1.4,0.5, 0.05, M_SIGN)
g.box("Sgn_wetfloor", -5,-3.6, 0.05,0.95, LZ0-0.2,LZ0-0.12, M_SIGN,"prop")   # on the south floor near stairs

# ===== stairs down (west end) to a service ledge — stepped, each step on the previous =====
ledge=g.slab_xz("StairLedge", -7,-1.5, -7,-3.5, -2.9,0.3, M_DECK)
prev_top=0.0
for i in range(6):
    z0=-1.0-i*0.55; y=-0.0-i*0.45
    g.box("Stair_%d"%i, -6.5,-2.0, y-0.45,y, z0-0.55,z0, M_MID,"structure")

# ===== pilasters + buttresses (on the walls) =====
for u in (0.2,0.5,0.8):
    g.on_wall("PilE_%d"%int(u*100), back_E, '+z', u, 0.5, 0.5,5.2, 0.18, M_MID)
for u in (0.15,0.4,0.65,0.9):
    g.on_wall("ButN_%d"%int(u*100), wall_N, '-z', u, 0.42, 0.7,8.0, 0.5, M_MID)

# ===== red strips (attached to walls / on the deck edge) =====
g.on_wall("Strip_E", back_E, '+z', 0.5, 0.03, (back_E.x1-back_E.x0)*0.95, 0.12, 0.08, M_RED)
g.on_wall("Strip_L", door["L"], '+z', 0.5, 0.03, (door["L"].x1-door["L"].x0)*0.9, 0.12, 0.08, M_RED)
g.on_wall("Strip_N", wall_N, '-z', 0.5, 0.5, (wall_N.x1-wall_N.x0)*0.96, 0.1, 0.08, M_REDM)

# ===== validate (mereotopology) =====
issues=g.validate()
print("=== VALIDATE: %d issue(s) ==="%len(issues))
for s in issues: print("  "+s)

# ===== emit to Blender =====
g.emit(scene)

# ===== lights (chunk coords -> Blender) =====
def light(name,gx,gy,gz,color,energy,rng=14.0):
    d=bpy.data.lights.new(name,'POINT'); d.color=color; d.energy=energy; d.shadow_soft_size=1.5
    try: d.use_custom_distance=True; d.cutoff_distance=rng
    except Exception: pass
    o=bpy.data.objects.new(name,d); o.location=(gx,-gz,gy); scene.collection.objects.link(o)
sun_d=bpy.data.lights.new("Sun",'SUN'); sun_d.energy=0.85; sun_d.color=(0.5,0.58,0.85); sun_d.angle=0.1
sun=bpy.data.objects.new("Sun",sun_d); sun.rotation_euler=(0.95,0.15,0.7); scene.collection.objects.link(sun)
light("Ldoor",3,1.6,-3.6,(1.0,0.22,0.1),320,12); light("Lpanel",-1.6,1.6,-3.0,(1.0,0.55,0.22),180,11)
light("Lsign",30,2.0,-3.2,(1.0,0.3,0.12),120,10); light("Lgate",43,3.0,14.5,(1.0,0.4,0.16),300,16)
for i,cx in enumerate(CHX): light("Lch_%d"%i,cx,1.2,0.0,(1.0,0.2,0.09),180,12)
light("Lwater1",10,1.5,10,(1.0,0.2,0.09),260,18); light("Lwater2",34,1.5,10,(1.0,0.2,0.09),260,18)
light("Lhide",9.8,1.4,-11.8,(0.6,1.0,0.5),120,9); light("Lcrate",30,2.0,1.4,(1.0,0.35,0.18),110,9)
world=bpy.data.worlds.new("W"); scene.world=world; world.use_nodes=True
world.node_tree.nodes["Background"].inputs[0].default_value=(0.03,0.035,0.05,1)

# ===== cameras + render =====
cam_d=bpy.data.cameras.new("Cam"); cam_d.lens=32
cam=bpy.data.objects.new("Cam",cam_d); scene.collection.objects.link(cam); scene.camera=cam
scene.render.engine='BLENDER_EEVEE'
for a in ("use_ssr","use_ssr_refraction","use_raytracing","use_bloom"):
    try: setattr(scene.eevee,a,True)
    except Exception: pass
scene.render.resolution_x=1400; scene.render.resolution_y=1000; scene.render.image_settings.file_format='PNG'
def do(): bpy.ops.render.render(write_still=True)
def render_to(path):
    scene.render.filepath=path
    try: do()
    except Exception:
        W=bpy.context.window_manager.windows[0]; A=[a for a in W.screen.areas if a.type=='VIEW_3D'][0]; R=[r for r in A.regions if r.type=='WINDOW'][0]
        with bpy.context.temp_override(window=W,area=A,region=R): do()
def aim(loc,tgt):
    cam.location=loc; cam.rotation_euler=(mathutils.Vector(tgt)-mathutils.Vector(loc)).to_track_quat('-Z','Y').to_euler()
aim((-14,-24,30),(22,-2,1)); render_to(r"C:\tmp\channels_overview.png")
aim((-6,-7,9),(16,-0.5,-0.2)); render_to(r"C:\tmp\channels_render.png")

import os
os.makedirs(BL+r"\channels",exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BL+r"\channels\channels.blend")
result={"objects":len(bpy.data.objects),"validate_issues":len(issues),"issues":issues}

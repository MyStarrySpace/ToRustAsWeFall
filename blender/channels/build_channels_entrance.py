import bpy, math, mathutils, sys, importlib
BL = r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender"
if BL not in sys.path: sys.path.insert(0, BL)
import spatial_grammar; importlib.reload(spatial_grammar)
from spatial_grammar import Grammar

bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene
def mat(n,c,e=None,es=0.0,r=0.8,m=0.0):
    M=bpy.data.materials.new(n); M.use_nodes=True; b=M.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value=(*c,1); b.inputs["Roughness"].default_value=r; b.inputs["Metallic"].default_value=m
    if e: b.inputs["Emission Color"].default_value=(*e,1); b.inputs["Emission Strength"].default_value=es
    return M
M_WALL=mat("Wall",(0.10,0.10,0.12),r=0.75,m=0.25); M_MID=mat("Mid",(0.17,0.16,0.18),r=0.6,m=0.4)
M_DECK=mat("Deck",(0.13,0.13,0.15),r=0.7,m=0.3);   M_GRATE=mat("Grate",(0.08,0.08,0.09),r=0.7,m=0.3)
M_RUST=mat("Rust",(0.24,0.11,0.06),r=0.85);        M_PIPE=mat("Pipe",(0.2,0.19,0.18),r=0.55,m=0.55)
M_RED=mat("Red",(0.9,0.12,0.07),e=(1,0.12,0.05),es=12,r=0.5)
M_PLANT=mat("Plant",(0.18,0.45,0.2),e=(0.2,0.6,0.25),es=0.6,r=0.7)
M_POT=mat("Pot",(0.35,0.22,0.14),r=0.8)
M_TERM=mat("Term",(0.1,0.5,0.55),e=(0.2,0.9,1.0),es=3.0,r=0.4)
M_WATER=mat("Water",(0.015,0.03,0.045),r=0.06)

g=Grammar()
CX,CZ=0.0,0.0           # well centre
RAD=6.5; YTOP=9.0; TURNS=1.75; SPT=8; DROP=4.5; RAMP_W=2.8

# ---- outer octagonal enclosure wall (8 angled segments around the spiral) ----
OUTR=9.6
for k in range(8):
    a=k/8.0*2*math.pi
    px=CX+OUTR*math.cos(a); pz=CZ+OUTR*math.sin(a)
    seg=2*OUTR*math.sin(math.pi/8)*1.05
    g.pbox("OWall_%d"%k, px,4.5,pz, seg,9.0,0.5, a+math.pi/2, M_WALL)

# ---- the descending octagonal spiral ramp (relational coil) ----
steps=g.coil("Ramp", CX,CZ, RAD, YTOP, TURNS, SPT, DROP, 1.10, RAMP_W, 0.35, M_DECK)
# grate inlay + a low outer kerb on each step; plants & terminals on alternating steps
for st in steps:
    px,py,pz=st["center"]; yaw=st["amid"]; i=st["i"]
    g.pbox("RampGrate_%d"%i, px,py+0.2,pz, 4.4,0.05,RAMP_W-0.5, yaw+math.pi/2, M_GRATE)
    # outer kerb (low rail lip on the well-facing... actually on the OUTER edge)
    ox=math.cos(st["amid"]); oz=math.sin(st["amid"])
    g.pbox("Kerb_%d"%i, px+ox*(RAMP_W/2-0.1), py+0.4, pz+oz*(RAMP_W/2-0.1), 4.6,0.5,0.16, st["amid"]+math.pi/2, M_RUST)
    if i%2==0:                      # plant on even steps (visible from the overlook -> Peris reads them)
        ppx,ppz=px+ox*0.6, pz+oz*0.6
        g.box("Pot_%d"%i, ppx-0.35,ppx+0.35, py+0.2,py+0.55, ppz-0.35,ppz+0.35, M_POT, "prop")
        g.box("Plant_%d"%i, ppx-0.3,ppx+0.3, py+0.55,py+1.5, ppz-0.3,ppz+0.3, M_PLANT, "prop")
    else:                           # terminal on odd steps
        tpx,tpz=px+ox*0.5, pz+oz*0.5
        g.pbox("Term_%d"%i, tpx,py+0.85,tpz, 0.9,1.3,0.3, st["amid"]+math.pi/2, M_MID)
        g.pbox("TermScr_%d"%i, tpx-ox*0.16,py+0.95,tpz-oz*0.16, 0.7,0.8,0.06, st["amid"]+math.pi/2, M_TERM)

# ---- central well floor + start-shelter pool at the bottom (washouts land here) ----
g.slab_xz("WellFloor", CX-5,CX+5, CZ-5,CZ+5, top=0.0, thick=0.4, mat=M_WALL)
g.box("Pool", CX-3.4,CX+3.4, -0.3,0.02, CZ-3.4,CZ+3.4, M_WATER, "water")
g.slab_xz("ShelterPad", CX+4.0,CX+9.0, CZ-2.5,CZ+2.5, top=0.15, thick=0.5, mat=M_DECK)
g.box("ShelterGlow", CX+4.2,CX+8.8, 0.16,0.2, CZ-2.2,CZ+2.2, M_RED, "prop")

# ---- entry BRIDGE atop the spiral (you cross it and look down into the well) ----
bridge=g.box("Bridge", -16.0,-1.5, YTOP+0.6,YTOP+0.9, -1.6,1.6, M_DECK, "floor")
g.box("BridgeGrate", -15.6,-1.8, YTOP+0.9,YTOP+0.95, -1.2,1.2, M_GRATE, "floor")
for zside in (-1.6,1.6):
    g.box("BrRail_%d"%int(zside), -16,-1.5, YTOP+0.9,YTOP+1.5, zside-0.06,zside+0.06, M_MID, "structure")
g.row("BrPost", (-15,YTOP+0.9,-1.6),(-2,YTOP+0.9,-1.6), 2.0, lambda i,p: g.box("BrPost_a%d"%i,p[0]-0.06,p[0]+0.06,p[1],p[1]+0.6,p[2]-0.06,p[2]+0.06,M_MID,"structure"))
g.row("BrPostB",(-15,YTOP+0.9,1.6),(-2,YTOP+0.9,1.6), 2.0, lambda i,p: g.box("BrPost_b%d"%i,p[0]-0.06,p[0]+0.06,p[1],p[1]+0.6,p[2]-0.06,p[2]+0.06,M_MID,"structure"))

# ---- the LARGE PIPE: arcs in over the bridge, turns down the well, feeds the wash below ----
g.box("PipeIn", -16,-2.5, YTOP+2.0,YTOP+3.6, -0.8,0.8, M_PIPE, "structure")           # horizontal intake over the bridge
g.box("PipeElbow", -3.5,-1.5, YTOP+0.5,YTOP+3.6, -0.8,0.8, M_PIPE, "structure")        # elbow down
g.pbox("PipeDown", -1.0, 4.6, 1.2, 9.6,1.5,1.5, math.pi/2*0.0, M_PIPE)                 # big vertical down the well
g.box("PipeBand1", -1.9,-0.1, 6.4,6.8, 0.3,2.1, M_RUST, "structure")
g.box("PipeBand2", -1.9,-0.1, 2.4,2.8, 0.3,2.1, M_RUST, "structure")
g.box("PipeOut", -1.0,2.6, 0.6,2.0, 0.6,1.8, M_PIPE, "structure")                       # outflow at the bottom
g.box("PipeOutGlow", 2.4,2.7, 0.7,1.9, 0.7,1.7, M_RED, "prop")

# ---- red strips around the well rim + on the bridge ----
g.box("RimStripA", -16,-2, YTOP+0.62,YTOP+0.66, -1.55,-1.45, M_RED, "prop")
g.box("RimStripB", -16,-2, YTOP+0.62,YTOP+0.66, 1.45,1.55, M_RED, "prop")

issues=g.validate()
print("=== VALIDATE: %d ==="%len(issues))
for s in issues: print("  "+s)
g.emit(scene)

# ---- lights ----
def light(n,gx,gy,gz,col,en,rng=20.0):
    d=bpy.data.lights.new(n,'POINT'); d.color=col; d.energy=en; d.shadow_soft_size=2.0
    try: d.use_custom_distance=True; d.cutoff_distance=rng
    except Exception: pass
    o=bpy.data.objects.new(n,d); o.location=(gx,-gz,gy); scene.collection.objects.link(o)
sun=bpy.data.lights.new("Sun",'SUN'); sun.energy=0.8; sun.color=(0.5,0.58,0.85)
so=bpy.data.objects.new("Sun",sun); so.rotation_euler=(0.9,0.2,0.6); scene.collection.objects.link(so)
light("Lwell",0,4,0,(1.0,0.25,0.12),200,26)
light("Lbottom",1,1.5,1,(1.0,0.2,0.1),110,16)
light("Lbridge",-9,YTOP+2,0,(0.7,0.4,0.3),200,16)
light("Lshelter",6.5,1.6,0,(1.0,0.35,0.18),160,12)
for st in steps:                       # a soft terminal/plant glow per step
    px,py,pz=st["center"]; light("Lstep_%d"%st["i"], px,py+1.0,pz,(0.6,0.8,0.7),28,5.5)
world=bpy.data.worlds.new("W"); scene.world=world; world.use_nodes=True
world.node_tree.nodes["Background"].inputs[0].default_value=(0.025,0.03,0.045,1)

# ---- camera: from above the entry bridge, looking down into the spiral well (the overlook) ----
cam_d=bpy.data.cameras.new("Cam"); cam_d.lens=30
cam=bpy.data.objects.new("Cam",cam_d); scene.collection.objects.link(cam); scene.camera=cam
def chunk_to_bl(p): return mathutils.Vector((p[0], -p[2], p[1]))
cam.location=chunk_to_bl((-17.0, 20.0, -10.0))
tgt=chunk_to_bl((1.0, 3.0, 1.0))
cam.rotation_euler=(tgt-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.engine='BLENDER_EEVEE'
for a in ("use_ssr","use_ssr_refraction","use_raytracing","use_bloom"):
    try: setattr(scene.eevee,a,True)
    except Exception: pass
scene.render.resolution_x=1300; scene.render.resolution_y=1000; scene.render.image_settings.file_format='PNG'
def do(): bpy.ops.render.render(write_still=True)
def render_to(p):
    scene.render.filepath=p
    try: do()
    except Exception:
        W=bpy.context.window_manager.windows[0]; A=[a for a in W.screen.areas if a.type=='VIEW_3D'][0]; R=[r for r in A.regions if r.type=='WINDOW'][0]
        with bpy.context.temp_override(window=W,area=A,region=R): do()
render_to(r"C:\tmp\channels_entrance.png")
import os
os.makedirs(BL+r"\channels",exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BL+r"\channels\channels_entrance.blend")
result={"placed":len(g.placed),"boxes":len(g.boxes),"validate":len(issues),"issues":issues}

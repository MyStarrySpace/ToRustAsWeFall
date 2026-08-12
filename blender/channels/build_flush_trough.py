import bpy, math, mathutils, sys, importlib
BL=r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender"
if BL not in sys.path: sys.path.insert(0,BL)
import spatial_grammar; importlib.reload(spatial_grammar)
from spatial_grammar import Grammar

bpy.ops.wm.read_homefile(use_empty=True)
scene=bpy.context.scene
def mat(n,c,e=None,es=0.0,r=0.8,m=0.0):
    M=bpy.data.materials.new(n); M.use_nodes=True; b=M.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value=(*c,1); b.inputs["Roughness"].default_value=r; b.inputs["Metallic"].default_value=m
    if e: b.inputs["Emission Color"].default_value=(*e,1); b.inputs["Emission Strength"].default_value=es
    return M
M_GROUND=mat("Ground",(0.14,0.14,0.16),r=0.7,m=0.3); M_TROUGH=mat("Trough",(0.09,0.10,0.12),r=0.6,m=0.35)
M_GRATE=mat("Grate",(0.08,0.08,0.09),r=0.7,m=0.3); M_PIPE=mat("Pipe",(0.2,0.19,0.18),r=0.55,m=0.55)
M_RUST=mat("Rust",(0.24,0.11,0.06),r=0.85)
M_FLOW=mat("Flow",(0.12,0.3,0.55),e=(0.3,0.55,0.95),es=1.2,r=0.15)
M_HAZ=mat("Haz",(0.8,0.6,0.05),r=0.7)

g=Grammar()

# ===== REUSABLE SET PIECE: a flush trough =====
# A walkable GROUND with a LOWERED channel cut into it; one or more PIPES pour water through the channel.
# Standing in the lowered area while it flows -> flushed out. `pipes` = list of (x,z) inflow points.
# Composable: pass a BIG trough rect + several pipes to get "one large lowered area".
def flush_trough(g, name, fx0,fx1,fz0,fz1, tx0,tx1,tz0,tz1, gy, depth, pipes, flow_axis="z"):
    # ground apron: border slabs that tile around the trough (recess pattern for a FLOOR -> no gaps)
    if tx0>fx0+0.05: g.slab_xz(name+"_gW", fx0,tx0, fz0,fz1, gy,0.3, M_GROUND)
    if tx1<fx1-0.05: g.slab_xz(name+"_gE", tx1,fx1, fz0,fz1, gy,0.3, M_GROUND)
    if tz1<fz1-0.05: g.slab_xz(name+"_gN", tx0,tx1, tz1,fz1, gy,0.3, M_GROUND)
    if tz0>fz0+0.05: g.slab_xz(name+"_gS", tx0,tx1, fz0,tz0, gy,0.3, M_GROUND)
    # lowered trough floor + side walls (open at the flow ends so water runs THROUGH)
    g.slab_xz(name+"_floor", tx0,tx1,tz0,tz1, gy-depth,0.3, M_TROUGH)
    g.box(name+"_grate", tx0+0.15,tx1-0.15, gy-depth,gy-depth+0.05, tz0+0.15,tz1-0.15, M_GRATE, "floor")
    if flow_axis=="z":   # water runs along Z -> long walls on +/-X
        g.box(name+"_wW", tx0-0.18,tx0, gy-depth,gy+0.1, tz0,tz1, M_GROUND, "wall")
        g.box(name+"_wE", tx1,tx1+0.18, gy-depth,gy+0.1, tz0,tz1, M_GROUND, "wall")
    else:                # water runs along X -> long walls on +/-Z
        g.box(name+"_wS", tx0,tx1, gy-depth,gy+0.1, tz0-0.18,tz0, M_GROUND, "wall")
        g.box(name+"_wN", tx0,tx1, gy-depth,gy+0.1, tz1,tz1+0.18, M_GROUND, "wall")
    # hazard lip painted around the trough edge (placeholder), on the apron
    g.box(name+"_hazA", tx0-0.3,tx1+0.3, gy,gy+0.04, tz0-0.3,tz0-0.1, M_HAZ, "prop")
    g.box(name+"_hazB", tx0-0.3,tx1+0.3, gy,gy+0.04, tz1+0.1,tz1+0.3, M_HAZ, "prop")
    # the water sheet in the trough (the flush)
    g.box(name+"_flow", tx0+0.2,tx1-0.2, gy-depth,gy-depth+0.08, tz0+0.2,tz1-0.2, M_FLOW, "prop")
    # pipes pouring in
    for pi,(px,pz) in enumerate(pipes):
        g.box(name+"_pipe%d"%pi, px-0.7,px+0.7, gy+0.6,gy+3.2, pz-0.7,pz+0.7, M_PIPE, "structure")
        g.box(name+"_band%d"%pi, px-0.78,px+0.78, gy+1.4,gy+1.7, pz-0.78,pz+0.78, M_RUST, "structure")
        g.box(name+"_mouth%d"%pi, px-0.55,px+0.55, gy-depth+0.1,gy+0.7, pz-0.55,pz+0.55, M_PIPE, "structure")

# --- DEMO A: a single pipe + a narrow flush channel crossing the path (flow along Z) ---
flush_trough(g, "A", 0,10, -5,5, 4.2,6.0, -4.5,4.5, gy=0.0, depth=0.7,
             pipes=[(5.1,4.6)], flow_axis="z")

# --- DEMO B: several pipes + lowered areas JOINED into one large lowered basin to cross ---
flush_trough(g, "B", 13,27, -5,5, 15.0,24.0, -4.5,4.5, gy=0.0, depth=0.8,
             pipes=[(16.5,4.6),(19.5,4.6),(22.5,4.6)], flow_axis="z")

issues=g.validate()
print("=== VALIDATE: %d ==="%len(issues))
for s in issues[:14]: print("  "+s)
g.emit(scene)

def light(n,gx,gy,gz,col,en,rng=26.0):
    d=bpy.data.lights.new(n,'POINT'); d.color=col; d.energy=en; d.shadow_soft_size=2.0
    try: d.use_custom_distance=True; d.cutoff_distance=rng
    except Exception: pass
    o=bpy.data.objects.new(n,d); o.location=(gx,-gz,gy); scene.collection.objects.link(o)
sun=bpy.data.lights.new("Sun",'SUN'); sun.energy=1.6; sun.color=(0.55,0.62,0.88)
so=bpy.data.objects.new("Sun",sun); so.rotation_euler=(0.9,0.2,0.6); scene.collection.objects.link(so)
light("LflowA",5,1.5,0,(0.3,0.5,1.0),120,12); light("LflowB",19.5,1.5,0,(0.3,0.5,1.0),200,18)
light("Lkey",6,6,-9,(1.0,0.6,0.4),120,40)
world=bpy.data.worlds.new("W"); scene.world=world; world.use_nodes=True
world.node_tree.nodes["Background"].inputs[0].default_value=(0.05,0.06,0.08,1)

cam_d=bpy.data.cameras.new("Cam"); cam_d.lens=32
cam=bpy.data.objects.new("Cam",cam_d); scene.collection.objects.link(cam); scene.camera=cam
def c2b(p): return mathutils.Vector((p[0],-p[2],p[1]))
cam.location=c2b((2,11,-15)); cam.rotation_euler=(c2b((14,0,1))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.engine='BLENDER_EEVEE'
for at in ("use_ssr","use_ssr_refraction","use_raytracing","use_bloom"):
    try: setattr(scene.eevee,at,True)
    except Exception: pass
scene.render.resolution_x=1400; scene.render.resolution_y=900; scene.render.image_settings.file_format='PNG'
scene.render.filepath=r"C:\tmp\flush_trough.png"
def do(): bpy.ops.render.render(write_still=True)
try: do()
except Exception:
    W=bpy.context.window_manager.windows[0]; A=[a for a in W.screen.areas if a.type=='VIEW_3D'][0]; Rg=[r for r in A.regions if r.type=='WINDOW'][0]
    with bpy.context.temp_override(window=W,area=A,region=Rg): do()
import os
os.makedirs(BL+r"\channels",exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BL+r"\channels\flush_trough_demo.blend")
result={"placed":len(g.placed),"boxes":len(g.boxes),"validate":len(issues),"issues":issues[:8]}

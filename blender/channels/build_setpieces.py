import bpy, math, mathutils, sys, importlib
BL=r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender"
if BL not in sys.path: sys.path.insert(0,BL)
import spatial_grammar; importlib.reload(spatial_grammar)
from spatial_grammar import Grammar
bpy.ops.wm.read_homefile(use_empty=True); scene=bpy.context.scene
def mat(n,c,e=None,es=0.0,r=0.8,m=0.0):
    M=bpy.data.materials.new(n); M.use_nodes=True; b=M.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value=(*c,1); b.inputs["Roughness"].default_value=r; b.inputs["Metallic"].default_value=m
    if e: b.inputs["Emission Color"].default_value=(*e,1); b.inputs["Emission Strength"].default_value=es
    return M
M_G=mat("Ground",(0.14,0.14,0.16),r=0.7,m=0.3); M_T=mat("Low",(0.09,0.10,0.12),r=0.6,m=0.35)
M_GR=mat("Grate",(0.08,0.08,0.09),r=0.7,m=0.3); M_PIPE=mat("Pipe",(0.2,0.19,0.18),r=0.55,m=0.55)
M_RUST=mat("Rust",(0.24,0.11,0.06),r=0.85); M_MID=mat("Mid",(0.17,0.16,0.18),r=0.6,m=0.4)
M_FLOW=mat("Flow",(0.12,0.3,0.55),e=(0.3,0.55,0.95),es=1.3,r=0.15)
M_HAZ=mat("Haz",(0.8,0.6,0.05),r=0.7)
M_AMBER=mat("Amber",(0.7,0.4,0.06),e=(1.0,0.55,0.1),es=3.0,r=0.4)
M_RED=mat("Red",(0.8,0.1,0.06),e=(1.0,0.12,0.05),es=4.0,r=0.5)
M_JET=mat("Jet",(0.4,0.6,0.9),e=(0.5,0.7,1.0),es=2.2,r=0.1)
g=Grammar()

# ===== SET PIECE: timed SLUICE GATE — a barrier that raises/lowers; pass on the open window =====
def sluice_gate(g, name, ox, oz, gy=0.0, gate_state=0.6):   # state 0=open(up) .. 1=closed(down)
    g.slab_xz(name+"_floor", ox-2.2,ox+2.2, oz-2.6,oz+2.6, gy,0.3, M_G)
    g.box(name+"_wW", ox-2.2,ox+2.2, gy,gy+3.4, oz-2.8,oz-2.6, M_G, "wall")
    g.box(name+"_wE", ox-2.2,ox+2.2, gy,gy+3.4, oz+2.6,oz+2.8, M_G, "wall")
    g.box(name+"_postL", ox-1.9,ox-1.6, gy,gy+3.4, oz-2.6,oz+2.6, M_MID, "wall")
    g.box(name+"_postR", ox+1.6,ox+1.9, gy,gy+3.4, oz-2.6,oz+2.6, M_MID, "wall")
    g.box(name+"_header", ox-2.0,ox+2.0, gy+3.1,gy+3.6, oz-2.6,oz+2.6, M_MID, "wall")
    gb=gy + (1.0-gate_state)*2.6                 # gate panel bottom
    g.box(name+"_gate", ox-1.55,ox+1.55, gb,gb+2.6, oz-0.18,oz+0.18, M_RUST, "structure")
    for r in range(4):
        g.box(name+"_bar%d"%r, ox-1.55,ox+1.55, gb+0.3+r*0.6,gb+0.42+r*0.6, oz-0.22,oz+0.22, M_MID, "structure")
    g.box(name+"_warn", ox-0.3,ox+0.3, gy+3.2,gy+3.4, oz-0.1,oz+0.1, M_AMBER, "prop")
    g.box(name+"_haz", ox-1.7,ox+1.7, gy,gy+0.04, oz-0.2,oz+0.2, M_HAZ, "prop")

# ===== SET PIECE: PRESSURE-PLATE BRIDGE — a held plate extends a bridge over a gap (co-op) =====
def plate_bridge(g, name, ox, oz, gy=0.0):
    g.slab_xz(name+"_near", ox-4.2,ox-1.0, oz-2.6,oz+2.6, gy,0.3, M_G)
    g.slab_xz(name+"_far",  ox+1.0,ox+4.2, oz-2.6,oz+2.6, gy,0.3, M_G)   # gap [ox-1,ox+1] open between them
    # pressure plate on the near side (held -> amber)
    g.box(name+"_plate", ox-3.1,ox-2.1, gy-0.06,gy+0.06, oz-0.9,oz+0.9, M_AMBER, "prop")
    g.box(name+"_plateRim", ox-3.3,ox-1.9, gy,gy+0.1, oz-1.1,oz+1.1, M_MID, "structure")
    # the bridge it extends across the gap (shown extended)
    g.box(name+"_bridge", ox-1.05,ox+1.05, gy-0.08,gy+0.06, oz-0.9,oz+0.9, M_GR, "structure")
    g.box(name+"_bridgeRail", ox-1.05,ox+1.05, gy+0.06,gy+0.7, oz+0.85,oz+0.95, M_MID, "structure")
    g.box(name+"_bridgeRail2",ox-1.05,ox+1.05, gy+0.06,gy+0.7, oz-0.95,oz-0.85, M_MID, "structure")
    # linkage hint: a pipe/strut from plate to the bridge mechanism
    g.box(name+"_link", ox-2.6,ox-1.0, gy+0.4,gy+0.55, oz-0.1,oz+0.1, M_PIPE, "structure")

# ===== SET PIECE: CROSS-CURRENT NARROWS — narrow catwalk with water washing across; current shoves you off =====
def current_narrows(g, name, ox, oz, gy=0.0):
    # side channels (lower, water) flank a narrow catwalk over them
    g.slab_xz(name+"_chN", ox-4.5,ox+4.5, oz+0.8,oz+3.4, gy-0.6,0.3, M_T)
    g.slab_xz(name+"_chS", ox-4.5,ox+4.5, oz-3.4,oz-0.8, gy-0.6,0.3, M_T)
    g.slab_xz(name+"_cat", ox-4.5,ox+4.5, oz-0.8,oz+0.8, gy,0.3, M_GR)   # the narrow walkway
    # the cross-current: a flow sheet washing across the catwalk in +Z + arrows
    g.box(name+"_flow", ox-4.3,ox+4.3, gy+0.31,gy+0.37, oz-0.7,oz+0.7, M_FLOW, "prop")
    for ax in (ox-3,ox-1,ox+1,ox+3):
        g.box(name+"_arrow%d"%int(ax*10), ax-0.12,ax+0.12, gy+0.32,gy+0.36, oz-0.5,oz+0.5, M_HAZ, "prop")
    # feed pipes pouring into the side channels
    g.box(name+"_pipe", ox-0.6,ox+0.6, gy+0.5,gy+3.0, oz+3.0,oz+3.6, M_PIPE, "structure")
    g.box(name+"_flowN", ox-4.3,ox+4.3, gy-0.6,gy-0.52, oz+1.0,oz+3.2, M_FLOW, "prop")
    g.box(name+"_flowS", ox-4.3,ox+4.3, gy-0.6,gy-0.52, oz-3.2,oz-1.0, M_FLOW, "prop")

# ===== SET PIECE: JET GAUNTLET — floor nozzles erupt vertical water jets on a cadence =====
def jet_gauntlet(g, name, ox, oz, gy=0.0, cols=4, rows=3):
    g.slab_xz(name+"_floor", ox-3.6,ox+3.6, oz-2.6,oz+2.6, gy,0.3, M_G)
    for c in range(cols):
        for r in range(rows):
            nx=ox-2.7+c*1.8; nz=oz-1.8+r*1.8
            g.box(name+"_noz%d_%d"%(c,r), nx-0.35,nx+0.35, gy,gy+0.06, nz-0.35,nz+0.35, M_GR, "prop")
            g.box(name+"_haz%d_%d"%(c,r), nx-0.45,nx+0.45, gy,gy+0.04, nz-0.45,nz+0.45, M_HAZ, "prop")
            if (c+r)%2==0:        # this nozzle is erupting (a tall water jet)
                g.box(name+"_jet%d_%d"%(c,r), nx-0.22,nx+0.22, gy+0.06,gy+2.8, nz-0.22,nz+0.22, M_JET, "structure")

# ---- gallery: 2x2 grid ----
sluice_gate(g, "Sluice", 0, 0)
plate_bridge(g, "Plate", 12, 0)
current_narrows(g, "Current", 0, 13)
jet_gauntlet(g, "Jets", 12, 13)

issues=g.validate()
print("=== VALIDATE: %d ==="%len(issues))
for s in issues[:14]: print("  "+s)
g.emit(scene)

def light(n,gx,gy,gz,col,en,rng=20.0):
    d=bpy.data.lights.new(n,'POINT'); d.color=col; d.energy=en; d.shadow_soft_size=2.0
    try: d.use_custom_distance=True; d.cutoff_distance=rng
    except Exception: pass
    o=bpy.data.objects.new(n,d); o.location=(gx,-gz,gy); scene.collection.objects.link(o)
sun=bpy.data.lights.new("Sun",'SUN'); sun.energy=1.7; sun.color=(0.55,0.62,0.88)
so=bpy.data.objects.new("Sun",sun); so.rotation_euler=(0.9,0.2,0.6); scene.collection.objects.link(so)
light("Ls",0,2.5,0,(1.0,0.55,0.2),120,13); light("Lp",12,2,0,(1.0,0.55,0.15),120,13)
light("Lc",0,2,13,(0.35,0.55,1.0),170,17); light("Lj",12,2.5,13,(0.45,0.65,1.0),190,17)
light("Lkey",6,9,-9,(0.9,0.75,0.6),160,55)
world=bpy.data.worlds.new("W"); scene.world=world; world.use_nodes=True
world.node_tree.nodes["Background"].inputs[0].default_value=(0.05,0.06,0.08,1)
cam_d=bpy.data.cameras.new("Cam"); cam_d.lens=33
cam=bpy.data.objects.new("Cam",cam_d); scene.collection.objects.link(cam); scene.camera=cam
def c2b(p): return mathutils.Vector((p[0],-p[2],p[1]))
cam.location=c2b((10,10,-15)); cam.rotation_euler=(c2b((20,0,1))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.engine='BLENDER_EEVEE'
for at in ("use_ssr","use_ssr_refraction","use_raytracing","use_bloom"):
    try: setattr(scene.eevee,at,True)
    except Exception: pass
scene.render.resolution_x=1300; scene.render.resolution_y=1040; scene.render.image_settings.file_format='PNG'
scene.render.filepath=r"C:\tmp\setpieces.png"
cam.location=c2b((6,17,-13)); cam.rotation_euler=(c2b((6,0,6.5))-cam.location).to_track_quat('-Z','Y').to_euler()
def do(): bpy.ops.render.render(write_still=True)
try: do()
except Exception:
    W=bpy.context.window_manager.windows[0]; A=[a for a in W.screen.areas if a.type=='VIEW_3D'][0]; Rg=[r for r in A.regions if r.type=='WINDOW'][0]
    with bpy.context.temp_override(window=W,area=A,region=Rg): do()
import os
os.makedirs(BL+r"\channels",exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BL+r"\channels\setpieces_demo.blend")
result={"placed":len(g.placed),"boxes":len(g.boxes),"validate":len(issues),"issues":issues[:8]}

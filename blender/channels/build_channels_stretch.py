import bpy, math, mathutils, sys, importlib, os
BL = r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender"
if BL not in sys.path: sys.path.insert(0, BL)
import spatial_grammar; importlib.reload(spatial_grammar)
from spatial_grammar import Grammar

bpy.ops.wm.read_homefile(use_empty=True)
scene=bpy.context.scene
def mat(n,c,e=None,es=0.0,r=0.8,m=0.0):
    M=bpy.data.materials.new(n); M.use_nodes=True; b=M.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value=(*c,1); b.inputs["Roughness"].default_value=r; b.inputs["Metallic"].default_value=m
    if e: b.inputs["Emission Color"].default_value=(*e,1); b.inputs["Emission Strength"].default_value=es
    return M
M_WALL=mat("Wall",(0.10,0.10,0.12),r=0.75,m=0.25); M_MID=mat("Mid",(0.17,0.16,0.18),r=0.6,m=0.4)
M_DECK=mat("Deck",(0.13,0.13,0.15),r=0.7,m=0.3);   M_GRATE=mat("Grate",(0.08,0.08,0.09),r=0.7,m=0.3)
M_RUST=mat("Rust",(0.24,0.11,0.06),r=0.85);        M_PIPE=mat("Pipe",(0.2,0.19,0.18),r=0.55,m=0.55)
M_RED=mat("Red",(0.9,0.12,0.07),e=(1,0.12,0.05),es=12,r=0.5)
M_PLANT=mat("Plant",(0.18,0.45,0.2),e=(0.2,0.6,0.25),es=0.6,r=0.7); M_POT=mat("Pot",(0.35,0.22,0.14),r=0.8)
M_TERM=mat("Term",(0.1,0.5,0.55),e=(0.2,0.9,1.0),es=3.0,r=0.4)
M_WATER=mat("Water",(0.02,0.05,0.08),e=(0.1,0.35,0.7),es=0.5,r=0.1)
M_FLOW=mat("Flow",(0.12,0.3,0.55),e=(0.25,0.5,0.9),es=0.7,r=0.2)
M_AMBER=mat("Amber",(0.7,0.4,0.06),e=(1.0,0.55,0.1),es=3.0,r=0.4)
M_TLOW=mat("TLow",(0.05,0.06,0.08),r=0.6,m=0.3)
M_JET=mat("Jet",(0.4,0.6,0.9),e=(0.5,0.7,1.0),es=2.0,r=0.1)

g=Grammar()
CX,CZ=0.0,0.0
# ---- ChannelsArc helix params — MUST match scripts/game/world/channels_arc.gd EXACTLY ----
A0=0.0; KTHETA=0.0907; R0=11.0; Y0=1.0; KCLIMB=0.1333; LANE_HALF=4.0; S_MAX=90.0
R_IN=R0-LANE_HALF; R_OUT=R0+LANE_HALF; DPZ=2.0
def apos(s, lane=0.0):                    # linear (s, lane) -> chunk-frame point on the helix
    ang=A0+s*KTHETA; rad=R0+lane
    return (CX+rad*math.cos(ang), Y0+s*KCLIMB, CZ+rad*math.sin(ang))
def hyaw(s): return A0+s*KTHETA + math.pi/2

# A sloped helix arc band (deck/wall) from s0..s1 across lanes [lane0,lane1]; `drop` lowers its top
# below the deck line (lowered channels / basins). Segmented finely so it tracks the climb smoothly.
def harc(name, s0, s1, lane0, lane1, thick, m, tag="floor", drop=0.0):
    L=abs(s1-s0); n=max(1,int(round(L/1.1))); lmid=(lane0+lane1)/2.0; lw=abs(lane1-lane0) or 0.05
    for k in range(n):
        sa=s0+(s1-s0)*k/n; sb=s0+(s1-s0)*(k+1)/n; smid=(sa+sb)/2.0
        cx,cy,cz=apos(smid, lmid); chord=(R0+lmid)*abs(sb-sa)*KTHETA*1.12
        g.pbox("%s_%d"%(name,k), cx, cy-drop-thick/2.0, cz, chord, thick, lw, hyaw(smid), m, tag)

# An oriented prop sitting on the deck at (s, lane): y_off = its vertical CENTRE above the deck top.
def hprop(name, s, lane, w_tan, h, w_rad, y_off, m, tag="structure"):
    cx,cy,cz=apos(s, lane); g.pbox(name, cx, cy+y_off, cz, w_tan, h, w_rad, hyaw(s), m, tag)

# Threats are RUNTIME Enemy nodes — the model bakes NO guard stand-ins (a static
# red body at a section midpoint misinforms about live threat positions).
def _guard(tag, s, deck_drop=0.0):
    pass
def _alcove(tag, s, lane):
    hprop(tag+"_alcRoof", s, lane, 2.0, 0.3, 1.3, 2.0, M_MID)
    hprop(tag+"_alcGlow", s, lane, 1.7, 0.06, 1.0, 0.04, M_TERM)
def _flure(tag, s, lane):
    hprop(tag+"_flure", s, lane, 0.5, 0.95, 0.5, 0.7, M_AMBER)

# ---- one builder per gameplay section type (spans s0..s1; lanes are radial offsets) ----
def sp_flush(tag, s0, s1):
    harc(tag+"_apIn",  s0,s1, -LANE_HALF,-0.9, 0.32, M_DECK)
    harc(tag+"_apOut", s0,s1, 0.9,LANE_HALF, 0.32, M_DECK)
    harc(tag+"_chF",   s0,s1, -0.9,0.9, 0.3, M_GRATE, drop=0.6)
    harc(tag+"_chW",   s0,s1, -0.8,0.8, 0.06, M_FLOW, "water", drop=0.28)
    hprop(tag+"_spout", (s0+s1)/2, 0.0, 0.85,1.0,0.85, 2.4, M_PIPE)
def sp_current(tag, s0, s1):
    harc(tag+"_cN",  s0,s1, 0.9,LANE_HALF, 0.3, M_TLOW, drop=0.5)
    harc(tag+"_cS",  s0,s1, -LANE_HALF,-0.9, 0.3, M_TLOW, drop=0.5)
    harc(tag+"_cat", s0,s1, -0.9,0.9, 0.3, M_GRATE)
    harc(tag+"_flow",s0,s1, -0.8,0.8, 0.05, M_FLOW, "water", drop=-0.32)
def sp_jet(tag, s0, s1):
    harc(tag+"_deck", s0,s1, -LANE_HALF,LANE_HALF, 0.34, M_DECK)
    for i in range(2):
        s=s0+(s1-s0)*(i+0.5)/2.0
        for j,lane in enumerate((-1.4,0.0,1.4)):
            # nozzle hardware only — a baked always-on jet column would LIE about
            # the wash cadence; the live jets are the runtime flood telegraphs
            hprop(tag+"_noz%d_%d"%(i,j), s, lane, 0.5,0.08,0.5, 0.05, M_GRATE)
def sp_plate(tag, s0, s1):
    sm=(s0+s1)/2.0; gw=(s1-s0)*0.28
    harc(tag+"_near", s0, sm-gw, -LANE_HALF,LANE_HALF, 0.34, M_DECK)
    harc(tag+"_far",  sm+gw, s1, -LANE_HALF,LANE_HALF, 0.34, M_DECK)
    harc(tag+"_span", sm-gw, sm+gw, -0.85,0.85, 0.22, M_GRATE)
    hprop(tag+"_plate", s0+(s1-s0)*0.16, 0.0, 1.0,0.16,1.7, 0.1, M_AMBER)
def sp_sluice(tag, s0, s1):
    harc(tag+"_deck", s0,s1, -LANE_HALF,LANE_HALF, 0.34, M_DECK)
    sm=(s0+s1)/2.0
    for nm,lane in (("postL",-LANE_HALF+0.4),("postR",LANE_HALF-0.4)):
        hprop(tag+"_"+nm, sm, lane, 0.4,3.4,0.5, 1.7, M_MID)
    hprop(tag+"_header", sm, 0.0, 0.5,0.5, 2*LANE_HALF-0.6, 3.35, M_MID)
    hprop(tag+"_gate",   sm, 0.0, 0.22,2.0, 2*LANE_HALF-1.0, 1.9, M_RUST)
    for r in range(3): hprop(tag+"_bar%d"%r, sm, 0.0, 0.28,0.12, 2*LANE_HALF-1.0, 1.2+r*0.6, M_MID)
def sp_patrol(tag, s0, s1):
    harc(tag+"_deck", s0,s1, -LANE_HALF,LANE_HALF, 0.34, M_DECK)
    sm=(s0+s1)/2.0; _guard(tag, sm); _alcove(tag, sm, LANE_HALF-0.8)
def sp_lure(tag, s0, s1):
    harc(tag+"_deck", s0,s1, -LANE_HALF,LANE_HALF, 0.34, M_DECK)
    sm=(s0+s1)/2.0; ch=(R0)*abs(s1-s0)*KTHETA*0.5
    for lane in (-LANE_HALF+0.7, LANE_HALF-0.7): hprop(tag+"_wall%d"%int(lane*10), sm, lane, ch,2.2,1.1, 1.1, M_MID)
    _guard(tag, sm); _flure(tag, s0+(s1-s0)*0.22, LANE_HALF-0.8)
def sp_basin(tag, s0, s1):
    harc(tag+"_apIn",  s0,s1, -LANE_HALF,-LANE_HALF+1.0, 0.32, M_DECK)
    harc(tag+"_apOut", s0,s1, LANE_HALF-1.0,LANE_HALF, 0.32, M_DECK)
    harc(tag+"_floor", s0,s1, -LANE_HALF+1.0,LANE_HALF-1.0, 0.3, M_TLOW, drop=0.5)
    harc(tag+"_water", s0,s1, -LANE_HALF+1.1,LANE_HALF-1.1, 0.06, M_FLOW, "water", drop=0.16)
    for i in range(2): hprop(tag+"_spout%d"%i, s0+(s1-s0)*(i+0.5)/2.0, 0.0, 0.9,1.0,0.9, 2.3, M_PIPE)
    sm=(s0+s1)/2.0; _guard(tag, sm, deck_drop=0.5); _alcove(tag, sm, LANE_HALF-0.5)
def sp_double_plate(tag, s0, s1):
    sm=(s0+s1)/2.0; gw=(s1-s0)*0.28
    harc(tag+"_near", s0, sm-gw, -LANE_HALF,LANE_HALF, 0.34, M_DECK)
    harc(tag+"_far",  sm+gw, s1, -LANE_HALF,LANE_HALF, 0.34, M_DECK)
    harc(tag+"_span", sm-gw, sm+gw, -0.8,0.8, 0.22, M_GRATE)
    for lane in (-DPZ, DPZ): hprop(tag+"_pad%d"%int(lane*10), s0+(s1-s0)*0.16, lane, 1.0,0.16,1.5, 0.1, M_AMBER)

SET_PIECE_FN={"flush":sp_flush,"current":sp_current,"jet":sp_jet,"plate":sp_plate,"sluice":sp_sluice,
              "patrol":sp_patrol,"lure":sp_lure,"basin":sp_basin,"double_plate":sp_double_plate}

# ---- the gameplay's nine sections (mirror of wash_relay_chunk.gd; s == the gameplay x) ----
SECTIONS=[("flush",6,11),("current",14,19),("jet",22,27),("plate",30,35),("sluice",38,41),
          ("patrol",46,53),("lure",56,61),("basin",64,71),("double_plate",74,79)]
CHUNK_END=84.0
# connectors fill the s-gaps so the walkway is continuous (start->first, between, last->chunk end)
bounds=[0.0]+[v for (_,a,b) in SECTIONS for v in (a,b)]+[CHUNK_END]
for i in range(0,len(bounds),2):
    a,b=bounds[i],bounds[i+1]
    if b-a>0.2: harc("Conn_%d"%i, a, b, -LANE_HALF, LANE_HALF, 0.34, M_DECK)
for si,(name,x0,x1) in enumerate(SECTIONS):
    SET_PIECE_FN[name]("S%d_%s"%(si,name), float(x0), float(x1))

# ---- threats placed at the gameplay positions (apos of each), so model + data align ----
for ai,(s,lane) in enumerate([(49.5,3.3),(67.5,3.3)]):
    _alcove("HA%d"%ai, s, lane)                 # (also drawn inside patrol/basin; this echoes the nook glow)
# ---- connect-back devices: terminal + sloperope at the chunk end, climb at the start ----
def _term(tag, s, lane):
    hprop(tag+"_term", s, lane, 0.9,1.3,0.3, 0.85, M_MID); hprop(tag+"_scr", s, lane, 0.7,0.8,0.06, 0.95, M_TERM)
def _rope(tag, s, lane):
    hprop(tag+"_post", s, lane, 0.4,2.2,0.4, 1.1, M_RUST); hprop(tag+"_line", s, lane, 0.16,4.2,0.16, -1.6, M_RUST)
_term("CBterm", CHUNK_END, 2.5); _rope("CBrope", CHUNK_END, -2.5)
_rope("CLIMB", 5.0, 2.5)                         # the dropped line's lower end at the start shelter

# ---- start shelter pool in the well centre (below the spiral) + the chunk-end overlook ----
ybot=Y0-2.0
g.slab_xz("WellFloor", CX-6.5,CX+6.5, CZ-6.5,CZ+6.5, top=ybot-0.4, thick=0.5, mat=M_WALL)
g.box("Pool", CX-5.0,CX+5.0, ybot-0.7,ybot-0.35, CZ-5.0,CZ+5.0, M_WATER, "water")
hprop("ShelterGlow", 2.0, 0.0, 3.2, 0.05, 2.0, 0.04, M_RED)   # the start-shelter rest marker (on the deck)
ytop=Y0+CHUNK_END*KCLIMB
_ox,_oy,_oz=apos(CHUNK_END+3.0, 0.0)
g.box("Overlook", _ox-7.0,_ox+7.0, _oy+0.02,_oy+0.32, _oz-1.7,_oz+1.7, M_DECK, "floor")
for zs in (-1.7,1.7):
    g.box("OvRail_%d"%int(zs*10), _ox-7.0,_ox+7.0, _oy+0.32,_oy+1.0, _oz+zs-0.06,_oz+zs+0.06, M_MID, "structure")
# central downpipe in the well + a plant by the start
g.pbox("Downpipe", CX, (ytop+ybot)/2.0, CZ, 1.6, (ytop-ybot)+4.0, 1.6, 0.0, M_PIPE)
_px,_py,_pz=apos(4.0, LANE_HALF-0.9)
g.box("StartPot", _px-0.35,_px+0.35, _py,_py+0.35, _pz-0.35,_pz+0.35, M_POT, "prop")
g.box("StartPlant", _px-0.3,_px+0.3, _py+0.35,_py+1.3, _pz-0.3,_pz+0.3, M_PLANT, "prop")

issues=g.validate()
print("=== VALIDATE: %d ==="%len(issues))
for s in issues[:14]: print("  "+s)
g.emit(scene)

# ---- TEXTURE: tile structural surfaces with the per-surface VARIATION ATLASES (cube-projected,
#      Closest+REPEAT). Each atlas is an 8x8 grid of 32px cells (gen_variation_atlases.py: per-cell
#      seeded painters + periodic Perlin wear drift), mapped world-aligned at 1m = 1 cell — every
#      metre shows a DIFFERENT tile, wrapping seamlessly at 8m. Glows / water / markers keep their
#      flat emissive look. ----
ATLAS_DIR = BL + r"\textures\atlases"
ATLAS_N = 8   # cells per atlas side — must match gen_variation_atlases.N
SURFACE_TILE = {"Deck":"deck_metal","Grate":"grate","Wall":"wall_panel","Mid":"facility_metal",
                "Rust":"rust_iron","Pipe":"facility_metal","TLow":"rust_iron","Pot":"rock"}
def tiled_mat(key, png):
    m=bpy.data.materials.new("T_"+key); m.use_nodes=True; nt=m.node_tree; nt.nodes.clear()
    out=nt.nodes.new("ShaderNodeOutputMaterial"); bsdf=nt.nodes.new("ShaderNodeBsdfPrincipled")
    # WET reflective deck (concept plate B): lower roughness + a touch of metallic so
    # the authored coloured lights glint and pool on the planks/grating instead of
    # reading matte. Metal surfaces (grate/pipe/rust) go glossier than the wood.
    metalish = key in ("Grate","Pipe","Rust","Mid")
    bsdf.inputs["Roughness"].default_value=0.24 if metalish else 0.36
    bsdf.inputs["Metallic"].default_value=0.45 if metalish else 0.16
    tex=nt.nodes.new("ShaderNodeTexImage"); tex.image=bpy.data.images.load(png)
    tex.interpolation='Closest'; tex.extension='REPEAT'
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"]); nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return m
def cube_uv(obj, tile=1.0):
    # World-aligned cube projection into the variation atlas: 1 tile-metre = 1 atlas CELL
    # (1/ATLAS_N of UV), so consecutive metres sample different cells and adjacent objects
    # stay tile-continuous (UV is a pure function of world position).
    me=obj.data
    if not me.uv_layers: me.uv_layers.new(name="UVMap")
    uv=me.uv_layers.active.data; mw=obj.matrix_world; nm=mw.to_3x3()
    span=tile*ATLAS_N
    for poly in me.polygons:
        n=nm @ poly.normal; ax=max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co=mw @ me.vertices[me.loops[li].vertex_index].co
            if ax==0: uu,vv=co.y,co.z
            elif ax==1: uu,vv=co.x,co.z
            else: uu,vv=co.x,co.y
            uv[li].uv=(uu/span, vv/span)
# ONE atlas material per surface: the per-metre variety lives in the atlas cells themselves
# (per-face-cell variant pick in UV space — the Aster-floor technique), not in per-object
# material picks, so a single big face (the sluice gate) still varies per metre.
_tilemats={}
for _b,_stem in SURFACE_TILE.items():
    _tilemats[_b]=tiled_mat(_b, ATLAS_DIR+("\\%s_var%d.png"%(_stem,ATLAS_N)))
for obj in list(scene.collection.objects):
    if obj.type!='MESH' or not obj.data.materials: continue
    base=obj.data.materials[0].name.split(".")[0]
    if base in SURFACE_TILE:
        obj.data.materials.clear(); obj.data.materials.append(_tilemats[base]); cube_uv(obj, 1.0)

def light(n,gx,gy,gz,col,en,rng=24.0):
    d=bpy.data.lights.new(n,'POINT'); d.color=col; d.energy=en; d.shadow_soft_size=2.0
    try: d.use_custom_distance=True; d.cutoff_distance=rng
    except Exception: pass
    o=bpy.data.objects.new(n,d); o.location=(gx,-gz,gy); scene.collection.objects.link(o)
sun=bpy.data.lights.new("Sun",'SUN'); sun.energy=1.7; sun.color=(0.55,0.62,0.88)
so=bpy.data.objects.new("Sun",sun); so.rotation_euler=(0.9,0.2,0.6); scene.collection.objects.link(so)
light("Lwell",0,(ytop+ybot)/2,0,(1.0,0.25,0.12),300,34)
for (nm,x0,x1) in SECTIONS:
    px,py,pz=apos((x0+x1)/2.0, 0.0); light("L_%s"%nm, px,py+1.5,pz,(0.4,0.6,1.0),60,8)
world=bpy.data.worlds.new("W"); scene.world=world; world.use_nodes=True
world.node_tree.nodes["Background"].inputs[0].default_value=(0.06,0.07,0.09,1)

cam_d=bpy.data.cameras.new("Cam"); cam_d.lens=24
cam=bpy.data.objects.new("Cam",cam_d); scene.collection.objects.link(cam); scene.camera=cam
def c2b(p): return mathutils.Vector((p[0],-p[2],p[1]))
def aim(loc,tgt): cam.location=c2b(loc); cam.rotation_euler=(c2b(tgt)-c2b(loc)).to_track_quat('-Z','Y').to_euler()
for _eng in ('BLENDER_EEVEE_NEXT','BLENDER_EEVEE','CYCLES'):   # 4.2 renamed EEVEE -> EEVEE_NEXT
    try: scene.render.engine=_eng; break
    except Exception: pass
for at in ("use_ssr","use_ssr_refraction","use_raytracing","use_bloom"):
    try: setattr(scene.eevee,at,True)
    except Exception: pass
scene.render.resolution_x=1300; scene.render.resolution_y=1040; scene.render.image_settings.file_format='PNG'
def do(): bpy.ops.render.render(write_still=True)
def render_to(p):
    scene.render.filepath=p
    try: do()
    except Exception:
        W=bpy.context.window_manager.windows[0]; A=[a2 for a2 in W.screen.areas if a2.type=='VIEW_3D'][0]; Rg=[r for r in A.regions if r.type=='WINDOW'][0]
        with bpy.context.temp_override(window=W,area=A,region=Rg): do()
aim((34, ytop+12, -34),(0,(ytop+ybot)/2,0)); render_to(r"C:\tmp\channels_stretch.png")
cam_d.lens=20; aim((0.3, ytop+26, 0.5),(0.0, ybot, 0.0)); render_to(r"C:\tmp\channels_top.png")
cam_d.lens=32; _cx,_cy,_cz=apos(17.0,0.0); aim((_cx+5,_cy+4,_cz+6),(_cx,_cy+0.5,_cz)); render_to(r"C:\tmp\channels_close.png")

os.makedirs(BL+r"\channels",exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BL+r"\channels\channels_stretch.blend")
# ---- EXPORT the textured spiral to the game (GLB, Y-up, textures embedded) ----
GLB=r"C:\Users\quest\Programming\Games\ToRustAsWeFall\to-rust-as-we-fall\resources\models\channels\channels.glb"
os.makedirs(os.path.dirname(GLB), exist_ok=True)
_meshes=[o for o in scene.collection.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in _meshes: o.select_set(True)
bpy.context.view_layer.objects.active=_meshes[0]
def _do_glb():
    bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', use_selection=True, export_apply=True,
        export_yup=True, export_cameras=False, export_lights=False, export_texcoords=True, export_normals=True)
try: _do_glb()
except Exception:
    W=bpy.context.window_manager.windows[0]; A=[a2 for a2 in W.screen.areas if a2.type=='VIEW_3D'][0]; Rg=[r for r in A.regions if r.type=='WINDOW'][0]
    with bpy.context.temp_override(window=W,area=A,region=Rg,active_object=_meshes[0],object=_meshes[0],selected_objects=_meshes): _do_glb()
result={"placed":len(g.placed),"boxes":len(g.boxes),"validate":len(issues),"meshes":len(_meshes),"glb":os.path.exists(GLB),"issues":issues[:8]}

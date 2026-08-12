"""
The Paranucleus — Act 2 boss mega-landmark.  ATOM / ORBITALS form.

Concept: *paranucleus* puns on *nucleus* -> the landmark is an ATOM: a glowing pink-red
NUCLEUS wrapped in NESTED RING-SHELLS (electron shells) with CROSSING ELLIPTICAL ORBITAL
RINGS on tilted planes (Bohr orbits). Unifies the canon: "rings within rings within rings"
= nested shells; ophanim "wheels within wheels" + "rings rotate, alignments open/close paths"
= the crossing tilted orbital rings.

Biology (According to PubMed): paranucleus = Abeta42 PENTAMER/HEXAMER globular unit that strings
into BEADED superstructures -> protofibrils (Bitan/Teplow 2003 PNAS 10.1073/pnas.222681699). So
every ring is a NECKLACE OF BEADS, and each BEAD is a HEXAGONAL BIPYRAMID = the hexamer (6-fold);
ring bead-counts are a multiple of 6 = the subunit register. Annular oligomers = ring pore-formers
(Lasagna-Reeves/Kayed 2011); concentric beta-barrels = nested shells (Durell & Guy 2021).

Accuracy vs performance: bulk detail = cheap hexamer-bead geometry + painted texture (NOT
per-monomer meshes). Accurate beta-hairpin monomer / rosette live in the asset kit for close-up
hero use only. Keeps the whole landmark ~25k verts.

NUTECH facility (GDD 11.2.3-4): a discontinued body-of-water spray plant; central reservoirs hold
LAVENDER LAKE (retrieval target) and a sealed, inaccessible FLORAL SPRING. Grey buildings +
reservoirs sit at the base, half-engulfed by the aggregate.

Visual canon (GDD 4.5): bone-white + pale-lavender, DEEP PURPLE toward the core, faint PINK-RED
nucleus (boss-exclusive), grey NUTECH base, hazy GRAY/PURPLE sky. PS2 low-poly + pixel textures.

Run:  python /c/tmp/blsend.py < blender/paranucleus/build_paranucleus.py
"""
import bpy, bmesh, math, os
from mathutils import Vector
TAU=math.tau

# ============================================================ PARAMETERS
CENTER_Z   = 11.2
SHELL_R    = [10.5, 7.2, 4.2]
SHELL_LATS = 7
BEAD_SPACE = 1.15
ORBITS     = [(0.55,0.2),(1.15,1.9),(0.8,3.4),(1.45,4.7),(0.35,5.6)]
ORBIT_R    = 11.6
ORBIT_ELL  = 0.82
CORE_STR   = 8.0
NUTECH_N   = 12
RES_R      = 4.8
TILE_SCALE = 0.5

def lerp(a,b,t): return a+(b-a)*t
def h01(n): return (math.sin(n*12.9898)*43758.5453)%1.0

# ============================================================ SCENE RESET
for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
for coll in (bpy.data.meshes,bpy.data.materials,bpy.data.lights,bpy.data.cameras,bpy.data.worlds,bpy.data.images):
    for it in list(coll):
        try: coll.remove(it)
        except Exception: pass

# ============================================================ PIXEL TEXTURES + MATERIALS
def make_pixel_tex(name, base, accent, size=16, seed=0.0):
    img=bpy.data.images.new(name,size,size,alpha=False); px=[0.0]*(size*size*4)
    for y in range(size):
        for x in range(size):
            val=1.0+(h01(x*3.1+y*7.7+seed)-0.5)*0.13; speck=h01(x*5.3+y*2.1+seed*2.0)
            col=[base[0]*val,base[1]*val,base[2]*val]
            if speck>0.90: col=[lerp(col[i],accent[i],0.6) for i in range(3)]
            idx=(y*size+x)*4
            px[idx]=min(1,max(0,col[0])); px[idx+1]=min(1,max(0,col[1])); px[idx+2]=min(1,max(0,col[2])); px[idx+3]=1.0
    img.pixels=px; img.pack(); return img

def mat_tiled(name, image, rough=0.82, metal=0.0):
    m=bpy.data.materials.new(name); m.use_nodes=True; nt=m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out=nt.nodes.new('ShaderNodeOutputMaterial'); out.location=(700,0)
    b=nt.nodes.new('ShaderNodeBsdfPrincipled'); b.location=(420,0)
    b.inputs['Roughness'].default_value=rough; b.inputs['Metallic'].default_value=metal
    tex=nt.nodes.new('ShaderNodeTexImage'); tex.location=(120,0); tex.image=image
    tex.interpolation='Closest'; tex.projection='BOX'; tex.extension='REPEAT'
    try: tex.projection_blend=0.15
    except Exception: pass
    mp=nt.nodes.new('ShaderNodeMapping'); mp.location=(-120,0); mp.inputs['Scale'].default_value=(TILE_SCALE,)*3
    tc=nt.nodes.new('ShaderNodeTexCoord'); tc.location=(-320,0)
    nt.links.new(tc.outputs['Object'],mp.inputs['Vector']); nt.links.new(mp.outputs['Vector'],tex.inputs['Vector'])
    nt.links.new(tex.outputs['Color'],b.inputs['Base Color']); nt.links.new(b.outputs[0],out.inputs[0]); return m

def mat_emission(name,color,strength):
    m=bpy.data.materials.new(name); m.use_nodes=True; nt=m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out=nt.nodes.new('ShaderNodeOutputMaterial'); e=nt.nodes.new('ShaderNodeEmission')
    e.inputs['Color'].default_value=(color[0],color[1],color[2],1.0); e.inputs['Strength'].default_value=strength
    nt.links.new(e.outputs[0],out.inputs[0]); return m

def mat_liquid(name,color,rough,emit):
    m=bpy.data.materials.new(name); m.use_nodes=True; nt=m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out=nt.nodes.new('ShaderNodeOutputMaterial'); b=nt.nodes.new('ShaderNodeBsdfPrincipled')
    b.inputs['Base Color'].default_value=(color[0],color[1],color[2],1.0); b.inputs['Roughness'].default_value=rough
    if 'Emission Color' in b.inputs: b.inputs['Emission Color'].default_value=(color[0],color[1],color[2],1.0)
    if 'Emission Strength' in b.inputs: b.inputs['Emission Strength'].default_value=emit
    nt.links.new(b.outputs[0],out.inputs[0]); return m

BONE   = mat_tiled("amyloid_bone",     make_pixel_tex("bone_tex",(0.93,0.91,0.85),(0.80,0.75,0.88),seed=1))
LAV    = mat_tiled("amyloid_lavender", make_pixel_tex("lav_tex",(0.70,0.63,0.88),(0.55,0.48,0.78),seed=7))
PURP   = mat_tiled("amyloid_purple",   make_pixel_tex("pur_tex",(0.28,0.18,0.42),(0.18,0.10,0.30),seed=3), rough=0.88)
GREY   = mat_tiled("nutech_grey",      make_pixel_tex("grey_tex",(0.43,0.45,0.50),(0.33,0.35,0.40),seed=5), rough=0.6, metal=0.2)
CORE   = mat_emission("paranucleus_core",(1.0,0.13,0.32),CORE_STR)
LAKE   = mat_liquid("lavender_lake",(0.50,0.34,0.82),0.12,0.30)    # lavender body of water (reads purple, faint glow)
FLORAL = mat_liquid("floral_spring",(0.44,0.70,0.48),0.18,0.18)    # sealed pale-green (inaccessible)
SHELL_MAT=[BONE,LAV,PURP]

# ============================================================ GEOMETRY HELPERS
def _finish(bm,name,mat):
    me=bpy.data.meshes.new(name); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth=False
    o=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(o); o.data.materials.append(mat); return o

def add_bead(bm,cx,cy,cz,r):
    # hexagonal bipyramid = the HEXAMER (6-fold), low-poly (8 verts, 12 tris)
    h=r*1.35; eq=[bm.verts.new((cx+r*math.cos(k/6*TAU),cy+r*math.sin(k/6*TAU),cz)) for k in range(6)]
    top=bm.verts.new((cx,cy,cz+h)); bot=bm.verts.new((cx,cy,cz-h))
    for k in range(6):
        j=(k+1)%6; bm.faces.new([eq[k],eq[j],top]); bm.faces.new([eq[j],eq[k],bot])

def make_beaded_ring(name, radius, bead_r, mat, spacing=BEAD_SPACE, a0=0.0, ell=1.0):
    n=max(6,int(round(TAU*radius/spacing))); n=(n//6)*6
    bm=bmesh.new()
    for k in range(n):
        a=a0+k/n*TAU; add_bead(bm, radius*math.cos(a), radius*math.sin(a)*ell, 0.0, bead_r)
    return _finish(bm,name,mat)

def make_ico(name,cx,cy,cz,r,mat,sub=2):
    bm=bmesh.new(); bmesh.ops.create_icosphere(bm,subdivisions=sub,radius=r)
    for v in bm.verts: v.co+=Vector((cx,cy,cz))
    return _finish(bm,name,mat)

def make_box_yaw(name,cx,cy,cz,sx,sy,sz,yaw,mat):
    hx,hy,hz=sx/2,sy/2,sz/2; c=math.cos(yaw); s=math.sin(yaw)
    loc=[(-hx,-hy,-hz),(hx,-hy,-hz),(hx,hy,-hz),(-hx,hy,-hz),(-hx,-hy,hz),(hx,-hy,hz),(hx,hy,hz),(-hx,hy,hz)]
    bm=bmesh.new(); vs=[bm.verts.new((cx+lx*c-ly*s,cy+lx*s+ly*c,cz+lz)) for (lx,ly,lz) in loc]
    for f in [(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]: bm.faces.new([vs[i] for i in f])
    return _finish(bm,name,mat)

def make_ring(name,z0,z1,r_in,r_out,seg,mat):
    bm=bmesh.new(); ti=[];to=[];bi=[];bo=[]
    for i in range(seg):
        a=i/seg*TAU; c=math.cos(a); s=math.sin(a)
        bi.append(bm.verts.new((r_in*c,r_in*s,z0))); bo.append(bm.verts.new((r_out*c,r_out*s,z0)))
        ti.append(bm.verts.new((r_in*c,r_in*s,z1))); to.append(bm.verts.new((r_out*c,r_out*s,z1)))
    for i in range(seg):
        j=(i+1)%seg
        bm.faces.new([bo[i],bo[j],to[j],to[i]]); bm.faces.new([bi[j],bi[i],ti[i],ti[j]])
        bm.faces.new([ti[i],ti[j],to[j],to[i]]); bm.faces.new([bo[i],bo[j],bi[j],bi[i]])
    return _finish(bm,name,mat)

def make_disc(name,cx,cy,cz,r,seg,mat):
    bm=bmesh.new(); rim=[bm.verts.new((cx+r*math.cos(i/seg*TAU),cy+r*math.sin(i/seg*TAU),cz)) for i in range(seg)]
    bm.faces.new(rim); return _finish(bm,name,mat)

def make_cyl(name,cx,cy,z0,z1,r,seg,mat):
    bm=bmesh.new(); bot=[];top=[]
    for i in range(seg):
        a=i/seg*TAU; c=math.cos(a); s=math.sin(a)
        bot.append(bm.verts.new((cx+r*c,cy+r*s,z0))); top.append(bm.verts.new((cx+r*c,cy+r*s,z1)))
    for i in range(seg):
        j=(i+1)%seg; bm.faces.new([bot[i],bot[j],top[j],top[i]])
    bm.faces.new(list(reversed(bot))); bm.faces.new(top); return _finish(bm,name,mat)

# ============================================================ NESTED RING-SHELLS
for si,R in enumerate(SHELL_R):
    mat=SHELL_MAT[si % len(SHELL_MAT)]; bead=lerp(0.55,0.40, si/max(1,len(SHELL_R)-1))
    for k in range(SHELL_LATS):
        theta=math.radians(lerp(20,160, k/(SHELL_LATS-1))); rr=R*math.sin(theta)
        if rr<0.7: continue
        o=make_beaded_ring("shell%d_lat%d"%(si,k), rr, bead, mat, a0=si*0.3+k*0.12)
        o.location=(0,0,CENTER_Z + R*math.cos(theta))

# ============================================================ CROSSING ORBITAL RINGS
for oi,(tl,yw) in enumerate(ORBITS):
    o=make_beaded_ring("orbit_%d"%oi, ORBIT_R, 0.52, BONE if oi%2==0 else LAV, spacing=1.25, ell=ORBIT_ELL)
    o.rotation_euler=(tl,0.0,yw); o.location=(0,0,CENTER_Z)

# ============================================================ NUCLEUS
make_ico("nucleus_core",0,0,CENTER_Z,1.25,CORE,sub=2)
bm=bmesh.new()
for k in range(6):
    a=k/6*TAU; add_bead(bm, 1.7*math.cos(a), 1.7*math.sin(a), 0.35*math.sin(a*2.0), 0.55)
o=_finish(bm,"nucleus_beads",CORE); o.location=(0,0,CENTER_Z)

# ============================================================ NUTECH FACILITY BASE (half-engulfed)
for b in range(NUTECH_N):
    a=b/NUTECH_N*TAU+0.3; dist=lerp(6.5, SHELL_R[0]+1.0, h01(b*1.3))
    w=lerp(1.8,3.6,h01(b*2.1)); d=lerp(2.0,3.4,h01(b*0.9)); hh=lerp(2.4,6.0,h01(b*3.7))
    make_box_yaw("nutech_%d"%b, dist*math.cos(a), dist*math.sin(a), hh/2, w,d,hh, a+math.pi/2, GREY)

# ============================================================ CENTRAL RESERVOIRS: LAVENDER LAKE + sealed FLORAL SPRING
make_ring("reservoir_wall",0.0,1.5,RES_R-0.55,RES_R,32,GREY)
make_disc("lavender_lake_surface",0,0,1.22,RES_R-0.65,32,LAKE)
for t in range(3):                                   # NUTECH feed tanks around the lake
    a=t/3*TAU+0.5; tx=(RES_R+1.3)*math.cos(a); ty=(RES_R+1.3)*math.sin(a)
    make_cyl("res_tank_%d"%t,tx,ty,0.0,lerp(2.6,3.8,h01(t*2.2)),0.85,12,GREY)
fx,fy=(RES_R+3.4)*math.cos(2.2),(RES_R+3.4)*math.sin(2.2)   # Floral Spring: sealed, inaccessible
make_cyl("floral_spring_tank",fx,fy,0.0,3.0,1.5,14,GREY)
make_disc("floral_spring_cap",fx,fy,3.06,1.4,14,FLORAL)

# ============================================================ WORLD + LIGHT
w=bpy.data.worlds.new("Sky"); bpy.context.scene.world=w; w.use_nodes=True; wnt=w.node_tree
for n in list(wnt.nodes): wnt.nodes.remove(n)
wout=wnt.nodes.new('ShaderNodeOutputWorld'); wbg=wnt.nodes.new('ShaderNodeBackground')
wbg.inputs['Color'].default_value=(0.34,0.29,0.42,1.0); wbg.inputs['Strength'].default_value=0.75
wnt.links.new(wbg.outputs[0],wout.inputs[0])
def add_sun(name,loc,tgt,e):
    l=bpy.data.lights.new(name,'SUN'); l.energy=e
    o=bpy.data.objects.new(name,l); bpy.context.scene.collection.objects.link(o); o.location=loc
    o.rotation_euler=(Vector(tgt)-Vector(loc)).to_track_quat('-Z','Y').to_euler()
add_sun("Key",(34,-26,44),(0,0,CENTER_Z),2.6); add_sun("Fill",(-30,22,26),(0,0,CENTER_Z),1.1)

# ============================================================ RENDER + SAVE + EXPORT
sc=bpy.context.scene
try: sc.render.engine='BLENDER_EEVEE_NEXT'
except TypeError:
    sc.render.engine='CYCLES'
    try: sc.cycles.samples=24
    except Exception: pass
sc.render.resolution_x=1280; sc.render.resolution_y=960; sc.render.image_settings.file_format='PNG'
try: sc.view_settings.view_transform='AgX'
except Exception: pass
cam_data=bpy.data.cameras.new("Cam"); cam=bpy.data.objects.new("Cam",cam_data)
bpy.context.scene.collection.objects.link(cam); bpy.context.scene.camera=cam
def render_from(loc,tgt,lens,path):
    cam.location=loc; cam.data.lens=lens
    cam.rotation_euler=(Vector(tgt)-Vector(loc)).to_track_quat('-Z','Y').to_euler()
    sc.render.filepath=path; bpy.ops.render.render(write_still=True)
render_from((34,-34,17),(0,0,CENTER_Z),40,r"C:\tmp\paranucleus_preview.png")
# reservoir cutaway: hide the aggregate rings to reveal the NUTECH interior + LAVENDER LAKE
for o in bpy.data.objects:
    if o.name.startswith(('shell','orbit','nucleus_beads')): o.hide_render=True
render_from((15,-21,8),(0,0,2.6),40,r"C:\tmp\paranucleus_reservoir.png")
for o in bpy.data.objects: o.hide_render=False

os.makedirs(r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\paranucleus",exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\paranucleus\paranucleus.blend")
out_dir=r"C:\Users\quest\Programming\Games\ToRustAsWeFall\to-rust-as-we-fall\resources\models\paranucleus"; os.makedirs(out_dir,exist_ok=True)
for o in bpy.data.objects: o.select_set(o.type=='MESH')
meshes=[o for o in bpy.data.objects if o.type=='MESH']
if meshes: bpy.context.view_layer.objects.active=meshes[0]
bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir,"paranucleus.glb"), export_format='GLB',
    use_selection=True, export_apply=True, export_yup=True, export_cameras=False, export_lights=False)
tv=sum(len(o.data.vertices) for o in meshes)
print("PARANUCLEUS_ATOM shells=%d orbits=%d objects=%d verts=%d" % (len(SHELL_R),len(ORBITS),len(bpy.data.objects),tv))

"""
Paranucleus BIOLOGICAL ASSET KIT — accurate hero geometry for close-up use only.

Chain (According to PubMed): Abeta42 MONOMER (beta-hairpin) -> PARANUCLEUS (pentamer/hexamer
= 5-6 hairpins around a central pore, a small beta-barrel / annular oligomer) -> BEADED
SUPERSTRUCTURE (paranuclei strung together) -> protofibril. Bitan/Teplow 2003 PNAS
10.1073/pnas.222681699; annular pore-formers Lasagna-Reeves/Kayed 2011; concentric beta-barrels
Durell & Guy 2021.

These are the HERO assets: real 3D beta-hairpin ribbons, used only for reservoir-chamber /
scripted close-ups. The LANDMARK bulk uses cheap hexamer-bead geometry (build_paranucleus.py) --
never instance these thousands of times.

Row rendered L->R:  monomer | pentamer | hexamer | beaded protofibril (3 paranuclei).

Run:  python /c/tmp/blsend.py < blender/paranucleus/build_bio_assets.py
"""
import bpy, bmesh, math
from mathutils import Vector
TAU=math.tau

# ============================================================ RESET
for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
for coll in (bpy.data.meshes,bpy.data.materials,bpy.data.lights,bpy.data.cameras,bpy.data.worlds):
    for it in list(coll):
        try: coll.remove(it)
        except Exception: pass

def matp(name,color,rough=0.6,emit=0.0):
    m=bpy.data.materials.new(name); m.use_nodes=True; nt=m.node_tree
    for n in list(nt.nodes): nt.nodes.remove(n)
    out=nt.nodes.new('ShaderNodeOutputMaterial'); b=nt.nodes.new('ShaderNodeBsdfPrincipled')
    b.inputs['Base Color'].default_value=(color[0],color[1],color[2],1.0); b.inputs['Roughness'].default_value=rough
    if emit>0 and 'Emission Color' in b.inputs:
        b.inputs['Emission Color'].default_value=(color[0],color[1],color[2],1.0); b.inputs['Emission Strength'].default_value=emit
    nt.links.new(b.outputs[0],out.inputs[0]); return m

LAV  = matp("mono_lavender",(0.68,0.60,0.88),0.55)
BONE = matp("mono_bone",(0.92,0.90,0.85),0.6)
CORE = matp("pore_core",(1.0,0.30,0.42),0.4,emit=4.0)

def _finish(bm,name,mat):
    me=bpy.data.meshes.new(name); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth=False
    o=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(o); o.data.materials.append(mat); return o

# ---- beta-hairpin centerline: strand up, semicircle turn, strand down (in local XZ plane) ----
def hairpin_pts(s=0.8, H=3.0, sseg=6, tseg=6):
    pts=[]
    for i in range(sseg): pts.append((-s,0.0,H*i/(sseg-1)))                 # strand 1 up
    for i in range(1,tseg): a=math.pi-math.pi*i/tseg; pts.append((s*math.cos(a),0.0,H+s*math.sin(a)))  # turn
    for i in range(sseg): pts.append(( s,0.0,H*(1-i/(sseg-1))))             # strand 2 down
    return pts

def make_monomer(name, mat, s=0.8, H=3.0, rw=0.52):
    pts=hairpin_pts(s,H); N=len(pts); bm=bmesh.new(); L=[];R=[]
    for i,p in enumerate(pts):
        if i==0: t=(pts[1][0]-p[0],0,pts[1][2]-p[2])
        elif i==N-1: t=(p[0]-pts[-2][0],0,p[2]-pts[-2][2])
        else: t=(pts[i+1][0]-pts[i-1][0],0,pts[i+1][2]-pts[i-1][2])
        nx,nz=-t[2],t[0]; d=math.hypot(nx,nz) or 1; nx/=d; nz/=d
        w=rw
        if i==N-2: w=rw*1.9          # arrow base (beta-strand cartoon points at the C-terminus)
        if i==N-1: w=rw*0.08         # arrow tip
        L.append(bm.verts.new((p[0]+nx*w/2,0.0,p[2]+nz*w/2)))
        R.append(bm.verts.new((p[0]-nx*w/2,0.0,p[2]-nz*w/2)))
    for i in range(N-1): bm.faces.new([L[i],R[i],R[i+1],L[i+1]])
    return _finish(bm,name,mat)

def place_copy(src, loc, rotz):
    d=src.copy(); d.data=src.data.copy(); bpy.context.scene.collection.objects.link(d)
    d.location=loc; d.rotation_euler=(0,0,rotz); return d

def rosette(src, n, R, cx, cy, cz=0.0, pore_glow=True):
    for k in range(n):
        a=k/n*TAU
        place_copy(src,(cx+R*math.cos(a),cy+R*math.sin(a),cz), a+math.pi/2)
    if pore_glow:
        bm=bmesh.new(); bmesh.ops.create_icosphere(bm,subdivisions=1,radius=0.35)
        for v in bm.verts: v.co+=Vector((cx,cy,cz+1.4))
        _finish(bm,"pore_%.1f_%.1f"%(cx,cy),CORE)

# ============================================================ THE KIT (row L->R)
mono = make_monomer("monomer", BONE); mono.location=(-9.5,0,0)                 # 1) single monomer
srcL = make_monomer("_srcL", LAV); srcL.location=(0,0,-50)                     # hidden template (lavender)
rosette(srcL, 5, 1.15, -3.5, 0)                                               # 2) pentamer
rosette(srcL, 6, 1.30,  3.0, 0)                                               # 3) hexamer
for i,(dx,dy) in enumerate([(9.5,0),(12.6,1.1),(15.6,0.2)]):                  # 4) beaded protofibril
    rosette(srcL, 6, 1.25, dx, dy, pore_glow=(i==0))

# ============================================================ WORLD / LIGHT / CAMERA / RENDER
w=bpy.data.worlds.new("W"); bpy.context.scene.world=w; w.use_nodes=True; wnt=w.node_tree
for n in list(wnt.nodes): wnt.nodes.remove(n)
o_=wnt.nodes.new('ShaderNodeOutputWorld'); bg=wnt.nodes.new('ShaderNodeBackground')
bg.inputs['Color'].default_value=(0.045,0.05,0.07,1.0); bg.inputs['Strength'].default_value=0.6
wnt.links.new(bg.outputs[0],o_.inputs[0])
def sun(nm,loc,tgt,e):
    l=bpy.data.lights.new(nm,'SUN'); l.energy=e; o=bpy.data.objects.new(nm,l); bpy.context.scene.collection.objects.link(o)
    o.location=loc; o.rotation_euler=(Vector(tgt)-Vector(loc)).to_track_quat('-Z','Y').to_euler()
sun("Key",(6,-14,12),(3,0,2),3.0); sun("Fill",(-10,-8,6),(0,0,2),1.3)
cam=bpy.data.cameras.new("C"); co=bpy.data.objects.new("C",cam); bpy.context.scene.collection.objects.link(co)
co.data.lens=34; co.location=(3.0,-30,12.5); co.rotation_euler=(Vector((3,0,1.3))-Vector(co.location)).to_track_quat('-Z','Y').to_euler()
bpy.context.scene.camera=co
sc=bpy.context.scene
try: sc.render.engine='BLENDER_EEVEE_NEXT'
except TypeError: sc.render.engine='CYCLES'
sc.render.resolution_x=1600; sc.render.resolution_y=780; sc.render.image_settings.file_format='PNG'
try: sc.view_settings.view_transform='AgX'
except Exception: pass
sc.render.filepath=r"C:\tmp\paranucleus_bio_assets.png"; bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\paranucleus\bio_assets.blend")
print("BIO_ASSETS objects=%d verts=%d" % (len(bpy.data.objects), sum(len(o.data.vertices) for o in bpy.data.objects if o.type=='MESH')))

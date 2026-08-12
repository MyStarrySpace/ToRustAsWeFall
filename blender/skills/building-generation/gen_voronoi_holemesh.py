"""
Standalone ORGANIC GENERATOR: Voronoi hole-mesh (cellular web).

The membrane-pore / basement-membrane / cell-wall look: a plane seeded with points ->
Voronoi cells -> the cell EDGES thickened into a web of struts, with actual HOLES where the
cells are. Optionally MERGE cells (drop edges) with a falloff from the centre, so cells
fuse into bigger openings further out.

Two LODs from the SAME params:
  build_holemesh(...)      -> NEAR: real 3D strut web (raised borders, holes).
  build_holemesh_far(...)  -> FAR : a single flat plane with a Voronoi-edge SHADER, holes as
                                    alpha. One quad, no geometry cost.

No SciPy needed: Delaunay via mathutils.geometry.delaunay_2d_cdt, Voronoi = its dual
(circumcenters of adjacent triangles).

Reusable: call the build_* functions from any scene. Running this file renders a demo
(near vs far, + a merged-disc variant) to C:\\tmp and saves the .blend.

Run:  python /c/tmp/blsend.py < blender/skills/building-generation/gen_voronoi_holemesh.py
"""
import bpy, bmesh, math
from mathutils import Vector
from mathutils.geometry import delaunay_2d_cdt

def _h(n): return (math.sin(n*127.13)*43758.5453) % 1.0
def _smooth(t): t=max(0.0,min(1.0,t)); return t*t*(3-2*t)

# ============================================================ VORONOI CORE
def _seeds(size, n, seed=0.0, jitter=0.8):
    step=2*size/n; out=[]
    for i in range(n):
        for j in range(n):
            jx=(_h(i*12.9+j*7.3+seed)-0.5)*step*jitter
            jy=(_h(i*3.1+j*19.7+seed*2.0)-0.5)*step*jitter
            out.append((-size+(i+0.5)*step+jx, -size+(j+0.5)*step+jy))
    return out

def _circum(a,b,c):
    ax,ay=a; bx,by=b; cx,cy=c
    d=2*(ax*(by-cy)+bx*(cy-ay)+cx*(ay-by))
    if abs(d)<1e-9: return None
    a2=ax*ax+ay*ay; b2=bx*bx+by*by; c2=cx*cx+cy*cy
    return ((a2*(by-cy)+b2*(cy-ay)+c2*(ay-by))/d, (a2*(cx-bx)+b2*(ax-cx)+c2*(bx-ax))/d)

def voronoi_edges(size, density=7, seed=0.0):
    """Return a list of ((x0,y0),(x1,y1)) Voronoi edge segments in a 2*size square."""
    seeds=_seeds(size, density, seed)
    vin=[Vector(p) for p in seeds]
    res=delaunay_2d_cdt(vin, [], [], 0, 1e-5)
    vout, faces = res[0], res[2]
    cc=[]
    for f in faces:
        if len(f)!=3: cc.append(None); continue
        a,b,c=(vout[f[0]].x,vout[f[0]].y),(vout[f[1]].x,vout[f[1]].y),(vout[f[2]].x,vout[f[2]].y)
        cc.append(_circum(a,b,c))
    emap={}
    for ti,f in enumerate(faces):
        if len(f)!=3: continue
        for k in range(3):
            e=tuple(sorted((f[k],f[(k+1)%3]))); emap.setdefault(e,[]).append(ti)
    lim=size*1.15; edges=[]
    for e,tris in emap.items():
        if len(tris)==2 and cc[tris[0]] and cc[tris[1]]:
            p0,p1=cc[tris[0]],cc[tris[1]]
            if abs(p0[0])<=lim and abs(p0[1])<=lim and abs(p1[0])<=lim and abs(p1[1])<=lim:
                edges.append((p0,p1))
    return edges

def _in_shape(p, size, shape):
    if shape=='disc': return math.hypot(p[0],p[1])<=size
    return abs(p[0])<=size and abs(p[1])<=size

# ============================================================ NEAR: 3D strut web
def _add_strut(bm, p0, p1, w, h, z0=0.0, ext=0.0):
    dx=p1[0]-p0[0]; dy=p1[1]-p0[1]; L=math.hypot(dx,dy)
    if L<1e-6: return
    ux,uy=dx/L,dy/L
    if ext: p0=(p0[0]-ux*ext,p0[1]-uy*ext); p1=(p1[0]+ux*ext,p1[1]+uy*ext)
    px,py=-uy*w/2, ux*w/2
    def V(x,y,z): return bm.verts.new((x,y,z))
    a0=V(p0[0]+px,p0[1]+py,z0); b0=V(p0[0]-px,p0[1]-py,z0)
    a1=V(p1[0]+px,p1[1]+py,z0); b1=V(p1[0]-px,p1[1]-py,z0)
    a0t=V(p0[0]+px,p0[1]+py,z0+h); b0t=V(p0[0]-px,p0[1]-py,z0+h)
    a1t=V(p1[0]+px,p1[1]+py,z0+h); b1t=V(p1[0]-px,p1[1]-py,z0+h)
    bm.faces.new([a0,b0,b1,a1]); bm.faces.new([a0t,a1t,b1t,b0t])
    bm.faces.new([a0,a1,a1t,a0t]); bm.faces.new([b0,b0t,b1t,b1])
    bm.faces.new([a0,a0t,b0t,b0]); bm.faces.new([a1,b1,b1t,a1t])

def _add_node(bm, p, r, h, z0=0.0):
    def V(x,y,z): return bm.verts.new((x,y,z))
    c=[V(p[0]-r,p[1]-r,z0),V(p[0]+r,p[1]-r,z0),V(p[0]+r,p[1]+r,z0),V(p[0]-r,p[1]+r,z0),
       V(p[0]-r,p[1]-r,z0+h),V(p[0]+r,p[1]-r,z0+h),V(p[0]+r,p[1]+r,z0+h),V(p[0]-r,p[1]+r,z0+h)]
    for f in [(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]: bm.faces.new([c[i] for i in f])

def build_holemesh(name="holemesh", size=6.0, density=7, thickness=0.28, height=0.5,
                   merge=0.0, merge_start=0.5, shape='square', seed=0.0, mat=None):
    """NEAR LOD: one continuous, WELDED organic Voronoi web with real holes (built from the cell polygons
    via the wireframe operator -- no overlapping struts, no joint artifacts). merge (0..1) fuses cells past
    merge_start (fraction of size) into larger openings."""
    seeds=_seeds(size, density, seed)
    vin=[Vector(p) for p in seeds]
    res=delaunay_2d_cdt(vin, [], [], 0, 1e-5)
    vout, faces = res[0], res[2]
    cc=[None]*len(faces)
    for ti,f in enumerate(faces):
        if len(f)==3:
            cc[ti]=_circum((vout[f[0]].x,vout[f[0]].y),(vout[f[1]].x,vout[f[1]].y),(vout[f[2]].x,vout[f[2]].y))
    vtri={}
    for ti,f in enumerate(faces):
        if len(f)==3:
            for vi in f: vtri.setdefault(vi,[]).append(ti)
    lim=size*1.05
    bm=bmesh.new(); ccv={}
    def getv(ti):
        v=ccv.get(ti)
        if v is None: v=bm.verts.new((cc[ti][0],cc[ti][1],0.0)); ccv[ti]=v
        return v
    for vi,tris in vtri.items():                                    # one Voronoi CELL per seed = ordered ring of circumcenters
        tv=[ti for ti in tris if cc[ti]]
        if len(tv)<3: continue
        sx,sy=vout[vi].x,vout[vi].y
        if any(abs(cc[ti][0])>lim or abs(cc[ti][1])>lim for ti in tv): continue   # drop unbounded boundary cells
        if not _in_shape((sx,sy), size-thickness, shape): continue
        if merge>0:
            d=math.hypot(sx,sy)/size
            if d>merge_start and _h(vi*5.31+seed*3.0) < _smooth((d-merge_start)/(1.0-merge_start))*merge: continue
        tv.sort(key=lambda ti: math.atan2(cc[ti][1]-sy, cc[ti][0]-sx))
        try: bm.faces.new([getv(ti) for ti in tv])                  # shared verts -> a proper welded planar subdivision
        except Exception: pass
    if bm.faces:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bmesh.ops.wireframe(bm, faces=bm.faces[:], thickness=thickness, offset=0.0,
                            use_replace=True, use_boundary=True, use_even_offset=True, use_relative_offset=False)
        if height>0 and bm.faces:
            bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=height)
    me=bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for pf in me.polygons: pf.use_smooth=False
    o=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(o)
    if mat: o.data.materials.append(mat)
    return o

# ============================================================ FAR: flat plane + Voronoi shader impostor
def build_holemesh_far(name="holemesh_far", size=6.0, density=7, thickness=0.28, base=(0.7,0.66,0.5)):
    bm=bmesh.new()
    v=[bm.verts.new((-size,-size,0)),bm.verts.new((size,-size,0)),bm.verts.new((size,size,0)),bm.verts.new((-size,size,0))]
    bm.faces.new(v); me=bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(o)
    m=bpy.data.materials.new(name+"_mat"); m.use_nodes=True; nt=m.node_tree
    for attr,val in (('blend_method','CLIP'),('surface_render_method','DITHERED'),('shadow_method','CLIP')):
        try: setattr(m,attr,val)
        except Exception: pass
    for n in list(nt.nodes): nt.nodes.remove(n)
    out=nt.nodes.new('ShaderNodeOutputMaterial'); out.location=(700,0)
    bsdf=nt.nodes.new('ShaderNodeBsdfPrincipled'); bsdf.location=(460,0)
    bsdf.inputs['Base Color'].default_value=(base[0],base[1],base[2],1.0); bsdf.inputs['Roughness'].default_value=0.8
    tc=nt.nodes.new('ShaderNodeTexCoord'); tc.location=(-400,0)
    vor=nt.nodes.new('ShaderNodeTexVoronoi'); vor.location=(-180,0)
    vor.feature='DISTANCE_TO_EDGE'; vor.inputs['Scale'].default_value=float(density)   # ~density cells across the 0..1 plane
    mr=nt.nodes.new('ShaderNodeMapRange'); mr.location=(80,-150)
    mr.inputs['From Min'].default_value=0.0; mr.inputs['From Max'].default_value=max(0.02, thickness*density/(4.0*size))
    mr.inputs['To Min'].default_value=1.0; mr.inputs['To Max'].default_value=0.0   # near-edge -> 1 (opaque strut), interior -> 0 (hole)
    nt.links.new(tc.outputs['Generated'], vor.inputs['Vector'])
    nt.links.new(vor.outputs['Distance'], mr.inputs['Value'])
    nt.links.new(mr.outputs['Result'], bsdf.inputs['Alpha'])
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    o.data.materials.append(m); return o

# ============================================================ DEMO
if __name__=="__main__" or True:
    for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
    for c in (bpy.data.meshes,bpy.data.materials,bpy.data.lights,bpy.data.cameras,bpy.data.worlds):
        for it in list(c):
            try: c.remove(it)
            except Exception: pass
    def mat(name,col,rough=0.75):
        m=bpy.data.materials.new(name); m.use_nodes=True; b=m.node_tree.nodes.get('Principled BSDF')
        b.inputs['Base Color'].default_value=(col[0],col[1],col[2],1.0); b.inputs['Roughness'].default_value=rough; return m
    MEMB=mat("membrane",(0.72,0.67,0.52))
    a=build_holemesh("near_square", size=6, density=8, thickness=0.14, height=0.22, mat=MEMB);           a.location=(-14,0,0)
    b=build_holemesh("near_disc_merged", size=6, density=9, thickness=0.13, height=0.22, merge=0.9, merge_start=0.35, shape='disc', mat=MEMB); b.location=(0,0,0)
    c=build_holemesh_far("far_impostor", size=6, density=8, thickness=0.14, base=(0.72,0.67,0.52));     c.location=(14,0,0)
    # world/light/cam
    w=bpy.data.worlds.new("W"); bpy.context.scene.world=w; w.use_nodes=True
    w.node_tree.nodes['Background'].inputs['Color'].default_value=(0.05,0.055,0.07,1.0)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value=0.6
    def sun(loc,tgt,e):
        l=bpy.data.lights.new("S",'SUN'); l.energy=e; o=bpy.data.objects.new("S",l); bpy.context.scene.collection.objects.link(o)
        o.location=loc; o.rotation_euler=(Vector(tgt)-Vector(loc)).to_track_quat('-Z','Y').to_euler()
    sun((6,-10,16),(0,0,0),3.2); sun((-12,8,10),(0,0,0),1.2)
    cam=bpy.data.cameras.new("C"); co=bpy.data.objects.new("C",cam); bpy.context.scene.collection.objects.link(co)
    co.data.lens=38; co.location=(0.5,-4,44); co.rotation_euler=(Vector((0.5,0,0))-Vector(co.location)).to_track_quat('-Z','Y').to_euler()
    bpy.context.scene.camera=co
    sc=bpy.context.scene
    try: sc.render.engine='BLENDER_EEVEE_NEXT'
    except TypeError: sc.render.engine='CYCLES'
    sc.render.resolution_x=1600; sc.render.resolution_y=540; sc.render.image_settings.file_format='PNG'
    try: sc.view_settings.view_transform='AgX'
    except Exception: pass
    sc.render.filepath=r"C:\tmp\gen_voronoi_demo.png"; bpy.ops.render.render(write_still=True)
    import os
    os.makedirs(r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\generators",exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\generators\gen_voronoi_holemesh.blend")
    tv=sum(len(o.data.vertices) for o in bpy.data.objects if o.type=='MESH')
    print("VORONOI_DEMO objects=%d verts=%d" % (len(bpy.data.objects), tv))

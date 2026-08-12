"""
Standalone ORGANIC GENERATOR: blobby mass-of-spheres (amyloid aggregate / soft biological cluster).

NEAR: clustered METABALLS polygonised into one lumpy blob mesh (spheres fuse into a soft mass).
FAR : a flat plane carrying a lumpy blob ALPHA texture (silhouette only) -- the impostor.
Both from the SAME params, so a distant blob is one textured quad instead of a mesh.

Params: count, cluster_r, size range, resolution (metaball detail), squash, seed.

Reusable: call build_blob_mass(...) / build_blob_far(...) from any scene. Running this file
renders a near-vs-far demo to C:\\tmp and saves the .blend.

Run:  python /c/tmp/blsend.py < blender/skills/building-generation/gen_blob_mass.py
"""
import bpy, bmesh, math
from mathutils import Vector
TAU=math.tau
def _h(n): return (math.sin(n*127.13)*43758.5453)%1.0
def lerp(a,b,t): return a+(b-a)*t

def _cluster_pts(count, cluster_r, size_min, size_max, squash, seed):
    pts=[]
    for i in range(count):
        r=cluster_r*(_h(i*1.31+seed)**0.5)            # sqrt -> denser toward centre
        th=_h(i*3.77+seed*2.0)*TAU; ph=math.acos(2*_h(i*5.13+seed*3.0)-1)
        pts.append((r*math.sin(ph)*math.cos(th), r*math.sin(ph)*math.sin(th), r*math.cos(ph)*squash,
                    lerp(size_min,size_max,_h(i*7.91+seed*4.0))))
    return pts

# ============================================================ NEAR: metaball blob -> mesh
def build_blob_mass(name="blob", count=16, cluster_r=3.0, size_min=1.3, size_max=2.3,
                    resolution=0.32, squash=0.75, seed=0.0, mat=None, faceted=True):
    mb=bpy.data.metaballs.new(name); mb.resolution=resolution; mb.render_resolution=resolution
    ob=bpy.data.objects.new(name+"_mb", mb); bpy.context.scene.collection.objects.link(ob)
    for (x,y,z,rad) in _cluster_pts(count,cluster_r,size_min,size_max,squash,seed):
        el=mb.elements.new(); el.co=(x,y,z); el.radius=rad
    bpy.context.view_layer.update()
    deps=bpy.context.evaluated_depsgraph_get()
    me=bpy.data.meshes.new_from_object(ob.evaluated_get(deps))
    bpy.data.objects.remove(ob, do_unlink=True)
    if faceted:
        for p in me.polygons: p.use_smooth=False
    out=bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(out)
    if mat: out.data.materials.append(mat)
    return out

# ============================================================ FAR: flat plane + blob alpha impostor
def build_blob_far(name="blob_far", plane=4.2, count=16, cluster_r=3.0, size_min=1.3, size_max=2.3,
                   squash=0.75, seed=0.0, base=(0.6,0.55,0.72), res=72, upright=True):
    pts=_cluster_pts(count,cluster_r,size_min,size_max,squash,seed)
    cen=[(x,z,rad) for (x,y,z,rad) in pts]   # silhouette uses x (across) and z (up, squashed)
    img=bpy.data.images.new(name+"_tex", res, res, alpha=True); px=[0.0]*(res*res*4)
    span=plane*2.0
    for iy in range(res):
        for ix in range(res):
            wx=(ix/(res-1)-0.5)*span; wy=(iy/(res-1)-0.5)*span
            field=0.0
            for (cx,cy,rad) in cen: field+=math.exp(-(((wx-cx)**2+(wy-cy)**2)/(rad*rad))*2.0)
            a=1.0 if field>0.55 else 0.0
            k=(iy*res+ix)*4; px[k]=base[0]; px[k+1]=base[1]; px[k+2]=base[2]; px[k+3]=a
    img.pixels=px; img.pack()
    bm=bmesh.new()
    v=[bm.verts.new((-plane,-plane,0)),bm.verts.new((plane,-plane,0)),bm.verts.new((plane,plane,0)),bm.verts.new((-plane,plane,0))]
    bm.faces.new(v); me=bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(o)
    if upright: o.rotation_euler=(math.pi/2,0,0)
    m=bpy.data.materials.new(name+"_mat"); m.use_nodes=True
    for attr,val in (('blend_method','CLIP'),('surface_render_method','DITHERED')):
        try: setattr(m,attr,val)
        except Exception: pass
    nt=m.node_tree; b=nt.nodes.get('Principled BSDF')
    tex=nt.nodes.new('ShaderNodeTexImage'); tex.image=img; tex.interpolation='Closest'; tex.location=(-300,0)
    tc=nt.nodes.new('ShaderNodeTexCoord'); tc.location=(-500,0)
    nt.links.new(tc.outputs['Generated'], tex.inputs['Vector'])
    nt.links.new(tex.outputs['Color'], b.inputs['Base Color']); nt.links.new(tex.outputs['Alpha'], b.inputs['Alpha'])
    o.data.materials.append(m); return o

# ============================================================ DEMO
if __name__=="__main__" or True:
    for ob in list(bpy.data.objects): bpy.data.objects.remove(ob, do_unlink=True)
    for c in (bpy.data.meshes,bpy.data.materials,bpy.data.lights,bpy.data.cameras,bpy.data.worlds,bpy.data.metaballs,bpy.data.images):
        for it in list(c):
            try: c.remove(it)
            except Exception: pass
    def matp(name,col,rough=0.7):
        m=bpy.data.materials.new(name); m.use_nodes=True; b=m.node_tree.nodes.get('Principled BSDF')
        b.inputs['Base Color'].default_value=(col[0],col[1],col[2],1.0); b.inputs['Roughness'].default_value=rough; return m
    BLOB=matp("blob_mat",(0.62,0.55,0.74))
    a=build_blob_mass("near_blob", count=18, cluster_r=3.0, resolution=0.30, seed=2, mat=BLOB); a.location=(-6,0,3)
    b=build_blob_far("far_blob", count=18, cluster_r=3.0, seed=2, base=(0.62,0.55,0.74));        b.location=(6,0,3)
    w=bpy.data.worlds.new("W"); bpy.context.scene.world=w; w.use_nodes=True
    w.node_tree.nodes['Background'].inputs['Color'].default_value=(0.05,0.055,0.07,1.0)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value=0.6
    def sun(loc,tgt,e):
        l=bpy.data.lights.new("S",'SUN'); l.energy=e; o=bpy.data.objects.new("S",l); bpy.context.scene.collection.objects.link(o)
        o.location=loc; o.rotation_euler=(Vector(tgt)-Vector(loc)).to_track_quat('-Z','Y').to_euler()
    sun((7,-9,12),(0,0,3),3.0); sun((-9,7,7),(0,0,3),1.2)
    cam=bpy.data.cameras.new("C"); co=bpy.data.objects.new("C",cam); bpy.context.scene.collection.objects.link(co)
    co.data.lens=42; co.location=(0,-20,5); co.rotation_euler=(Vector((0,0,2.6))-Vector(co.location)).to_track_quat('-Z','Y').to_euler()
    bpy.context.scene.camera=co
    sc=bpy.context.scene
    try: sc.render.engine='BLENDER_EEVEE_NEXT'
    except TypeError: sc.render.engine='CYCLES'
    sc.render.resolution_x=1500; sc.render.resolution_y=640; sc.render.image_settings.file_format='PNG'
    try: sc.view_settings.view_transform='AgX'
    except Exception: pass
    sc.render.filepath=r"C:\tmp\gen_blob_demo.png"; bpy.ops.render.render(write_still=True)
    import os
    os.makedirs(r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\generators",exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=r"C:\Users\quest\Programming\Games\ToRustAsWeFall\blender\generators\gen_blob_mass.blend")
    print("BLOB_DEMO objects=%d verts=%d" % (len(bpy.data.objects), sum(len(o.data.vertices) for o in bpy.data.objects if o.type=='MESH')))

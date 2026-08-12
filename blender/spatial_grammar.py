"""
Spatial grammar for boxy low-poly builds — relational placement instead of raw coordinates.

Everything is an axis-aligned Box (AABB). You don't write coordinates; you state RELATIONS:
  - slab(region)            a floor filling a footprint, top at a height
  - wall(on an edge line)   a wall standing on a floor edge
  - recess(wall, opening)   carve a door/window -> wall auto-splits into L/R/lintel (NO GAP) + alcove
  - on(surface, u,v)        a prop sitting ON a surface (bottom flush -> never floats)
  - on_wall(wall, face,u,v) a decoration ON a wall face (back flush, protruding -> never floats / over nothing)
  - span(a, b)              a beam/pipe/rail between two anchor points
  - row(a, b, spacing, fac) repeat along a line (posts, brackets, rungs)
  - group(...)              a sub-assembly placed relative to a host (hierarchy)

validate() then reports FLOATERS (props with nothing supporting/hosting them) and
OVER-NOTHING (floor props whose footprint isn't actually over a floor). Mereotopology:
support = bottom externally-connected to a floor top with footprint overlap; attachment =
a face externally-connected to (or embedded in) a wall with overlap.

Authoring frame: (x = east, y = UP, z = depth/north). emit() maps to Blender Z-up via the
chunk convention Blender(x, -z, y) so a yup glTF export lands back in Godot coords.
"""
import bpy

EPS = 0.025

class Box:
    __slots__ = ("name","x0","x1","y0","y1","z0","z1","mat","tag")
    def __init__(self, name, x0,x1, y0,y1, z0,z1, mat, tag="part"):
        self.name=name; self.mat=mat; self.tag=tag
        self.x0,self.x1=min(x0,x1),max(x0,x1)
        self.y0,self.y1=min(y0,y1),max(y0,y1)
        self.z0,self.z1=min(z0,z1),max(z0,z1)
    @property
    def size(self): return (self.x1-self.x0, self.y1-self.y0, self.z1-self.z0)
    @property
    def center(self): return ((self.x0+self.x1)/2,(self.y0+self.y1)/2,(self.z0+self.z1)/2)
    # parametric points across each extent (0..1)
    def px(self,t): return self.x0+(self.x1-self.x0)*t
    def py(self,t): return self.y0+(self.y1-self.y0)*t
    def pz(self,t): return self.z0+(self.z1-self.z0)*t
    def face(self,d):  # coordinate of a face
        return {"+x":self.x1,"-x":self.x0,"+z":self.z1,"-z":self.z0,"top":self.y1,"bottom":self.y0}[d]
    # mereotopology helpers (interiors-overlap on a 2D projection)
    def ox(self,o): return self.x0 < o.x1-EPS and self.x1 > o.x0+EPS
    def oy(self,o): return self.y0 < o.y1-EPS and self.y1 > o.y0+EPS
    def oz(self,o): return self.z0 < o.z1-EPS and self.z1 > o.z0+EPS
    def footprint_in(self,o):   # this XZ footprint lies within o's XZ footprint
        return self.x0 >= o.x0-EPS and self.x1 <= o.x1+EPS and self.z0 >= o.z0-EPS and self.z1 <= o.z1+EPS

class Grammar:
    def __init__(self):
        self.boxes=[]; self.regions=[]
        self.placed=[]   # yaw-rotated boxes (spiral ramps, angled spans) — emitted oriented
    # ----- atoms -----
    def add(self,b):
        self.boxes.append(b); return b
    def region(self, name, x0,x1, y0,y1, z0,z1):
        r=Box(name,x0,x1,y0,y1,z0,z1,None,"region"); self.regions.append(r); return r
    def box(self, name, x0,x1, y0,y1, z0,z1, mat, tag="part"):
        return self.add(Box(name,x0,x1,y0,y1,z0,z1,mat,tag))
    # ----- floors -----
    def slab(self, name, region, top, thick, mat, tag="floor"):
        return self.box(name, region.x0,region.x1, top-thick,top, region.z0,region.z1, mat, tag)
    def slab_xz(self, name, x0,x1,z0,z1, top, thick, mat, tag="floor"):
        return self.box(name, x0,x1, top-thick,top, z0,z1, mat, tag)
    # ----- walls (stand ON an edge line) -----
    def wall(self, name, axis, at, lo,hi, base, height, thick, mat, side=1, tag="wall"):
        # axis 'x' -> runs in x (lo..hi) at depth `at`, thickness in z toward side(+1=+z); 'z' mirror
        if axis=='x':
            z0,z1 = (at,at+thick) if side>0 else (at-thick,at)
            return self.box(name, lo,hi, base,base+height, z0,z1, mat, tag)
        else:
            x0,x1 = (at,at+thick) if side>0 else (at-thick,at)
            return self.box(name, x0,x1, base,base+height, lo,hi, mat, tag)
    def recess(self, wall, a0, a1, opening_h, mat=None, frame_mat=None, frame=0.0):
        """Carve an opening [a0,a1] (absolute along the wall's run axis), height opening_h from the
        wall base. Replaces the wall with L/R/lintel segments whose UNION == wall minus the opening
        (no gap). Returns dict of the new pieces (so you can attach a door/strips to them)."""
        self.boxes.remove(wall)
        nm=wall.name; mat=mat or wall.mat
        run_x = (wall.x1-wall.x0) >= (wall.z1-wall.z0)
        base=wall.y0; top=wall.y1
        pieces={}
        if run_x:
            pieces["L"]=self.box(nm+"_L", wall.x0,a0, base,top, wall.z0,wall.z1, mat,"wall")
            pieces["R"]=self.box(nm+"_R", a1,wall.x1, base,top, wall.z0,wall.z1, mat,"wall")
            pieces["lintel"]=self.box(nm+"_lintel", a0,a1, base+opening_h,top, wall.z0,wall.z1, mat,"wall")
            pieces["opening"]=Box(nm+"_opening", a0,a1, base,base+opening_h, wall.z0,wall.z1, None,"opening")
        else:
            pieces["L"]=self.box(nm+"_L", wall.x0,wall.x1, base,top, wall.z0,a0, mat,"wall")
            pieces["R"]=self.box(nm+"_R", wall.x0,wall.x1, base,top, a1,wall.z1, mat,"wall")
            pieces["lintel"]=self.box(nm+"_lintel", wall.x0,wall.x1, base+opening_h,top, a0,a1, mat,"wall")
            pieces["opening"]=Box(nm+"_opening", wall.x0,wall.x1, base,base+opening_h, a0,a1, None,"opening")
        return pieces
    # ----- props ON surfaces (never float) -----
    def on(self, name, surf, u,v, sx,sz, sy, mat, tag="prop"):
        cx,cz=surf.px(u),surf.pz(v); top=surf.y1
        return self.box(name, cx-sx/2,cx+sx/2, top,top+sy, cz-sz/2,cz+sz/2, mat, tag)
    def stack(self, name, base_box, sx,sz, sy, mat, tag="prop"):
        cx,_,cz=base_box.center; top=base_box.y1
        return self.box(name, cx-sx/2,cx+sx/2, top,top+sy, cz-sz/2,cz+sz/2, mat, tag)
    # ----- decorations ON a wall face (never float / over nothing) -----
    def on_wall(self, name, wall, face, u,v, w,h, depth, mat, tag="prop"):
        """face '+z'/'-z'/'+x'/'-x' of the wall; u along its run, v along its height; protrudes `depth`."""
        if face in ("+z","-z"):
            cx=wall.px(u); cy=wall.py(v); zf=wall.face(face)
            z0,z1=(zf-depth*0.3, zf+depth*0.7) if face=="+z" else (zf-depth*0.7, zf+depth*0.3)
            return self.box(name, cx-w/2,cx+w/2, cy-h/2,cy+h/2, z0,z1, mat, tag)
        else:
            cz=wall.pz(u); cy=wall.py(v); xf=wall.face(face)
            x0,x1=(xf-depth*0.3, xf+depth*0.7) if face=="+x" else (xf-depth*0.7, xf+depth*0.3)
            return self.box(name, x0,x1, cy-h/2,cy+h/2, cz-w/2,cz+w/2, mat, tag)
    # ----- spans + rows -----
    def span(self, name, p0, p1, r, mat, tag="part"):
        (x0,y0,z0),(x1,y1,z1)=p0,p1
        return self.box(name, min(x0,x1)-r,max(x0,x1)+r, min(y0,y1)-r,max(y0,y1)+r, min(z0,z1)-r,max(z0,z1)+r, mat, tag)
    def row(self, prefix, p0, p1, spacing, factory):
        import math
        (x0,y0,z0),(x1,y1,z1)=p0,p1
        L=math.dist((x0,y0,z0),(x1,y1,z1))
        n=max(1,int(round(L/spacing)))
        out=[]
        for i in range(n+1):
            t=i/n if n>0 else 0
            p=(x0+(x1-x0)*t, y0+(y1-y0)*t, z0+(z1-z0)*t)
            r=factory(i,p)
            if r is not None: out.append(r)
        return out
    # ----- rotated placement (spirals / angled spans) -----
    def pbox(self, name, cx,cy,cz, sx,sy,sz, yaw, mat, tag="structure"):
        """A box centered at (cx,cy,cz), size (sx along its own length, sy up, sz across), rotated by
        `yaw` about the UP axis. Emitted oriented. (Tag 'structure' — kept out of the floater check;
        a coil's segments connect to each other by construction.)"""
        self.placed.append((name,cx,cy,cz,sx,sy,sz,yaw,mat,tag)); return (cx,cy,cz,yaw)
    def coil(self, prefix, cx, cz, radius, y_top, turns, seg_per_turn, drop_per_turn, seg_len_scale, seg_w, thick, mat, start_angle=0.0):
        """An octagonal (faceted) descending spiral ramp around (cx,cz): `turns` loops of
        `seg_per_turn` flat stepped segments, dropping `drop_per_turn` per loop. Returns each
        segment's (center, yaw) so you can drop landings / rails / props on chosen steps."""
        import math
        n = int(round(turns*seg_per_turn))
        chord = 2.0*radius*math.sin(math.pi/seg_per_turn)
        out=[]
        for i in range(n):
            amid = start_angle + (i+0.5)/seg_per_turn*2.0*math.pi
            px = cx + radius*math.cos(amid); pz = cz + radius*math.sin(amid)
            py = y_top - (i+0.5)*(drop_per_turn/seg_per_turn)
            yaw = amid + math.pi/2.0   # tangent
            self.pbox("%s_%d"%(prefix,i), px,py,pz, chord*seg_len_scale, thick, seg_w, yaw, mat, "structure")
            out.append({"center":(px,py,pz), "yaw":yaw, "amid":amid, "i":i})
        return out

    # ----- stairs (reusable: connect two platforms) -----
    def stairs(self, name, p0, p1, width, mat, step_rise=0.32, tag="structure"):
        """A solid stepped staircase from p0 to p1 (3D points, p0 higher). Step count derives from the
        height difference; each tread overlaps the step below so it reads as one solid stair. Returns
        the top-tread and bottom-tread centres so you can butt landings against them with no gap."""
        import math
        x0,y0,z0=p0; x1,y1,z1=p1
        dx,dz=x1-x0, z1-z0; run=math.hypot(dx,dz); drop=y0-y1
        n=max(1, int(round(abs(drop)/step_rise)))
        yaw=math.atan2(dz,dx); tread=run/n if n else run; dstep=drop/n if n else drop
        for k in range(n):
            t=(k+0.5)/n
            cx=x0+dx*t; cz=z0+dz*t; ytop=y0-dstep*(k+1)
            h=abs(dstep)+step_rise*0.7
            self.pbox("%s_%d"%(name,k), cx, ytop-h/2, cz, tread*1.04, h, width, yaw, mat, tag)
        return {"top":(x0,y0,z0), "bottom":(x1,y1,z1), "n":n}
    def stairs_arc(self, name, center, radius, a0, a1, width, y0, y1, mat, step_rise=0.32, tag="structure"):
        """Stairs that FOLLOW an arc (spiral descents, curved ramps) — center (cx,cz), from angle a0
        to a1, descending y0->y1. Same solid-overlap treads as stairs()."""
        import math
        cx,cz=center; rise=y0-y1
        n=max(1, int(round(abs(rise)/step_rise)))
        dstep=rise/n; da=(a1-a0)
        for k in range(n):
            t=(k+0.5)/n; a=a0+da*t; ytop=y0-dstep*(k+1)
            h=abs(dstep)+step_rise*0.7
            chord=2*radius*math.sin(abs(da)/n/2)*1.25
            self.pbox("%s_%d"%(name,k), cx+radius*math.cos(a), ytop-h/2, cz+radius*math.sin(a),
                      chord, h, width, a+math.pi/2, mat, tag)
        return {"n":n}

    # ----- validation (mereotopology) -----
    def _touch(self, b, o):  # AABB contact-or-overlap on all 3 axes (externally connected or interpenetrating)
        return (b.x0<=o.x1+EPS and b.x1>=o.x0-EPS and b.y0<=o.y1+EPS and b.y1>=o.y0-EPS and b.z0<=o.z1+EPS and b.z1>=o.z0-EPS)
    def _footprint_covered(self, b, floors):
        # every footprint sample (corners + centre) must sit over SOME floor at the prop's rest level —
        # so a prop spanning several abutting floors is fine, but one half over a hole/water is flagged
        xs=(b.x0+EPS, b.x1-EPS, (b.x0+b.x1)/2); zs=(b.z0+EPS, b.z1-EPS, (b.z0+b.z1)/2)
        for cxp in (xs[0],xs[1],xs[2]):
            for czp in (zs[0],zs[1],zs[2]):
                if not any(f.x0-EPS<=cxp<=f.x1+EPS and f.z0-EPS<=czp<=f.z1+EPS and abs(b.y0-f.y1)<EPS*4 for f in floors):
                    return False
        return True
    def validate(self):
        issues=[]
        solids=[b for b in self.boxes if b.mat is not None]
        floors=[b for b in self.boxes if b.tag in ("floor","structure")]
        walls =[b for b in self.boxes if b.tag=="wall"]
        for b in self.boxes:
            if b.tag!="prop": continue
            # FLOATING: a prop must be externally connected to at least one other solid
            if not any(self._touch(b,o) for o in solids if o is not b):
                issues.append("FLOATING: %s (touches nothing)"%b.name); continue
            # OVER-NOTHING: a prop resting at a floor level must have its whole footprint over that floor
            rests = any(abs(b.y0-f.y1)<EPS*4 and b.ox(f) and b.oz(f) for f in floors)
            wallbacked = any(self._touch(b,w) for w in walls)
            if rests and not wallbacked and not self._footprint_covered(b, floors):
                issues.append("OVER-NOTHING: %s (part of its footprint is over a hole/water)"%b.name)
        return issues
    # ----- emit to Blender (chunk frame -> Blender Z-up: (x,-z,y)) -----
    def emit(self, scene):
        for b in self.boxes:
            if b.mat is None: continue
            cx,cy,cz=b.center; sx,sy,sz=b.size
            bx,by,bz=(cx,-cz,cy); bsx,bsy,bsz=(sx,sz,sy)
            hx,hy,hz=bsx/2,bsy/2,bsz/2
            me=bpy.data.meshes.new(b.name)
            v=[(bx-hx,by-hy,bz-hz),(bx+hx,by-hy,bz-hz),(bx+hx,by+hy,bz-hz),(bx-hx,by+hy,bz-hz),
               (bx-hx,by-hy,bz+hz),(bx+hx,by-hy,bz+hz),(bx+hx,by+hy,bz+hz),(bx-hx,by+hy,bz+hz)]
            f=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
            me.from_pydata(v,[],f); me.update()
            o=bpy.data.objects.new(b.name,me); scene.collection.objects.link(o); o.data.materials.append(b.mat)
        # oriented (yaw-rotated) boxes
        import math
        F=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
        for (name,cx,cy,cz,sx,sy,sz,yaw,mat,tag) in self.placed:
            if mat is None: continue
            hx,hy,hz=sx/2,sy/2,sz/2; c=math.cos(yaw); s=math.sin(yaw)
            local=[(-hx,-hy,-hz),(hx,-hy,-hz),(hx,hy,-hz),(-hx,hy,-hz),(-hx,-hy,hz),(hx,-hy,hz),(hx,hy,hz),(-hx,hy,hz)]
            vv=[]
            for (lx,ly,lz) in local:
                rx=lx*c - lz*s; rz=lx*s + lz*c
                wx,wy,wz=cx+rx, cy+ly, cz+rz
                vv.append((wx,-wz,wy))   # chunk(x,y_up,z) -> Blender(x,-z,y_up)
            me=bpy.data.meshes.new(name); me.from_pydata(vv,[],F); me.update()
            o=bpy.data.objects.new(name,me); scene.collection.objects.link(o); o.data.materials.append(mat)

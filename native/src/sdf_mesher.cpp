#include "sdf_mesher.h"

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

using namespace godot;

namespace {

const double SDF_FAR = 1.0e9;

struct Grid {
	const std::vector<float> *field;
	Vector3 mn;
	double cell;
	int nx, ny, nz;
};

double prim_dist(const Dictionary &pr, const Vector3 &p) {
	String type = pr.get("type", "sphere");
	if (type == String("capsule")) {
		Vector3 a = pr["a"];
		Vector3 b = pr["b"];
		double r1 = (double)pr.get("r1", 0.1);
		double r2 = (double)pr.get("r2", r1);
		Vector3 ab = b - a;
		double denom = ab.length_squared();
		double t = denom > 1.0e-9 ? CLAMP((double)(p - a).dot(ab) / denom, 0.0, 1.0) : 0.0;
		return (p - (a + ab * t)).length() - (r1 + (r2 - r1) * t);
	} else if (type == String("ellipsoid")) {
		Vector3 c = pr["c"];
		Vector3 r = pr["r"];
		Vector3 q = p - c;
		double k0 = Vector3(q.x / r.x, q.y / r.y, q.z / r.z).length();
		double k1 = Vector3(q.x / (r.x * r.x), q.y / (r.y * r.y), q.z / (r.z * r.z)).length();
		return k0 * (k0 - 1.0) / MAX(k1, 1.0e-6);
	} else if (type == String("box")) {
		Vector3 bc = pr["c"];
		Vector3 bb = pr["b"];
		double rnd = (double)pr.get("round", 0.05);
		Vector3 d = (p - bc).abs() - (bb - Vector3(1, 1, 1) * rnd);
		Vector3 outside(MAX(d.x, 0.0), MAX(d.y, 0.0), MAX(d.z, 0.0));
		return outside.length() + MIN(MAX(d.x, MAX(d.y, d.z)), 0.0) - rnd;
	}
	Vector3 c = pr["c"];
	return (p - c).length() - (double)pr.get("r1", 0.1);
}

AABB prim_aabb(const Dictionary &pr) {
	double margin = MAX(0.001, (double)pr.get("k", 0.1)) * 1.6;
	String type = pr.get("type", "sphere");
	if (type == String("capsule")) {
		Vector3 a = pr["a"];
		Vector3 b = pr["b"];
		double r = MAX((double)pr.get("r1", 0.1), (double)pr.get("r2", 0.1)) + margin;
		Vector3 lo = a.min(b) - Vector3(1, 1, 1) * r;
		return AABB(lo, a.max(b) + Vector3(1, 1, 1) * r - lo);
	} else if (type == String("ellipsoid")) {
		Vector3 c = pr["c"];
		Vector3 r2 = (Vector3)pr["r"] + Vector3(1, 1, 1) * margin;
		return AABB(c - r2, r2 * 2.0);
	} else if (type == String("box")) {
		Vector3 bc = pr["c"];
		Vector3 bh = (Vector3)pr["b"] + Vector3(1, 1, 1) * margin;
		return AABB(bc - bh, bh * 2.0);
	}
	Vector3 c3 = pr["c"];
	double r3 = (double)pr.get("r1", 0.1) + margin;
	return AABB(c3 - Vector3(1, 1, 1) * r3, Vector3(1, 1, 1) * r3 * 2.0);
}

double sample_field(const Grid &g, const Vector3 &p) {
	double fx = CLAMP((p.x - g.mn.x) / g.cell, 0.0, (double)(g.nx - 1) - 0.001);
	double fy = CLAMP((p.y - g.mn.y) / g.cell, 0.0, (double)(g.ny - 1) - 0.001);
	double fz = CLAMP((p.z - g.mn.z) / g.cell, 0.0, (double)(g.nz - 1) - 0.001);
	int xi = (int)fx, yi = (int)fy, zi = (int)fz;
	double tx = fx - xi, ty = fy - yi, tz = fz - zi;
	const std::vector<float> &f = *g.field;
	auto at = [&](int x, int y, int z) -> double { return (double)f[((size_t)(z * g.ny + y) * g.nx) + x]; };
	double c000 = at(xi, yi, zi), c100 = at(xi + 1, yi, zi);
	double c010 = at(xi, yi + 1, zi), c110 = at(xi + 1, yi + 1, zi);
	double c001 = at(xi, yi, zi + 1), c101 = at(xi + 1, yi, zi + 1);
	double c011 = at(xi, yi + 1, zi + 1), c111 = at(xi + 1, yi + 1, zi + 1);
	double a = c000 + (c100 - c000) * tx, b = c010 + (c110 - c010) * tx;
	double c = c001 + (c101 - c001) * tx, d = c011 + (c111 - c011) * tx;
	double e = a + (b - a) * ty, fm = c + (d - c) * ty;
	return e + (fm - e) * tz;
}

Vector3 gradient(const Grid &g, const Vector3 &p) {
	double e = g.cell * 0.6;
	Vector3 gr(
			sample_field(g, p + Vector3(e, 0, 0)) - sample_field(g, p - Vector3(e, 0, 0)),
			sample_field(g, p + Vector3(0, e, 0)) - sample_field(g, p - Vector3(0, e, 0)),
			sample_field(g, p + Vector3(0, 0, e)) - sample_field(g, p - Vector3(0, 0, e)));
	return gr.length_squared() > 1.0e-12 ? gr.normalized() : Vector3(0, 1, 0);
}

} // namespace

Dictionary SdfMesherNative::build(const Array &prims, double cell, const Color &color) {
	Dictionary out;
	if (prims.size() == 0) {
		out["mesh"] = Variant();
		out["verts"] = 0;
		out["tris"] = 0;
		out["aabb"] = AABB();
		return out;
	}

	Vector3 mn(SDF_FAR, SDF_FAR, SDF_FAR);
	Vector3 mx = -mn;
	for (int i = 0; i < prims.size(); i++) {
		AABB pb = prim_aabb((Dictionary)prims[i]);
		mn = mn.min(pb.position);
		mx = mx.max(pb.position + pb.size);
	}
	mn -= Vector3(1, 1, 1) * cell * 2.0;
	mx += Vector3(1, 1, 1) * cell * 2.0;
	int nx = (int)Math::ceil((mx.x - mn.x) / cell) + 1;
	int ny = (int)Math::ceil((mx.y - mn.y) / cell) + 1;
	int nz = (int)Math::ceil((mx.z - mn.z) / cell) + 1;
	std::vector<float> field((size_t)nx * ny * nz, (float)SDF_FAR);

	for (int pi = 0; pi < prims.size(); pi++) {
		Dictionary pd = (Dictionary)prims[pi];
		double k = MAX(0.001, (double)pd.get("k", 0.1));
		AABB pb = prim_aabb(pd);
		int x0 = MAX(0, (int)((pb.position.x - mn.x) / cell));
		int y0 = MAX(0, (int)((pb.position.y - mn.y) / cell));
		int z0 = MAX(0, (int)((pb.position.z - mn.z) / cell));
		int x1 = MIN(nx - 1, (int)Math::ceil((pb.position.x + pb.size.x - mn.x) / cell));
		int y1 = MIN(ny - 1, (int)Math::ceil((pb.position.y + pb.size.y - mn.y) / cell));
		int z1 = MIN(nz - 1, (int)Math::ceil((pb.position.z + pb.size.z - mn.z) / cell));
		for (int zi = z0; zi <= z1; zi++) {
			for (int yi = y0; yi <= y1; yi++) {
				int row = (zi * ny + yi) * nx;
				double py = mn.y + yi * cell;
				double pz = mn.z + zi * cell;
				for (int xi = x0; xi <= x1; xi++) {
					double d = prim_dist(pd, Vector3(mn.x + xi * cell, py, pz));
					size_t idx = (size_t)row + xi;
					double old = field[idx];
					double h = CLAMP(0.5 + 0.5 * (old - d) / k, 0.0, 1.0);
					field[idx] = (float)((old + (d - old) * h) - k * h * (1.0 - h));
				}
			}
		}
	}

	Grid g{ &field, mn, cell, nx, ny, nz };

	static const int tets[6][4] = { { 0, 1, 3, 7 }, { 0, 1, 5, 7 }, { 0, 2, 3, 7 }, { 0, 2, 6, 7 }, { 0, 4, 5, 7 }, { 0, 4, 6, 7 } };
	static const int corner_off[8][3] = { { 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 }, { 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 } };

	std::vector<Vector3> verts;
	std::vector<int32_t> indices;
	std::unordered_map<uint64_t, int> vert_ids;
	auto vid = [&](const Vector3 &p) -> int {
		int64_t qx = (int64_t)llround(p.x * 5000.0) + (1LL << 30);
		int64_t qy = (int64_t)llround(p.y * 5000.0) + (1LL << 30);
		int64_t qz = (int64_t)llround(p.z * 5000.0) + (1LL << 30);
		uint64_t key = ((uint64_t)(qx & 0x1FFFFF) << 42) | ((uint64_t)(qy & 0x1FFFFF) << 21) | (uint64_t)(qz & 0x1FFFFF);
		auto it = vert_ids.find(key);
		if (it != vert_ids.end()) return it->second;
		int id = (int)verts.size();
		verts.push_back(p);
		vert_ids[key] = id;
		return id;
	};

	double cv[8];
	auto edge_point = [&](int ca, int cb, const Vector3 &base) -> Vector3 {
		double va = cv[ca], vb = cv[cb];
		double t = std::fabs(va - vb) > 1.0e-9 ? CLAMP(va / (va - vb), 0.02, 0.98) : 0.5;
		Vector3 pa = base + Vector3(corner_off[ca][0], corner_off[ca][1], corner_off[ca][2]) * cell;
		Vector3 pb = base + Vector3(corner_off[cb][0], corner_off[cb][1], corner_off[cb][2]) * cell;
		return pa.lerp(pb, t);
	};
	auto push_tri = [&](const Vector3 &p0, const Vector3 &p1, const Vector3 &p2) {
		Vector3 e1 = p1 - p0, e2 = p2 - p0;
		Vector3 n = e1.cross(e2);
		if (n.length_squared() < 1.0e-12) return;
		Vector3 gr = gradient(g, (p0 + p1 + p2) / 3.0);
		bool flip = n.dot(gr) < 0.0;
		int i0 = vid(p0), i1 = vid(p1), i2 = vid(p2);
		if (i0 == i1 || i1 == i2 || i0 == i2) return;
		if (flip) {
			indices.push_back(i0); indices.push_back(i2); indices.push_back(i1);
		} else {
			indices.push_back(i0); indices.push_back(i1); indices.push_back(i2);
		}
	};

	for (int zi = 0; zi < nz - 1; zi++) {
		for (int yi = 0; yi < ny - 1; yi++) {
			for (int xi = 0; xi < nx - 1; xi++) {
				int neg = 0, pos = 0;
				for (int ci = 0; ci < 8; ci++) {
					double v = field[((size_t)((zi + corner_off[ci][2]) * ny + (yi + corner_off[ci][1])) * nx) + xi + corner_off[ci][0]];
					cv[ci] = v;
					if (v < 0.0) neg++; else pos++;
				}
				if (neg == 0 || pos == 0) continue;
				Vector3 base(mn.x + xi * cell, mn.y + yi * cell, mn.z + zi * cell);
				for (int ti = 0; ti < 6; ti++) {
					const int *tet = tets[ti];
					int inside[4], outside[4], ni = 0, no = 0;
					for (int j = 0; j < 4; j++) {
						if (cv[tet[j]] < 0.0) inside[ni++] = tet[j];
						else outside[no++] = tet[j];
					}
					if (ni == 0 || no == 0) continue;
					if (ni == 1 || ni == 3) {
						int lone = (ni == 1) ? inside[0] : outside[0];
						const int *others = (ni == 1) ? outside : inside;
						Vector3 p0 = edge_point(lone, others[0], base);
						Vector3 p1 = edge_point(lone, others[1], base);
						Vector3 p2 = edge_point(lone, others[2], base);
						push_tri(p0, p1, p2);
					} else {
						int a0 = inside[0], a1 = inside[1], b0 = outside[0], b1 = outside[1];
						Vector3 q0 = edge_point(a0, b0, base);
						Vector3 q1 = edge_point(a0, b1, base);
						Vector3 q2 = edge_point(a1, b1, base);
						Vector3 q3 = edge_point(a1, b0, base);
						push_tri(q0, q1, q2);
						push_tri(q0, q2, q3);
					}
				}
			}
		}
	}

	if (indices.empty()) {
		out["mesh"] = Variant();
		out["verts"] = 0;
		out["tris"] = 0;
		out["aabb"] = AABB();
		return out;
	}

	PackedVector3Array pverts, pnormals;
	PackedInt32Array pindices;
	pverts.resize(verts.size());
	pnormals.resize(verts.size());
	for (size_t i = 0; i < verts.size(); i++) {
		pverts.set(i, verts[i]);
		pnormals.set(i, gradient(g, verts[i]));
	}
	pindices.resize(indices.size());
	for (size_t i = 0; i < indices.size(); i++) {
		pindices.set(i, indices[i]);
	}

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = pverts;
	arrays[Mesh::ARRAY_NORMAL] = pnormals;
	arrays[Mesh::ARRAY_INDEX] = pindices;
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	Ref<StandardMaterial3D> mat;
	mat.instantiate();
	mat->set_albedo(color);
	mat->set_roughness(0.85);
	mesh->surface_set_material(0, mat);

	AABB out_aabb(verts[0], Vector3());
	for (size_t i = 0; i < verts.size(); i++) {
		out_aabb = out_aabb.expand(verts[i]);
	}

	out["mesh"] = mesh;
	out["verts"] = (int)verts.size();
	out["tris"] = (int)(indices.size() / 3);
	out["aabb"] = out_aabb;
	return out;
}

void SdfMesherNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "prims", "cell", "color"), &SdfMesherNative::build);
}

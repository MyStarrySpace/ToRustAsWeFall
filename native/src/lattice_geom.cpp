#include "lattice_geom.h"

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cmath>

using namespace godot;

Array LatticeGeomNative::segment_crossings(const Array &paths) {
	Array out;
	int np = paths.size();
	for (int i = 0; i < np; i++) {
		PackedVector2Array pa = paths[i];
		int na = pa.size();
		for (int j = i + 1; j < np; j++) {
			PackedVector2Array pb = paths[j];
			int nb = pb.size();
			for (int si = 0; si + 1 < na; si++) {
				Vector2 a1 = pa[si];
				Vector2 da = pa[si + 1] - a1;
				for (int sj = 0; sj + 1 < nb; sj++) {
					Vector2 b1 = pb[sj];
					Vector2 db = pb[sj + 1] - b1;
					double den = (double)da.x * db.y - (double)da.y * db.x;
					if (std::fabs(den) < 1.0e-9) {
						continue;
					}
					double t = ((double)(b1.x - a1.x) * db.y - (double)(b1.y - a1.y) * db.x) / den;
					double u = ((double)(b1.x - a1.x) * da.y - (double)(b1.y - a1.y) * da.x) / den;
					if (t > 0.02 && t < 0.98 && u > 0.02 && u < 0.98) {
						Dictionary d;
						d["pos"] = a1 + da * t;
						d["da"] = da;
						d["db"] = db;
						out.push_back(d);
					}
				}
			}
		}
	}
	return out;
}

void LatticeGeomNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("segment_crossings", "paths"), &LatticeGeomNative::segment_crossings);
}

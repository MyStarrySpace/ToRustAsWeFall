#ifndef SDF_MESHER_H
#define SDF_MESHER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>

using namespace godot;

// Native port of scripts/generation/sdf_mesher.gd. Splats SDF primitives (capsule/ellipsoid/sphere/
// box, each with a smooth-min blend radius k) into a scalar field, then polygonises it with marching
// TETRAHEDRA (Kuhn 6-tet decomposition) into a closed manifold ArrayMesh with gradient normals.
// Mirrors the GDScript algorithm exactly (same field, tets, edge clamps, vertex dedup) so output and
// determinism match; the GDScript SdfMesher.build() delegates here when the extension is loaded.
class SdfMesherNative : public RefCounted {
	GDCLASS(SdfMesherNative, RefCounted);

public:
	// prims: Array of Dictionaries; cell: voxel size (m); color: surface albedo.
	// Returns {"mesh": ArrayMesh|null, "verts": int, "tris": int, "aabb": AABB}.
	// Instance method (not static) so GDScript can call it dynamically on a throwaway instance
	// (`ClassDB.instantiate("SdfMesherNative").call("build", ...)`) with no compile-time dependency.
	Dictionary build(const Array &prims, double cell, const Color &color);

protected:
	static void _bind_methods();
};

#endif // SDF_MESHER_H

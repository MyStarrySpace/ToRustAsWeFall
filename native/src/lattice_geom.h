#ifndef LATTICE_GEOM_H
#define LATTICE_GEOM_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

using namespace godot;

// Native geometry helpers for LatticeBuilder. segment_crossings is the O(n^2) rib-crossing detection
// used by the junction rib-merge (algorithm 3) — the hot part of building a lattice. Mirrors the
// GDScript _seg_x loop exactly (same 0.02..0.98 interior thresholds); GDScript delegates here.
class LatticeGeomNative : public RefCounted {
	GDCLASS(LatticeGeomNative, RefCounted);

public:
	// paths: Array of PackedVector2Array (rib centrelines). Returns Array of Dictionaries
	// {"pos": Vector2, "da": Vector2, "db": Vector2} — one per interior crossing of two DIFFERENT paths.
	Array segment_crossings(const Array &paths);

protected:
	static void _bind_methods();
};

#endif // LATTICE_GEOM_H

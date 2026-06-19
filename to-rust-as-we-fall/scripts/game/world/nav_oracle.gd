class_name NavOracle
extends RefCounted

## A NavigationServer3D map baked at RUNTIME from a scene's STATIC COLLISION, used as a fast COARSE ORACLE
## for the grid pathfinder — NOT as the authoritative path. Two jobs:
##   distance(a, b)  — the navmesh geodesic length. A continuous any-angle shortest path is never LONGER
##                     than the grid's 8-direction shortest path, so this is an ADMISSIBLE lower bound and
##                     can weight the grid A*'s scores (tighter than octile around walls) without changing
##                     the optimal result — only pruning the search.
##   reachable(a, b) — empty path => geometrically unreachable (a deterministic cull verdict).
##
## DETERMINISM: NavigationServer3D.map_get_path is a SYNCHRONOUS A* + funnel with no RNG (the non-determinism
## in Godot navigation lives in the avoidance/RVO subsystem, which this never touches), so identical queries
## return identical paths WITHIN A BUILD. The one caveat is the navmesh BAKE (float voxelization) — bit-exact
## within a build, not guaranteed across platforms/engine versions; fine for in-process replay, flag it for
## shipped cross-platform replay. The grid stays the replay-authoritative path; this only guides + culls it.
##
## Lifecycle: bake_from_collision() then query immediately (it force-updates the map). Call free_oracle()
## when done — the map/region are NavigationServer RIDs, not nodes, so they won't free themselves.

var _map: RID
var _region: RID
var _baked := false
var cell_size := 0.25

func is_ready() -> bool:
	return _baked

## Bake from the STATIC COLLIDERS under `root` matching `collision_mask` (layer 1 = the ground/deck the
## player ray already queries). Synchronous: parses on the main thread, bakes, builds the map + region, and
## force-updates so queries work this frame. Returns false (and stays un-baked) if no geometry was found.
func bake_from_collision(root: Node, p_cell_size := 0.25, agent_radius := 0.3, collision_mask := 1) -> bool:
	free_oracle()
	if root == null:
		return false
	cell_size = p_cell_size
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = p_cell_size
	nav_mesh.agent_radius = agent_radius
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = collision_mask
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, root)
	if source.get_vertices().is_empty():
		return false
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	if nav_mesh.get_polygon_count() == 0:
		return false
	# The map's cell_size/cell_height MUST match the navmesh or the region's polygons are silently rejected.
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(_map, nav_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(_map, nav_mesh.cell_height)
	NavigationServer3D.map_set_active(_map, true)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_transform(_region, Transform3D())
	NavigationServer3D.region_set_navigation_mesh(_region, nav_mesh)
	NavigationServer3D.region_set_map(_region, _map)
	NavigationServer3D.map_force_update(_map)
	_baked = true
	return true

func _path(a: Vector3, b: Vector3) -> PackedVector3Array:
	if not _baked:
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(_map, a, b, true)

## Navmesh geodesic length from a to b, or INF if unreachable. An admissible lower bound on the grid path.
func distance(a: Vector3, b: Vector3) -> float:
	var p := _path(a, b)
	if p.size() < 2:
		return INF
	var d := 0.0
	for i in range(1, p.size()):
		d += p[i - 1].distance_to(p[i])
	return d

## The funnel-smoothed waypoints from a to b (empty if unreachable). For guidance / debug draw.
func waypoints(a: Vector3, b: Vector3) -> PackedVector3Array:
	return _path(a, b)

## True iff the navmesh can route from a to b (the path actually reaches near b — the server clamps an
## off-mesh request to the nearest polygon, so a far-off endpoint means unreachable).
func reachable(a: Vector3, b: Vector3, tol := 1.0) -> bool:
	var p := _path(a, b)
	return p.size() >= 2 and p[p.size() - 1].distance_to(b) <= tol

## Force the navigation map to synchronize NOW. A freshly-assigned region's polygons land on the map only
## after one physics frame has processed the queued region command, so the usage contract is: bake, let one
## physics frame pass, then sync() — after that queries are valid (and synchronous). A scene that bakes in
## _ready gets this for free on its first physics frame.
func sync() -> void:
	if _baked:
		NavigationServer3D.map_force_update(_map)

## The nearest point on the navmesh to `p` (for snapping / debug). Returns p unchanged if un-baked.
func closest(p: Vector3) -> Vector3:
	if not _baked:
		return p
	return NavigationServer3D.map_get_closest_point(_map, p)

func free_oracle() -> void:
	if _region.is_valid():
		NavigationServer3D.free_rid(_region)
		_region = RID()
	if _map.is_valid():
		NavigationServer3D.free_rid(_map)
		_map = RID()
	_baked = false

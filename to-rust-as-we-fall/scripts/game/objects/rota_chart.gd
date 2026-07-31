class_name RotaChart
extends Interactable

## The ROTA CHART — the Balancing Basin's FORESIGHT branch (docs/BALANCING_BASIN.md).
## The fill schedule as a physical info surface: its EXISTENCE is visible from the whole floor
## (a lit board over the works — the tradeoff is advertised before any crossing is attempted);
## its CONTENT is earned up close, where reading it reports the full repeating schedule and the
## next boundary from the basin's authoritative record. Foresight only: the chart changes no
## mechanics and gates nothing — the maintenance crew posted their rota, and knowing which
## window is the LONG one converts waiting into scheduling (instruments sharpen, never gate).

signal chart_read(rota_text: String)

const STATE_NAMES := ["LOW", "MID", "HIGH"]
const BAR_COLORS := [Color(0.24, 0.5, 0.46), Color(0.3, 0.7, 0.78), Color(0.85, 0.4, 0.3)]

var _gs = null
var _basin_tag := "basin"
var _read_count := 0
var _board: MeshInstance3D = null
var _bars: Array = []

func configure(gs, spec: Dictionary) -> void:
	_gs = gs
	position = spec.get("pos", Vector3.ZERO)
	_basin_tag = str(spec.get("basin_tag", "basin"))
	interaction_radius = float(spec.get("radius", 1.5))
	description = str(spec.get("desc", "The posted fill rota"))
	tutorial_label = str(spec.get("label", "READ THE ROTA CHART"))
	interactable_type = InteractableType.INSPECTION
	if not interacted.is_connected(_on_read):
		interacted.connect(_on_read)

func read_count() -> int:
	return _read_count

func _ready() -> void:
	super._ready()
	_build_board()
	call_deferred("_wire_board_outline")
	# The bars render the authored rota; build once the basin has published its record.
	call_deferred("_build_bars")

func _on_read() -> void:
	var snapshot := _basin_snapshot()
	if snapshot.is_empty():
		return
	_read_count += 1
	var parts: Array = []
	for entry_v in (snapshot.get("rota", []) as Array):
		var entry := entry_v as Dictionary
		var lvl := clampi(int(entry.get("level", 0)), 0, STATE_NAMES.size() - 1)
		parts.append("%s %ds" % [STATE_NAMES[lvl], int(round(float(entry.get("dwell", 0.0))))])
	var text := "ROTA // " + " > ".join(PackedStringArray(parts))
	var next_state := clampi(int(snapshot.get("next_state", 0)), 0, STATE_NAMES.size() - 1)
	var next_in := float(snapshot.get("next_change_in", -1.0))
	if next_in >= 0.0:
		text += " // NEXT: %s in %.0fs" % [STATE_NAMES[next_state], next_in]
	chart_read.emit(text)

func _basin_snapshot() -> Dictionary:
	if _gs == null or not _gs.has_method("get_world_state"):
		return {}
	var saved: Variant = _gs.get_world_state("kit:basin:%s" % _basin_tag, null)
	return (saved as Dictionary) if saved is Dictionary else {}

# --- visuals: a lit board; the schedule drawn as proportional bars (readable up close) ---

func _build_board() -> void:
	if _board != null:
		return
	_board = MeshInstance3D.new()
	_board.name = "ChartBoard"
	var bm := BoxMesh.new()
	bm.size = Vector3(1.7, 1.05, 0.08)
	_board.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.09, 0.11, 0.12)
	bmat.emission_enabled = true
	bmat.emission = Color(0.3, 0.6, 0.62)
	bmat.emission_energy_multiplier = 0.35
	_board.material_override = bmat
	_board.position = Vector3(0.0, 1.5, 0.0)
	add_child(_board)

func _build_bars() -> void:
	if _board == null or not _bars.is_empty():
		return
	var snapshot := _basin_snapshot()
	var rota: Array = snapshot.get("rota", []) as Array
	if rota.is_empty():
		return
	var total := 0.0
	for entry_v in rota:
		total += maxf(0.5, float((entry_v as Dictionary).get("dwell", 0.0)))
	if total <= 0.0:
		return
	var usable := 1.5
	var x := -usable * 0.5
	for entry_v in rota:
		var entry := entry_v as Dictionary
		var dwell := maxf(0.5, float(entry.get("dwell", 0.0)))
		var w := usable * dwell / total
		var lvl := clampi(int(entry.get("level", 0)), 0, BAR_COLORS.size() - 1)
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(maxf(0.03, w - 0.02), 0.16, 0.05)
		bar.mesh = bar_mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = BAR_COLORS[lvl]
		mat.emission_enabled = true
		mat.emission = BAR_COLORS[lvl]
		mat.emission_energy_multiplier = 0.8
		bar.material_override = mat
		# Bars stack by height as well as hue: the water level IS the bar's altitude.
		bar.position = Vector3(x + w * 0.5, -0.18 + 0.22 * float(lvl), 0.06)
		_board.add_child(bar)
		_bars.append(bar)
		x += w

func _wire_board_outline() -> void:
	var mgr := OutlineFeedbackManager.ensure(self)
	if mgr == null or _board == null:
		return
	var target := mgr.outline_meshes(self, str(name) + "Outline", [_board],
		"rota_chart", maxf(1.0, interaction_radius))
	if target == null:
		return
	if target.has_method("set_interaction_delegate"):
		target.call("set_interaction_delegate", self)
	set_outline_target(target)

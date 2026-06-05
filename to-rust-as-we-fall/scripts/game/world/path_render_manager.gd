class_name PathRenderManager
extends Node3D

## Scene-level movement-path rendering. Add ONE of these per scene, point it at the GameState, and
## it draws a path ribbon for EVERY registered character that is moving (or has a queued move) —
## player, party member, NPC, escort — anchored to that character's node and tinted by it.
##
## This is the REUSABLE home for movement-path visuals. Do NOT bake a PathRenderer into one
## controller (it was in player.gd, so only the single player ever showed a path, and scenes that
## move other characters — the elevator party, escorts — showed nothing). The manager binds the
## GameState/char_id/anchor every frame from the SCENE's perspective, so a path appears regardless
## of whether the character's own node is processing, and a queued move (movement set while the
## scheduler is paused) draws too. Purely cosmetic — it reads the scheduler clock, writes nothing.

var game_state: GameState
var search_root: Node             # where character nodes live (defaults to the parent scene)
var default_color := Color(1.0, 0.7, 0.3)

var _renderers := {}              # char_id -> PathRenderer
var _nodes := {}                  # char_id -> Node3D (cached anchor; re-found if freed)

func setup(state: GameState, root: Node = null) -> void:
	game_state = state
	search_root = root if root != null else get_parent()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or game_state == null:
		return
	for char_id in game_state.characters.keys():
		var pr: PathRenderer = _renderers.get(char_id)
		if pr == null:
			pr = PathRenderer.new()
			add_child(pr)
			_renderers[char_id] = pr
		var node := _node_for(char_id)
		# Re-bind every frame: cheap, and it survives late node creation + chunk reloads.
		pr.setup(game_state, char_id, _color_for(node), node)
		pr.set_running(game_state.is_running(char_id))

func _color_for(node: Node) -> Color:
	if node != null and "color" in node:
		return node.color
	return default_color

func _node_for(char_id: String) -> Node3D:
	var cached = _nodes.get(char_id)
	if cached != null and is_instance_valid(cached):
		return cached
	var found := _find_node(char_id)
	_nodes[char_id] = found
	return found

func _find_node(char_id: String) -> Node3D:
	if search_root == null or not is_instance_valid(search_root):
		return null
	for n in search_root.find_children("*", "", true, false):
		if n is Node3D and "char_id" in n and str(n.char_id) == char_id:
			return n
	return null

class_name SimCommand

## Simulated input command for headless testing and CLI play.
## Each command represents a player action or a wait condition.

enum Type {
	CLICK,          # Click at a world position (movement)
	CLICK_GRID,     # Click at a grid cell (A* pathfinding)
	KEY_PRESS,      # Press a key (E, Shift, Q, Tab, etc.)
	WAIT_TIME,      # Wait N seconds of game time
	WAIT_FRAMES,    # Wait N process frames
	WAIT_PHASE,     # Wait until a sequence reaches a named phase
	WAIT_NEAR,      # Wait until player is within range of a position
	WAIT_DIALOGUE,  # Wait until dialogue finishes (advancing at wait gates)
	ADVANCE_DIALOGUE, # Advance the dialogue one step (a click / acknowledge)
	TRIGGER_INTERACTABLE, # Interact with a named interactable (a click on it)
	LIST_INTERACTABLES, # Print interactables within the party's combined visible range
	MOVE_TO_INTERACTABLE, # Walk the active character to a named/registered interactable
	EQUIP_ITEM,     # Pick an item into a free hand slot (equip)
	DROP_ITEM,      # Drop a held item at the character's feet
	GIVE_ITEM,      # Transfer a held item to another character
	THROW_OBJECT,   # Throw a physics object to a target location along an arc
	QUEUE_MOVES,    # Queue several destinations; the character walks them in order
	REST,           # Restore the party (rest at a shelter)
	ASSERT_STAT,    # Assert a player stat value
	ASSERT_PHASE,   # Assert the current sequence phase
	ASSERT_NEAR,    # Assert player is near a position
	PRINT_STATE,    # Print current game state (for CLI)
}

var type: Type
var args: Dictionary

static func click(world_x: float, world_z: float) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.CLICK
	cmd.args = {"x": world_x, "z": world_z}
	return cmd

static func click_grid(grid_x: int, grid_z: int) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.CLICK_GRID
	cmd.args = {"gx": grid_x, "gz": grid_z}
	return cmd

static func key_press(keycode: int) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.KEY_PRESS
	cmd.args = {"keycode": keycode}
	return cmd

static func wait_time(seconds: float) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.WAIT_TIME
	cmd.args = {"seconds": seconds}
	return cmd

static func wait_frames(count: int) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.WAIT_FRAMES
	cmd.args = {"count": count}
	return cmd

static func wait_phase(phase_name: String) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.WAIT_PHASE
	cmd.args = {"phase": phase_name}
	return cmd

static func wait_near(x: float, z: float, radius: float = 1.5) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.WAIT_NEAR
	cmd.args = {"x": x, "z": z, "radius": radius}
	return cmd

static func wait_dialogue() -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.WAIT_DIALOGUE
	cmd.args = {}
	return cmd

## Advance dialogue one step. Driver command only — UI pacing, never logged.
static func advance_dialogue() -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.ADVANCE_DIALOGUE
	cmd.args = {}
	return cmd

## Interact with a named interactable (the data-layer equivalent of clicking it).
static func trigger_interactable(node_name: String) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.TRIGGER_INTERACTABLE
	cmd.args = {"name": node_name}
	return cmd

## Print every interactable within the party's combined visible range (the data
## layer's "what can we act on right now" query).
static func list_interactables(radius: float = 0.0) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.LIST_INTERACTABLES
	cmd.args = {"radius": radius}
	return cmd

## Walk the active character to a registered interactable (by id or node name).
static func move_to_interactable(id: String, char_id := "") -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.MOVE_TO_INTERACTABLE
	cmd.args = {"id": id, "char_id": char_id}
	return cmd

## Equip: move an item into a free hand slot (pick it up).
static func equip_item(item_id: String, char_id := "") -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.EQUIP_ITEM
	cmd.args = {"item_id": item_id, "char_id": char_id}
	return cmd

## Drop a held item at the character's feet.
static func drop_item(item_id: String, char_id := "") -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.DROP_ITEM
	cmd.args = {"item_id": item_id, "char_id": char_id}
	return cmd

## Hand a held item to another character.
static func give_item(item_id: String, to_char: String, char_id := "") -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.GIVE_ITEM
	cmd.args = {"item_id": item_id, "to_char": to_char, "char_id": char_id}
	return cmd

## Throw a physics object to a target world location along an arc.
static func throw_object(obj_id: String, x: float, z: float, arc_time := 0.0) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.THROW_OBJECT
	cmd.args = {"obj_id": obj_id, "x": x, "z": z, "arc_time": arc_time}
	return cmd

## Queue several destinations; the character walks them in order (one click each).
static func queue_moves(points: Array, char_id := "") -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.QUEUE_MOVES
	cmd.args = {"points": points, "char_id": char_id}
	return cmd

## Rest at a shelter: restore the party's hp / stamina / atp.
static func rest(char_id := "") -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.REST
	cmd.args = {"char_id": char_id}
	return cmd

static func assert_stat(stat_name: String, op: String, value: float) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.ASSERT_STAT
	cmd.args = {"stat": stat_name, "op": op, "value": value}
	return cmd

static func assert_phase(phase_name: String) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.ASSERT_PHASE
	cmd.args = {"phase": phase_name}
	return cmd

static func assert_near(x: float, z: float, radius: float = 2.0) -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.ASSERT_NEAR
	cmd.args = {"x": x, "z": z, "radius": radius}
	return cmd

static func print_state() -> SimCommand:
	var cmd := SimCommand.new()
	cmd.type = Type.PRINT_STATE
	cmd.args = {}
	return cmd

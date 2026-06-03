class_name SketchHistory
extends RefCounted

## Snapshot-based undo/redo for a SketchModel. Each commit() captures the model's full
## state; undo/redo restore neighbouring snapshots in place. Sketches are small, so
## whole-state snapshots are simpler and safer than diffing individual edits.

const LIMIT := 200

var _model: SketchModel
var _stack: Array = []   # Array of to_dict() snapshots, oldest first
var _index := -1         # index of the snapshot the model currently matches

func _init(model: SketchModel) -> void:
	_model = model
	reset()

## Drop all history and make the model's current state the only baseline.
func reset() -> void:
	_stack = [_model.to_dict()]
	_index = 0

## Record the model's current state as a new step, if it changed since the last one.
## Any redo future is discarded. Returns true if a step was actually recorded.
func commit() -> bool:
	var snap := _model.to_dict()
	if _index >= 0 and _same(snap, _stack[_index]):
		return false
	if _index < _stack.size() - 1:
		_stack = _stack.slice(0, _index + 1)
	_stack.append(snap)
	_index += 1
	if _stack.size() > LIMIT:
		_stack.remove_at(0)
		_index -= 1
	return true

func can_undo() -> bool:
	return _index > 0

func can_redo() -> bool:
	return _index < _stack.size() - 1

## Restore the previous step into the model. Returns true if it moved.
func undo() -> bool:
	if not can_undo():
		return false
	_index -= 1
	_model.from_dict(_stack[_index])
	return true

## Restore the next step into the model. Returns true if it moved.
func redo() -> bool:
	if not can_redo():
		return false
	_index += 1
	_model.from_dict(_stack[_index])
	return true

static func _same(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a) == JSON.stringify(b)

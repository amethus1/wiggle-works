class_name Saves
## Saving and loading your playground (user://playground.json).

const PATH := "user://playground.json"


static func has_slot() -> bool:
	return FileAccess.file_exists(PATH)


static func save_slot(world: World) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(world.serialize()))


static func load_slot(world: World) -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY:
		world.push_undo()
		world.restore(d)

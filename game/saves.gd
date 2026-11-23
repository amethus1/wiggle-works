class_name Saves
## Saving and loading playgrounds: 6 slots, each a file in user://playgrounds/
## (slot1.json ... slot6.json) with a little picture of it (slotN.png). A slot
## keeps its name, the world, when it was saved and the whole playground
## (World.serialize()). The single save from before (user://playground.json)
## moves into slot 1 the first time the slots are looked at.

const SLOTS := 6
const PATH := "user://playground.json"     # the old single save (migrate())
const THUMB := Vector2i(256, 144)


static func dir() -> String:
	return "user://playgrounds_test" if Settings.testing else "user://playgrounds"


static func legacy_path() -> String:
	return "user://playground_test.json" if Settings.testing else PATH


static func path(slot: int) -> String:
	return "%s/slot%d.json" % [dir(), slot]


static func thumb_path(slot: int) -> String:
	return "%s/slot%d.png" % [dir(), slot]


## The old single save becomes slot 1 (if slot 1 is free), and the old file is
## kept as playground.json.old. True if it moved one.
static func migrate() -> bool:
	var old := legacy_path()
	if not FileAccess.file_exists(old) or FileAccess.file_exists(path(1)):
		return false
	var f := FileAccess.open(old, FileAccess.READ)
	if f == null:
		return false
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not d is Dictionary:
		return false
	var wid := String((d as Dictionary).get("world", "meadow"))
	var when := Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(old), true)
	if not _write(1, {"v": 2, "name": "My playground", "world": wid, "when": when, "data": d}):
		return false
	DirAccess.rename_absolute(old, old + ".old")
	return true


## Any slot used? (`slot` 0), or that slot?
static func has_slot(slot := 0) -> bool:
	migrate()
	if slot > 0:
		return FileAccess.file_exists(path(slot))
	for i in SLOTS:
		if FileAccess.file_exists(path(i + 1)):
			return true
	return false


## Saves the playground in `slot`. `name` "" keeps the slot's old name (or
## names it after the world); `thumb` is a picture of it (or none).
static func save_slot(world: World, slot := 1, name := "", thumb: Image = null) -> bool:
	migrate()
	if slot < 1 or slot > SLOTS:
		return false
	var wd: Dictionary = Catalog.world_def(world.world_id)
	if name.strip_edges() == "":
		name = String(read(slot).get("name", ""))
	if name.strip_edges() == "":
		name = "%s %s" % [wd.get("emoji", "🫧"), wd.get("name", "My playground")]
	var ok := _write(slot, {"v": 2, "name": name.strip_edges().left(24), "world": world.world_id,
		"when": Time.get_datetime_string_from_system(false, true), "data": world.serialize()})
	if ok:
		if thumb != null and not thumb.is_empty():
			var img := thumb.duplicate() as Image
			img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_BILINEAR)
			img.save_png(thumb_path(slot))
		elif FileAccess.file_exists(thumb_path(slot)):
			DirAccess.remove_absolute(thumb_path(slot))      # (an old picture of something else)
	return ok


static func _write(slot: int, d: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir())
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	return true


## Slot `slot` as saved: {name, world, when, data}, or {} if it's empty.
## (A raw playground with no name around it, like the old save, still reads.)
static func read(slot: int) -> Dictionary:
	if not FileAccess.file_exists(path(slot)):
		return {}
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return {}
	var dd: Dictionary = d
	if not dd.has("data"):
		return {"name": "My playground", "world": String(dd.get("world", "meadow")), "when": "", "data": dd}
	return dd


static func load_slot(world: World, slot := 1) -> bool:
	migrate()
	var d := read(slot)
	var data: Variant = d.get("data")
	if not data is Dictionary:
		return false
	world.push_undo()
	world.restore(data as Dictionary)
	return true


## Gives slot `slot` a new name (kept short).
static func rename(slot: int, name: String) -> bool:
	var d := read(slot)
	if d.is_empty() or name.strip_edges() == "":
		return false
	d["name"] = name.strip_edges().left(24)
	d["v"] = 2
	return _write(slot, d)


## Slot `slot`'s picture, or null.
static func thumb(slot: int) -> Texture2D:
	var p := thumb_path(slot)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## "Sat 21:40" style: when slot `slot` was saved ("" if it doesn't say).
static func when_text(d: Dictionary) -> String:
	var w := String(d.get("when", "")).replace("T", " ")
	return w.substr(0, 16) if w.length() >= 16 else w


static func delete_all_test_saves() -> void:
	if not Settings.testing:
		return
	for i in SLOTS:
		for p in [path(i + 1), thumb_path(i + 1)]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
	for p in [legacy_path(), legacy_path() + ".old"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

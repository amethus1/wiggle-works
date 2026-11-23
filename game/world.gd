class_name World
extends Node2D
## The playground: terrain, water, toys, Wigglies, links, power, magic and
## stickers. Every player action arrives as a command (apply_command), so a
## friend's clicks over Wi-Fi go through exactly the same code as yours.
## On a network client the world is a "puppet": it draws what the host sends.

signal fx(name: String, args: Dictionary)   # every visual/sound event (the host forwards these)
## rebuilt: the playground was loaded, undone or cleared (old effects go too);
## false when only a setting changed (pause, speed, night, gravity, fighting).
signal world_changed(rebuilt: bool)

const UNDO_MAX := 15
const MAX_TOYS := 420
const MAX_WIGGLIES := 40
const MAX_FIGHTERS := 120
const BURIED := 16.0           # px: something whose middle is this deep in the ground is stuck in it (see _cleanup)
const SPLIT_STRETCH := 2.35

## Speed checks (tests/test_bench2d.gd): more fighters than the game allows,
## and how long each part of a physics step takes (microseconds, in `prof`).
var max_fighters := MAX_FIGHTERS
static var profiling := false
var prof := {}
var _prof_t := 0

var world_id := "meadow"
var gravity_id := "normal"
var paused := false
var time_scale := 1.0
var night := false
var allow_world_actions := true
var puppet := false
var vision_time := 0.0

var terrain: Node2D
var water_view: Node2D
var bodies: Node2D
var wiggly_layer: Node2D
var link_view: Node2D
var pin_parent: Node2D
var backdrop: Backdrop
var decor: Node2D
var night_tint: CanvasModulate

var water: Array = []        # Rect2 areas (top edge = surface)
var water_shapes: Array = [] # [{poly, top, x0, x1}] water cut to the shape of the ground
var water_version := 0       # goes up every time water_shapes is worked out again (WaterView redraws then)
var bounds := Rect2(-2000, -1800, 4000, 3200)
var view_rect := Rect2(-900, -650, 1800, 1100)
var spawn_points: Array = [Vector2(0, -200)]
var next_uid := 1
## uid -> Toy | Wiggly | Fighter. Change it only through _put_thing, _drop_thing,
## renumber and forget (or _clear_all), which keep the lists below up to date.
var things := {}
var links: Array = []
var grabs := {}              # player id -> grab dict
var magic := {}              # magic id -> seconds left
var wind_dir := 1.0
var booms := 0
var _undo: Array = []
var _undo_key := ""            # the last small change saved for undo (see push_undo)
var _undo_at := 0
var _sticker_t := 0.0
var _ball_rain := 0
var _ball_rain_t := 0.0
var battle_on := true          # fighters fight (off = everyone just stands around)
var auto_clean := true         # KO'd fighters disappear after a while
var last_winner := ""
## Stand-offs: seconds of battle with nobody hurt. After a while everyone gets
## `brave` and charges straight at their enemy (hopping off towers and walls),
## so two shooters with a wall between them can't stall a battle forever.
## (Only while two teams are up: building an army on your own isn't a
## stand-off, or the charge went off the moment an enemy was put down.)
const QUIET_CHARGE := 15.0
var quiet_t := 0.0
var brave := false
var teams_up := 0              # teams (not wild beasts) with someone still standing (see Combat.battle_check)
var fires: Array = []          # burning ground: {p, r, t}
var liquid_kinds: Array = []   # kind of each water rect: water | lava | acid
var liquid_groups: Array = []  # which placed tub each liquid belongs to (0 = part of the world)
var platforms: Array = []      # {poly, style, group, node}
var next_group := 1
var fighter_layer: Node2D
var ko_stars: Node2D            # the knocked-out fighters' spinning stars (FighterArt.KoStars)
var _battle_t := 0.0
var _strikes: Array = []       # bombs and shells still to drop: {t, p, kind}
var _impacts: Array = []       # collisions waiting to be handled (see queue_impact)
var cars_on := 0               # go-karts and monster trucks driving (last step)
var flung := 0                 # things that left the world through the floor or the sides (bench2d counts them)
var blown := 0                 # ...of them, ones already miles past the edge: thrown there in a single step
var _water_hold := 0           # above 0: adding several platforms, cut the water once at the end
var _jelly_q: PhysicsShapeQueryParameters2D = null
# fighters(), toys() and wigglies(), rebuilt only after `things` (or the
# fighter layer) changes. Read-only: they're handed out, never changed in place,
# so anyone looping over one while things come and go keeps a steady list.
var _fighter_list: Array = []
var _toy_list: Array = []
var _wiggly_list: Array = []
var _fighters_ok := false
var _toys_ok := false
var _wigglies_ok := false
var _lists_n := [-1, -1, -1, -1]   # things.size() each list was made from (a safety net)
var _all_list: Array = []        # all_things()
var _all_ok := false
# ride_parts(): which toys belong to which ride, worked out again when the toy
# list or anyone's parent_uid changes
var parent_changes := 0
var _parts_of := {}
var _parts_src: Array = []
var _parts_stamp := -1
const _NO_PARTS: Array = []


func _ready() -> void:
	night_tint = CanvasModulate.new()
	night_tint.color = Color.WHITE
	add_child(night_tint)
	backdrop = Backdrop.new()
	backdrop.world = self
	add_child(backdrop)
	water_view = WaterView.new()
	water_view.world = self
	terrain = Node2D.new()
	terrain.name = "Terrain"
	decor = Node2D.new()
	decor.name = "Decor"
	bodies = Node2D.new()
	bodies.name = "Bodies"
	pin_parent = Node2D.new()
	pin_parent.name = "Pins"
	wiggly_layer = Node2D.new()
	wiggly_layer.name = "Wigglies"
	link_view = LinkView.new()
	link_view.world = self
	fighter_layer = Node2D.new()
	fighter_layer.name = "Fighters"
	ko_stars = FighterArt.KoStars.new()
	ko_stars.name = "KoStars"
	ko_stars.world = self
	var glow := NightLights.new()   # (lava, fires, glowing Wigglies and laser swords light up the night)
	glow.name = "NightLights"
	glow.world = self
	for n in [decor, terrain, bodies, pin_parent, link_view, fighter_layer, ko_stars, wiggly_layer, water_view, glow]:
		add_child(n)
	fighter_layer.child_entered_tree.connect(func(_n: Node) -> void: _fighters_ok = false)
	fighter_layer.child_exiting_tree.connect(func(_n: Node) -> void: _fighters_ok = false)


# ------------------------------------------------------------------ worlds
func load_world(id: String, with_starters := true) -> void:
	_clear_all()
	world_id = id
	for c in terrain.get_children():
		c.queue_free()
	for c in decor.get_children():
		c.queue_free()
	water.clear()
	liquid_kinds.clear()
	liquid_groups.clear()
	platforms.clear()
	_water_hold += 1
	Worlds.build(self, id)
	_water_hold -= 1
	while liquid_kinds.size() < water.size():
		liquid_kinds.append("water")
		liquid_groups.append(0)
	_cut_water()
	set_gravity(Worlds.default_gravity(id))
	set_night(Worlds.starts_at_night(id))
	if with_starters and not puppet:
		Worlds.add_starters(self, id)
	_undo.clear()
	Settings.mark("worlds", id, "explorer", Catalog.WORLDS.size())
	world_changed.emit(true)


## Water areas are rectangles; cut away the ground so only the pond shows.
func _cut_water() -> void:
	if _water_hold > 0:
		return   # (whoever is adding platforms cuts it once they're all there)
	water_version += 1
	water_shapes.clear()
	for wi in water.size():
		var rect: Rect2 = water[wi]
		var pieces: Array = [PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])]
		for g in terrain.get_children():
			# ground from the last world (or a removed platform) is still here until
			# the end of the frame: it mustn't cut holes in the new water
			if not (g is Ground) or g.is_queued_for_deletion():
				continue
			var next: Array = []
			for pc in pieces:
				for out in Geometry2D.clip_polygons(pc, g.poly):
					# clockwise pieces are holes (ground sunk completely in the water)
					if not Geometry2D.is_polygon_clockwise(out):
						next.append(out)
			pieces = next
		for pc in pieces:
			var x0 := INF
			var x1 := -INF
			for v in pc:
				if absf(v.y - rect.position.y) < 1.0:
					x0 = minf(x0, v.x)
					x1 = maxf(x1, v.x)
			water_shapes.append({"poly": pc, "top": rect.position.y, "x0": x0, "x1": x1, "kind": liquid_kinds[wi] if wi < liquid_kinds.size() else "water"})


## Adds a pool of water, lava or acid (its top edge is the surface).
func add_liquid(r: Rect2, kind: String, group := 0) -> void:
	water.append(r)
	liquid_kinds.append(kind)
	liquid_groups.append(group)


## "" if `p` is not in any liquid, else water / lava / acid.
func in_liquid(p: Vector2) -> String:
	for i in water.size():
		if water[i].has_point(p):
			return String(liquid_kinds[i]) if i < liquid_kinds.size() else "water"
	return ""


# -------------------------------------------------------------- platforms
func add_platform(poly: PackedVector2Array, style: String, group := 0) -> Ground:
	if group == 0:
		next_group += 1
		group = next_group
	var g := Ground.new()
	g.setup(poly, Worlds.platform_style(style), group)
	g.set_meta("group", group)
	terrain.add_child(g)
	var hp := _platform_hp(poly, style)
	platforms.append({"poly": poly, "style": style, "group": group, "node": g, "hp": hp, "max": hp})
	_cut_water()
	wake_resting()   # (one built right on top of a knocked-out fighter pushes it out)
	return g


## How much blasting a platform you built takes before it breaks: wood least,
## concrete most, and big ones more than small ones.
const PLATFORM_HP := {"wood": 160.0, "stone": 320.0, "metal": 420.0, "steel": 420.0, "concrete": 520.0, "rock": 520.0}


static func _platform_hp(poly: PackedVector2Array, style: String) -> float:
	var area := 0.0
	for i in poly.size():
		area += poly[i].cross(poly[(i + 1) % poly.size()])
	return float(PLATFORM_HP.get(style, 300.0)) * clampf(absf(area) * 0.5 / 5000.0, 0.6, 2.5)


## Can blasts break this platform? Only ones you built (the world's own forts,
## catwalks and islands stay), and not the walls of a tub (the lava would go
## everywhere).
func platform_breakable(pl: Dictionary) -> bool:
	return int(pl.group) > 0 and not liquid_groups.has(int(pl.group))


## An explosion at `p` cracks the platforms you built nearby, and breaks them
## once they've taken enough (see Combat.blast).
func damage_platforms(p: Vector2, rad: float, dmg: float) -> void:
	if puppet:
		return
	var broke: Array = []
	for pl in platforms:
		if not platform_breakable(pl):
			continue
		var poly: PackedVector2Array = pl.poly
		var d := 0.0
		var near := p
		if not Geometry2D.is_point_in_polygon(p, poly):
			d = INF
			for i in poly.size():
				var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
				if p.distance_to(q) < d:
					d = p.distance_to(q)
					near = q
		if d > rad:
			continue
		pl.hp = float(pl.get("hp", 100.0)) - dmg * 2.2 * (1.0 - d / rad)
		if pl.hp <= 0.0:
			broke.append(pl)
		elif is_instance_valid(pl.node):
			var before: int = pl.node.cracks
			(pl.node as Ground).set_damage(1.0 - float(pl.hp) / maxf(1.0, float(pl.get("max", 100.0))))
			if pl.node.cracks != before:
				fx_event("plat_crack", {"p": near, "c": (pl.node as Ground).style.get("fill", Color.GRAY)})
	for pl in broke:
		_break_platform(pl)


## A platform blown to bits: whatever stood on it falls.
func _break_platform(pl: Dictionary) -> void:
	platforms.erase(pl)
	var poly: PackedVector2Array = pl.poly
	var box := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		box = box.expand(v)
	var col: Color = Worlds.platform_style(String(pl.style)).get("fill", Color.GRAY)
	if is_instance_valid(pl.node):
		pl.node.queue_free()
	fx_event("plat_break", {"p": box.get_center(), "w": box.size.x, "h": box.size.y, "c": col})
	_cut_water.call_deferred()
	wake_resting()


func platform_at(p: Vector2) -> int:
	for pl in platforms:
		if Geometry2D.is_point_in_polygon(p, pl.poly):
			return int(pl.group)
	return 0


## Removes every platform (and tub liquid) in a group.
func remove_platform_group(group: int) -> void:
	if group == 0:
		return
	var keep: Array = []
	for pl in platforms:
		if int(pl.group) == group:
			if is_instance_valid(pl.node):
				pl.node.queue_free()
				fx_event("crumble", {"p": _poly_center(pl.poly)})
		else:
			keep.append(pl)
	platforms = keep
	for i in range(water.size() - 1, -1, -1):
		if i < liquid_groups.size() and int(liquid_groups[i]) == group:
			water.remove_at(i)
			liquid_kinds.remove_at(i)
			liquid_groups.remove_at(i)
	_cut_water.call_deferred()
	wake_resting()   # knocked-out fighters lying on it fall


## Knocked-out ragdolls lying still (frozen, see Fighter._rest_check) move
## again: all of them, or the ones within `r` of `p`. For the gravity
## changing, or the ground (or a toy) going from under them.
func wake_resting(p := Vector2.INF, r := 0.0, and_neighbours := true) -> void:
	for f in fighters():
		if f.is_resting() and (p == Vector2.INF or f.center().distance_to(p) < r + f.radius() * 2.0):
			f.wake(and_neighbours)


static func _poly_center(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in poly:
		c += v
	return c / maxf(1.0, poly.size())


static func rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func set_gravity(id: String) -> void:
	gravity_id = id
	var g: Vector2 = Catalog.gravity_def(id).g
	if magic.has("float"):
		g = Vector2(0, -60)
	var space := get_world_2d().space
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY, g.length())
	PhysicsServer2D.area_set_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY_VECTOR, g.normalized() if g != Vector2.ZERO else Vector2.DOWN)
	wake_resting()   # knocked-out ragdolls lying still feel the new gravity too


func gravity_dir() -> Vector2:
	var g: Vector2 = Catalog.gravity_def(gravity_id).g
	if magic.has("float"):
		return Vector2.ZERO
	return g.normalized() if g != Vector2.ZERO else Vector2.ZERO


## Gravity right now, in px/s² (Float Away makes it a gentle pull upward).
func gravity_vec() -> Vector2:
	if magic.has("float"):
		return Vector2(0, -60)
	return Catalog.gravity_def(gravity_id).g


func set_night(on: bool) -> void:
	night = on
	night_tint.color = Color(0.36, 0.4, 0.62) if on else Color.WHITE
	for t in all_things():
		if t is Toy:
			ToyLogic.update_light(self, t)


func set_paused(p: bool) -> void:
	paused = p
	if not puppet:
		PhysicsServer2D.set_active(not p)


func set_speed(s: float) -> void:
	time_scale = clampf(s, 0.1, 2.0)
	if not puppet:
		Engine.time_scale = time_scale


# ---------------------------------------------------------------- spawning
func _uid() -> int:
	next_uid += 1
	return next_uid


func spawn(id: String, pos: Vector2, team := "", pers := "") -> Node:
	if id.begins_with("f:"):
		return spawn_fighter(id.substr(2), pos, team, pers)
	if id.begins_with("plat:"):
		var pd := Catalog.platform_def(id.substr(5))
		if pd.is_empty():
			return null
		return Builders.platform_preset(self, String(pd.id), pos)
	if id.begins_with("w:"):
		return spawn_wiggly(id.substr(2), pos)
	if id.begins_with("build:"):
		return Builders.build(self, id.substr(6), pos)
	var d := Catalog.toy(id)
	if d.is_empty():
		return null
	if d.has("tub"):
		return Builders.tub(self, id, pos)
	if d.has("build"):
		return Builders.ride(self, id, pos)
	return spawn_toy(id, pos)


## People, animals and dinosaurs. They come with their usual weapon.
func spawn_fighter(type: String, pos: Vector2, team := "", pers := "", s := 1.0, armed := true) -> Fighter:
	if Catalog.fighter(type).is_empty() or fighters().size() >= max_fighters:
		return null
	var f := Fighter.new()
	f.uid = _uid()
	f.setup(self, type, pos, team, pers, s)
	if puppet:
		f.puppet = true
	fighter_layer.add_child(f)
	_put_thing(f.uid, f)
	if not puppet:
		f.make_standing(pos)
		f.home = f.center()
		var wid := String(f.def.get("weapon", ""))
		if armed and wid != "":
			var wt := spawn_toy(wid, f.center())
			if wt:
				f.equip(wt)
		if type == "trex":
			Settings.award("dino")
	return f


## Everyone on the fighter layer that's still in the world, in the order they
## were added. Don't change the list you get (it's shared and read-only).
func fighters() -> Array:
	if not _fighters_ok or int(_lists_n[0]) != things.size():
		_fighter_list = fighter_layer.get_children().filter(func(f): return f is Fighter and things.get(f.uid) == f)
		_fighter_list.make_read_only()
		_fighters_ok = true
		_lists_n[0] = things.size()
	return _fighter_list


## Moves a spawn point up until a circle of radius `r` there is clear of the ground.
func lift_out_of_ground(pos: Vector2, r: float) -> Vector2:
	var p := pos
	for step in 80:
		var blocked := false
		for g in terrain.get_children():
			if not (g is Ground):
				continue
			for k in 9:
				var q := p if k == 8 else p + Vector2.from_angle(TAU * k / 8.0) * r
				if Geometry2D.is_point_in_polygon(q, g.poly):
					blocked = true
					break
			if blocked:
				break
		if not blocked:
			return p
		p.y -= 12.0
	return pos


## True if `p` is inside the solid ground (or a platform).
func in_ground(p: Vector2) -> bool:
	for g in terrain.get_children():
		if g is Ground and Geometry2D.is_point_in_polygon(p, g.poly):
			return true
	return false


## Back out on top of the ground, standing still (see _cleanup).
func _unbury(t) -> void:
	if t is Fighter:
		t.unbury()
	elif t is Toy and not t.freeze and t.parent_uid == 0 and not t.def.has("build"):   # (not part of a ride: that would tear it apart)
		var to := lift_out_of_ground(t.global_position, minf(t.half_extents().x, t.half_extents().y) * 0.9)
		if to != t.global_position:
			t.global_position = to
			t.linear_velocity = Vector2.ZERO
			t.angular_velocity = 0.0


func spawn_toy(id: String, pos: Vector2, rot := 0.0, s := 1.0, def_override := {}) -> Toy:
	if count_toys() >= MAX_TOYS:
		return null
	var d: Dictionary = def_override if not def_override.is_empty() else Catalog.toy(id)
	if not puppet and def_override.is_empty():
		var ext := Vector2(float(d.get("w", d.get("r", 12) * 2)), float(d.get("h", d.get("r", 12) * 2))) * 0.5 * s
		pos = lift_out_of_ground(pos, minf(ext.x, ext.y) * 0.9)
	var t := Toy.new()
	t.world = self
	t.uid = _uid()
	t.setup(id, d, pos, rot, s)
	if id == "conveyor":
		t.on = true
	bodies.add_child(t)
	_put_thing(t.uid, t)
	ToyLogic.on_spawn(self, t)
	if puppet:
		t.make_puppet()
	return t


func spawn_wiggly(kind: String, pos: Vector2, s := 1.0) -> Wiggly:
	if count_wigglies() >= MAX_WIGGLIES:
		return null
	var w := Wiggly.new()
	w.uid = _uid()
	if not puppet:
		pos = lift_out_of_ground(pos, Wiggly.BASE_R * s * 1.15)
	w.setup(self, kind, pos, s)
	if puppet:
		w.puppet = true
	else:
		w.make_bodies(bodies)
	wiggly_layer.add_child(w)
	_put_thing(w.uid, w)
	return w


func count_toys() -> int:
	return toys().size()


func count_wigglies() -> int:
	return wigglies().size()


## Every Wiggly, in `things` order. Shared and read-only, like fighters().
func wigglies() -> Array:
	if not _wigglies_ok or int(_lists_n[2]) != things.size():
		_wiggly_list = all_things().filter(func(t): return t is Wiggly)
		_wiggly_list.make_read_only()
		_wigglies_ok = true
		_lists_n[2] = things.size()
	return _wiggly_list


## Fighters sorted into strips SEP_W px wide, per team, once a physics step
## (see teammates_near).
const SEP_W := 64.0
var _sep_frame := -1
var _sep_src: Array = []
var _sep_strips := {}            # team -> {strip number: [indices into fighters()]}
var _sep_out := PackedInt32Array()


## The fighters of `team` whose middle is between `x0` and `x1` (give or take
## a strip), as indices into fighters(), in that list's order. Fighters spread
## out from teammates close by: looking only in the nearby strips instead of
## at the whole army makes that O(n) instead of O(n²). It's only a first sift:
## callers check the real distance (and the fighter's state) themselves, so
## the answers are the same as looking at everyone. Shared: don't keep it.
func teammates_near(team: String, x0: float, x1: float) -> PackedInt32Array:
	var fl := fighters()
	var frame := Engine.get_physics_frames()
	if frame != _sep_frame or not is_same(fl, _sep_src):
		_sep_frame = frame
		_sep_src = fl
		_sep_strips.clear()
		for i in fl.size():
			var f: Fighter = fl[i]
			if not _sep_strips.has(f.team):
				_sep_strips[f.team] = {}
			var strips: Dictionary = _sep_strips[f.team]
			var k := floori(f.center().x / SEP_W)
			if not strips.has(k):
				strips[k] = []
			(strips[k] as Array).append(i)
	_sep_out.clear()
	var mine: Dictionary = _sep_strips.get(team, {})
	if mine.is_empty():
		return _sep_out
	# (one strip more each side: someone can be moved a little during the step)
	for k in range(floori(x0 / SEP_W) - 1, floori(x1 / SEP_W) + 2):
		var strip: Array = mine.get(k, [])
		for i in strip:
			_sep_out.append(i)
	_sep_out.sort()
	return _sep_out


## Every toy, Wiggly and fighter: `things.values()`, in the same order, without
## making a new list every time (fans, magnets, the saucer's beam and blasts
## look through everything every step). Shared and read-only, like fighters().
func all_things() -> Array:
	if not _all_ok or int(_lists_n[3]) != things.size():
		_all_list = things.values()
		_all_list.make_read_only()
		_all_ok = true
		_lists_n[3] = things.size()
	return _all_list


## Every toy (ride parts, weapons and flying rockets too), in `things` order.
## Shared and read-only, like fighters().
func toys() -> Array:
	if not _toys_ok or int(_lists_n[1]) != things.size():
		_toy_list = all_things().filter(func(t): return t is Toy)
		_toy_list.make_read_only()
		_toys_ok = true
		_lists_n[1] = things.size()
	return _toy_list


## A ride's parts (wheels, its balloon or sail): the toys whose parent_uid is
## `uid`, in `things` order. Shared: don't change the list.
func ride_parts(uid: int) -> Array:
	var ts := toys()
	if not is_same(ts, _parts_src) or _parts_stamp != parent_changes:
		_parts_of.clear()
		for t in ts:
			if t.parent_uid != 0:
				if not _parts_of.has(t.parent_uid):
					_parts_of[t.parent_uid] = []
				_parts_of[t.parent_uid].append(t)
		_parts_src = ts
		_parts_stamp = parent_changes
	return _parts_of.get(uid, _NO_PARTS)


func _put_thing(uid: int, t) -> void:
	if things.has(uid):
		_list_changed(things[uid])
	things[uid] = t
	_list_changed(t)


func _drop_thing(uid: int) -> void:
	if things.has(uid):
		_list_changed(things[uid])
		things.erase(uid)


## Gives a toy, Wiggly or fighter another number (loading a save, or a friend's
## copy taking the host's number). Whatever already had that number is dropped.
func renumber(t, uid: int) -> void:
	_drop_thing(t.uid)
	t.uid = uid
	_put_thing(uid, t)


## Loading: something just made takes its saved number, unless (in a broken
## save) another loaded thing has it already: then it keeps its new one.
func _take_saved_number(t, uid: int) -> void:
	if uid > 0 and not (things.has(uid) and things[uid] != t):
		renumber(t, uid)


## Takes `uid` out of the world's lists without freeing anything (Wi-Fi puppets).
func forget(uid: int) -> void:
	_drop_thing(uid)


func _list_changed(t) -> void:
	_all_ok = false
	if not is_instance_valid(t):
		_fighters_ok = false
		_toys_ok = false
		_wigglies_ok = false
	elif t is Fighter:
		_fighters_ok = false
	elif t is Toy:
		_toys_ok = false
	elif t is Wiggly:
		_wigglies_ok = false


func remove(uid: int, effect := true) -> void:
	var t = things.get(uid)
	if t == null:
		return
	_drop_thing(uid)
	var p := _pos_of(t)
	# whatever was lying on it falls
	wake_resting(p, (t.bound_radius() if t is Toy else t.radius()) + 60.0)
	if t is Wiggly:
		for pid in grabs.keys():
			if grabs[pid].uid == uid:
				grabs.erase(pid)
		for l in links:
			if l.a is JellyPoint and l.a.wiggly == t or l.b is JellyPoint and l.b.wiggly == t:
				l.destroy()
		t.free_bodies()
		t.queue_free()
	elif t is Fighter:
		for pid in grabs.keys():
			if grabs[pid].uid == uid:
				grabs.erase(pid)
		for l in links:
			if l.a is FighterPart and l.a.fighter == t or l.b is FighterPart and l.b.fighter == t:
				l.destroy()
		t._drop_weapon(Vector2.ZERO)
		t.free_bodies()
		t.queue_free()
	else:
		for l in links:
			if l.a == t or l.b == t:
				l.destroy()
		for pid in grabs.keys():
			if grabs[pid].uid == uid:
				grabs.erase(pid)
		# parts of a ride go with it
		for o in all_things():
			if o is Toy and o.parent_uid == uid:
				remove(o.uid, false)
		ToyLogic.on_remove(self, t)
		t.queue_free()
	links = links.filter(func(l): return not l.broken)
	if effect:
		fx_event("poof", {"p": p})


func _clear_all() -> void:
	for uid in things.keys():
		var t = things[uid]
		if t is Wiggly or t is Fighter:
			t.free_bodies()
		t.queue_free()
	things.clear()
	_all_ok = false
	_fighters_ok = false
	_toys_ok = false
	_wigglies_ok = false
	fires.clear()
	_strikes.clear()
	last_winner = ""
	quiet_t = 0.0
	brave = false
	teams_up = 0
	for l in links:
		l.destroy()
	links.clear()
	grabs.clear()
	magic.clear()


func clear_toys() -> void:
	push_undo()
	_clear_all()
	clear_placed()


## Takes away every platform and pit the players built (the world's own stay).
func clear_placed() -> void:
	var groups := {}
	# placed things have groups above 0; the world's own forts and catwalks are below 0
	for pl in platforms:
		if int(pl.group) > 0:
			groups[int(pl.group)] = true
	for i in liquid_groups.size():
		if int(liquid_groups[i]) > 0:
			groups[int(liquid_groups[i])] = true
	for g in groups:
		remove_platform_group(g)


func get_thing(uid: int):
	return things.get(uid)


func _pos_of(t) -> Vector2:
	if t is Wiggly:
		return t.com
	if t is Fighter:
		return t.center()
	return t.global_position


# ------------------------------------------------------------------ links
func add_link(kind: String, a: PhysicsBody2D, b: PhysicsBody2D, pa: Vector2, pb: Vector2) -> Link:
	if a == null or b == null or a == b:
		return null
	var l := Link.new()
	l.setup(kind, a, b, pa, pb)
	l.uid_a = _owner_uid(a)
	l.uid_b = _owner_uid(b)
	if l.uid_a == l.uid_b and l.uid_a != 0:
		return null
	l.build(pin_parent)
	links.append(l)
	for body in [a, b]:
		if body is FighterPart and body.fighter:
			body.fighter.wake()   # (a knocked-out fighter lying still: the rope or glue can move it now)
	return l


## Toy `a` passes through toy `b` from now on, and goes on doing so after a
## save, an undo or loading (the Spinny Wheel's arms and seats turn in front
## of its post). Kept in `a.extra.nc`: asking the physics for a body's list
## complains about bodies that have gone since.
func no_collide(a: Toy, b: Toy) -> void:
	a.add_collision_exception_with(b)
	if not a.extra.has("nc"):
		a.extra.nc = []
	if not (a.extra.nc as Array).has(b.uid):
		(a.extra.nc as Array).append(b.uid)


func _owner_uid(body: PhysicsBody2D) -> int:
	if body is JellyPoint:
		return body.wiggly.uid
	if body is FighterPart:
		return body.fighter.uid
	if body is Toy:
		return body.uid
	return 0


func links_of(uid: int) -> Array:
	return links.filter(func(l): return l.uid_a == uid or l.uid_b == uid)


## The physics body under `p` for linking: a toy, or the nearest edge point of a Wiggly.
func body_at(p: Vector2) -> PhysicsBody2D:
	var t = thing_at(p)
	if t is Toy:
		return t
	if t is Wiggly and not t.points.is_empty():
		return t.points[t.nearest_point(p)]
	if t is Fighter:
		return t.body_near(p)
	return null


## The toy, Wiggly or fighter under `p` (topmost first).
func thing_at(p: Vector2, pad := 6.0):
	for w in wiggly_layer.get_children():
		if w is Wiggly and things.get(w.uid) == w and w.hit_test(p):
			return w
	var fs := fighter_layer.get_children()
	for i in range(fs.size() - 1, -1, -1):
		var f = fs[i]
		if f is Fighter and things.get(f.uid) == f and f.hit_test(p):
			return f
	var kids := bodies.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var t = kids[i]
		if t is Toy and things.get(t.uid) == t and t.hit_test(p):
			return _holder_or(t)
	for i in range(kids.size() - 1, -1, -1):
		var t = kids[i]
		if t is Toy and things.get(t.uid) == t and t.hit_test(p, pad):
			return _holder_or(t)
	return null


## A weapon in someone's hands counts as part of them: clicking it picks the person.
func _holder_or(t: Toy):
	if t.extra.has("held_by"):
		var f = things.get(int(t.extra.held_by))
		if f is Fighter:
			return f
	return t


# --------------------------------------------------------------- commands
## Everything a player can do. pid 0 = the local/host player.
func apply_command(pid: int, c: Dictionary) -> void:
	var t = things.get(int(c.get("uid", -1)))
	var at := Vector2(float(c.get("x", 0.0)), float(c.get("y", 0.0)))
	match String(c.get("cmd", "")):
		"spawn":
			push_undo()
			var made = spawn(String(c.id), at, String(c.get("team", "")), String(c.get("pers", "")))
			if made:
				fx_event("spawn", {"p": at})
				if made is Wiggly:
					Settings.award("hello")
					if count_wigglies() >= 12:
						Settings.award("family")
		"grab":
			if t:
				grab_start(pid, t, at)
		"drag":
			if grabs.has(pid):
				grabs[pid].target = at
				grabs[pid].whole = bool(c.get("whole", false))
				grabs[pid].seen = Time.get_ticks_msec()
		"release":
			grab_end(pid)
		"use":
			if t is Toy or t is Wiggly or t is Fighter:
				push_undo("use %d" % t.uid)
			if t is Toy:
				ToyLogic.use(self, t)
			elif t is Wiggly:
				t.use_special()
			elif t is Fighter and t.state == "stand" and not t.helpless():
				var en = t._nearest(func(o): return t.enemy_of(o), 900.0)
				var aim_at: Vector2 = en.center() if en else t.center() + Vector2(t.facing * 200.0, -20)
				t.aim = t._aim_at(aim_at, t._wtype())
				t._attack(aim_at, t._wtype())
		"team":
			if t is Fighter:
				push_undo("team %d" % t.uid)
				t.team = String(c.get("team", t.team))
				t.target = null
		"pers":
			if t is Fighter:
				push_undo("pers %d" % t.uid)
				t.pers = String(c.get("pers", t.pers))
				t.home = t.center()
				t.target = null
		"give":
			if t is Toy and (t.def.has("weapon") or t.def.has("armor")):
				var best: Fighter = null
				var bd := 260.0
				for f in fighters():
					if f.state == "stand" and not f.beast and f.center().distance_to(t.global_position) < bd:
						bd = f.center().distance_to(t.global_position)
						best = f
				if best and best.equip(t):
					Settings.count("gifts", "armory", 5)
				else:
					fx_event("nope", {})
		"drop":
			if t is Fighter:
				t._drop_weapon(Vector2(t.facing * 150.0, -200))
				t.weapon_id = ""
		"revive":
			# just this one fighter (✨ Heal Everyone is the spell for everybody)
			if t is Fighter:
				t.revive()
				fx_event("heal", {"p": t.center()})
		"fight":
			battle_on = bool(c.get("on", true))
			for f in fighters():
				f.target = null
			fx_event("battle_start" if battle_on else "click", {})
			world_changed.emit(false)
		"platform":
			var a := Vector2(c.x0, c.y0)
			var b := Vector2(c.x1, c.y1)
			var r := Rect2(a, Vector2.ZERO).expand(b)
			if r.size.x < 12.0:
				r = r.grow_individual(6, 0, 6, 0)
			if r.size.y < 12.0:
				r = r.grow_individual(0, 6, 0, 6)
			push_undo()
			add_platform(rect_poly(r), String(c.get("style", "wood")))
			fx_event("build", {"p": r.get_center()})
			Settings.count("platforms", "builder", 10)
		"unplatform":
			var g := platform_at(at)
			if g != 0:
				push_undo()
				remove_platform_group(g)
		"detonate":
			for o in toys():
				if o.id == "c4":
					ToyLogic.trigger(self, o)
		"link":
			var a := _resolve_body(int(c.get("a", -1)), int(c.get("ai", -1)), Vector2(c.ax, c.ay))
			var b := _resolve_body(int(c.get("b", -1)), int(c.get("bi", -1)), Vector2(c.bx, c.by))
			if a and b:
				push_undo()
				var l := add_link(String(c.kind), a, b, Vector2(c.ax, c.ay), Vector2(c.bx, c.by))
				if l:
					fx_event("link", {"p": Vector2(c.bx, c.by), "k": String(c.kind)})
					var src = things.get(l.uid_a)
					var dst = things.get(l.uid_b)
					if l.kind == "wire" and src is Toy and dst is Toy and (ToyLogic.is_source(src) or ToyLogic.is_source(dst)):
						Settings.award("inventor")
		"unlink":
			if t:
				push_undo()
				for l in links_of(t.uid):
					l.destroy()
				links = links.filter(func(l): return not l.broken)
				fx_event("click", {"p": _pos_of(t)})
		"paint":
			if t:
				push_undo("paint %d" % t.uid)
				t.paint = Color(String(c.get("color", "ffffff")))
				if t is Fighter:
					t.queue_redraw()
				fx_event("paint", {"p": _pos_of(t), "c": t.paint})
				Settings.count("paints", "painter", 10)
		"erase":
			if t:
				push_undo()
				remove(t.uid)
		"clone":
			if t:
				push_undo()
				clone(t)
		"resize":
			if t:
				push_undo("resize %d" % t.uid)
			if t is Fighter:
				resize_fighter(t, float(c.get("s", 1.0)))
			elif t is Toy:
				t.set_size(float(c.get("s", 1.0)))
			elif t is Wiggly:
				resize_wiggly(t, float(c.get("s", 1.0)))
		"flip":
			if t is Toy:
				t.set_facing(-t.facing)
			elif t is Fighter:
				t.facing = -t.facing
		"nail":
			if t is Toy and not t.extra.has("held_by"):
				t.nailed = not t.nailed
				t.update_freeze()
				fx_event("nail", {"p": t.global_position, "on": t.nailed})
		"rotate":
			if t is Toy:
				if t.freeze or paused:
					t.rotation += float(c.get("d", 0.0)) * 0.12
				else:
					t.angular_velocity = float(c.get("d", 0.0)) * 5.0
		"play":
			for w in wigglies():
				if w.player_id == pid:
					w.player_id = -1
			for f in fighters():
				if f.player_id == pid:
					f.player_id = -1
					f.want_attack = false
					f.move_input = 0.0
			if t is Wiggly:
				t.player_id = pid
				t.idle_t = 0.0
			elif t is Fighter:
				t.player_id = pid
		"input":
			for w in wigglies():
				if w.player_id == pid:
					w.move_input = clampf(float(c.get("move", 0.0)), -1.0, 1.0)
					if bool(c.get("jump", false)):
						w.want_jump = true
					if bool(c.get("special", false)):
						w.use_special()
			for f in fighters():
				if f.player_id == pid:
					f.move_input = clampf(float(c.get("move", 0.0)), -1.0, 1.0)
					if bool(c.get("jump", false)):
						f.want_jump = true
					if c.has("attack"):
						f.want_attack = bool(c.attack)
					if c.has("ax"):
						f.aim_point = Vector2(c.ax, c.ay)
		"magic":
			push_undo()
			cast_magic(String(c.get("id", "")))
		"gravity":
			set_gravity(String(c.get("id", "normal")))
			world_changed.emit(false)
		"night":
			set_night(bool(c.get("on", false)))
			world_changed.emit(false)
		"pause":
			set_paused(bool(c.get("on", false)))
			world_changed.emit(false)
		"speed":
			set_speed(float(c.get("v", 1.0)))
			world_changed.emit(false)
		"world":
			if allow_world_actions or pid == 0:
				load_world(String(c.get("id", "meadow")))
		"clear":
			if allow_world_actions or pid == 0:
				clear_toys()
				world_changed.emit(true)
		"undo":
			if allow_world_actions or pid == 0:
				undo()


func _resolve_body(uid: int, idx: int, at := Vector2.INF) -> PhysicsBody2D:
	var t = things.get(uid)
	if t is Toy:
		return t
	if t is Fighter:
		return t.body_near(at if at != Vector2.INF else t.center())
	if t is Wiggly and not t.points.is_empty():
		return t.points[clampi(idx, 0, t.points.size() - 1)]
	return null


func clone(t) -> void:
	if t is Fighter:
		var f := spawn_fighter(t.type, t.center() + Vector2(t.radius() + 30.0, -10), t.team, t.pers, t.size / float(t.def.get("scale", 1.0)))
		if f:
			f.paint = t.paint
	elif t is Wiggly:
		var w := spawn_wiggly(t.kind, t.com + Vector2(t.radius() * 2.2, -20), t.size)
		if w:
			w.paint = t.paint
	elif t is Toy and t.parent_uid == 0:
		var made = spawn(t.id, t.global_position + Vector2(t.bound_radius() * 1.6 + 10, -20))
		if made is Toy:
			made.paint = t.paint
			made.set_size(t.size_scale)
			made.rotation = t.rotation
	fx_event("spawn", {"p": _pos_of(t)})


# ------------------------------------------------------------------ grabs
func grab_start(pid: int, t, at: Vector2) -> void:
	if t is Toy and t.extra.has("held_by"):
		return   # a weapon in someone's hands goes where they go
	var g := {"uid": t.uid, "target": at, "whole": false, "seen": Time.get_ticks_msec(), "pull": 0.0}
	if t is Wiggly:
		g.idx = t.nearest_point(at)
		g.off = t.pts[g.idx] - at
		t.grabbed_by[pid] = true
		t.idle_t = 0.0
	elif t is Fighter:
		t.wake()
		if t.frozen_t > 0.0:
			t.thaw(true)   # grabbing an ice block cracks it open
		if t.state == "stand":
			t.ragdoll()
		var part: PhysicsBody2D = t.body_near(at)
		g.part = part
		g.local = part.to_local(at) if part else Vector2.ZERO
		t.held_by[pid] = true
	else:
		g.local = t.to_local(at)
	grabs[pid] = g
	fx_event("grab", {"p": at})


func grab_end(pid: int) -> void:
	if not grabs.has(pid):
		return
	var g: Dictionary = grabs[pid]
	grabs.erase(pid)
	var t = things.get(g.uid)
	if t is Fighter:
		t.held_by.erase(pid)
		t.down_t = 0.6
		t.wake()
	elif t is Toy and (t.def.has("weapon") or t.def.has("armor")):
		# drop a weapon or armor on a person to give it to them
		for f in fighters():
			if f.state == "stand" and not f.beast and f.hit_test(t.global_position, 18.0):
				if f.equip(t):
					Settings.count("gifts", "armory", 5)
				break
	if t is Wiggly:
		t.grabbed_by.erase(pid)
		# Drop a Wiggly onto one of the same kind to combine them.
		for o in wigglies():
			if o != t and o.kind == t.kind and o.com.distance_to(t.com) < (o.radius() + t.radius()) * 0.85 and not _just_popped(o, t):
				merge_wigglies(o, t)
				break


func _drive_grabs(dt: float) -> void:
	var now := Time.get_ticks_msec()
	for pid in grabs.keys():
		var g: Dictionary = grabs[pid]
		var t = things.get(g.uid)
		if t == null or (pid != 0 and now - int(g.seen) > 1500):
			grab_end(pid)
			continue
		var target: Vector2 = g.target
		if t is Wiggly:
			if t.points.is_empty():
				continue
			if paused:
				# physics is stopped, so pushing won't move it: carry the whole Wiggly
				var mv: Vector2 = target + g.off - t.points[int(g.idx)].global_position
				t.teleport(t.com + mv)
				continue
			if g.whole or t.frozen_t > 0.0:
				var d: Vector2 = target - t.com
				for p in t.points:
					p.linear_velocity = d * 14.0
				continue
			var n := Wiggly.N
			for k in [-1, 0, 1]:
				var i: int = (int(g.idx) + k + n) % n
				var body: JellyPoint = t.points[i]
				var want: Vector2 = target + g.off
				var err := want - body.global_position
				body.linear_velocity = (err * (22.0 if k == 0 else 12.0)).limit_length(2800.0)
			if t.stretch > SPLIT_STRETCH:
				g.pull += dt
				if g.pull > 0.12:
					split_wiggly(t, pid)
			else:
				g.pull = 0.0
		elif t is Fighter:
			var part = g.get("part")
			if part == null or not is_instance_valid(part):
				if t.state == "stand":
					t.ragdoll()
				part = t.body_near(target)
				g.part = part
				g.local = Vector2.ZERO
			if part:
				var pa: Vector2 = part.to_global(g.local)
				if paused:
					# physics is stopped: carry every piece of the ragdoll along
					for b in t.all_bodies():
						b.global_position += target - pa
				else:
					part.linear_velocity = ((target - pa) * 16.0).limit_length(2600.0)
				t.down_t = 0.0
		elif t is Toy:
			var anchor: Vector2 = t.to_global(g.local)
			var delta: Vector2 = target - anchor
			wake_resting(t.global_position, t.bound_radius() + 40.0)   # (dragging it out from under one)
			if t.freeze or paused:
				t.global_position += delta
				if t.freeze:
					PhysicsServer2D.body_set_state(t.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, t.global_transform)
			else:
				t.linear_velocity = (delta * 16.0).limit_length(2600.0)
				t.angular_velocity *= 0.85


# ---------------------------------------------------------- Wiggly magic
func split_wiggly(w: Wiggly, pid := -1) -> void:
	if w.size < 0.62:
		return
	var s: float = w.size * 0.74
	var c: Vector2 = w.com
	var g = grabs.get(pid)
	var pull_dir := Vector2.RIGHT
	if g != null:
		pull_dir = (Vector2(g.target) - c).normalized()
	var kind := w.kind
	var paint := w.paint
	var vel := w.com_vel
	remove(w.uid, false)
	var w1 := spawn_wiggly(kind, c - pull_dir * 18.0 * s, s)
	var w2 := spawn_wiggly(kind, c + pull_dir * 30.0 * s, s)
	for nw in [w1, w2]:
		if nw:
			nw.paint = paint
			nw.dizzy_t = 1.2
			nw.set_meta("popped_t", nw.t)
	if w1:
		w1.set_velocity(vel - pull_dir * 260.0)
	if w2:
		w2.set_velocity(vel + pull_dir * 260.0)
		# remove() let go of the old Wiggly, so keep hold of this half instead
		if pid >= 0 and g != null:
			grab_start(pid, w2, Vector2(g.target))
	fx_event("split", {"p": c, "k": kind})
	Settings.award("pop")


## The two halves of a Wiggly that just popped: letting go of one right away
## mustn't stick them straight back together.
func _just_popped(a: Wiggly, b: Wiggly) -> bool:
	return a.t - float(a.get_meta("popped_t", -INF)) < 1.0 and b.t - float(b.get_meta("popped_t", -INF)) < 1.0


func merge_wigglies(a: Wiggly, b: Wiggly) -> void:
	var s := minf(2.2, sqrt(a.size * a.size + b.size * b.size))
	var c := (a.com * a.size + b.com * b.size) / (a.size + b.size)
	var kind := a.kind
	var paint := a.paint
	remove(a.uid, false)
	remove(b.uid, false)
	var w := spawn_wiggly(kind, c + Vector2(0, -10), s)
	if w:
		w.paint = paint
		w.party_t = 1.5
	fx_event("merge", {"p": c, "k": kind})


func resize_wiggly(w: Wiggly, s: float) -> void:
	var c := w.com
	var kind := w.kind
	var paint := w.paint
	var pid := w.player_id
	remove(w.uid, false)
	var nw := spawn_wiggly(kind, c, s)
	if nw:
		nw.paint = paint
		nw.player_id = pid


func zap_area(c: Vector2, rad: float, from: Wiggly) -> void:
	var hits: Array = []
	var zapped: Array = []
	var metal: Array = []
	for t in all_things():
		if t == from:
			continue
		var p := _pos_of(t)
		if p.distance_to(c) > rad:
			continue
		if t is Toy:
			t.zap_power = 3.0
			t.electric = 1.0
			hits.append(p)
			if t.def.get("metal", false):
				metal.append(t)
		elif t is Wiggly:
			t.electric = 1.2
			hits.append(p)
		elif t is Fighter and t.alive() and t.frozen_t <= 0.0:
			zapped.append(t)
			hits.append(p)
	fx_event("zap", {"p": c, "hits": hits, "r": rad})
	_zap_water(c, rad, from, zapped)
	_zap_metal(metal, zapped)
	if not zapped.is_empty():
		_zap_chain(zapped)


## A zap that reaches a pond runs through all of it: everyone and everything
## in the water gets it (up to the knees counts).
func _zap_water(c: Vector2, rad: float, from, zapped: Array) -> void:
	for i in water.size():
		if i < liquid_kinds.size() and String(liquid_kinds[i]) != "water":
			continue
		var r: Rect2 = water[i]
		var near := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
		if near.distance_to(c) > rad:
			continue
		var pool := r.grow_individual(0.0, 50.0, 0.0, 0.0)
		for t in all_things():
			if t == from or not pool.has_point(_pos_of(t)):
				continue
			if t is Fighter:
				if t.alive() and t.frozen_t <= 0.0 and not zapped.has(t):
					t.wet = maxf(t.wet, 1.0)
					zapped.append(t)
			elif t is Wiggly:
				t.electric = 1.2
			elif t is Toy:
				t.zap_power = 3.0
				t.electric = 1.0
		fx_event("zap_pool", {"p": near, "x0": r.position.x, "x1": r.end.x, "y": r.position.y})


var _metal_q: PhysicsShapeQueryParameters2D = null


## ...and along metal: from the metal toys it hit to every metal toy touching
## them (a row of beams, a machine standing on one), and into anyone touching
## any of it (standing on a metal beam, leaning on a barrel).
func _zap_metal(start: Array, zapped: Array) -> void:
	if start.is_empty():
		return
	if _metal_q == null:
		_metal_q = PhysicsShapeQueryParameters2D.new()
		_metal_q.collision_mask = Toy.LAYER_TOYS | Fighter.LAYER
		_metal_q.margin = 4.0
	var space := get_world_2d().direct_space_state
	var seen := {}
	for t in start:
		seen[t] = true
	var queue: Array = start.duplicate()
	var pairs: Array = []
	var i := 0
	while i < queue.size() and i < 40:
		var t: Toy = queue[i]
		i += 1
		if not is_instance_valid(t):
			continue
		var cs: CollisionShape2D = null
		for k in t.get_children():
			if k is CollisionShape2D and not k.is_queued_for_deletion():
				cs = k
				break
		if cs == null or cs.shape == null:
			continue
		_metal_q.shape = cs.shape
		_metal_q.transform = t.global_transform * cs.transform
		_metal_q.exclude = [t.get_rid()]
		for hit in space.intersect_shape(_metal_q, 12):
			var o = hit.collider
			if o is Toy and o.def.get("metal", false) and not seen.has(o) and things.get(o.uid) == o:
				seen[o] = true
				o.electric = 1.0
				o.zap_power = 3.0
				queue.append(o)
				pairs.append([t.global_position, o.global_position])
			elif o is FighterPart and o.fighter and o.fighter.alive() and o.fighter.frozen_t <= 0.0 and not zapped.has(o.fighter):
				zapped.append(o.fighter)
				pairs.append([t.global_position, o.fighter.center()])
	if not pairs.is_empty():
		fx_event("zap_metal", {"p": pairs[0][0], "pairs": pairs})


## Twinkle's warp takes the fighters close by along: each one pops out high in
## the air above where it stood, and comes tumbling down (softly).
func warp_fighters(c: Vector2, rad: float) -> void:
	var up := -gravity_dir() if gravity_dir() != Vector2.ZERO else Vector2.UP
	var n := 0
	for f in fighters():
		if n >= 4:
			break
		if not f.alive() or f.frozen_t > 0.0 or f.center().distance_to(c) > rad + f.radius() * 0.5:
			continue
		var at: Vector2 = f.center()
		var to := lift_out_of_ground(at + up * randf_range(300.0, 400.0) + Vector2(randf_range(-60.0, 60.0), 0.0), f.radius() * 0.5)
		f.warp_to(to)
		fx_event("warp", {"a": at, "b": to, "r": f.radius()})
		n += 1


## Zappy's zap jumps on from soldier to soldier, further through wet ones
## (a whole pond of them) and ones in metal armor. Up to 12 in all.
func _zap_chain(first: Array) -> void:
	var hit := {}
	for f in first:
		hit[f] = true
	var others: Array = fighters().filter(func(o): return o.alive() and o.frozen_t <= 0.0 and not hit.has(o))
	var queue: Array = first.duplicate()
	var pairs: Array = []
	var i := 0
	while i < queue.size() and hit.size() < 12:
		var a: Fighter = queue[i]
		i += 1
		var ac := a.center()
		var reach := 70.0 + a.radius() * 0.5 + (110.0 if a.wet > 0.2 else 0.0) + 30.0 * minf(2.0, a.metal())
		for o in others:
			if hit.has(o):
				continue
			var oc: Vector2 = o.center()
			var r2 := reach + (60.0 if o.wet > 0.2 and a.wet > 0.2 else 0.0) + 20.0 * minf(2.0, o.metal())
			if ac.distance_to(oc) < r2:
				hit[o] = true
				queue.append(o)
				pairs.append([ac, oc])
				if hit.size() >= 12:
					break
	for f in hit:
		f.zap()
	if not pairs.is_empty():
		fx_event("zap_chain", {"p": pairs[0][0], "pairs": pairs})


func heat_area(c: Vector2, rad: float, from: Wiggly) -> void:
	for t in all_things():
		if t == from:
			continue
		var p := _pos_of(t)
		if p.distance_to(c) > rad:
			continue
		if t is Toy:
			if t.frozen_t > 0.0:
				t.frozen_t = 0.01
			ToyLogic.heat(self, t)
		elif t is Wiggly and t.frozen_t > 0.0:
			t.set_frozen(0.0)
		elif t is Fighter:
			t.ignite(3.0)   # (melts the ice instead if it's frozen)
	fx_event("heat", {"p": c, "r": rad})


func freeze_area(c: Vector2, rad: float, sec: float, from = null) -> void:
	var mid_air := false
	for t in all_things():
		if t == from:
			continue
		var p := _pos_of(t)
		if p.distance_to(c) > rad:
			continue
		if t is Toy and not t.nailed:
			if t.get_contact_count() == 0 and t.linear_velocity.length() > 60.0:
				mid_air = true
			t.frozen_t = sec
			t.update_freeze()
		elif t is Wiggly:
			if not t.grounded:
				mid_air = true
			t.set_frozen(sec)
		elif t is Fighter and t.alive():
			if t.state == "stand" and not t.grounded and not t.def.get("flies", false):
				mid_air = true
			t.set_frozen(sec)
	if mid_air:
		Settings.award("freeze")
	fx_event("freeze", {"p": c, "r": rad})


func ground_pound(c: Vector2, rad: float, from: Wiggly) -> void:
	push_away(c, rad, 950.0, from)
	# squads standing nearby get launched (a T-Rex only wobbles unless it's right there)
	var power := 1000.0 * sqrt(from.size) if from else 1000.0
	var up := -gravity_dir() if gravity_dir() != Vector2.ZERO else Vector2.UP
	for f in fighters():
		var d: Vector2 = f.center() - c
		var dist := d.length()
		if dist > rad + f.radius() * 0.5:
			continue
		var k := pow(clampf(1.0 - dist / (rad + f.radius() * 0.5), 0.0, 1.0), 0.7)
		var dir := ((d / dist if dist > 1.0 else up) + up * 0.9).normalized()
		f.shove(dir * power * k / sqrt(f._mass_k()), 8.0 * k)
	fx_event("pound", {"p": c, "r": rad})


## Throws everything near `c` outward (heavier things move less).
func push_away(c: Vector2, rad: float, power: float, skip = null) -> void:
	var up := -gravity_dir() if gravity_dir() != Vector2.ZERO else Vector2.UP
	for t in all_things():
		if t == skip:
			continue
		var p := _pos_of(t)
		var d := p - c
		var dist := d.length()
		if dist > rad:
			continue
		var f := pow(1.0 - dist / rad, 0.7)
		var dir := d / dist if dist > 1.0 else up
		var dv := dir * power * f + up * power * 0.3 * f
		if t is Toy and not t.freeze:
			t.linear_velocity += dv * clampf(3.0 / t.mass, 0.12, 1.4)
			t.angular_velocity += randf_range(-6, 6) * f
		elif t is Wiggly and t.frozen_t <= 0.0:
			t.add_velocity(dv)
			if f > 0.5:
				t.dizzy_t = 2.0


## Wigglies don't push standing fighters around (a squishy jelly on a soldier's
## head would bounce them about), but a big or fast one rolling into them
## bowls them over, and a sticky Gummy grabs on. One shape check per Wiggly
## that's moving fast enough (or sticky), so even a big army costs little.
func _wigglies_vs_fighters() -> void:
	for w in wiggly_layer.get_children():
		if not (w is Wiggly) or things.get(w.uid) != w or w.points.is_empty() or w.frozen_t > 0.0:
			continue
		var sticky: bool = w.kind == "gummy" and w.special_t > 0.0 and w.stuck_links < 3
		var bouncy: bool = w.kind == "bloop"   # (a living trampoline: see _trampoline)
		var m: float = float(w.def.mass) * Wiggly.N * w.size * w.size
		var spd: float = w.com_vel.length()
		if not sticky and not bouncy and spd * m / (m + 1.0) < 120.0:
			continue   # too small or slow to bump anybody
		if _jelly_q == null:
			_jelly_q = PhysicsShapeQueryParameters2D.new()
			_jelly_q.shape = CircleShape2D.new()
			_jelly_q.collision_mask = Fighter.LAYER
		(_jelly_q.shape as CircleShape2D).radius = w.radius() * 0.95 + 4.0
		_jelly_q.transform = Transform2D(0.0, w.com)
		for hit in get_world_2d().direct_space_state.intersect_shape(_jelly_q, 8):
			var b = hit.collider
			if not (b is FighterPart) or b.part != "body" or b.fighter == null:
				continue
			var f: Fighter = b.fighter
			var d: Vector2 = f.center() - w.com
			if bouncy and _trampoline(w, f, b, d):
				continue
			if not sticky and spd * m / (m + 1.0) < 120.0:
				continue   # (a slow Bloop just being a trampoline)
			var dir := d.normalized() if d.length() > 1.0 else Vector2(signf(w.com_vel.x), 0)
			if sticky:
				var jp: JellyPoint = w.points[w.nearest_point(f.center())]
				if not links.any(func(l): return l.a == jp and l.b == b):
					sticky_touch(w, jp, b, jp.global_position)
			var rel: float = (w.com_vel - (b as RigidBody2D).linear_velocity).dot(dir)
			if rel > 60.0:
				f.jelly_bump(w, rel, dir)


## Someone coming down on top of a Bloop: BOING! It throws them up high (a
## living trampoline) and squashes down under them. True if it did.
func _trampoline(w: Wiggly, f: Fighter, b, d: Vector2) -> bool:
	var up := -gravity_dir() if gravity_dir() != Vector2.ZERO else Vector2.UP
	# (only landing on top: feet above its middle, not standing beside it)
	var feet := d - up * f.half_size().y
	if feet.dot(up) < w.radius() * 0.25 or absf(feet.dot(up.orthogonal())) > w.radius() * 0.8:
		return false
	var v: Vector2 = (b as RigidBody2D).linear_velocity
	var falling := -(v - w.com_vel).dot(up)
	if falling < 140.0 or not f.bounce(up * clampf(falling * 1.1 + 420.0, 650.0, 1300.0)):
		return false
	w.add_velocity(-up * minf(falling, 600.0) * 0.45)
	fx_event("boing", {"p": w.com + up * w.radius(), "big": true})
	return true


func sticky_touch(w: Wiggly, p: JellyPoint, other, at: Vector2) -> void:
	if w.stuck_links >= 3 or not (other is PhysicsBody2D):
		return
	if other is JellyPoint and other.wiggly == w:
		return
	for l in links:
		if (l.a == p and l.b == other) or (l.a == other and l.b == p):
			return
	if other is StaticBody2D:
		return
	var l := add_link("glue", p, other, p.global_position, at)
	if l:
		w.stuck_links += 1
		fx_event("glue", {"p": at})
		if other is FighterPart and other.fighter:
			other.fighter.stick(3.0)   # and it stays slow while Gummy hangs on (see _physics_process)


# -------------------------------------------------------------- impacts
## Collision callbacks run while Godot is busy solving physics, when bodies
## can't be created or changed. So collisions are queued here and handled at
## the start of the next physics step.
func queue_impact(kind: String, a: Object, other: Object, closing: float, at: Vector2, n := Vector2.ZERO) -> void:
	if _impacts.size() < 400:
		_impacts.append([kind, a, other, closing, at, n])


func _handle_impacts() -> void:
	var list := _impacts
	_impacts = []
	for e in list:
		var a = e[1]
		if not is_instance_valid(a):
			continue
		var other = e[2] if is_instance_valid(e[2]) else null
		if other is FighterPart and other.fighter and other.fighter.is_resting():
			_bump_resting(e[0], a, other.fighter, float(e[3]))
		match String(e[0]):
			"toy":
				if things.get(a.uid) == a:
					on_impact(a, other, e[3], e[4], e[5])
			"jelly":
				if a.wiggly and is_instance_valid(a.wiggly):
					a.wiggly.on_point_impact(a, other, e[3], e[4])
			"fighter":
				if a.fighter and is_instance_valid(a.fighter):
					a.fighter.on_part_impact(a, other, e[3], e[4], e[5])


## Something ran into a knocked-out fighter lying still (its bodies are frozen,
## so it bounced off): it wakes and takes the knock. Not other knocked-out
## bodies: a heap of them jostles all the time, and a heap wakes as one anyway.
func _bump_resting(kind: String, hitter, f: Fighter, closing: float) -> void:
	var m := 1.0
	match kind:
		"toy", "jelly":
			# (dropped weapons lie about among the bodies and rattle against them:
			# only one that's thrown counts)
			if hitter is Toy and (hitter.def.has("weapon") or hitter.def.has("armor")) and closing < 600.0:
				return
			m = hitter.mass
		"fighter":
			if hitter.fighter == null or not is_instance_valid(hitter.fighter) or not hitter.fighter.alive():
				return
			m = hitter.fighter.weight()
	f.knocked_while_resting(hitter.global_position, closing, m)


func on_impact(t: Toy, other, closing: float, at: Vector2, _n: Vector2) -> void:
	ToyLogic.impact(self, t, other, closing, at)


func on_wiggly_impact(w: Wiggly, other, closing: float, at: Vector2) -> void:
	# one squish per landing, not one per edge point touching down
	if closing > 210.0 and w.t - float(w.get_meta("squish_t", -1.0)) > 0.18:
		w.set_meta("squish_t", w.t)
		fx_event("squish", {"p": at, "k": w.kind, "s": w.size, "v": closing})
	if other is Toy and other.id == "spring_pad":
		return  # the pad launches it from its side


# --------------------------------------------------------------- queries
func nearest_toy(p: Vector2, max_d: float) -> Toy:
	var best: Toy = null
	var bd := max_d
	for t in all_things():
		if t is Toy and t.parent_uid == 0:
			var d: float = t.global_position.distance_to(p)
			if d < bd:
				bd = d
				best = t
	return best


## Position of the closest lit fuse (Wigglies run away from it), or null.
func nearest_danger(p: Vector2, max_d: float):
	var best = null
	var bd := max_d
	for t in all_things():
		if t is Toy and t.fuse >= 0.0:
			var d: float = t.global_position.distance_to(p)
			if d < bd:
				bd = d
				best = t.global_position
	return best


func random_open_spot(near: Vector2) -> Vector2:
	for i in 20:
		var p := Vector2(randf_range(view_rect.position.x + 80, view_rect.end.x - 80), randf_range(view_rect.position.y + 60, view_rect.end.y - 200))
		if p.distance_to(near) < 200.0:
			continue
		var q := PhysicsPointQueryParameters2D.new()
		q.position = p
		q.collision_mask = Toy.LAYER_GROUND | Toy.LAYER_TOYS
		if get_world_2d().direct_space_state.intersect_point(q, 1).is_empty():
			return p
	return near + Vector2(0, -150)


## The pool of water at `p` (lava and acid don't count: they hurt, they don't float things).
func in_water(p: Vector2) -> Rect2:
	for i in water.size():
		if water[i].has_point(p) and (i >= liquid_kinds.size() or liquid_kinds[i] == "water"):
			return water[i]
	return Rect2()


# ----------------------------------------------------------- the loop
func _physics_process(dt: float) -> void:
	vision_time += dt
	if puppet:
		return
	if paused:
		_drive_grabs(dt)   # everything is stopped, but you can still move things around
		return
	if profiling:
		_prof_t = Time.get_ticks_usec()
	_handle_impacts()
	if profiling:
		_lap("impacts")
	for w in wiggly_layer.get_children():
		# a Wiggly being removed can share its id with its replacement (undo, loads)
		if w is Wiggly and things.get(w.uid) == w and not w.points.is_empty():
			w.physics_step(dt)
	if profiling:
		_lap("wigglies")
	_wigglies_vs_fighters()
	if profiling:
		_lap("wigglies_vs_fighters")
	for f in fighters():
		f.physics_step(dt)
	if profiling:
		_lap("fighters")
	Combat.hazards(self, dt)
	if profiling:
		_lap("hazards")
	Worlds.tick(self, dt)
	_step_strikes(dt)
	_battle_t -= dt
	if _battle_t <= 0.0:
		_battle_t = 0.5
		Combat.battle_check(self)
	if battle_on and last_winner == "" and not paused and teams_up >= 2:
		quiet_t += dt
		if quiet_t > QUIET_CHARGE and not brave:
			brave = true
			fx_event("charge_all", {})
	elif last_winner != "" or teams_up < 2:
		quiet_t = 0.0
		brave = false
	_drive_grabs(dt)
	if profiling:
		_lap("battle_check")
	for l in links:
		if not l.broken and not l.step(dt):
			fx_event("snap", {"p": l.world_b() if is_instance_valid(l.b) else Vector2.ZERO})
			l.destroy()
		elif l.kind == "glue" and l.a is JellyPoint and l.b is FighterPart and l.b.fighter:
			l.b.fighter.goo_t = maxf(l.b.fighter.goo_t, 0.3)   # a Wiggly stuck on: slow going
			if l.a.wiggly.special_t <= 0.0 and randf() < dt * 0.4:
				# Sticky Mode is over: sooner or later they shake the Gummy off
				fx_event("snap", {"p": l.world_b()})
				l.destroy()
	if links.any(func(l): return l.broken):
		links = links.filter(func(l): return not l.broken)
	if profiling:
		_lap("links")
	_step_power()
	if profiling:
		_lap("power")
	cars_on = 0
	for t in toys():
		ToyLogic.step(self, t, dt)
	if profiling:
		_lap("toys")
	_step_water(dt)
	_step_magic(dt)
	if profiling:
		_lap("water_magic")
	_cleanup()
	_sticker_t -= dt
	if _sticker_t <= 0.0:
		_sticker_t = 0.5
		_check_stickers()
	if profiling:
		_lap("cleanup_stickers")


func _lap(part: String) -> void:
	var now := Time.get_ticks_usec()
	prof[part] = int(prof.get(part, 0)) + now - _prof_t
	_prof_t = now


## Power flows from active sources through wires to everything connected.
## A switch, button or timer that is off blocks the flow.
func _step_power() -> void:
	var ts := toys()
	for t in ts:
		t.powered = false
	var adj := {}
	for l in links:
		if l.kind != "wire" or l.broken:
			l.signal_on = false
			continue
		if not adj.has(l.uid_a):
			adj[l.uid_a] = []
		adj[l.uid_a].append(l.uid_b)
		if not adj.has(l.uid_b):
			adj[l.uid_b] = []
		adj[l.uid_b].append(l.uid_a)
	var queue: Array = []
	for t in ts:
		if ToyLogic.emits(t):
			queue.append(t.uid)
	var seen := {}
	while not queue.is_empty():
		var u: int = queue.pop_back()
		if seen.has(u):
			continue
		seen[u] = true
		var t = things.get(u)
		if t is Toy and not ToyLogic.emits(t):
			t.powered = true
			if ToyLogic.is_source(t):
				continue   # an "off" switch/button/timer stops the power here
		for v in adj.get(u, []):
			if not seen.has(v):
				queue.append(v)
	for l in links:
		if l.kind == "wire":
			l.signal_on = seen.has(l.uid_a) and seen.has(l.uid_b)


func _step_water(dt: float) -> void:
	if water.is_empty():
		return
	var g: float = Catalog.gravity_def(gravity_id).g.length()
	g = maxf(g, 300.0)
	for t in all_things():
		if t is Toy:
			if t.freeze:
				continue
			var he: Vector2 = t.half_extents()
			var r: Rect2 = in_water(t.global_position + Vector2(0, he.y))
			if r.size == Vector2.ZERO:
				t.extra.erase("in_water")
				continue
			var sub := clampf((t.global_position.y + he.y - r.position.y) / (he.y * 2.0), 0.0, 1.0)
			var lift := 1.9 if t.def.get("floaty", false) else 0.55
			t.linear_velocity += Vector2(0, -g * lift * sub * dt)
			t.linear_velocity *= maxf(0.0, 1.0 - 2.4 * sub * dt)
			t.angular_velocity *= maxf(0.0, 1.0 - 2.0 * sub * dt)
			t.wet = 1.0
			if not t.extra.has("in_water"):
				t.extra.in_water = true
				if t.linear_velocity.length() > 160.0:
					fx_event("splash", {"p": Vector2(t.global_position.x, r.position.y), "s": he.length() / 30.0})
		elif t is Wiggly:
			if t.frozen_t > 0.0 or t.points.is_empty():
				continue
			var under := 0
			var surface := 0.0
			for p in t.points:
				var r: Rect2 = in_water(p.global_position)
				if r.size != Vector2.ZERO:
					under += 1
					surface = r.position.y
					var lift := 0.55 if t.kind == "boulder" else 1.7
					p.linear_velocity += Vector2(0, -g * lift * dt)
					p.linear_velocity *= maxf(0.0, 1.0 - 2.0 * dt)
			if under > 0:
				t.wet = 1.0
				if not t.has_meta("in_water"):
					t.set_meta("in_water", true)
					Settings.award("splash")
					if t.com_vel.length() > 140.0:
						fx_event("splash", {"p": Vector2(t.com.x, surface), "s": t.size * 1.2})
			elif t.has_meta("in_water"):
				t.remove_meta("in_water")


# ------------------------------------------------------------------ magic
func cast_magic(id: String) -> void:
	match id:
		"party":
			magic.party = 8.0
			for w in wigglies():
				w.party_t = 8.0
		"ball_rain":
			_ball_rain = 26
		"wind":
			wind_dir = -1.0 if randf() < 0.5 else 1.0
			magic.wind = 5.0
		"rain":
			magic.rain = 10.0
		"snow":
			magic.snow = 12.0
		"wobble":
			magic.wobble = 4.0
		"float":
			magic["float"] = 6.0
			set_gravity(gravity_id)
		"airstrike":
			var y := view_rect.position.y - 120.0
			var dir := 1.0 if randf() < 0.5 else -1.0
			var x0 := view_rect.position.x if dir > 0.0 else view_rect.end.x
			fx_event("plane", {"y": y - 60.0, "dir": dir, "x0": x0, "w": view_rect.size.x})
			for i in 9:
				_strikes.append({"t": 0.8 + i * 0.22, "p": Vector2(x0 + dir * view_rect.size.x * (0.1 + i * 0.1), y), "kind": "shell", "v": Vector2(dir * 300.0, 200.0)})
		"artillery":
			fx_event("alarm", {})
			for i in 10:
				_strikes.append({"t": 1.2 + i * 0.35 + randf() * 0.2, "p": Vector2(randf_range(view_rect.position.x + 80, view_rect.end.x - 80), view_rect.position.y - 150.0), "kind": "shell", "v": Vector2(randf_range(-80, 80), 600.0), "whistle": true})
		"meteors":
			for i in 12:
				_strikes.append({"t": 0.3 + i * 0.3 + randf() * 0.2, "p": Vector2(randf_range(view_rect.position.x, view_rect.end.x), view_rect.position.y - 150.0), "kind": "meteor", "v": Vector2(randf_range(150, 350), 500.0)})
		"heal_all":
			for f in fighters():
				f.revive()
		"rainbow":
			var i := 0
			var sorted := toys().duplicate()
			sorted.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
			for t in sorted:
				if t.parent_uid == 0 or true:
					t.paint = Color.from_hsv(fmod(float(i) * 0.09, 1.0), 0.65, 1.0)
					i += 1
			for w in wigglies():
				w.paint = Color.from_hsv(randf(), 0.55, 1.0)
	fx_event("magic", {"id": id, "dir": wind_dir})


func _step_magic(dt: float) -> void:
	for k in magic.keys():
		magic[k] -= dt
		if magic[k] <= 0.0:
			magic.erase(k)
			if k == "float":
				set_gravity(gravity_id)
			fx_event("magic_end", {"id": k})
	if magic.has("wind"):
		for t in all_things():
			if t is Toy and not t.freeze:
				t.linear_velocity.x += wind_dir * 900.0 * dt * clampf(2.0 / t.mass, 0.1, 1.0)
			elif t is Wiggly and t.frozen_t <= 0.0:
				t.add_velocity(Vector2(wind_dir * 700.0 * dt * (2.0 if t.kind == "puffy" else 1.0), 0))
			elif t is Fighter:
				t.blow(Vector2(wind_dir * 240.0, 0), dt)   # armies lean into it; chickens tumble away
	if magic.has("wobble"):
		for t in all_things():
			if t is Fighter:
				# now and then the ground bucks under someone's feet
				if randf() < 0.012:
					t.shove(Vector2(randf_range(-160, 160), randf_range(-260, -120)))
			elif randf() < 0.08:
				var kick := Vector2(randf_range(-260, 260), randf_range(-420, -120))
				if t is Toy and not t.freeze:
					t.linear_velocity += kick * clampf(3.0 / t.mass, 0.2, 1.0)
				elif t is Wiggly:
					t.add_velocity(kick)
	if magic.has("rain"):
		# everyone gets wet: burning fighters fizzle out, and the napalm fires die down
		for t in all_things():
			if t is Fighter or t is Toy:
				t.wet = 1.0
		for z in fires:
			z.t -= dt * 2.5
	if magic.has("float"):
		for w in wigglies():
			w.add_velocity(Vector2(0, -30.0 * dt))
	if _ball_rain > 0:
		_ball_rain_t -= dt
		if _ball_rain_t <= 0.0:
			_ball_rain_t = 0.11
			_ball_rain -= 1
			var ids := ["beach_ball", "bouncy_ball", "soccer_ball", "marble", "bouncy_ball"]
			var b := spawn_toy(ids[randi() % ids.size()], Vector2(randf_range(view_rect.position.x + 60, view_rect.end.x - 60), view_rect.position.y - 60))
			if b:
				b.linear_velocity = Vector2(randf_range(-80, 80), 200)


func _step_strikes(dt: float) -> void:
	for st in _strikes:
		st.t -= dt
		if st.t <= 0.0:
			var b := spawn_toy(String(st.kind), st.p, 0.0, 1.0, Combat.PROJ[String(st.kind)])
			if b:
				b.extra.proj = "bomb"
				b.extra.life = 8.0
				b.linear_velocity = st.v
				if st.kind == "meteor":
					b.extra.meteor = true
				if st.get("whistle", false):
					fx_event("whistle", {"p": st.p})
	_strikes = _strikes.filter(func(st): return st.t > 0.0)


func shoot(shooter, from: Vector2, ang: float, rng: float, dmg: float, knock: float, laser := false) -> void:
	Combat.shoot(self, shooter, from, ang, rng, dmg, knock, laser)


func launch(shooter, kind: String, at: Vector2, ang: float, speed: float) -> void:
	Combat.launch(self, shooter, kind, at, ang, speed)


func flame(shooter, from: Vector2, ang: float, rng: float, dmg: float) -> void:
	Combat.flame(self, shooter, from, ang, rng, dmg)


func on_fighter_ko(_f: Fighter) -> void:
	_battle_t = 0.0


func resize_fighter(f: Fighter, s: float) -> void:
	var base := float(f.def.get("scale", 1.0))
	var ns := clampf(s / base, 0.5, 2.5)
	var nf := spawn_fighter(f.type, f.center(), f.team, f.pers, ns, false)
	if nf == null:
		return
	nf.paint = f.paint
	if f.weapon_toy and is_instance_valid(f.weapon_toy):
		var wt := f.weapon_toy
		f._drop_weapon(Vector2.ZERO)
		nf.equip(wt)
	remove(f.uid, false)


# ---------------------------------------------------------------- cleanup
func _cleanup() -> void:
	var tick := Engine.get_physics_frames()
	for t in all_things():
		var p := _pos_of(t)
		# things thrown high into the sky come back down, so only the floor and sides count
		if bounds.has_point(p) or (p.y < bounds.position.y and p.y > bounds.position.y - 8000.0 and p.x > bounds.position.x and p.x < bounds.end.x):
			# Squeezed deep into the ground (by a heap, or right on a seam
			# between two pieces of it), a body gets pushed sideways instead of
			# up and sinks right through: pop it back out on top. (Only when its
			# middle is more than BURIED px down, so nothing just pressed into
			# the ground a little jumps about; an eighth of everything each
			# step, as the check isn't free.)
			if (tick + t.uid) % 8 == 0 and not puppet and in_ground(p - Vector2(0.0, BURIED)):
				_unbury(t)
			continue
		flung += 1
		var past := maxf(maxf(bounds.position.x - p.x, p.x - bounds.end.x), maxf(p.y - bounds.end.y, bounds.position.y - 8000.0 - p.y))
		if past > 1000.0 or not p.is_finite():
			blown += 1
		if t is Wiggly:
			# Wigglies are friends: bring them back instead of losing them.
			var sp: Vector2 = spawn_points[randi() % spawn_points.size()]
			t.teleport(sp)
			t.set_velocity(Vector2.ZERO)
			fx_event("poof", {"p": sp})
		else:
			remove(t.uid, false)


func _check_stickers() -> void:
	var ground_y := Worlds.ground_y(world_id)
	for w in wigglies():
		if w.com.y < ground_y - 1500.0:
			Settings.award("sky")
	# Tower: a Letter/Wood block/brick sitting high above the ground, not held.
	for t in toys():
		if t.id in ["wood_block", "brick", "abc_block"] and not t.freeze and t.linear_velocity.length() < 5.0:
			if t.global_position.y < ground_y - 330.0 and t.get_contact_count() > 0:
				var held := false
				for g in grabs.values():
					if g.uid == t.uid:
						held = true
				if not held:
					Settings.award("tower")


# --------------------------------------------------------------- effects
func fx_event(name: String, args: Dictionary) -> void:
	fx.emit(name, args)


# ------------------------------------------------------------------- undo
## Saves the playground for Ctrl+Z. `key` names a small change ("paint 12"):
## doing the same one again within a couple of seconds (painting, resizing,
## flipping a switch, clicking away) is one step to undo, not fifteen.
func push_undo(key := "") -> void:
	if puppet:
		return
	var now := Time.get_ticks_msec()
	if key != "" and key == _undo_key and now - _undo_at < 2000 and not _undo.is_empty():
		_undo_at = now
		return
	_undo_key = key
	_undo_at = now
	_undo.append(serialize())
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()


func undo() -> void:
	if _undo.is_empty():
		fx_event("nope", {})
		return
	_undo_key = ""
	restore(_undo.pop_back())
	fx_event("undo", {})


## The whole playground as plain data (saves, undo).
func serialize() -> Dictionary:
	var ts: Array = []
	var ws: Array = []
	for t in all_things():
		if t is Toy:
			var e := {"uid": t.uid, "id": t.id, "x": t.global_position.x, "y": t.global_position.y, "a": t.rotation,
				"vx": t.linear_velocity.x, "vy": t.linear_velocity.y, "va": t.angular_velocity, "s": t.size_scale,
				"paint": t.paint.to_html() if t.paint.a > 0.0 else "", "letter": t.letter, "on": t.on, "f": t.facing,
				"nail": t.nailed, "parent": t.parent_uid, "pr": t.r if t.def.get("part", false) else 0.0}
			if t.frozen_t > 0.0:
				e.ice = t.frozen_t
			if t.bubble_t > 0.0:
				e.bub = t.bubble_t
			# toys this one passes through (see no_collide)
			var nc: Array = []
			for o_uid in t.extra.get("nc", []):
				if things.get(int(o_uid)) is Toy:
					nc.append(int(o_uid))
			if not nc.is_empty():
				e.nc = nc
			ts.append(e)
		elif t is Wiggly:
			var pp: Array = []
			for p in t.pts:
				pp.append([p.x, p.y])
			ws.append({"uid": t.uid, "kind": t.kind, "s": t.size, "x": t.com.x, "y": t.com.y,
				"paint": t.paint.to_html() if t.paint.a > 0.0 else "", "pts": pp})
	var fs: Array = []
	for f in fighters():
		var c: Vector2 = f.center()
		var e := {"uid": f.uid, "type": f.type, "team": f.team, "pers": f.pers, "s": f.size / float(f.def.get("scale", 1.0)),
			"x": c.x, "y": c.y, "hp": f.hp, "armor": f.armor, "helmet": f.helmet, "body_armor": f.body_armor, "shield": f.shield,
			"weapon": f.weapon_toy.uid if f.weapon_toy and is_instance_valid(f.weapon_toy) else 0, "f": f.facing,
			"paint": f.paint.to_html() if f.paint.a > 0.0 else ""}
		# what toys and powers are doing to them: 🧊 🫧 ⚡ 🍬 💧 🔥
		var fx_now := {"ice": f.frozen_t, "bub": f.bubble_t, "zap": f.stun_t, "goo": f.goo_t, "wet": f.wet, "burn": f.burning, "acid": f.acid}
		for k in fx_now:
			if float(fx_now[k]) > 0.0:
				e[k] = fx_now[k]
		fs.append(e)
	var ps: Array = []
	for pl in platforms:
		var pts: Array = []
		for v in pl.poly:
			pts.append([v.x, v.y])
		var pe := {"poly": pts, "style": pl.style, "group": pl.group}
		if float(pl.get("hp", 0.0)) < float(pl.get("max", 0.0)):
			pe.hp = pl.hp   # (cracked by blasts)
		ps.append(pe)
	var lq: Array = []
	for i in water.size():
		if i < liquid_groups.size() and int(liquid_groups[i]) != 0:
			var r: Rect2 = water[i]
			lq.append({"r": [r.position.x, r.position.y, r.size.x, r.size.y], "kind": liquid_kinds[i], "group": liquid_groups[i]})
	var ls: Array = []
	for l in links:
		if l.broken or not l.valid():
			continue
		ls.append({"k": l.kind, "a": l.uid_a, "ai": l.a.index if l.a is JellyPoint else -1, "b": l.uid_b,
			"bi": l.b.index if l.b is JellyPoint else -1, "la": [l.la.x, l.la.y], "lb": [l.lb.x, l.lb.y], "rest": l.rest})
	return {"v": 2, "world": world_id, "gravity": gravity_id, "night": night, "next_uid": next_uid, "toys": ts, "wigglies": ws, "links": ls,
		"fighters": fs, "platforms": ps, "liquids": lq, "battle": battle_on}


func restore(d: Dictionary) -> void:
	if String(d.get("world", world_id)) != world_id:
		load_world(String(d.world), false)
	_clear_all()
	# Each thing is made under a new number and then given its saved one. New
	# numbers start above every saved one, so a new thing can't land on a number
	# that something loaded a moment ago already has (that knocked the older one
	# out of the world, but left it lying there: a stray nobody could touch).
	for key in ["toys", "wigglies", "fighters"]:
		for e in d.get(key, []):
			next_uid = maxi(next_uid, int(e.get("uid", 0)))
	# placed platforms and tubs
	for pl in platforms:
		if is_instance_valid(pl.node):
			pl.node.queue_free()
	platforms.clear()
	for i in range(water.size() - 1, -1, -1):
		if i < liquid_groups.size() and int(liquid_groups[i]) != 0:
			water.remove_at(i)
			liquid_kinds.remove_at(i)
			liquid_groups.remove_at(i)
	_water_hold += 1
	for e in d.get("platforms", []):
		var poly := PackedVector2Array()
		for v in e.poly:
			poly.append(Vector2(v[0], v[1]))
		var made := add_platform(poly, String(e.style), int(e.group))
		if e.has("hp"):
			var pl: Dictionary = platforms[platforms.size() - 1]
			pl.hp = float(e.hp)
			made.set_damage(1.0 - float(pl.hp) / maxf(1.0, float(pl.max)))
		next_group = maxi(next_group, int(e.group))
	for e in d.get("liquids", []):
		add_liquid(Rect2(e.r[0], e.r[1], e.r[2], e.r[3]), String(e.kind), int(e.group))
	_water_hold -= 1
	_cut_water()
	battle_on = bool(d.get("battle", true))
	set_gravity(String(d.get("gravity", "normal")))
	set_night(bool(d.get("night", false)))
	for e in d.get("toys", []):
		var def_o: Dictionary = Builders.part_def(String(e.id), float(e.pr)) if float(e.get("pr", 0.0)) > 0.0 else {}
		var t := spawn_toy(String(e.id), Vector2(e.x, e.y), float(e.a), float(e.get("s", 1.0)), def_o)
		if t == null:
			continue
		_take_saved_number(t, int(e.uid))
		t.linear_velocity = Vector2(e.vx, e.vy)
		t.angular_velocity = float(e.va)
		if String(e.get("paint", "")) != "":
			t.paint = Color(String(e.paint))
		t.letter = String(e.get("letter", ""))
		t.on = bool(e.get("on", false))
		if float(e.get("f", 1.0)) < 0.0:
			t.set_facing(-1.0)
		t.nailed = bool(e.get("nail", false))
		if t.nailed:
			t.global_position = Vector2(e.x, e.y)   # (right where it was nailed, even set into the ground like a trap's plate)
		t.parent_uid = int(e.get("parent", 0))
		t.frozen_t = float(e.get("ice", 0.0))
		if float(e.get("bub", 0.0)) > 0.0:
			ToyLogic._bubble(self, t, float(e.bub))
		t.update_freeze()
		ToyLogic.update_light(self, t)
	for e in d.get("toys", []):
		var t = things.get(int(e.get("uid", 0)))
		for o_uid in e.get("nc", []):
			var o = things.get(int(o_uid))
			if t is Toy and o is Toy and o != t:
				no_collide(t, o)
	for e in d.get("wigglies", []):
		var w := spawn_wiggly(String(e.kind), Vector2(e.x, e.y), float(e.get("s", 1.0)))
		if w == null:
			continue
		_take_saved_number(w, int(e.uid))
		if String(e.get("paint", "")) != "":
			w.paint = Color(String(e.paint))
		var pp: Array = e.get("pts", [])
		if pp.size() == Wiggly.N:
			for i in Wiggly.N:
				w.points[i].global_position = Vector2(pp[i][0], pp[i][1])
	for e in d.get("fighters", []):
		var f := spawn_fighter(String(e.type), Vector2(e.x, e.y), String(e.team), String(e.pers), float(e.get("s", 1.0)), false)
		if f == null:
			continue
		_take_saved_number(f, int(e.uid))
		f.hp = float(e.get("hp", f.max_hp))
		f.armor = float(e.get("armor", f.armor))
		f.helmet = String(e.get("helmet", f.helmet))
		f.body_armor = bool(e.get("body_armor", false))
		f.shield = bool(e.get("shield", false))
		f.facing = float(e.get("f", 1.0))
		if String(e.get("paint", "")) != "":
			f.paint = Color(String(e.paint))
		var wt = things.get(int(e.get("weapon", 0)))
		if wt is Toy:
			f.equip(wt)
		if f.hp <= 0.0:
			f.hp = 0.0
			f._ko(Vector2.ZERO, null)
		else:
			# what toys and powers were doing to them
			f.wet = float(e.get("wet", 0.0))
			f.burning = float(e.get("burn", 0.0))
			f.acid = float(e.get("acid", 0.0))
			f.goo_t = float(e.get("goo", 0.0))
			f.stun_t = float(e.get("zap", 0.0))
			if float(e.get("bub", 0.0)) > 0.0:
				f.set_bubble(float(e.bub))
			if float(e.get("ice", 0.0)) > 0.0:
				f.set_frozen(float(e.ice))
			if f.stun_t > 0.0:
				f.mood = "zapped"
			f._show_status()
	next_uid = maxi(next_uid, int(d.get("next_uid", next_uid)))
	await get_tree().physics_frame
	for e in d.get("links", []):
		var a := _resolve_body(int(e.a), int(e.ai))
		var b := _resolve_body(int(e.b), int(e.bi))
		if a == null or b == null:
			continue
		var l := Link.new()
		l.kind = String(e.k)
		l.a = a
		l.b = b
		l.la = Vector2(e.la[0], e.la[1])
		l.lb = Vector2(e.lb[0], e.lb[1])
		l.rest = float(e.get("rest", 20.0))
		l.uid_a = int(e.a)
		l.uid_b = int(e.b)
		l.build(pin_parent)
		links.append(l)
	world_changed.emit(true)

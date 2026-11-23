class_name World
extends Node2D
## The playground: terrain, water, toys, Wigglies, links, power, magic and
## stickers. Every player action arrives as a command (apply_command), so a
## friend's clicks over Wi-Fi go through exactly the same code as yours.
## On a network client the world is a "puppet": it draws what the host sends.
## All the state lives here. Some of the work is in helpers next door that
## take the world: WorldTerrain (platforms and pools), WorldLinks (links and
## power), WorldPowers (Wiggly powers), WorldMagic (spells), WorldCommands
## (commands and grabbing) and WorldSave (saving, loading and undo).

signal fx(name: String, args: Dictionary)   # every visual/sound event (the host forwards these)
## rebuilt: the playground was loaded, undone or cleared (old effects go too);
## false when only a setting changed (pause, speed, night, gravity, fighting).
signal world_changed(rebuilt: bool)

const UNDO_MAX := 15
const MAX_TOYS := 420
const MAX_WIGGLIES := 40
const MAX_FIGHTERS := 120
const SINK_FAST := 350.0        # px/s down: checked for being stuck in the ground every step (see _cleanup)
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
var _jelly_q: PhysicsShapeQueryParameters2D = null   # (Wigglies bumping into fighters: see WorldPowers)
var _metal_q: PhysicsShapeQueryParameters2D = null   # (zaps running along metal: see WorldPowers)
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


# ------------------------------------------------------- platforms and pools
# (building platforms, blasts breaking them, pools of water, lava and acid,
# and cutting the water to the shape of the ground are in world_terrain.gd:
# WorldTerrain)
## Water areas are rectangles; cut away the ground so only the pond shows.
func _cut_water() -> void:
	WorldTerrain.cut_water(self)


## Adds a pool of water, lava or acid (its top edge is the surface).
func add_liquid(r: Rect2, kind: String, group := 0) -> void:
	WorldTerrain.add_liquid(self, r, kind, group)


## "" if `p` is not in any liquid, else water / lava / acid.
func in_liquid(p: Vector2) -> String:
	for i in water.size():
		if water[i].has_point(p):
			return String(liquid_kinds[i]) if i < liquid_kinds.size() else "water"
	return ""


func add_platform(poly: PackedVector2Array, style: String, group := 0) -> Ground:
	return WorldTerrain.add_platform(self, poly, style, group)


## An explosion at `p` cracks the platforms you built nearby, and breaks them
## once they've taken enough (see Combat.blast).
func damage_platforms(p: Vector2, rad: float, dmg: float) -> void:
	WorldTerrain.damage_platforms(self, p, rad, dmg)


static func rect_poly(r: Rect2) -> PackedVector2Array:
	return WorldTerrain.rect_poly(r)


## Knocked-out ragdolls lying still (frozen, see Fighter._rest_check) move
## again: all of them, or the ones within `r` of `p`. For the gravity
## changing, or the ground (or a toy) going from under them.
func wake_resting(p := Vector2.INF, r := 0.0, and_neighbours := true) -> void:
	for f in fighters():
		if f.is_resting() and (p == Vector2.INF or f.center().distance_to(p) < r + f.radius() * 2.0):
			f.wake(and_neighbours)


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


## Heading down faster than SINK_FAST px/s (see _cleanup).
func _sinking_fast(t) -> bool:
	var b: RigidBody2D = null
	if t is Fighter:
		var f := t as Fighter
		b = f.body if f.state == "stand" and is_instance_valid(f.body) else f.parts.get("torso") as RigidBody2D
	elif t is Toy:
		b = t
	return b != null and is_instance_valid(b) and b.linear_velocity.y > SINK_FAST


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
	WorldTerrain.clear_placed(self)


func get_thing(uid: int):
	return things.get(uid)


func _pos_of(t) -> Vector2:
	if t is Wiggly:
		return t.com
	if t is Fighter:
		return t.center()
	return t.global_position


# ------------------------------------------------------------------ links
# (making links, and the power along wires, are in world_links.gd: WorldLinks)
func add_link(kind: String, a: PhysicsBody2D, b: PhysicsBody2D, pa: Vector2, pb: Vector2) -> Link:
	return WorldLinks.add_link(self, kind, a, b, pa, pb)


## Toy `a` passes through toy `b` from now on (and after a save, an undo or loading).
func no_collide(a: Toy, b: Toy) -> void:
	WorldLinks.no_collide(a, b)


func links_of(uid: int) -> Array:
	return WorldLinks.links_of(self, uid)


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


# ------------------------------------------------------ commands and grabs
# (every command, and grabbing and dragging things, are in world_commands.gd:
# WorldCommands)
## Everything a player can do. pid 0 = the local/host player.
func apply_command(pid: int, c: Dictionary) -> void:
	WorldCommands.apply(self, pid, c)


func grab_end(pid: int) -> void:
	WorldCommands.grab_end(self, pid)


# ---------------------------------------------------------- Wiggly powers
# (popping and merging Wigglies, zaps, heat, ice, ground pounds, warps and
# pushes are in world_powers.gd: WorldPowers)
func split_wiggly(w: Wiggly, pid := -1) -> void:
	WorldPowers.split_wiggly(self, w, pid)


func merge_wigglies(a: Wiggly, b: Wiggly) -> void:
	WorldPowers.merge_wigglies(self, a, b)


func zap_area(c: Vector2, rad: float, from: Wiggly) -> void:
	WorldPowers.zap_area(self, c, rad, from)


func warp_fighters(c: Vector2, rad: float) -> void:
	WorldPowers.warp_fighters(self, c, rad)


func heat_area(c: Vector2, rad: float, from: Wiggly) -> void:
	WorldPowers.heat_area(self, c, rad, from)


func freeze_area(c: Vector2, rad: float, sec: float, from = null) -> void:
	WorldPowers.freeze_area(self, c, rad, sec, from)


func ground_pound(c: Vector2, rad: float, from: Wiggly) -> void:
	WorldPowers.ground_pound(self, c, rad, from)


## Throws everything near `c` outward (heavier things move less).
func push_away(c: Vector2, rad: float, power: float, skip = null) -> void:
	WorldPowers.push_away(self, c, rad, power, skip)


func sticky_touch(w: Wiggly, p: JellyPoint, other, at: Vector2) -> void:
	WorldPowers.sticky_touch(self, w, p, other, at)


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
		WorldCommands.drive_grabs(self, dt)   # everything is stopped, but you can still move things around
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
	WorldPowers.wigglies_vs_fighters(self)
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
	WorldMagic.step_strikes(self, dt)
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
	WorldCommands.drive_grabs(self, dt)
	if profiling:
		_lap("battle_check")
	WorldLinks.step(self, dt)
	if profiling:
		_lap("links")
	WorldLinks.step_power(self)
	if profiling:
		_lap("power")
	cars_on = 0
	for t in toys():
		ToyLogic.step(self, t, dt)
	if profiling:
		_lap("toys")
	WorldTerrain.step_water(self, dt)
	WorldMagic.step(self, dt)
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


# ------------------------------------------------------------------ magic
# (in world_magic.gd: WorldMagic)
func cast_magic(id: String) -> void:
	WorldMagic.cast(self, id)


# --------------------------------------------------------------- fighting
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
			# step, as the check isn't free, but every step for anything
			# heading down fast, which could sink through between two looks.)
			if ((tick + t.uid) % 8 == 0 or _sinking_fast(t)) and not puppet and in_ground(p - Vector2(0.0, BURIED)):
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
# (in world_save.gd: WorldSave)
## Saves the playground for Ctrl+Z (`key`: see WorldSave.push_undo).
func push_undo(key := "") -> void:
	WorldSave.push_undo(self, key)


func undo() -> void:
	WorldSave.undo(self)


## The whole playground as plain data (saves, undo).
func serialize() -> Dictionary:
	return WorldSave.serialize(self)


## Loads serialize()'s data. The links between things go back a physics step
## later, once the things they join are there.
func restore(d: Dictionary) -> void:
	WorldSave.restore(self, d)
	await get_tree().physics_frame
	WorldSave.restore_links(self, d)


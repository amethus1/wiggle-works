class_name B3Battle
extends Node3D
## 3D Battle: an isometric battlefield sandbox. Place soldiers, animals and
## dinosaurs on teams, drop explosives, pour lava, build towers, press Fight.
## Started by main.gd (`begin(opts)`); `main.show_menu()` goes back.
##
## This node owns the lists of everything on the field and the shared
## actions (spawn, explode, nuke, clear). Units, ragdolls, props, projectiles
## and hazards each run their own little scripts; B3Tools turns the mouse
## and keys into actions; B3UI is the HUD.

const SND_FALLBACK := {
	"gun_rifle": "snap", "gun_pistol": "snap", "gun_mg": "tick", "gun_sniper": "cannon", "gun_laser": "zap",
	"bazooka": "cannon", "rocket": "whoosh", "bow": "whoosh", "arrow_hit": "thud", "swing": "whoosh",
	"clang": "clink", "slash": "whoosh", "punch": "thud", "bonk": "thud", "oof1": "squish", "oof2": "squish",
	"oof3": "squish", "ko": "dizzy", "charge": "rumble", "heal": "magic", "roar": "rumble", "screech": "eek",
	"growl": "rumble", "bark": "pop", "moo": "rumble", "cluck": "pop", "trumpet": "wee", "stomp": "pound",
	"nuke": "mega_boom", "whistle": "wee", "plane": "wind", "alarm": "nope", "sizzle": "steam", "fizz": "fuse",
	"crumble": "thud", "metal_hit": "clink", "reload": "click", "pin": "tick", "victory": "yay",
	"battle_start": "party", "snap": "snap", "honk": "nope",
}

var main = null
var world: B3World
var cam: B3Cam
var fx: B3Fx
var ui = null
var tools = null
var unit_root: Node3D
var ragdoll_root: Node3D
var prop_root: Node3D
var struct_root: Node3D
var hazard_root: Node3D
var proj_root: Node3D
var units: Array[B3Unit] = []
var ragdolls: Array[B3Ragdoll] = []
var props: Array[B3Prop] = []
var chunks: Array[RigidBody3D] = []
var structs: Array[B3Struct] = []
var hazards: Array[B3Hazard] = []
var planes: Array = []
var fighting := false
var paused := false
var slowmo := false
var time := 0.0
var think_period := 0.25
var winner := ""
var teams_seen := 0
var team_count := 0
var scenario := ""
var map_id := "grassland"
var kos := 0
var rng := RandomNumberGenerator.new()
var _events: Array = []
var _waves: Array = []
var _sinking: Array = []
var _ray := PhysicsRayQueryParameters3D.new()
var _shape_q := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()
var _old_tps := 60
var _old_interp := false
var _hz_t := 0.0
var _vic_t := 0.0
var _began := false
# Battle Rules (see B3Rules), cached for speed
var r_speed := 1.0
var r_tough := 1.0
var r_knock := 1.0
var weather: B3Weather = null
var _respawns: Array = []        # [{t, kind, team, pos, pers}] (Reinforcements rule)
var mvp: Dictionary = {}         # best fighter this battle: {kind, team, kills}
var team_kos := {}               # team -> knock-outs it scored
var net: B3Net = null             # 👥 playing together (see B3Net)
var puppet := false               # a friend's copy of someone else's battle: no physics or brains here
var start_layout: Dictionary = {}  # everything as it was when Fight! was pressed (⏮ Reset puts it back)


func begin(opts: Dictionary) -> void:
	var seed_v: int = opts.get("seed", 0)
	if seed_v != 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	_old_tps = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60
	_old_interp = get_tree().physics_interpolation
	get_tree().physics_interpolation = true
	Engine.time_scale = 1.0
	PhysicsServer3D.set_active(true)
	world = B3World.new()
	add_child(world)
	for n in ["Units", "Ragdolls", "Props", "Structs", "Hazards", "Projectiles"]:
		var r := Node3D.new()
		r.name = n
		add_child(r)
	unit_root = get_node("Units")
	ragdoll_root = get_node("Ragdolls")
	prop_root = get_node("Props")
	struct_root = get_node("Structs")
	hazard_root = get_node("Hazards")
	proj_root = get_node("Projectiles")
	fx = B3Fx.new()
	fx.battle = self
	add_child(fx)
	cam = B3Cam.new()
	cam.battle = self
	add_child(cam)
	_sphere.radius = 1.0
	_shape_q.shape = _sphere
	_shape_q.collide_with_bodies = true
	_shape_q.collide_with_areas = false
	if not opts.get("no_ui", false):
		tools = load("res://battle3d/b3_tools.gd").new()
		tools.battle = self
		add_child(tools)
		ui = load("res://battle3d/b3_ui.gd").new()
		ui.battle = self
		add_child(ui)
	scenario = String(opts.get("scenario", ""))
	var map_s := String(opts.get("map", ""))
	if map_s == "":
		map_s = B3Scenarios.map_for(scenario)
	weather = B3Weather.new()
	weather.battle = self
	add_child(weather)
	# --rules=time:night,weather:rain (screenshots and testing)
	for kv in String(opts.get("rules", "")).split(",", false):
		var pr := kv.split(":")
		if pr.size() == 2 and B3Rules.DEFAULTS.has(pr[0]):
			B3Rules.set_value(pr[0], pr[1])
	load_map(map_s)
	apply_rules()
	cam.fit(Vector3.ZERO, 38.0)
	_began = true
	if String(opts.get("net", "")) == "client":
		join_game(String(opts.get("ip", "127.0.0.1")))
	elif int(opts.get("surprise", 0)) != 0:
		B3Surprise.run(self, int(opts.surprise))
	elif String(opts.get("history", "")) != "":
		run_history(String(opts.history))
	elif scenario != "":
		B3Scenarios.run(self, scenario)
	elif ui:
		ui.toast("Pick something on the left, then click the ground to place it!  Drag to place a whole line.", false)
	if String(opts.get("net", "")) == "host":
		start_hosting()
	if ui:
		ui.refresh()
		# --play (first red person) or --play=tank (first unit of that kind); --fp looks out of its eyes
		var play_s := String(opts.get("play", ""))
		if play_s != "" and tools:
			for u in units:
				if (play_s == "1" and u.team == "red" and String(u.def.body) == "human") or u.kind == play_s:
					var fp_on: bool = opts.get("fp", false)
					later(0.5, func(): tools.play_as(u, fp_on))
					break
		match String(opts.get("open", "")):
			"rules":
				ui._show_rules()
			"saves":
				ui._show_saves()
			"help":
				ui.toggle_help()
			"history":
				ui._show_history()


## Sets up one of the 📜 History battles (B3History).
func run_history(id: String) -> void:
	B3History.run(self, id)


# ------------------------------------------------------------ 👥 together
## Lets friends on the same Wi-Fi join this battle.
func start_hosting() -> bool:
	if net:
		return net.is_host()
	net = B3Net.new()
	net.battle = self
	add_child(net)
	if not net.host():
		net.queue_free()
		net = null
		if ui:
			ui.toast("Couldn't start sharing. Is another game already hosting on this computer?", false)
		return false
	if ui:
		ui.toast("👥 Friends on the same Wi-Fi can join your battle now!", false)
		ui.refresh_net()
	return true


## Joins a friend's battle: everything here becomes a copy of theirs.
func join_game(ip: String) -> bool:
	if net:
		stop_net()
	if tools:
		tools.stop_playing()
	set_fighting(false)
	load_map(map_id)
	start_layout = {}
	puppet = true
	net = B3Net.new()
	net.battle = self
	add_child(net)
	if not net.join(ip):
		net_lost("Couldn't join that address.")
		return false
	if ui:
		ui.toast("👥 Joining %s..." % ip, false)
		ui.refresh_net()
	return true


func stop_net() -> void:
	if net == null:
		return
	var was_client := net.is_client()
	net.close()
	net.queue_free()
	net = null
	if was_client:
		_back_to_solo("👋 You left the battle.")
	elif ui:
		ui.toast("👥 Stopped sharing the battle.", false)
		ui.refresh_net()


## The connection to the host ended.
func net_lost(why: String) -> void:
	if net:
		net.queue_free()
		net = null
	_back_to_solo(why)


func _back_to_solo(msg: String) -> void:
	puppet = false
	B3Rules.load_from_settings()
	apply_rules()
	if tools:
		tools.stop_playing()
	set_paused(false)
	set_slowmo(false)
	load_map(map_id)
	start_layout = {}
	fighting = false
	if ui:
		ui.hide_banner()
		ui.refresh()
		ui.refresh_net()
		ui.toast(msg, false)


## A friend's copy sends this to the host instead of doing it here.
func _client_cmd(c: Dictionary) -> bool:
	if puppet and net and net.is_client():
		net.send_cmd(c)
		return true
	return false


func _exit_tree() -> void:
	B3Player.stop()
	B3Player.me.fp = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE     # never leave the mouse locked after first person
	if is_inside_tree():
		PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	B3Mats.clear_cache()
	B3Hazard.clear_cache()
	Engine.time_scale = 1.0
	PhysicsServer3D.set_active(true)
	if _began:
		Engine.physics_ticks_per_second = _old_tps
		get_tree().physics_interpolation = _old_interp


## Applies the ⚙️ Battle Rules: gravity, lighting, weather and the numbers
## fighters read every step.
func apply_rules() -> void:
	r_speed = B3Rules.speed_k()
	r_tough = B3Rules.toughness()
	r_knock = B3Rules.knock_k()
	if is_inside_tree():
		PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8 * B3Rules.gravity_k())
	if world:
		world.set_time(B3Rules.value("time"))
	if weather:
		weather.set_kind(B3Rules.value("weather"))
	if not B3Rules.respawn():
		_respawns.clear()


func leave() -> void:
	Engine.time_scale = 1.0
	PhysicsServer3D.set_active(true)
	if main:
		main.show_menu()


func space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state


# --------------------------------------------------------------- the clock
func toggle_play() -> void:
	if _client_cmd({"c": "fight"}):
		return
	if not fighting:
		set_fighting(true)
		set_paused(false)
	else:
		set_paused(not paused)


func set_fighting(on: bool) -> void:
	if fighting == on:
		return
	fighting = on
	if on:
		if not units.is_empty():
			start_layout = B3Saves.snapshot(self)
		snd("battle_start", null, 1.0)
		winner = ""
		teams_seen = _team_keys().size()
		if ui:
			ui.toast("⚔️  FIGHT!")
	if ui:
		ui.refresh()


## ⏮ Puts every fighter, building, barrel and pool back where it was when
## Fight! was pressed, ready to play the same battle again.
func reset_battle() -> bool:
	if _client_cmd({"c": "reset"}):
		return true
	if start_layout.is_empty():
		return false
	var keep := start_layout
	var was_paused := paused
	B3Saves.restore(self, keep, false, true)
	start_layout = keep
	if was_paused:
		set_paused(false)
	if ui:
		ui.hide_banner()
		ui.toast("⏮ Back to the start! Press Fight! to play it again.")
	snd("whoosh", null, 0.7)
	return true


func set_paused(on: bool) -> void:
	paused = on
	_apply_time()
	if ui:
		ui.refresh()


func set_slowmo(on: bool) -> void:
	slowmo = on
	_apply_time()
	if ui:
		ui.refresh()


func _apply_time() -> void:
	Engine.time_scale = 0.0 if paused else (0.3 if slowmo else 1.0)
	PhysicsServer3D.set_active(not paused)


## Runs `fn` after `t` seconds of battle time (stops while paused).
func later(t: float, fn: Callable) -> void:
	_events.append([t, fn])


# ------------------------------------------------------------------ spawning
func spawn_unit(kind: String, team: String, pos: Vector3, pers := "auto", yaw := INF, scale := 1.0, seed_ := -1) -> B3Unit:
	if not B3Defs.UNITS.has(kind):
		return null
	var u: B3Unit = B3Special.make(kind)    # fighter, special fighter or vehicle
	if scale != 1.0 and not (u is B3Vehicle):
		u.size_mult = scale
	var sd: int = rng.randi() if seed_ < 0 else seed_
	u.set_meta("seed", sd)      # the same seed gives the same look (horse colour, hair...)
	u.setup(self, kind, team, pers, sd)
	unit_root.add_child(u)
	var p := pos + Vector3(0, 0.05, 0)
	if u.flying:
		p.y += 5.0
	u.global_position = p
	u.home = Vector3(pos.x, pos.y, pos.z)
	u.facing = yaw if yaw != INF else atan2(-pos.x, -pos.z + 0.001)
	if u.rig:
		u.rig.rotation.y = u.facing
	u.reset_physics_interpolation()
	units.append(u)
	think_period = 0.2 + units.size() * 0.0016
	if winner != "":
		_check_victory()
	if ui:
		ui.counts_dirty = true
	return u


func spawn_prop(kind: String, pos: Vector3, yaw := 0.0) -> B3Prop:
	var p := B3Prop.new()
	p.setup(self, kind)
	prop_root.add_child(p)
	var lift := {"crate": 0.5, "xbarrel": 0.56, "dynamite": 0.3, "c4": 0.07, "mine": 0.02, "sandbag": 0.22}
	p.global_position = pos + Vector3(0, float(lift.get(kind, 0.3)), 0)
	p.rotation.y = yaw
	p.reset_physics_interpolation()
	props.append(p)
	if kind == "dynamite":
		snd("fuse", pos, 0.8)
	elif kind == "c4" and ui:
		ui.refresh()
	return p


func spawn_struct(kind: String, pos: Vector3, yaw := 0.0, length := 0.0, seed_ := -1) -> B3Struct:
	if kind == "crates":
		var b := Basis(Vector3.UP, yaw)
		var spots := [Vector3(-1.05, 0, 0), Vector3(0, 0, 0), Vector3(1.05, 0, 0), Vector3(-0.52, 1.02, 0), Vector3(0.52, 1.02, 0), Vector3(0, 2.04, 0)]
		var gy := world.height_at(pos.x, pos.z)
		for s in spots:
			var sp: Vector3 = s
			spawn_prop("crate", Vector3(pos.x, gy, pos.z) + b * sp + Vector3(0, 0.02, 0), yaw)
		snd("thud", pos, 0.6)
		return null
	if not B3Defs.STRUCTS.has(kind):
		return null
	var st := B3Struct.new()
	st.position = Vector3(pos.x, world.height_at(pos.x, pos.z) - 0.08, pos.z)
	st.rotation.y = yaw
	var sd: int = rng.randi() if seed_ < 0 else seed_
	st.set_meta("seed", sd)
	st.setup(self, kind, length, sd)
	struct_root.add_child(st)
	structs.append(st)
	snd("thud", pos, 0.8)
	fx.dust(st.position, 2.0)
	return st


## A building made of saved pieces (History battles' stakes, earth forts and
## fences, which aren't in the Build tab). See B3Struct.piece_data().
func spawn_custom_struct(kind: String, pos: Vector3, yaw: float, data: Array) -> B3Struct:
	var st := B3Struct.new()
	st.position = pos
	st.rotation.y = yaw
	st.setup(self, kind, 0.0, 0)      # an unknown kind builds nothing; the pieces come from `data`
	st.set_meta("seed", 0)
	struct_root.add_child(st)
	structs.append(st)
	st.build_from(data)
	return st


func spawn_hazard(kind: String, pos: Vector3, r: float, life := -1.0) -> B3Hazard:
	var h := B3Hazard.new()
	h.position = Vector3(pos.x, 0, pos.z)
	var lit := 0
	for o in hazards:
		if o.light:
			lit += 1
	h.setup(self, kind, r, life, lit < 6)
	hazard_root.add_child(h)
	hazards.append(h)
	return h


func spawn_proj(kind: String, pos: Vector3, vel: Vector3, shooter, w: Dictionary) -> B3Proj:
	var p := B3Proj.new()
	p.setup(self, kind, vel)
	proj_root.add_child(p)
	p.global_position = pos
	p.set_shooter(shooter)
	if w.has("dmg"):
		p.dmg = float(w.dmg)
	if w.has("radius"):
		p.radius = float(w.radius)
	if w.has("power"):
		p.power = float(w.power)
	if w.has("knock"):
		p.knock = float(w.knock)
	p.reset_physics_interpolation()
	return p


## Things from the Booms tab: `dir` is the screen-right direction (airstrikes).
func drop(id: String, pos: Vector3, dir := Vector3.RIGHT) -> void:
	if _client_cmd({"c": "drop", "id": id, "pos": pos, "dir": dir}):
		return
	var d: Dictionary = B3Defs.BOOMS.get(id, {})
	match id:
		"grenade":
			var p := spawn_proj("dropgrenade", pos + Vector3(0, 3.0, 0), Vector3(rng.randf_range(-1, 1), -1.0, rng.randf_range(-1, 1)), null, d)
			p.fuse = 2.3
		"dynamite", "c4", "mine", "xbarrel":
			spawn_prop(id, pos, rng.randf() * TAU)
		"cluster", "napalm", "acidbomb":
			spawn_proj(id, pos + Vector3(0, 26, 0), Vector3(0, -10, 0), null, d)
			snd("whistle", pos, 0.8)
		"airstrike":
			airstrike(pos, dir)
		"artillery":
			artillery(pos)
		"nuke":
			spawn_proj("nuke", pos + Vector3(0, 40, 0), Vector3(0, -16, 0), null, d)
			snd("alarm", pos, 1.0)
			snd("whistle", pos, 1.0)
			if ui:
				ui.toast("☢️  NUKE INCOMING!")


func airstrike(pos: Vector3, dir: Vector3) -> void:
	if puppet:
		return     # a friend's copy: the host does the real thing and sends the effects
	var d := Vector3(dir.x, 0, dir.z).normalized()
	if d == Vector3.ZERO:
		d = Vector3.RIGHT
	var plane := Node3D.new()
	var body := B3Mats.mat(Color("8a96a8"), 0.5)
	B3Mats.add(plane, B3Mats.capsule(0.6, 6.0), body, Vector3.ZERO, Vector3(90, 0, 0))
	B3Mats.add(plane, B3Mats.box(Vector3(9.0, 0.15, 1.6)), body, Vector3(0, 0, 0.2))
	B3Mats.add(plane, B3Mats.box(Vector3(3.2, 0.12, 0.9)), body, Vector3(0, 0.1, -2.6))
	B3Mats.add(plane, B3Mats.box(Vector3(0.12, 1.4, 1.0)), body, Vector3(0, 0.7, -2.6))
	B3Mats.add(plane, B3Mats.sphere(0.45, 10), B3Mats.mat(Color("6fd3ff"), 0.1), Vector3(0, 0.35, 1.6), Vector3.ZERO, Vector3(0.8, 0.6, 1.4))
	for sx in [-1.0, 1.0]:
		B3Mats.add(plane, B3Mats.box(Vector3(0.6, 0.16, 1.2)), B3Mats.mat(Color("ff4646")), Vector3(4.2 * sx, 0.02, 0.2), Vector3.ZERO, Vector3.ONE, false)
	proj_root.add_child(plane)
	var start := pos - d * 75.0 + Vector3(0, 20, 0)
	plane.global_position = start
	plane.global_basis = Basis.looking_at(d, Vector3.UP, true)
	plane.reset_physics_interpolation()
	var drops: Array[Vector3] = []
	for i in 8:
		drops.append(pos + d * (i - 3.5) * 2.8)
	planes.append({"node": plane, "dir": d, "speed": 34.0, "drops": drops, "i": 0, "life": 5.0})
	snd("plane", pos, 1.0)


func artillery(pos: Vector3) -> void:
	if puppet:
		return     # a friend's copy: the host does the real thing and sends the effects
	var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	for i in 10:
		var t := 0.2 + i * 0.28 + rng.randf() * 0.15
		var off := Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
		later(t, func():
			var target := pos + off
			target.y = world.height_at(target.x, target.z)
			var start := target + side * 18.0 + Vector3(0, 38, 0)
			var tt := 1.5
			var v := (target - start) / tt + Vector3(0, 0.5 * 9.8 * tt, 0)
			spawn_proj("shell", start, v, null, B3Defs.BOOMS.artillery)
			snd("whistle", target, 0.6))


# --------------------------------------------------------------- explosions
## The big one: knocks, damages, launches, breaks and chains. `power` is the
## launch speed (m/s) at the centre; it fades to nothing at `r`.
func explode(pos: Vector3, r: float, power: float, dmg: float, opts := {}) -> void:
	if puppet:
		return     # a friend's copy: the host does the real thing and sends the effects
	var up: float = opts.get("up", 0.8)
	var kind := String(opts.get("kind", "fire"))
	var by = opts.get("by", null)
	if by != null and not is_instance_valid(by):
		by = null
	r *= B3Rules.boom_r()
	power *= B3Rules.boom_power()
	var spare_team := ""
	if by != null and by is B3Unit and not B3Rules.friendly_fire() and String(by.team) != "wild":
		spare_team = String(by.team)
	_blast_bodies(pos, r, power * r_knock, dmg, up, {})
	for u: B3Unit in units.duplicate():
		if u.dead or not is_instance_valid(u):
			continue
		if spare_team != "" and u.team == spare_team:
			continue
		var c := u.center()
		var d := c - pos
		var dist := d.length()
		if dist > r + u.radius:
			continue
		var f := clampf(1.0 - maxf(0.0, dist - u.radius) / r, 0.0, 1.0)
		var dir := (Vector3(d.x, 0, d.z).normalized() + Vector3.UP * up).normalized()
		u.hurt(dmg * f, dir, power * f * 1.15 + 1.5, by, "blast")
	if bool(opts.get("quiet", false)):
		return
	fx.explosion(pos, r, 1 if kind == "acid" else 0)
	shake(clampf(r / 7.0, 0.15, 0.9), pos)
	if r >= 5.0:
		snd("mega_boom", pos, 1.0)
	else:
		snd("boom", pos, 0.9)


func _blast_bodies(pos: Vector3, r: float, power: float, dmg: float, up: float, skip: Dictionary, r_min := 0.0, fall_r := 0.0) -> void:
	var fr := fall_r if fall_r > 0.0 else r
	_sphere.radius = r
	_shape_q.transform = Transform3D(Basis.IDENTITY, pos)
	_shape_q.collision_mask = B3Defs.L_RAGDOLL | B3Defs.L_PROP | B3Defs.L_STRUCT | B3Defs.L_SCENERY
	var res := space().intersect_shape(_shape_q, 1024)
	var hit_rd := {}
	var touched := {}
	for hit in res:
		var c = hit.collider
		if c == null or not is_instance_valid(c):
			continue
		var id: int = (c as Object).get_instance_id()
		if skip.has(id):
			continue
		var cp: Vector3 = (c as Node3D).global_position
		var d := cp - pos
		var dist := d.length()
		if dist < r_min:
			continue
		skip[id] = true
		if c is B3Piece:
			var pc := c as B3Piece
			var ed := maxf(0.0, dist - pc.size.length() * 0.35)
			var f2 := clampf(1.0 - ed / fr, 0.0, 1.0)
			if f2 <= 0.0:
				continue
			pc.hp -= dmg * f2 * 1.4
			if pc.hp <= 0.0 or power * f2 > 14.0:
				var dir2 := (d.normalized() + Vector3.UP * 0.6).normalized()
				touched[pc.structure] = true
				break_piece(pc, dir2 * power * f2 * 0.8)
			continue
		var f := clampf(1.0 - dist / fr, 0.0, 1.0)
		if f <= 0.0:
			continue
		var dir := (d.normalized() if dist > 0.05 else Vector3.UP)
		dir = (dir + Vector3.UP * up * 0.6).normalized()
		if c is RigidBody3D:
			var b := c as RigidBody3D
			if b.has_meta("ragdoll"):
				var rd = b.get_meta("ragdoll")
				if is_instance_valid(rd):
					if rd.frozen and rd.sinking <= 0.0:
						rd.unfreeze()
					if rd.unit and is_instance_valid(rd.unit) and not hit_rd.has(rd.get_instance_id()):
						hit_rd[rd.get_instance_id()] = true
						rd.unit.hurt(dmg * f * 0.6, dir, 0.0, null, "blast")
				if not b.freeze:
					b.linear_velocity += dir * power * f * 1.1
					b.angular_velocity += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * power * f * 0.6
			elif b is B3Prop:
				var p := b as B3Prop
				if not p.freeze:
					var k := clampf(40.0 / p.mass, 0.4, 1.4)
					p.linear_velocity += dir * power * f * k
					p.angular_velocity += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * power * f * 0.4
				p.damage(dmg * f)
			elif not b.freeze:
				b.linear_velocity += dir * power * f
				b.angular_velocity += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * power * f * 0.3
		elif c is StaticBody3D and (c as Node).has_meta("scenery"):
			if power * f > 15.0:
				if net:
					net.rec_event(["uproot", world.scenery_index(c), dir * power * f * 0.7])
				world.uproot(c, dir * power * f * 0.7, self)
	for s in touched:
		if is_instance_valid(s):
			later(0.0, (s as B3Struct).settle)


## Pushes props and ragdolls around without damage (stomps, charges).
func blast_props(pos: Vector3, r: float, power: float) -> void:
	if puppet:
		return     # a friend's copy: the host does the real thing and sends the effects
	_sphere.radius = r
	_shape_q.transform = Transform3D(Basis.IDENTITY, pos)
	_shape_q.collision_mask = B3Defs.L_RAGDOLL | B3Defs.L_PROP
	for hit in space().intersect_shape(_shape_q, 128):
		var c = hit.collider
		if c is RigidBody3D and not (c as RigidBody3D).freeze:
			var b := c as RigidBody3D
			var d := b.global_position - pos
			var f := clampf(1.0 - d.length() / r, 0.0, 1.0)
			b.linear_velocity += (Vector3(d.x, 0, d.z).normalized() + Vector3.UP * 0.8).normalized() * power * f
		elif c is RigidBody3D and (c as Node).has_meta("ragdoll"):
			var rd = (c as Node).get_meta("ragdoll")
			if is_instance_valid(rd) and rd.frozen and rd.sinking <= 0.0:
				rd.unfreeze()


func nuke_blast(pos: Vector3) -> void:
	if puppet:
		return     # a friend's copy: the host does the real thing and sends the effects
	fx.nuke(pos)
	if ui:
		ui.flash(1.0)
	cam.shake(1.6)
	snd("nuke", pos, 1.4)
	snd("mega_boom", pos, 1.4)
	snd("rumble", pos, 1.2)
	explode(pos, 10.0, 42.0, 900.0, {"quiet": true, "up": 1.0})
	_waves.append({"pos": pos, "r": 10.0, "max": 46.0, "speed": 32.0, "power": 36.0, "dmg": 520.0, "skip": {}, "units": {}})


func _wave_tick(w: Dictionary, dt: float) -> bool:
	var pos: Vector3 = w.pos
	var r0: float = w.r
	var r1 := r0 + float(w.speed) * dt
	var mx: float = w.max
	w.r = r1
	var power: float = w.power
	var dmg: float = w.dmg
	var hit_units: Dictionary = w.units
	for u: B3Unit in units.duplicate():
		if u.dead or hit_units.has(u.uid):
			continue
		var c := u.center()
		var dist := Vector2(c.x - pos.x, c.z - pos.z).length()
		if dist > r1:
			continue
		hit_units[u.uid] = true
		var f := clampf(1.0 - dist / mx, 0.0, 1.0)
		var dir := (Vector3(c.x - pos.x, 0, c.z - pos.z).normalized() + Vector3.UP * 0.9).normalized()
		u.hurt(dmg * f, dir, power * f + 5.0, null, "blast")
	_blast_bodies(pos, r1, power, dmg, 0.9, w.skip, r0 - 1.0, mx)
	return r1 < mx


# ----------------------------------------------------------- hits & breaks
func shot_hit(hit: Dictionary, w: Dictionary, dir: Vector3, shooter) -> void:
	var c = hit.collider
	var p: Vector3 = hit.position
	if c is B3Unit:
		(c as B3Unit).hurt(float(w.dmg), dir, float(w.get("knock", 1.0)), shooter, "shot")
	elif c is B3Prop:
		var pr := c as B3Prop
		pr.damage(float(w.dmg))
		if not pr.freeze and is_instance_valid(pr):
			pr.apply_impulse(dir * float(w.dmg) * 0.5, p - pr.global_position)
		snd("metal_hit" if pr.kind == "xbarrel" else "thud", p, 0.4)
	elif c is B3Piece:
		var pc := c as B3Piece
		pc.hp -= float(w.dmg) * 0.15
		if pc.hp <= 0.0:
			break_piece(pc, dir * 3.0)
		fx.dust(p, 0.25)


func break_piece(p: B3Piece, vel: Vector3, whole := false) -> void:
	if not is_instance_valid(p) or p.is_queued_for_deletion():
		return
	var s: B3Struct = p.structure
	if net and is_instance_valid(s):
		net.rec_event(["brk", s.get_instance_id(), int(p.get_meta("pi", -1)), vel, whole])
	if s:
		s.pieces.erase(p)
	var xf := p.global_transform
	var mat: Material = null
	for c in p.get_children():
		if c is MeshInstance3D:
			mat = (c as MeshInstance3D).material_override
			break
	if p.whole or p.wedge or whole:
		var rb := _chunk_body(xf, p.size, 1.0)
		for c in p.get_children():
			(c as Node).reparent(rb, true)
		rb.linear_velocity = vel
		rb.angular_velocity = Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2)) * (0.3 + vel.length() * 0.1)
	else:
		var n := Vector3i(clampi(ceili(p.size.x / 1.3), 1, 3), clampi(ceili(p.size.y / 1.3), 1, 2), clampi(ceili(p.size.z / 1.3), 1, 3))
		var sub := p.size / Vector3(n)
		for ix in n.x:
			for iy in n.y:
				for iz in n.z:
					var lp := -p.size * 0.5 + sub * Vector3(ix + 0.5, iy + 0.5, iz + 0.5)
					var rb := _chunk_body(Transform3D(xf.basis, xf * lp), sub, 1.0)
					var cs := CollisionShape3D.new()
					var bs := BoxShape3D.new()
					bs.size = sub * 0.96
					cs.shape = bs
					rb.add_child(cs)
					B3Mats.add(rb, B3Mats.box(sub * 0.97), mat)
					var spread := Vector3(rng.randf_range(-1, 1), rng.randf_range(0, 1), rng.randf_range(-1, 1)) * (1.5 + vel.length() * 0.25)
					rb.linear_velocity = vel + spread
					rb.angular_velocity = Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)) * (0.3 + vel.length() * 0.08)
	p.queue_free()
	fx.dust(xf.origin, maxf(1.0, p.size.length() * 0.4))
	snd("crumble", xf.origin, 0.8)
	if s and s.pieces.is_empty():
		structs.erase(s)
		s.queue_free()
	elif s and not whole:
		later(0.0, s.settle)
	_trim_chunks()


func _chunk_body(xf: Transform3D, size: Vector3, _k: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = B3Defs.L_PROP
	rb.collision_mask = B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_RAGDOLL | B3Defs.L_PROP | B3Defs.L_SCENERY
	rb.mass = clampf(size.x * size.y * size.z * 120.0, 6.0, 160.0)
	rb.physics_material_override = B3Prop.pmat()
	rb.angular_damp = 0.5
	rb.set_meta("debris", true)
	prop_root.add_child(rb)
	rb.global_transform = xf
	rb.reset_physics_interpolation()
	chunks.append(rb)
	return rb


func break_crate(c: B3Prop) -> void:
	var xf := c.global_transform
	var v := c.linear_velocity
	remove_prop(c, false)
	var mat := B3Mats.mat(Color("c08a4e"))
	for i in 4:
		var lp := Vector3(0, -0.375 + i * 0.25, 0)
		var rb := _chunk_body(Transform3D(xf.basis, xf * lp), Vector3(1.0, 0.22, 0.3), 1.0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.0, 0.2, 0.3)
		cs.shape = bs
		rb.add_child(cs)
		B3Mats.add(rb, B3Mats.box(Vector3(1.0, 0.2, 0.3)), mat)
		rb.linear_velocity = v + Vector3(rng.randf_range(-3, 3), rng.randf_range(1, 5), rng.randf_range(-3, 3))
		rb.angular_velocity = Vector3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), rng.randf_range(-5, 5))
	fx.poof(xf.origin, 1.0)
	snd("crumble", xf.origin, 0.7)
	_trim_chunks()


func _trim_chunks() -> void:
	while chunks.size() > B3Defs.MAX_CHUNKS:
		var c: RigidBody3D = chunks.pop_front()
		if is_instance_valid(c):
			fx.poof(c.global_position, 0.5)
			c.queue_free()


# ------------------------------------------------------------ bookkeeping
func on_unit_ko(u: B3Unit, by) -> void:
	units.erase(u)
	kos += 1
	if tools and u == B3Player.unit and u.ctl == B3Player.me:
		B3Player.last_pos = u.global_position
		tools.player_lost()     # first person: into a teammate; overhead: back to watching
	if puppet:
		if ui:
			ui.counts_dirty = true
		return
	if net:
		var v := Vector3.ZERO
		if u.ragdoll and is_instance_valid(u.ragdoll):
			u.ragdoll.set_meta("nid", u.get_instance_id())
			if is_instance_valid(u.ragdoll.root_body):
				v = u.ragdoll.root_body.linear_velocity
		net.rec_event(["ko", u.get_instance_id(), v])
	if by != null and is_instance_valid(by) and by is B3Unit and by != u:
		team_kos[by.team] = int(team_kos.get(by.team, 0)) + 1
		if by.kills > int(mvp.get("kills", 0)):
			mvp = {"kind": by.kind, "team": by.team, "kills": by.kills, "uid": by.uid}
	if fighting and B3Rules.respawn():
		_respawns.append({"t": 5.0, "kind": u.kind, "team": u.team, "pos": u.home, "pers": u.pers_choice})
	think_period = 0.2 + units.size() * 0.0016
	if tools and tools.selected == u:
		tools.select(null)
	snd("ko", u.position, 0.5)
	_trim_corpses()
	if ui:
		ui.counts_dirty = true


func _trim_corpses() -> void:
	var dead_n := 0
	for rd in ragdolls:
		if rd.dead:
			dead_n += 1
	var i := 0
	while dead_n > B3Defs.MAX_CORPSES and i < ragdolls.size():
		var rd := ragdolls[i]
		if rd.dead:
			if is_instance_valid(rd):
				fx.poof(rd.center(), 1.0)
				rd.queue_free()
			ragdolls.remove_at(i)
			dead_n -= 1
		else:
			i += 1


func remove_unit(u: B3Unit, poof := true) -> void:
	if not is_instance_valid(u):
		return
	units.erase(u)
	if tools and u == B3Player.unit and u.ctl == B3Player.me:
		tools.stop_playing()
	if net:
		net.rec_event(["rm", u.get_instance_id()])
	if poof:
		fx.poof(u.center(), 1.0 + u.radius)
		snd("poof", u.position, 0.7)
	if u.ragdoll and is_instance_valid(u.ragdoll):
		ragdolls.erase(u.ragdoll)
		u.ragdoll.queue_free()
	if u.laser:
		u.laser.queue_free()
	if tools and tools.selected == u:
		tools.select(null)
	u.dead = true
	u.queue_free()
	if ui:
		ui.counts_dirty = true


func remove_ragdoll(rd: B3Ragdoll, poof := true) -> void:
	if not is_instance_valid(rd):
		return
	if rd.unit and is_instance_valid(rd.unit):
		remove_unit(rd.unit, poof)
		return
	ragdolls.erase(rd)
	if poof:
		fx.poof(rd.center(), 1.2)
		snd("poof", rd.center(), 0.6)
	rd.queue_free()


func remove_prop(p: B3Prop, poof := true) -> void:
	props.erase(p)
	if net and is_instance_valid(p):
		net.rec_event(["rm", p.get_instance_id()])
	if is_instance_valid(p):
		if poof:
			fx.poof(p.global_position, 0.8)
			snd("poof", p.global_position, 0.6)
		p.queue_free()
	if ui:
		ui.refresh_c4()


func remove_chunk(b: RigidBody3D, poof := true) -> void:
	chunks.erase(b)
	if is_instance_valid(b):
		if poof:
			fx.poof(b.global_position, 0.8)
		b.queue_free()


func remove_struct(s: B3Struct, poof := true) -> void:
	structs.erase(s)
	if net and is_instance_valid(s):
		net.rec_event(["rm", s.get_instance_id()])
	if is_instance_valid(s):
		if poof:
			for p in s.pieces:
				fx.poof(p.global_position, 1.5)
			snd("poof", s.global_position, 0.8)
		s.queue_free()


func remove_hazard(h: B3Hazard, poof := false) -> void:
	hazards.erase(h)
	if net and is_instance_valid(h):
		net.rec_event(["rm", h.get_instance_id()])
	if is_instance_valid(h):
		if poof:
			fx.steam(h.global_position, h.radius * 0.5)
			snd("fizz", h.global_position, 0.7)
		h.queue_free()


func c4_count() -> int:
	var n := 0
	for p in props:
		if p.kind == "c4" and not p.lit:
			n += 1
	return n


func detonate_c4() -> void:
	if _client_cmd({"c": "c4"}):
		return
	var t := 0.0
	var any := false
	for p in props:
		if p.kind == "c4" and not p.lit:
			p.trigger(t)
			t += 0.12
			any = true
	if any:
		snd("pin", null, 1.0)
	elif ui:
		ui.toast("No C4 placed yet! Pick 📟 C4 from the 💣 Booms tab.", false)


func clear_units() -> void:
	for u in units:
		if is_instance_valid(u):
			if u.laser:
				u.laser.queue_free()
			u.dead = true
			u.queue_free()
	units.clear()
	for rd in ragdolls:
		if is_instance_valid(rd):
			rd.queue_free()
	ragdolls.clear()
	if tools:
		tools.select(null)
	winner = ""
	teams_seen = 0
	set_fighting(false)
	if ui:
		ui.hide_banner()
		ui.counts_dirty = true
		ui.refresh()


func clear_debris() -> void:
	var keep: Array[B3Ragdoll] = []
	for rd in ragdolls:
		if is_instance_valid(rd):
			if rd.dead:
				rd.queue_free()
			else:
				keep.append(rd)
	ragdolls = keep
	for c in chunks:
		if is_instance_valid(c):
			c.queue_free()
	chunks.clear()
	for p in proj_root.get_children():
		p.queue_free()
	planes.clear()


## Takes everything off the battlefield but leaves the land, trees and sky alone.
func clear_battlefield() -> void:
	clear_units()
	clear_debris()
	for p in props:
		if is_instance_valid(p):
			p.queue_free()
	props.clear()
	for s in structs:
		if is_instance_valid(s):
			s.queue_free()
	structs.clear()
	for h in hazards:
		if is_instance_valid(h):
			h.queue_free()
	hazards.clear()
	_events.clear()
	_waves.clear()
	_sinking.clear()
	fx.clear()
	_respawns.clear()
	mvp = {}
	team_kos = {}


func clear_all() -> void:
	load_map(map_id)


func load_map(id: String) -> void:
	clear_battlefield()
	map_id = id if B3Defs.MAPS.has(id) else "grassland"
	world.load_map(map_id)
	world.set_time(B3Rules.value("time"))
	cam.limit = (float(world.call("half_size")) if world.has_method("half_size") else 64.0) - 4.0
	_respawns.clear()
	mvp = {}
	team_kos = {}
	var md: Dictionary = B3Defs.MAPS[map_id]
	fx.set_dust_color(md.get("dust", Color(0.7, 0.65, 0.55)))
	for bp in world.builtin_pools:
		spawn_hazard(String(bp.kind), bp.pos, float(bp.radius))
	if ui:
		ui.refresh()
		ui.refresh_c4()


# ----------------------------------------------------------------- queries
func raycast(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	_ray.from = from
	_ray.to = to
	_ray.collision_mask = mask
	_ray.exclude = exclude
	return space().intersect_ray(_ray)


## Height of the ground or a building under `p` (looking down from p).
func surface_y(p: Vector3) -> float:
	var hit := raycast(p, p - Vector3(0, 80, 0), B3Defs.L_TERRAIN | B3Defs.L_STRUCT)
	if hit.is_empty():
		return world.height_at(p.x, p.z)
	var hp: Vector3 = hit.position
	return hp.y


func hazard_at(p: Vector3, margin := 0.0) -> B3Hazard:
	for h in hazards:
		if h.contains(p, margin):
			return h
	return null


func unit_by_id(id: int) -> B3Unit:
	if id == 0:
		return null
	var o = instance_from_id(id)
	if o is B3Unit and is_instance_valid(o) and not (o as B3Unit).dead:
		return o
	return null


func unit_by_rid(rid: RID) -> B3Unit:
	if not rid.is_valid():
		return null
	for u in units:
		if u.get_rid() == rid:
			return u
	return null


func enemies_left(_u: B3Unit) -> bool:
	return team_count >= 2


func _team_keys() -> Dictionary:
	var keys := {}
	for r in _respawns:
		keys[String(r.team) if String(r.team) != "wild" else "wild:" + String(r.kind)] = true
	for u in units:
		if u.dead:
			continue
		keys[u.team if u.team != "wild" else "wild:" + u.kind] = true
	return keys


func team_counts() -> Dictionary:
	var c := {}
	for u in units:
		if u.dead:
			continue
		c[u.team] = int(c.get(u.team, 0)) + 1
	return c


## "⭐ MVP: the Red Knight with 5 knock-outs!" (or "" if nobody scored).
func mvp_text() -> String:
	if mvp.is_empty() or int(mvp.get("kills", 0)) < 2:
		return ""
	var d := B3Defs.unit_def(String(mvp.kind))
	var tname := "Wild" if String(mvp.team) == "wild" else String(B3Defs.TEAM[String(mvp.team)].name)
	return "⭐ MVP: the %s %s %s with %d knock-outs!" % [tname, d.icon, d.name, int(mvp.kills)]


func _check_victory() -> void:
	var keys := _team_keys()
	team_count = keys.size()
	if not fighting:
		return
	if winner != "":
		if team_count == 0 and winner != "nobody":
			winner = "nobody"
			if ui:
				ui.banner("💥  Nobody wins! It's a draw!", Color("ffcf4a"))
			return
		if team_count >= 2:
			winner = ""
			for u in units:
				u.cheer = false
			if ui:
				ui.hide_banner()
		return
	teams_seen = maxi(teams_seen, team_count)
	if teams_seen < 2 or team_count > 1:
		return
	if team_count == 0:
		winner = "nobody"
		if ui:
			ui.banner("💥  Nobody wins! It's a draw!", Color("ffcf4a"))
		snd("victory", null, 0.7)
		return
	var k := String(keys.keys()[0])
	winner = k
	var txt := ""
	var col := Color("ffcf4a")
	if k.begins_with("wild:"):
		var d := B3Defs.unit_def(k.substr(5))
		txt = "%s  The %s wins!  🏆" % [d.icon, d.name]
		col = B3Defs.team_col("wild").lightened(0.3)
	else:
		var td: Dictionary = B3Defs.TEAM[k]
		txt = "%s  %s wins!  🏆" % [td.icon, td.name]
		col = (td.col as Color).lightened(0.15)
	for u in units:
		u.cheer = true
	if ui:
		ui.banner(txt, col)
		var star := mvp_text()
		if star != "":
			later(1.2, func():
				if ui and winner != "":
					ui.toast(star))
	snd("victory", null, 1.0)
	snd("confetti", null, 0.8)
	var c := Vector3.ZERO
	for u in units:
		c += u.position
	if not units.is_empty():
		c /= units.size()
		for i in 5:
			later(i * 0.3, func(): fx.explosion(c + Vector3(rng.randf_range(-6, 6), 6.0 + rng.randf() * 4.0, rng.randf_range(-6, 6)), 0.9))


# ---------------------------------------------------------------- feedback
func snd(n: String, at = null, vol := 1.0, pitch := 1.0) -> void:
	if net:
		net.rec_fx(["snd", n, at, vol, pitch])
	var name_s := n
	if not Sfx.has(name_s) and SND_FALLBACK.has(name_s):
		name_s = String(SND_FALLBACK[name_s])
	var v := vol
	if at is Vector3 and cam:
		var p := at as Vector3
		var d := Vector2(p.x - cam.focus.x, p.z - cam.focus.z).length()
		v *= clampf(1.25 - d / (cam.size * 1.4), 0.12, 1.0)
	Sfx.play(name_s, null, v, pitch)


## Camera shake from something at `at`: fades with distance from what you're
## looking at, small bumps (gunfire, footsteps) are ignored, and the ⚙️ Screen
## shake rule scales it all (A little by default).
func shake(a: float, at = null) -> void:
	if net:
		net.rec_fx(["shake", a, at])
	var s := a
	if at is Vector3 and cam:
		var p := at as Vector3
		var c := cam.view_center()
		var d := Vector2(p.x - c.x, p.z - c.z).length()
		var reach := cam.size * 1.2 if not cam.first_person() else 30.0
		s *= clampf(1.3 - d / reach, 0.0, 1.0)
	if s < 0.18:
		return
	cam.shake(s)


# ------------------------------------------------------------------- tick
func _physics_process(dt: float) -> void:
	if dt <= 0.0:
		return
	time += dt
	_events_tick(dt)
	if puppet:
		return
	var i := 0
	while i < _waves.size():
		if not _wave_tick(_waves[i], dt):
			_waves.remove_at(i)
		else:
			i += 1
	_planes_tick(dt)
	_respawn_tick(dt)
	_hz_t -= dt
	if _hz_t <= 0.0:
		_hz_t = 0.15
		_hazard_bodies()
	i = 0
	while i < _sinking.size():
		var sk: Array = _sinking[i]
		var b: RigidBody3D = sk[0]
		sk[1] = float(sk[1]) + dt
		if not is_instance_valid(b) or float(sk[1]) > 2.2:
			if is_instance_valid(b):
				b.queue_free()
			_sinking.remove_at(i)
			continue
		b.global_position.y -= dt * 0.6
		i += 1
	_vic_t -= dt
	if _vic_t <= 0.0:
		_vic_t = 0.4
		_check_victory()


func _events_tick(dt: float) -> void:
	var i := 0
	while i < _events.size():
		var e: Array = _events[i]
		e[0] = float(e[0]) - dt
		if float(e[0]) <= 0.0:
			_events.remove_at(i)
			var fn: Callable = e[1]
			if fn.is_valid():
				fn.call()
		else:
			i += 1


## Reinforcements: knocked-out fighters come back where they were placed.
func _respawn_tick(dt: float) -> void:
	if _respawns.is_empty():
		return
	if not fighting or not B3Rules.respawn():
		_respawns.clear()
		return
	var i := 0
	while i < _respawns.size():
		var r: Dictionary = _respawns[i]
		r.t = float(r.t) - dt
		if float(r.t) <= 0.0:
			_respawns.remove_at(i)
			var p: Vector3 = r.pos
			p.y = surface_y(p)
			var nu := spawn_unit(String(r.kind), String(r.team), p, String(r.pers))
			if nu:
				fx.poof(p + Vector3(0, 0.8, 0), 1.0)
				snd("pop", p, 0.6)
		else:
			i += 1


func _planes_tick(dt: float) -> void:
	var i := 0
	while i < planes.size():
		var pl: Dictionary = planes[i]
		var node: Node3D = pl.node
		if not is_instance_valid(node):
			planes.remove_at(i)
			continue
		var d: Vector3 = pl.dir
		node.global_position += d * float(pl.speed) * dt
		var drops: Array[Vector3] = pl.drops
		var k: int = pl.i
		while k < drops.size():
			var target: Vector3 = drops[k]
			var rel := (node.global_position - target).dot(d)
			if rel < -9.5:
				break
			var b := spawn_proj("bomb", node.global_position - Vector3(0, 0.8, 0), d * 5.0 + Vector3(0, -2, 0), null, B3Defs.BOOMS.airstrike)
			b.reset_physics_interpolation()
			snd("whistle", target, 0.5)
			k += 1
		pl.i = k
		pl.life = float(pl.life) - dt
		if float(pl.life) <= 0.0:
			node.queue_free()
			planes.remove_at(i)
			continue
		i += 1


## Ragdolls, props and chunks that fall into lava/acid sink and vanish.
func _hazard_bodies() -> void:
	if hazards.is_empty():
		return
	for rd: B3Ragdoll in ragdolls.duplicate():
		if not is_instance_valid(rd) or rd.sinking > 0.0:
			continue
		var c := rd.center()
		for h in hazards:
			if h.kind != "fire" and h.contains(c, -0.3):
				rd.sink(h.kind)
				fx.splash(c, h.kind == "acid")
				snd("sizzle" if h.kind == "lava" else "fizz", c, 0.8)
				break
	for p: B3Prop in props.duplicate():
		if not is_instance_valid(p) or p.sinking > 0.0 or p.freeze:
			continue
		for h in hazards:
			if h.kind != "fire" and h.contains(p.global_position, -0.2):
				if p.kind == "xbarrel" or p.kind == "dynamite":
					p.trigger(0.2)
				else:
					p.sinking = 0.01
					p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
					p.freeze = true
					fx.splash(p.global_position, h.kind == "acid")
					snd("sizzle", p.global_position, 0.6)
				break
	for c: RigidBody3D in chunks.duplicate():
		if not is_instance_valid(c):
			chunks.erase(c)
			continue
		for h in hazards:
			if h.kind != "fire" and h.contains(c.global_position, -0.2):
				chunks.erase(c)
				c.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				c.freeze = true
				_sinking.append([c, 0.0])
				fx.splash(c.global_position, h.kind == "acid")
				break

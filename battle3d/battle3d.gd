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
	"battle_start": "party", "snap": "snap", "honk": "nope", "defeat": "dizzy",
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

## 🪙 Budget battles (🧩 Puzzles, 🌊 Wave Defense): points to spend on what you
## place. budget -1 means everything is free (the normal sandbox). Things you
## buy carry their price as meta "cost" and give it back if you erase them
## before the fight starts. build_zone limits where you may place things (an
## x/z rectangle; no size means anywhere) and build_team, if set, is the team
## everything you place joins.
signal budget_changed
signal battle_ended(winner: String)      # a team, "wild:kind" or "nobody"
var budget := -1
var spent := 0
var build_zone := Rect2()
var build_team := ""
var _spent_at_fight := 0
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
var _settling := {}               # buildings (instance ids) with a settle() waiting (_settle_soon)
var _ray := PhysicsRayQueryParameters3D.new()
var _shape_q := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()
# the physics settings from outside 3D Battle, put back when the last battle
# closes (a new battle can start while the old one is still closing: it must
# not mistake the old one's 60 ticks for the game's own)
static var _live := 0
static var _old_tps := 60
static var _old_interp := false
var _counted := false
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
var history_id := ""              # the 📜 History battle on the field (the 📜 History Buff sticker)
var ready_id := ""                # the 🎯 Ready-made battle on the field (B3Scenarios.on_fight at Fight!)
var puzzle: B3Puzzles = null      # the 🧩 Army Puzzle on the field (B3Puzzles), if one is
var zone_vis: Node3D = null       # the glowing build zone of a budget battle (B3Puzzles.zone_visual)
var modes: B3Modes = null         # 🏁 the battle goal (👑 King, 🚩 Hill) and 🌊 Wave Defense (B3Modes)
# 🏆 the scoreboard (see scoreboard()), counted from when Fight! is pressed
var fight_t0 := 0.0               # battle time then
var fight_end_t := 0.0            # ...and when it was won
var fight_kos0 := 0               # `kos` then
var fight_teams := {}             # team -> how many fighters it brought
var fighter_log := {}             # uid -> {team, kind, kills, at}: everyone who knocked someone out
var _scripted := false            # a later() script is running: booms it sets off aren't yours (no 📒 stickers)
var _respawning := false
const DRAW_TXT := "💥  Nobody wins! It's a draw!"
## Booms from the Toy Box that go off by themselves (the 🎆 Boom Boom Boom sticker counts them).
const SELF_BOOMS := ["grenade", "dynamite", "cluster", "napalm", "acidbomb", "airstrike", "artillery", "nuke"]


func begin(opts: Dictionary) -> void:
	var seed_v: int = opts.get("seed", 0)
	if seed_v != 0:
		rng.seed = seed_v
	else:
		rng.randomize()
	if _live == 0:
		_old_tps = Engine.physics_ticks_per_second
		_old_interp = get_tree().physics_interpolation
	if not _counted:
		_counted = true
		_live += 1
	Engine.physics_ticks_per_second = 60
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
	modes = B3Modes.new()
	modes.battle = self
	add_child(modes)
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
		Settings.sticker_earned.connect(_on_sticker)
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
				ui._show_history("history")
			"settings":
				ui.show_settings()
			"ready":
				ui._show_history("ready")
			var o:
				B3Puzzles.open_arg(self, String(o))     # puzzles, puzzle:ID, puzzle:ID:win (🧩)


## Sets up one of the 📜 History battles (B3History).
func run_history(id: String) -> void:
	B3History.run(self, id)
	var hid := id.trim_suffix("!")
	history_id = hid if not B3History.info(hid).is_empty() else ""


## Sets up one of the 🎯 Ready-made battles (B3Scenarios.MENU), ready for
## ▶ Fight!. Only the host can (like History).
func run_ready(id: String) -> bool:
	if puppet:
		return false
	return B3Scenarios.setup(self, id)


## 📒 A sticker was just earned: show it.
func _on_sticker(id: String) -> void:
	if ui:
		ui.sticker_pop(id)


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
	if Settings.sticker_earned.is_connected(_on_sticker):
		Settings.sticker_earned.disconnect(_on_sticker)
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
	if _counted:
		_counted = false
		_live -= 1
		if _live == 0:
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
		if puzzle:
			puzzle.before_fight()      # 🧩 the blue army starts as the puzzle made it (and ⏮ Reset remembers it all)
		_spent_at_fight = spent
		if not units.is_empty():
			start_layout = B3Saves.snapshot(self)
		snd("battle_start", null, 1.0)
		winner = ""
		teams_seen = _team_keys().size()
		# a fresh 🏆 scoreboard
		fight_t0 = time
		fight_end_t = time
		fight_kos0 = kos
		fight_teams = team_counts()
		fighter_log = {}
		team_kos = {}
		mvp = {}
		if ready_id != "":
			B3Scenarios.on_fight(self, ready_id)
		if ui:
			ui.toast("⚔️  FIGHT!")
	if modes:
		modes.on_fighting(on)      # 🏁 crowns the Kings, puts out the hill, sends wave 1 (or back to the start)
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
	var hid := history_id
	var rid := ready_id
	var pz := puzzle
	puzzle = null          # (clearing the field to put it back doesn't end a 🧩 puzzle)
	B3Saves.restore(self, keep, false, true)
	puzzle = pz
	start_layout = keep
	if budget >= 0:
		spent = _spent_at_fight      # what you'd bought when you pressed Fight!
		budget_changed.emit()
	if puzzle:
		puzzle.reset_done()    # 🧩 Try again: your army's yours to change, the blue one's back
	history_id = hid       # still the same History or Ready-made battle
	ready_id = rid
	if was_paused:
		set_paused(false)
	if ui:
		ui.refresh()      # ⏮ stays on: it works again and again
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
	grid_add(u, true)
	if fighting and not _respawning and not puppet:
		fight_teams[team] = int(fight_teams.get(team, 0)) + 1     # joined the fight (for the scoreboard)
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
## `mine` false: not this computer's person's doing (a friend's, sent to the
## host), so no 📒 stickers here. Nor for booms a script sets off by itself
## (🎯 Nuke! and C4 Surprise at Fight!, see later()).
func drop(id: String, pos: Vector3, dir := Vector3.RIGHT, mine := true) -> void:
	var spent0 := spent
	if puzzle and not puzzle.pay_boom(id, pos):
		return      # 🧩 in a puzzle, booms cost points and go on your side only
	if modes and not modes.pay_boom(id, pos):
		return      # 🌊 Wave Defense: the same, in your fort
	var paid := spent - spent0      # (a mine, barrel or C4 keeps it: erasing it before the fight gives it back)
	if mine and not _scripted:
		if id == "nuke":
			Settings.award("nuke")
		if id in SELF_BOOMS:
			Settings.count("booms", "boom", 10)
	if _client_cmd({"c": "drop", "id": id, "pos": pos, "dir": dir}):
		return
	var d: Dictionary = B3Defs.BOOMS.get(id, {})
	match id:
		"grenade":
			var p := spawn_proj("dropgrenade", pos + Vector3(0, 3.0, 0), Vector3(rng.randf_range(-1, 1), -1.0, rng.randf_range(-1, 1)), null, d)
			p.fuse = 2.3
		"dynamite", "c4", "mine", "xbarrel":
			var bp := spawn_prop(id, pos, rng.randf() * TAU)
			if paid > 0:
				bp.set_meta("cost", paid)
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
			var v := B3Proj.lob(start, target, tt, "shell")      # lands on target under the Gravity rule
			spawn_proj("shell", start, v, null, B3Defs.BOOMS.artillery)
			snd("whistle", target, 0.6))


# --------------------------------------------------------------- explosions
## The big one: knocks, damages, launches, breaks and chains. `power` is the
## launch speed (m/s) at the centre; it fades to nothing at `r`.
## opts: "by" (who threw or fired it), "team" (theirs, in case they've been
## knocked out since), "up", "kind", "quiet", and "hit" / "skip" (dictionaries
## that get the fighters' uids (with the damage each took) / the bodies it
## hit, so a blast that follows can leave them alone).
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
	if not B3Rules.friendly_fire():
		var own := String(by.team) if by != null and by is B3Unit else String(opts.get("team", ""))
		if own != "wild":
			spare_team = own
	var hit: Dictionary = opts.get("hit", {})
	if modes and modes.keep_up:
		modes.keep_blast(pos, r, dmg, String(by.team) if by is B3Unit else String(opts.get("team", "")))     # 🌊 the attackers' booms hurt the 🚩 keep
	_blast_bodies(pos, r, power * r_knock, dmg, up, opts.get("skip", {}), 0.0, 0.0, spare_team, {}, by as B3Unit)
	for u: B3Unit in units.duplicate():
		if u.dead or not is_instance_valid(u) or hit.has(u.uid):
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
		hit[u.uid] = dmg * f
		u.hurt(dmg * f, dir, power * f * 1.15 + 1.5, by, "blast")      # (its hit marker for you, too)
	if bool(opts.get("quiet", false)):
		return
	fx.explosion(pos, r, 1 if kind == "acid" else 0)
	shake(clampf(r / 7.0, 0.15, 0.9), pos)
	if r >= 5.0:
		snd("mega_boom", pos, 1.0)
	else:
		snd("boom", pos, 0.9)


## Blasts the loose things: ragdolls, props, building pieces and trees.
## `spare`: a team whose fighters lying on the ground are left alone
## (Battle Rules: blasts don't hurt teammates). `units_hit`: uids of fighters
## already hurt by this blast, whose ragdolls are only pushed, not hurt again.
## `by`: whose blast it is (knocking out someone lying on the ground counts for them).
func _blast_bodies(pos: Vector3, r: float, power: float, dmg: float, up: float, skip: Dictionary, r_min := 0.0, fall_r := 0.0, spare := "", units_hit: Dictionary = {}, by: B3Unit = null) -> void:
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
					var mate: bool = spare != "" and is_instance_valid(rd.unit) and not rd.unit.dead and String(rd.unit.team) == spare
					if mate:
						continue      # a teammate who's been knocked down isn't hurt or thrown about either
					if rd.frozen and rd.sinking <= 0.0:
						rd.unfreeze()
					if rd.unit and is_instance_valid(rd.unit) and not hit_rd.has(rd.get_instance_id()) and not units_hit.has(rd.unit.uid):
						hit_rd[rd.get_instance_id()] = true
						rd.unit.hurt(dmg * f * 0.6, dir, 0.0, by, "blast")
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
			_settle_soon(s as B3Struct)


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
	# the fireball in the middle, then the shock wave rolling out. The fireball
	# reaches past the wave's start with bigger explosions, so the wave only
	# adds whatever damage the fireball didn't already do (never both in full).
	var fire_hits := {}
	var hit_bodies := {}
	explode(pos, 10.0, 42.0, 900.0, {"quiet": true, "up": 1.0, "hit": fire_hits, "skip": hit_bodies})
	_waves.append({"pos": pos, "r": 10.0, "max": 46.0, "speed": 32.0, "power": 36.0, "dmg": 520.0, "skip": hit_bodies, "units": {}, "fire": fire_hits})


func _wave_tick(w: Dictionary, dt: float) -> bool:
	var pos: Vector3 = w.pos
	var r0: float = w.r
	var r1 := r0 + float(w.speed) * dt
	var mx: float = w.max
	w.r = r1
	var power: float = w.power
	var dmg: float = w.dmg
	var waved: Dictionary = w.units       # fighters this wave has reached
	var fire: Dictionary = w.get("fire", {})     # uid -> damage the fireball already did
	for u: B3Unit in units.duplicate():
		if u.dead or waved.has(u.uid):
			continue
		var c := u.center()
		var dist := Vector2(c.x - pos.x, c.z - pos.z).length()
		if dist > r1:
			continue
		waved[u.uid] = true
		var f := clampf(1.0 - dist / mx, 0.0, 1.0)
		var d := dmg * f - float(fire.get(u.uid, 0.0))
		if fire.has(u.uid) and d <= 0.0:
			continue      # the fireball already hit it harder than the wave would
		var dir := (Vector3(c.x - pos.x, 0, c.z - pos.z).normalized() + Vector3.UP * 0.9).normalized()
		u.hurt(d, dir, power * f + 5.0, null, "blast")
	_blast_bodies(pos, r1, power, dmg, 0.9, w.skip, r0 - 1.0, mx, "", fire.merged(waved))
	return r1 < mx


# ----------------------------------------------------------- hits & breaks
func shot_hit(hit: Dictionary, w: Dictionary, dir: Vector3, shooter) -> void:
	var c = hit.collider
	var p: Vector3 = hit.position
	if c is B3Unit:
		(c as B3Unit).hurt(float(w.dmg), dir, float(w.get("knock", 1.0)), shooter, "shot")      # (hurt shows your hit marker, not a dodge)
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


## Someone hurt `victim`. If it was the fighter or vehicle you're playing
## and `victim` is an enemy, the first-person crosshair shows a hit marker.
func player_hit(by, victim) -> void:
	if ui == null or by == null or not is_instance_valid(by) or not (by is B3Unit) or by != B3Player.unit:
		return
	if (by as B3Unit).ctl != B3Player.me or not (victim is B3Unit) or not (by as B3Unit).is_enemy(victim as B3Unit):
		return
	ui.hit_marker()


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
		_settle_soon(s)
	_trim_chunks()


## Anything left floating after pieces of `s` break falls, at the next go of
## the `later` list. One blast can break a dozen pieces of one building: it
## only needs checking once for all of them (settle() looks at every pair of
## pieces), so while one check is waiting no more are added.
func _settle_soon(s: B3Struct) -> void:
	var id := s.get_instance_id()
	if _settling.has(id):
		return
	_settling[id] = true
	# (looked up by id when it fires: a lambda that captured the building
	# itself makes Godot print an error if the building is gone by then)
	later(0.0, func():
		_settling.erase(id)
		var st := instance_from_id(id) as B3Struct
		if st != null and is_instance_valid(st):
			st.settle())


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
	# knocking out a teammate (🤝 Blasts hurt teammates) or yourself scores
	# nothing (B3Unit._credit_ko counts the same way)
	if by != null and is_instance_valid(by) and by is B3Unit and by != u and (by as B3Unit).is_enemy(u):
		team_kos[by.team] = int(team_kos.get(by.team, 0)) + 1
		if by.kills > int(mvp.get("kills", 0)):
			mvp = {"kind": by.kind, "team": by.team, "kills": by.kills, "uid": by.uid}
		# kept here, as `by` may be knocked out itself before the end
		fighter_log[by.uid] = {"team": by.team, "kind": by.kind, "kills": by.kills, "at": time}
	_ko_stickers(u, by)
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
	if poof and puzzle and not u.dead and puzzle.keeps(u):
		return      # 🧩 erasing: the puzzle's own fighters stay (beat them!)
	_refund(u)
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
	if poof and is_instance_valid(p):
		# 🪙 erased (not blown up): a bought mine, barrel or C4 gives its points back,
		# and a stack of crates was bought as one, so it goes (and pays back) as one
		if p.has_meta("stack") and budget >= 0 and not fighting:
			var sid := int(p.get_meta("stack"))
			p.remove_meta("stack")
			for o: B3Prop in props.duplicate():
				if is_instance_valid(o) and int(o.get_meta("stack", -1)) == sid:
					o.remove_meta("stack")
					remove_prop(o, poof)
		_refund(p)
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
	if poof and puzzle and puzzle.keeps(s):
		return      # 🧩 erasing: the puzzle's own buildings stay
	_refund(s)
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
	if poof and puzzle and puzzle.keeps(h):
		return      # 🧩 erasing: the puzzle's own pools stay
	_refund(h)
	hazards.erase(h)
	if net and is_instance_valid(h):
		net.rec_event(["rm", h.get_instance_id()])
	if is_instance_valid(h):
		if poof:
			fx.steam(h.global_position, h.radius * 0.5)
			snd("fizz", h.global_position, 0.7)
		h.queue_free()


## 📒 Stickers for knocking things out yourself (the fighter or vehicle this
## computer is playing), and for wrecking a tank.
func _ko_stickers(u: B3Unit, by) -> void:
	var by_u: B3Unit = by if by != null and is_instance_valid(by) and by is B3Unit else null
	var mine := by_u != null and by_u == B3Player.unit and by_u.ctl == B3Player.me
	for k in ko_stickers_for(by_u, u, mine):
		give_ko_sticker(k)


## 📒 What knocking out `u` earns the person playing `by` (null: a boom, a
## pool or a fall did it). `mine`: that person is the one who'd get them
## (this computer's, or on the host a friend's, for B3Net to send on).
##  - "ace": ✈️ knocked out by the plane or helicopter you fly (3 for Ace Pilot);
##  - "hero": 🦸 by the person you play, on foot or on horseback (5 for Hero);
##  - "tankbuster": 🧨 a tank wrecked by you, or by a boom, a pool or a fall
##    (not by the computer's fighters).
## Knocking out a teammate earns nothing.
static func ko_stickers_for(by: B3Unit, u: B3Unit, mine: bool) -> PackedStringArray:
	var out := PackedStringArray()
	if u == null or not is_instance_valid(u):
		return out
	if mine and by != null and is_instance_valid(by) and by.is_enemy(u):
		if by is B3Aircraft:
			out.append("ace")
		elif not (by is B3Vehicle) and String(by.def.body) in ["human", "rider"]:
			out.append("hero")
	if u.kind == "tank" and (mine or by == null):
		out.append("tankbuster")
	return out


## Earns (or counts towards) a sticker from ko_stickers_for. A friend's copy
## calls it for the ones the host sends it.
static func give_ko_sticker(id: String) -> void:
	match id:
		"ace":
			Settings.count("b3_air_kos", "ace", 3)
		"hero":
			Settings.count("b3_hero_kos", "hero", 5)
		"tankbuster":
			Settings.award("tankbuster")


func c4_count() -> int:
	var n := 0
	for p in props:
		if p.kind == "c4" and not p.lit:
			n += 1
	return n


## 💥 Sets off every C4. `mine`: as for drop() (a script's or a friend's
## press earns no 📒 stickers on this computer).
func detonate_c4(mine := true) -> void:
	var n := c4_count()
	if n > 0 and mine and not _scripted:
		Settings.count("booms", "boom", 10, n)
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


# ------------------------------------------------------------ 🪙 budget battles
## Turns on budget battles: `points` to spend, placing only inside `zone`
## (x/z; Rect2() = anywhere) and only for `team` ("" = whatever the Toy Box says).
func set_budget(points: int, zone := Rect2(), team := "") -> void:
	budget = points
	spent = 0
	build_zone = zone
	build_team = team
	# the glowing area on the ground where you can build (gone with no zone)
	if zone_vis and is_instance_valid(zone_vis):
		zone_vis.queue_free()
	zone_vis = null
	if zone.size != Vector2.ZERO and world:
		zone_vis = B3Puzzles.zone_visual(self, zone, B3Puzzles.ZONE_COL)
		add_child(zone_vis)
	budget_changed.emit()


## Back to the normal sandbox: everything free, place anywhere.
func clear_budget() -> void:
	set_budget(-1)


func points_left() -> int:
	return budget - spent if budget >= 0 else 1 << 30


## "" if `count` of `id` can go at `pos`, or why not (for a message).
func can_place(id: String, pos: Vector3, count := 1) -> String:
	if build_zone.size != Vector2.ZERO and not build_zone.has_point(Vector2(pos.x, pos.z)):
		return "🚧 You can only build on your side (the glowing area)."
	# 🌊 Wave Defense: no walls or pools on the 🚩 Fort Keep (fighters may land on its roof)
	if modes and modes.keep_up and (B3Defs.STRUCTS.has(id) or B3Defs.HAZARDS.has(id)) \
			and Vector2(pos.x - modes.keep_pos.x, pos.z - modes.keep_pos.z).length() < B3Modes.KEEP_R + 2.0:
		return "🚩 That's where the keep stands! Build round it."
	if budget >= 0 and B3Defs.cost(id) * count > points_left():
		return "🪙 Not enough points for that! You have %d left." % points_left()
	return ""


## Pays for `node` (a fighter, building or pool just placed as `id`). The
## price paid stays on it (meta "cost", and in B3Saves snapshots, so ⏮ Reset
## keeps it), and erasing it gives back exactly that.
func buy(node: Node, id: String) -> void:
	if budget < 0 or node == null:
		return
	var c := B3Defs.cost(id)
	node.set_meta("cost", c)
	spent += c
	budget_changed.emit()


## Pays for a stack of crates (spawn_struct("crates") makes 6 props): one
## price for the lot, kept on the first, and they all share meta "stack" so
## erasing any of them before the fight takes (and pays back) the whole stack.
func buy_stack(stack: Array, id: String) -> void:
	if budget < 0 or stack.is_empty():
		return
	var sid: int = (stack[0] as Node).get_instance_id()
	for o in stack:
		(o as Node).set_meta("stack", sid)
	buy(stack[0] as Node, id)


## 🪙 What a pool of `kind` ("lava" or "acid") with radius `r` is sold as:
## up to 5 m it's a Lava (Acid) Pool, bigger is a Lava Lake (Acid Swamp).
## Pools are priced by their real size, however they were made.
static func pool_id(kind: String, r: float) -> String:
	if r > POOL_MAX_R:
		return "lava_lake" if kind == "lava" else "acid_swamp"
	return kind


const POOL_MAX_R := 5.0       # the biggest pool that's still a Pool (see pool_id)
const LAKE_R := 7.0           # 🪙 budget battles: the biggest pool you can buy (a Lake)
const ZONE_SLACK := 1.0       # a building or pool may poke this far out of the glowing area


## 🪙 Budget battles: how big a pool at `at` can be, at most `r`: no bigger
## than a Lake, and only just over the edge of your side.
func pool_room(at: Vector3, r: float) -> float:
	if budget < 0:
		return r
	r = minf(r, LAKE_R)
	if build_zone.size != Vector2.ZERO:
		var edge := minf(minf(at.x - build_zone.position.x, build_zone.end.x - at.x), minf(at.z - build_zone.position.y, build_zone.end.y - at.z))
		r = minf(r, maxf(1.5, edge + ZONE_SLACK))
	return r


## `p` moved onto your side (the glowing area), if there is one.
func zone_clamp(p: Vector3) -> Vector3:
	if build_zone.size == Vector2.ZERO:
		return p
	var x := clampf(p.x, build_zone.position.x, build_zone.end.x)
	var z := clampf(p.z, build_zone.position.y, build_zone.end.y)
	return Vector3(x, world.height_at(x, z), z)


## Buildings' footprints on the ground (x across, z deep, as spawn_struct
## builds them before turning them by their yaw). A wall is as long as its length.
const FOOT := {"block": Vector2(3, 3), "wall": Vector2(6, 0.6), "ramp": Vector2(2.6, 6), "tower": Vector2(4, 4),
	"bunker": Vector2(5.6, 5.6), "bridge": Vector2(3, 19), "sandbags": Vector2(5, 1.5), "crates": Vector2(3.2, 1.1)}


## 🚧 True if building `id` at `at`, turned by `yaw` (a wall `length` long),
## fits on your side (the glowing area, give or take ZONE_SLACK). Always
## true when there's no zone.
func fits_zone(id: String, at: Vector3, yaw: float, length := 0.0) -> bool:
	if build_zone.size == Vector2.ZERO:
		return true
	var f: Vector2 = FOOT.get(id, Vector2(3, 3))
	if id == "wall" and length > 0.5:
		f.x = clampf(length, 2.0, 24.0)
	var zone := build_zone.grow(ZONE_SLACK)
	var rot := Basis(Vector3.UP, yaw)
	for c in [Vector3(-f.x, 0, -f.y), Vector3(f.x, 0, -f.y), Vector3(f.x, 0, f.y), Vector3(-f.x, 0, f.y)]:
		var w: Vector3 = at + rot * ((c as Vector3) * 0.5)
		if not zone.has_point(Vector2(w.x, w.z)):
			return false
	return true


## 🛡️ True for things nobody may change: a 🧩 puzzle's own army, buildings
## and pools (B3Puzzles.keeps) and 🌊 Wave Defense's attackers (B3Modes.keeps).
## The Eraser, the Inspector's buttons, 🎮 Play as, ✋ Grab and 🚀 Launch
## leave them alone (see hands_off).
func protected(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if puzzle and puzzle.keeps(n):
		return true
	return modes != null and modes.has_method("keeps") and bool(modes.call("keeps", n))


## Why `what` ("erase", "team", "mood", "launch", "heal", "play" or "grab")
## can't be done to `n` right now (a message), or "" if it can. Protected
## things (see protected) can't be touched at all. In a 🧩 puzzle your own
## army plays fair too: it stays red, there's no free 💚 healing or 🚀
## launching, and ✋ you can only move it about your side before ▶ Fight!
## (B3Tools keeps it in the glowing area).
func hands_off(n: Node, what: String) -> String:
	if protected(n):
		var theirs := puzzle != null and puzzle.keeps(n)
		if what == "play":
			return "🎮 You can only play your own army in a puzzle." if theirs else "🎮 You can only play your own side."
		return "🧩 The puzzle's army stays just as it is. Beat it in battle!" if theirs else "🛡️ Hands off! Beat them in battle."
	if puzzle == null:
		return ""
	match what:
		"team":
			return "🧩 Your army stays red in a puzzle."
		"heal":
			return "💚 No free healing in a puzzle. Bring a medic!"
		"launch":
			return "🚀 No launching in a puzzle. Win it in battle!"
		"grab":
			if fighting:
				return "✋ No grabbing once the fight's on. Your army's on its own!"
	return ""


## Erasing something you bought before the fight gives its points back.
func _refund(node: Node) -> void:
	if budget < 0 or node == null or not is_instance_valid(node) or not node.has_meta("cost"):
		return
	if fighting and not (modes and modes.can_refund(node)):
		return      # (🌊 in a break between waves, what you bought since the last one still can)
	spent = maxi(0, spent - int(node.get_meta("cost")))
	node.remove_meta("cost")
	budget_changed.emit()


## After clearing: what's still standing is what's still paid for.
func _recount_spent() -> void:
	if budget < 0:
		return
	var n := 0
	for arr: Array in [units, structs, hazards, props]:
		for o in arr:
			if is_instance_valid(o) and (o as Node).has_meta("cost"):
				n += int((o as Node).get_meta("cost"))
	spent = n
	budget_changed.emit()


func clear_units() -> void:
	if tools:
		tools.stop_playing()      # quietly: your fighter is being cleared away, not knocked out
		if tools.get("undo"):
			tools.undo.clear()    # ↶ nothing to undo back to on a cleared field (B3Undo)
	start_layout = {}             # nothing left to ⏮ Reset to (Reset itself puts its copy back)
	history_id = ""               # not that battle any more (⏮ Reset puts these back too)
	ready_id = ""
	if puzzle:
		puzzle.stop()             # 🧩 the puzzle's over: everything's free again
	for u in units:
		if is_instance_valid(u):
			if u.laser:
				u.laser.queue_free()
			u.dead = true
			u.queue_free()
	units.clear()
	_grid_reset()
	_recount_spent()
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
	_recount_spent()
	_events.clear()
	_settling.clear()
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


# ------------------------------------------------ the fighters' map (speed)
## Standing fighters sorted into GRID-metre squares, so "who's near here?"
## only looks at a few squares instead of every fighter on the field. It's
## made once per physics step, the first time something asks: fighters only
## move in the physics engine's step after all the scripts, so it stays right
## all step long (ones placed or getting up during the step are added as they
## come). It's only a first sort: callers still check the real distances, and
## knocked-out or knocked-down fighters in it are skipped.
## With only a few fighters on the field, outside the physics step and on a
## friend's copy it isn't made: everyone is simply looked at, in `units` order.
const GRID := 6.0
const GRID_FAR := 2000.0           # further out than this (about to be removed): always looked at
var grid_min := 64                 # fewer fighters than this: not worth making (tests set 0)
var grid_r := 0.0                  # the biggest radius of a fighter in it
var _grid := {}                    # square (cell_x * 4096 + cell_z) -> Array[B3Unit]
var _grid_far: Array[B3Unit] = []
var _grid_step := -1               # the physics step it was made (or not made) for
var _grid_on := false              # it's made for this step
var _num_step := -1                # the physics step everyone was numbered for without it
var _grid_n := 0                   # the next order number (B3Unit.grid_i, the order of `units`)
var _grid_count := 0
var _grid_x0 := 0                  # the squares anyone is in
var _grid_x1 := -1
var _grid_z0 := 0
var _grid_z1 := -1
var _foes_step := -1               # the physics step _side_n was counted for (foes_standing)
var _side_n := {}                  # side ("red", or "wild:wolf" for wild ones) -> fighters standing on it
var _standing_n := 0


## True if the map is made and good for this physics step (making it if
## it's worth it: B3Unit._think looks at everyone in one go if not).
func grid_on() -> bool:
	if puppet or not Engine.is_in_physics_frame():
		return false
	var f := Engine.get_physics_frames()
	if _grid_step != f:
		_grid_step = f
		_grid_on = units.size() >= grid_min
		if _grid_on:
			_grid_build()
	return _grid_on


## Every fighter, numbered in order (B3Unit.grid_i), for when there's no map.
func everyone() -> Array[B3Unit]:
	if not grid_on():
		var f := Engine.get_physics_frames() if Engine.is_in_physics_frame() else -1
		if f < 0 or f != _num_step:
			_num_step = f
			_grid_number()
	return units


func _grid_build() -> void:
	_grid.clear()
	_grid_far.clear()
	# (_grid_put, written out here: this runs for every fighter every step)
	var i := 0
	var x0 := 1 << 30
	var x1 := -(1 << 30)
	var z0 := 1 << 30
	var z1 := -(1 << 30)
	var rmax := 0.0
	var n := 0
	for u in units:
		u.grid_i = i
		i += 1
		if u.down:
			continue
		var p := u.position
		if u.radius > rmax:
			rmax = u.radius
		n += 1
		if absf(p.x) > GRID_FAR or absf(p.z) > GRID_FAR:
			_grid_far.append(u)
			continue
		var cx := floori(p.x / GRID)
		var cz := floori(p.z / GRID)
		if cx < x0:
			x0 = cx
		if cx > x1:
			x1 = cx
		if cz < z0:
			z0 = cz
		if cz > z1:
			z1 = cz
		var k := cx * 4096 + cz
		var a = _grid.get(k)
		if a == null:
			var na: Array[B3Unit] = [u]
			_grid[k] = na
		else:
			(a as Array[B3Unit]).append(u)
	_grid_n = i
	_grid_count = n
	grid_r = rmax
	_grid_x0 = x0
	_grid_x1 = x1
	_grid_z0 = z0
	_grid_z1 = z1


## Everyone's been cleared away: forget the map (it would otherwise hold on
## to the old fighters, and their size, until the next one is made).
func _grid_reset() -> void:
	_grid.clear()
	_grid_far.clear()
	grid_r = 0.0
	_grid_step = -1
	_grid_on = false
	_num_step = -1
	_grid_n = 0
	_grid_count = 0
	_grid_x0 = 0
	_grid_x1 = -1
	_grid_z0 = 0
	_grid_z1 = -1
	_foes_step = -1
	_side_n.clear()
	_standing_n = 0


## Without the map: just numbers everyone in order (B3Unit.grid_i).
func _grid_number() -> void:
	for i in units.size():
		units[i].grid_i = i
	_grid_n = units.size()


func _grid_put(u: B3Unit) -> void:
	var p := u.position
	if u.radius > grid_r:
		grid_r = u.radius
	_grid_count += 1
	if absf(p.x) > GRID_FAR or absf(p.z) > GRID_FAR:
		_grid_far.append(u)
		return
	var cx := floori(p.x / GRID)
	var cz := floori(p.z / GRID)
	if cx < _grid_x0:
		_grid_x0 = cx
	if cx > _grid_x1:
		_grid_x1 = cx
	if cz < _grid_z0:
		_grid_z0 = cz
	if cz > _grid_z1:
		_grid_z1 = cz
	var k := cx * 4096 + cz
	var a = _grid.get(k)
	if a == null:
		var na: Array[B3Unit] = [u]
		_grid[k] = na
	else:
		(a as Array[B3Unit]).append(u)


## A fighter placed (or getting up) in the middle of a physics step goes on
## the map too, if it's already been made for this step.
func grid_add(u: B3Unit, new_unit: bool) -> void:
	if _grid_step != Engine.get_physics_frames() or not Engine.is_in_physics_frame() or puppet:
		return
	if new_unit:
		u.grid_i = _grid_n      # (or numbered with everyone, if that's still to come)
		_grid_n += 1
	if _grid_on:
		_grid_put(u)
	_foes_step = -1


## False only if nobody standing could be `u`'s enemy (B3Unit.is_enemy) this
## physics step: then there's no point searching the whole field for one (a
## battle that's been won, or one side alone on the field).
func foes_standing(u: B3Unit) -> bool:
	if not grid_on():
		return true
	if _foes_step != _grid_step:
		_foes_step = _grid_step
		_side_n.clear()
		_standing_n = 0
		for o in units:
			if not o.down:
				var side: String = o.team if o.team != "wild" else "wild:" + o.kind
				_side_n[side] = int(_side_n.get(side, 0)) + 1
				_standing_n += 1
	var mine: String = u.team if u.team != "wild" else "wild:" + u.kind
	return _standing_n > int(_side_n.get(mine, 0))


## Someone changed sides in the middle of a step: count again.
func foes_changed() -> void:
	_foes_step = -1


## Every fighter that could be within `r` metres of `p` (across the ground:
## x and z), in no particular order. Check the real distance, and skip the
## knocked-down (`down`) and knocked-out (`dead`) ones. `r` grows by
## `biggest` times the biggest fighter's radius (1.0 for "touching": my
## reach plus their radius). It may be `units` itself: don't add or remove
## fighters while going through it (collect who to hit first).
func units_near(p: Vector3, r: float, biggest := 0.0) -> Array[B3Unit]:
	if not grid_on():
		return everyone()
	r += biggest * grid_r
	var out: Array[B3Unit] = []
	var x0 := maxi(floori((p.x - r) / GRID), _grid_x0)
	var x1 := mini(floori((p.x + r) / GRID), _grid_x1)
	var z0 := maxi(floori((p.z - r) / GRID), _grid_z0)
	var z1 := mini(floori((p.z + r) / GRID), _grid_z1)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var a = _grid.get(cx * 4096 + cz)
			if a != null:
				out.append_array(a)
	if not _grid_far.is_empty():
		out.append_array(_grid_far)
	return out


## For searching outwards from `p` square by square (see B3Unit._think):
## the fighters in the squares `ring` steps out (0: the square `p` is in).
## Everyone in ring r is at least (r - 1) * GRID metres away. Past
## grid_rings(p) there's nobody. Searching out that far would mean looking at
## more squares than there are fighters, so past grid_ring_cap() it's better
## to just look at everyone (`units`).
func grid_ring(p: Vector3, ring: int) -> Array[B3Unit]:
	var out: Array[B3Unit] = []
	var cx := floori(p.x / GRID)
	var cz := floori(p.z / GRID)
	if ring == 0:
		var a = _grid.get(cx * 4096 + cz)
		if a != null:
			out.append_array(a)
		if not _grid_far.is_empty():
			out.append_array(_grid_far)
		return out
	# the top and bottom rows, then the two sides between them
	for zz in [cz - ring, cz + ring]:
		var z: int = zz
		if z < _grid_z0 or z > _grid_z1:
			continue
		for x in range(maxi(cx - ring, _grid_x0), mini(cx + ring, _grid_x1) + 1):
			var a = _grid.get(x * 4096 + z)
			if a != null:
				out.append_array(a)
	for xx in [cx - ring, cx + ring]:
		var x: int = xx
		if x < _grid_x0 or x > _grid_x1:
			continue
		for z in range(maxi(cz - ring + 1, _grid_z0), mini(cz + ring - 1, _grid_z1) + 1):
			var a = _grid.get(x * 4096 + z)
			if a != null:
				out.append_array(a)
	return out


## How many rings out from `p` anyone could be (-1: nobody, or no map now).
func grid_rings(p: Vector3) -> int:
	if not grid_on():
		return -1
	if _grid_count == 0:
		return -1
	if _grid_x1 < _grid_x0:
		return 0      # (only far-off ones, in ring 0)
	var cx := floori(p.x / GRID)
	var cz := floori(p.z / GRID)
	return maxi(maxi(cx - _grid_x0, _grid_x1 - cx), maxi(cz - _grid_z0, _grid_z1 - cz))


func grid_ring_cap() -> int:
	return int(sqrt(float(_grid_count)) * 0.5) + 1


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
	if modes:
		keys = modes.standing(keys)     # 🏁 a fallen King, the hill's winner, or 🌊 the fort still holding (B3Modes)
	team_count = keys.size()
	if not fighting:
		return
	if winner != "":
		if team_count == 0 and winner != "nobody":
			winner = "nobody"
			_battle_over(DRAW_TXT, Color("ffcf4a"))
			return
		if team_count >= 2:
			winner = ""
			for u in units:
				u.cheer = false
			if ui:
				ui.hide_banner()
		elif ui:
			ui.update_score(scoreboard())     # the winners still standing (some may still be on fire...)
		return
	teams_seen = maxi(teams_seen, team_count)
	if teams_seen < 2 or team_count > 1:
		return
	fight_end_t = time
	if team_count == 0:
		winner = "nobody"
		_battle_over(DRAW_TXT, Color("ffcf4a"))
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
	if modes:
		txt = modes.win_text(k, txt)
	for u in units:
		u.cheer = (u.team if u.team != "wild" else "wild:" + u.kind) == k      # (only the winners cheer)
	if modes and modes.is_defeat(k):
		# 🌊 the keep fell: you lost. A gentle "aww", no confetti or fireworks.
		_battle_over(txt, Color("aebbd6"))
		snd("defeat", null, 0.9)
		return
	_battle_over(txt, col)
	if ui:
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


## The battle just ended (`winner` is set): the banner with the 🏆
## scoreboard under it, and the stickers it earned.
func _battle_over(txt: String, col: Color) -> void:
	battle_ended.emit(winner)
	var sb := scoreboard()
	victory_stickers(read_score(sb))
	if ui:
		ui.banner(txt, col, sb)


## The 🏆 scoreboard of the battle that just ended, as short lines of text.
## They ride along under the winner banner's headline to friends' screens
## (B3UI.banner), so it's plain and small:
##   "w|winner"                    a team, "wild:kind" or "nobody"
##   "s|seconds"                   how long the fight took (battle time)
##   "h|id"                        the 📜 History battle, if it was one
##   "t|team|brought|left|kos"     each team: fighters it brought, how many
##                                 are still standing, knock-outs it scored
##   "o|kos"                       knock-outs by booms, lava, falls (nobody's)
##   "f|team|kind|kos"             the top 3 fighters (even knocked-out ones)
func scoreboard() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("w|" + winner)
	out.append("s|%d" % roundi(maxf(0.0, (fight_end_t if winner != "" else time) - fight_t0)))
	if history_id != "":
		out.append("h|" + history_id)
	var left := team_counts()
	var by_teams := 0
	for t in B3Defs.TEAM_ORDER:
		if fight_teams.has(t) or left.has(t) or team_kos.has(t):
			out.append("t|%s|%d|%d|%d" % [t, int(fight_teams.get(t, 0)), int(left.get(t, 0)), int(team_kos.get(t, 0))])
			by_teams += int(team_kos.get(t, 0))
	var others := kos - fight_kos0 - by_teams
	if others > 0:
		out.append("o|%d" % others)
	var best: Array = fighter_log.values()
	# most knock-outs first; a tie goes to whoever got there first
	best.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return int(x.kills) > int(y.kills) or (int(x.kills) == int(y.kills) and float(x.at) < float(y.at)))
	for i in mini(3, best.size()):
		var e: Dictionary = best[i]
		if int(e.kills) > 0:
			out.append("f|%s|%s|%d" % [e.team, e.kind, int(e.kills)])
	return out


## Reads scoreboard() lines back into {win, secs, hist, teams: [{team,
## brought, left, kos}], others, top: [{team, kind, kos}]}, or {} if there's
## no scoreboard. On a friend's copy they come from the host, so anything odd
## (unknown teams or fighters, silly numbers, too many lines) is left out.
static func read_score(lines: PackedStringArray) -> Dictionary:
	var win := ""
	var secs := -1
	var hist := ""
	var others := 0
	var teams: Array[Dictionary] = []
	var top: Array[Dictionary] = []
	var seen := {}
	for ln: String in lines.slice(0, 24):
		var f := ln.split("|")
		match f[0]:
			"w":
				if f.size() == 2 and (f[1] == "nobody" or B3Defs.TEAM.has(f[1]) or (f[1].begins_with("wild:") and B3Defs.UNITS.has(f[1].substr(5)))):
					win = f[1]
			"s":
				if f.size() == 2 and f[1].is_valid_int():
					secs = clampi(f[1].to_int(), 0, 359999)
			"h":
				if f.size() == 2 and not B3History.info(f[1]).is_empty():
					hist = f[1]
			"o":
				if f.size() == 2 and f[1].is_valid_int():
					others = clampi(f[1].to_int(), 0, 99999)
			"t":
				if f.size() == 5 and B3Defs.TEAM.has(f[1]) and not seen.has(f[1]) and f[2].is_valid_int() and f[3].is_valid_int() and f[4].is_valid_int():
					seen[f[1]] = true
					teams.append({"team": f[1], "brought": clampi(f[2].to_int(), 0, 9999),
						"left": clampi(f[3].to_int(), 0, 9999), "kos": clampi(f[4].to_int(), 0, 9999)})
			"f":
				if f.size() == 4 and top.size() < 3 and B3Defs.TEAM.has(f[1]) and B3Defs.UNITS.has(f[2]) and f[3].is_valid_int():
					top.append({"team": f[1], "kind": f[2], "kos": clampi(f[3].to_int(), 0, 9999)})
	if win == "":
		return {}
	return {"win": win, "secs": secs, "hist": hist, "teams": teams, "others": others, "top": top}


## "45 seconds", "1 minute 5 seconds".
static func time_text(secs: int) -> String:
	var m := floori(secs / 60.0)
	var sec := secs - m * 60
	var st := "%d second%s" % [sec, "" if sec == 1 else "s"]
	if m == 0:
		return st
	return "%d minute%s%s" % [m, "" if m == 1 else "s", "" if sec == 0 else " " + st]


## 📒 Stickers for a battle that just ended, from its scoreboard. A friend's
## copy calls this too when the host's banner (with the scoreboard) arrives,
## so friends earn them as well.
func victory_stickers(sc: Dictionary) -> void:
	if sc.is_empty():
		return
	var hist := String(sc.hist)
	if hist != "":
		Settings.mark("b3_history", hist, "historybuff", 3)
		B3History.earn_stars(self, hist, String(sc.win))     # ⭐ finish, ⭐ change history, ⭐ hero
	var win := String(sc.win)
	if win == "nobody" or (modes and modes.is_defeat(win)):
		return      # (🌊 the keep fell: no 🏆 Victory or 🎖️ General for losing)
	Settings.award("b3win")
	# 🎖️ General: 5 or more on each team
	var teams: Array = sc.teams
	var big := teams.size() >= 2
	for e: Dictionary in teams:
		if int(e.brought) < 5:
			big = false
	if big:
		Settings.award("general")
	# 👀 First-Person Hero: your side won while you were looking out of its eyes
	if B3Player.active() and B3Player.me.fp and B3Player.unit.ctl == B3Player.me:
		var me := B3Player.unit
		if (me.team if me.team != "wild" else "wild:" + me.kind) == win:
			Settings.award("fphero")


# ---------------------------------------------------------------- feedback
func snd(n: String, at = null, vol := 1.0, pitch := 1.0) -> void:
	if net:
		net.rec_fx(["snd", n, at, vol, pitch])
	var name_s := n
	if not Sfx.has(name_s) and SND_FALLBACK.has(name_s):
		name_s = String(SND_FALLBACK[name_s])
	var v := vol
	var pan := 0.0
	if at is Vector3:
		var h := hear(at as Vector3)
		v *= h.x
		pan = h.y
	Sfx.play(name_s, null, v, pitch, pan)


## How loud (x, 0..1) and how far left or right (y) a sound at `p` is for
## whoever's watching (Sfx.hear3d), by its real 3D distance (height counts).
## First person: heard from your eyes, panned by the way it comes from.
## Overhead: heard from the ground in the middle of the view, panned by
## where it is across the screen.
func hear(p: Vector3) -> Vector2:
	if cam == null or cam.cam == null or not is_inside_tree():
		return Vector2(1.0, 0.0)
	if cam.first_person():
		return Sfx.hear3d(p, cam.cam.global_position, cam.cam.global_transform.basis, true)
	var ear := cam.focus
	if world:
		ear.y = world.height_at(ear.x, ear.z)
	var vp := get_viewport().get_visible_rect().size
	var half_w := cam.size * 0.5 * vp.x / maxf(vp.y, 1.0)
	return Sfx.hear3d(p, ear, cam.basis_now(), false, cam.size, half_w)


## The music for this battle (Sfx.mood_now): "battle" while the fighting's
## on (🌊 Wave Defense: while a wave is coming), otherwise "build" (setting
## up, between waves, and once it's won or lost).
func music_mood() -> String:
	if modes and modes.kind == "waves":
		return "battle" if modes.phase == "wave" else "build"
	return "battle" if fighting and winner == "" else "build"


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
				_scripted = true      # (whatever it sets off isn't yours: drop, detonate_c4)
				fn.call()
				_scripted = false
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
			_respawning = true
			var nu := spawn_unit(String(r.kind), String(r.team), p, String(r.pers))
			_respawning = false
			if nu:
				fx.poof(p + Vector3(0, 0.8, 0), 1.0)
				snd("pop", p, 0.6)
		else:
			i += 1


## How far before the target an airstrike plane lets go of a bomb: the bomb
## keeps 5 m/s of the plane's speed while it falls `h` metres (starting at
## 2 m/s down) under the Gravity rule, so it still lands on target in Moon gravity.
static func _bomb_lead(h: float) -> float:
	var g := B3Proj.gravity("bomb")
	var t := maxf(h, 0.0) / 2.0 if g < 0.01 else (-2.0 + sqrt(4.0 + 2.0 * g * maxf(h, 0.0))) / g
	return 5.0 * t


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
			if rel < -_bomb_lead(node.global_position.y - 0.8 - target.y):
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

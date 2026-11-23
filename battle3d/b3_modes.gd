class_name B3Modes
extends Node
## 🏁 Battle goals (⚙️ Battle Rules) and 🌊 Wave Defense (🎯 Ready-made).
##
##   ⚔️ Last team standing  the usual: nothing to do here.
##   👑 Defend the King     at Fight! each team gets a King: a Big fighter of
##                          its most common kind, with a gold crown and lots of
##                          health, behind its army, with a few guards. A team
##                          whose King falls is out, even with others standing:
##                          its army panics and runs off home (🏳️).
##   🚩 King of the Hill    a glowing circle in the middle of the fighting (on
##                          a hill if there's one close by). A team scores while
##                          it's the only one in it; the first to 100 wins (or
##                          the last team standing, as usual).
##   🌊 Wave Defense        Red (you, and friends) holds a fort. Before each
##                          wave you spend 🪙 points (B3Battle's budget) on
##                          defenders and defences in the fort; then Blue's
##                          attackers march in from the far side, stronger each
##                          time, with a boss every 5th wave. Knock-outs and
##                          holding the fort give more points. Attackers with
##                          nobody to fight go for the 🚩 Fort Keep at the back
##                          of the fort; you lose when it falls (so you can fly
##                          or ride out of the fort and still hold it).
##
## The host runs all of this; B3Battle._check_victory asks standing() which
## teams are still in, and win_text() for the banner. Friends (👥) get the
## state for their HUD and the hill in each snapshot (net_state / apply_net).
## B3ModeHud shows it.

const KING_SIZE := 1.6         # a King is Big (like the Toy Box size)...
const KING_HP := 4.0           # ...with this many times its kind's usual health...
const KING_MAX_HP := 2400.0    # ...but no more than this (or 1.5 times its usual, for the biggest)
const GUARDS := 3              # teammates who stay by the King (at most half its army)
const STALL_T := 12.0          # 👑 nobody hurt for this long: the guards and Kings charge
const ROUT_T := 4.5            # 🏳️ a team whose King fell runs about this long, then it's gone
const HILL_R := 5.0            # the capture circle's size (metres)
const HILL_WIN := 100.0        # points to win the hill
const HILL_RATE := 3.0         # points a second while one team holds it alone
const HILL_LOOK := 16.0        # how far from the middle of the fighting it looks for a hill
const FORT := Rect2(-14, 2, 28, 24)   # 🌊 the fort (x/z): your building area
const KEEP_AT := Vector2(0.0, 22.5)   # 🚩 the Fort Keep (x/z), at the back of the fort
const KEEP_R := 2.2            # its size (metres)
const KEEP_HP := 2500.0        # its health
const KEEP_FIX := 0.25         # after each wave the keep mends this much of its health...
const HEAL_BREAK := 0.3        # ...and your fighters still standing get this much of theirs back
const SIEGE_NEAR := 10.0       # an attacker with a defender closer than this fights it, not the keep
const SPAWN_Z := -50.0         # where attackers come from (the far side)
const START_POINTS := 25       # 🪙 to spend before wave 1
const BREAK := 20.0            # seconds between waves
const BOSS_SIZE := 2.2
const BOSS_HP := 2.5           # times the boss kind's normal health
const BEST_PATH := "user://b3_waves.cfg"
const HILL_ALPHA := [0.75, 1.0, 0.55]   # the hill's disc, rim and column of light

## 🌊 The waves: what comes, getting stronger. After 15 the last five come
## round again with more of everything; a boss every 5th wave.
const WAVES := [
	{"name": "Stick figures", "units": [["stick", 6]]},
	{"name": "Stick figures and soldiers", "units": [["stick", 6], ["soldier", 3]]},
	{"name": "Soldiers and archers", "units": [["soldier", 6], ["archer", 3], ["grenadier", 1]]},
	{"name": "Vikings!", "units": [["viking", 7], ["soldier", 4], ["archer", 3]]},
	{"name": "A HUGE giant", "boss": "giant", "units": [["viking", 5], ["knight", 4]]},
	{"name": "Knights and vikings", "units": [["knight", 7], ["viking", 6], ["archer", 4]]},
	{"name": "Cavalry and raptors", "units": [["cavalry", 5], ["raptor", 5], ["knight", 4]]},
	{"name": "Raptors and cavalry", "units": [["raptor", 8], ["cavalry", 5], ["rocketeer", 3]]},
	{"name": "Dinosaurs!", "units": [["trike", 2], ["stego", 1], ["raptor", 6], ["soldier", 6]]},
	{"name": "A HUGE T-Rex", "boss": "trex", "units": [["raptor", 6], ["trike", 2]]},
	{"name": "Tanks", "units": [["tank", 1], ["soldier", 10], ["rocketeer", 3]]},
	{"name": "Tanks and jeeps", "units": [["tank", 2], ["jeep", 2], ["soldier", 8], ["gunner", 2]]},
	{"name": "An air raid", "units": [["heli", 2], ["tank", 2], ["soldier", 8], ["rocketeer", 4]]},
	{"name": "A big air raid", "units": [["plane", 2], ["heli", 2], ["tank", 2], ["soldier", 10]]},
	{"name": "A HUGE dragon", "boss": "dragon", "units": [["tank", 3], ["plane", 2], ["heli", 2], ["soldier", 8]]},
]
const BOSSES := ["giant", "trex", "dragon", "mammoth", "gorilla"]

static var best := -1          # 🌊 the best wave held so far (saved in BEST_PATH)
static var best_file := BEST_PATH    # (tests point this somewhere else)

var battle = null
var kind := ""                 # "" (last team standing), "king", "hill" or "waves"
# 👑 Defend the King
var kings := {}                # team -> its King (host)
var fallen: Array[String] = [] # teams whose King fell (host)
var king_view: Array = []      # [[team, health 0..1, still up]] for the HUD (host and friends)
# 🚩 King of the Hill
var hill_on := false           # the circle is out (fighters head for it)
var hill_pos := Vector3.ZERO
var hill_r := HILL_R
var holder := ""               # "" nobody in it, "+" more than one team, or the one team in it
var scores := {}               # team -> 0..100
var hill_won := ""
var hill_node: Node3D = null
# 🌊 Wave Defense
var wave := 0                  # the wave that's on (or the last one)
var phase := ""                # "build" (before wave 1), "wave", "break" or "lost"
var break_t := 0.0             # seconds until the next wave
var left := 0                  # attackers still standing
var start_wave := 1
var wave_kos := 0              # attackers knocked out this wave
var wave_units: Array = []     # this wave's attackers still standing (host)
var wave_t := 0.0
var budget_at_fight := -1
var _bounty := {}              # attacker's instance id -> 🪙 points for knocking it out
var _host_best := -1           # a friend's copy: the host's best wave
# 🚩 the Fort Keep (host; friends get its place and health in the snapshot)
var keep_node: Node3D = null
var keep_pos := Vector3.ZERO
var keep_hp := 0.0
var keep_max := KEEP_HP
var keep_up := false           # standing (false once it falls, or with no keep at all)
var siege := false             # attackers head for the keep (B3Unit._hill_pull)
var _keep_bar: MeshInstance3D = null
var _keep_tower: Node3D = null
var _keep_flag: Node3D = null
var _keep_fall := -1.0         # how far it has crumbled (0..1; -1 standing)
var _keep_t := 0.0
var _keep_hit_t := 0.0
var _siege_dps := {}           # attacker's instance id -> how hard it hits the keep (a second)
# 👑 a stalled battle and teams running off
var _calm_t := 0.0
var _hp_sum := -1.0
var _charged := false
var _routing: Array = []       # [fighter, when it's gone]

var _tick_t := 0.0
var _toast_t := 0.0
var _said := {}                # toasts already shown this battle
var _hill_mats: Array[StandardMaterial3D] = []
var _hill_tint := Color.WHITE
var _pulse := 0.0
var _owns_budget := false


func _ready() -> void:
	load_best()


# ------------------------------------------------------------------ which
## What's on, by the host's rules: 🌊 Wave Defense while that battle is set
## up, otherwise the ⚙️ battle goal (but not in a 🧩 puzzle).
func current() -> String:
	if battle == null:
		return ""
	if String(battle.ready_id) == "waves":
		return "waves"
	if battle.get("puzzle") != null:
		return ""       # a 🧩 puzzle is won by knocking out the blue army, as it says
	var g := B3Rules.goal()
	return g if g == "king" or g == "hill" else ""


func active() -> bool:
	return kind != ""


## True for what you can't erase, grab, change or play as (B3Battle.protected):
## 🌊 Wave Defense's attackers. Beat them!
func keeps(n: Node) -> bool:
	if kind != "waves" or n == null or not is_instance_valid(n) or not (n is B3Unit):
		return false
	return n.has_meta("wave") and (n as B3Unit).team == "blue"


## True if the battle that just ended with `k` winning is a defeat for you:
## 🌊 the keep fell (B3Battle._check_victory: no confetti, no 🏆 stickers).
func is_defeat(k: String) -> bool:
	return kind == "waves" and k != "red"


## The fight just started (on) or stopped (⏮ Reset, loading, leaving).
func on_fighting(on: bool) -> void:
	if battle == null or battle.puppet:
		return
	_switch(current())
	_said = {}
	if on:
		match kind:
			"king":
				_crown_all()
			"hill":
				scores = {}
				hill_won = ""
				holder = ""
				_place_hill()
			"waves":
				budget_at_fight = int(battle.budget)
				if not keep_up:
					_new_keep()
				_start_wave(start_wave)
		return
	_clear_goal()
	if kind == "waves":
		phase = "build"
		wave = start_wave - 1
		wave_units.clear()
		_bounty = {}
		_siege_dps = {}
		siege = false
		left = 0
		_new_keep()          # (⏮ the keep's back up, good as new)
		if budget_at_fight >= 0 and int(battle.budget) >= 0:
			battle.budget = budget_at_fight      # what you had when you pressed Fight!
			battle.budget_changed.emit()
	elif kind == "hill":
		hill_on = false     # (the circle shows where it'll be, but nobody walks to it yet)


func _clear_goal() -> void:
	kings = {}
	fallen.clear()
	king_view = []
	scores = {}
	hill_won = ""
	holder = ""
	_calm_t = 0.0
	_hp_sum = -1.0
	_charged = false
	_routing.clear()


func _switch(k: String) -> void:
	if k == kind:
		return
	var was := kind
	kind = k
	_clear_goal()
	if was == "hill":
		_remove_hill()
	if was == "waves":
		phase = ""
		wave = 0
		wave_units.clear()
		_bounty = {}
		_siege_dps = {}
		siege = false
		_remove_keep()
		left = 0
		if _owns_budget and int(battle.budget) >= 0 and battle.build_zone == FORT and battle.get("puzzle") == null:
			battle.clear_budget()      # (unless something else, like a 🧩 puzzle, has its own points now)
		_owns_budget = false
	if k == "hill" and battle.fighting:
		_place_hill()


# ------------------------------------------------------------------- tick
func _physics_process(dt: float) -> void:
	if battle == null or dt <= 0.0 or battle.puppet:
		return
	_switch(current())
	_toast_t -= dt
	match kind:
		"king":
			_king_tick(dt)
		"hill":
			_hill_tick(dt)
		"waves":
			_waves_tick(dt)


func _process(dt: float) -> void:
	if keep_node != null:
		_keep_anim(dt)
	if hill_node == null or not is_instance_valid(hill_node):
		return
	_pulse += dt
	var col := _hill_tint
	var k := 0.85 + 0.15 * sin(_pulse * 3.2)
	if holder == "+":
		k = 0.7 + 0.3 * sin(_pulse * 9.0)      # flickers while two teams fight over it
	for i in _hill_mats.size():
		var m := _hill_mats[i]
		var a: float = HILL_ALPHA[mini(i, HILL_ALPHA.size() - 1)]
		m.albedo_color = Color(col.r, col.g, col.b, a * k)


## Which teams are still in, for B3Battle._check_victory: the usual "teams
## with fighters left" (`keys`), minus teams whose King fell, just the hill's
## winner once there is one, or (🌊) Red and Blue until the keep falls.
func standing(keys: Dictionary) -> Dictionary:
	match kind:
		"king":
			var out := keys.duplicate()
			for t in fallen:
				out.erase(t)
			return out
		"hill":
			if hill_won != "":
				return {hill_won: true}
		"waves":
			if phase == "lost":
				return {"blue": true}
			if battle.fighting and phase != "":
				return {"red": true, "blue": true}      # the fort holds: on to the next wave
	return keys


## The winner banner's headline for `k` (B3Battle._check_victory).
func win_text(k: String, txt: String) -> String:
	if k.begins_with("wild:") or not B3Defs.TEAM.has(k):
		return txt
	var nm := String(B3Defs.TEAM[k].name)
	match kind:
		"king":
			return "👑  %s wins!  🏆" % nm
		"hill":
			if hill_won == k:
				return "🚩  %s holds the hill!  🏆" % nm
		"waves":
			if phase == "lost":
				return "🚩  The keep fell on wave %d!" % wave
	return txt


func _toast(txt: String, key := "") -> void:
	if key != "":
		if _said.has(key):
			return
		_said[key] = true
	if battle.ui:
		battle.ui.toast(txt)


static func team_key(u: B3Unit) -> String:
	return u.team if u.team != "wild" else "wild:" + u.kind


static func team_name(k: String) -> String:
	if k.begins_with("wild:"):
		return "The " + String(B3Defs.unit_def(k.substr(5)).name)
	return String(B3Defs.TEAM.get(k, B3Defs.TEAM.wild).name)


# ------------------------------------------------------------- 👑 the King
func _king_tick(dt: float) -> void:
	_tick_t -= dt
	if _tick_t > 0.0:
		return
	_tick_t = 0.3
	if battle.fighting and battle.winner == "":
		# a team that joins later gets a King too
		var teams := _teams()
		for t in teams:
			if not kings.has(t) and not fallen.has(t):
				_crown(String(t), teams[t])
		for t in kings.keys():
			var k = kings[t]
			if k == null or not is_instance_valid(k) or (k as B3Unit).dead or (k as B3Unit).team != String(t):
				_king_fell(String(t), k)
		for t in fallen:
			_rout(t)       # (fighters put down later for a team that's out run off too)
		_king_calm(0.3)
	_routed_gone()
	_update_king_view()


## Fighters on each team ("wild" ones have no King): team -> [B3Unit].
func _teams() -> Dictionary:
	var out := {}
	for u: B3Unit in battle.units:
		if not is_instance_valid(u) or u.dead or u.team == "wild" or u.king or u.routed:
			continue
		if not out.has(u.team):
			out[u.team] = []
		(out[u.team] as Array).append(u)
	return out


func _crown_all() -> void:
	kings = {}
	fallen.clear()
	var teams := _teams()
	for t in teams:
		_crown(String(t), teams[t])
	_update_king_view()
	if not kings.is_empty():
		_toast("👑 All hail the Kings! Keep yours safe: if your King falls, your team is out!", "kings")


## Picks the team's King: a Big one of its most common fighter (not a vehicle
## or a flyer; a knight if it has none), behind its army, with guards.
func _crown(t: String, members: Array) -> void:
	var count := {}
	var c := Vector3.ZERO
	for u: B3Unit in members:
		c += u.position
		if not (u is B3Vehicle) and not u.flying:
			count[u.kind] = int(count.get(u.kind, 0)) + 1
	c /= maxf(1.0, members.size())
	var kind_s := "knight"
	var most := 0
	for k in count:
		if int(count[k]) > most:
			most = int(count[k])
			kind_s = String(k)
	# behind the army: away from everyone else
	var e := Vector3.ZERO
	var en := 0
	for u: B3Unit in battle.units:
		if is_instance_valid(u) and not u.dead and u.team != t:
			e += u.position
			en += 1
	var back := Vector3.ZERO
	if en > 0:
		e /= en
		back = Vector3(c.x - e.x, 0, c.z - e.z).normalized()
	var deep := 0.0
	for u: B3Unit in members:
		deep = maxf(deep, (u.position - c).dot(back))
	var spot := _free_spot(c + back * clampf(deep * 0.6, 2.0, 8.0))
	var yaw := atan2(-back.x, -back.z) if back != Vector3.ZERO else INF
	var king: B3Unit = battle.spawn_unit(kind_s, t, spot, "defend", yaw, KING_SIZE)
	if king == null:
		return
	king.make_king(king_hp(kind_s) / maxf(1.0, king.max_hp))
	kings[t] = king
	battle.fx.poof(spot + Vector3(0, 1.5, 0), 2.0)
	battle.fx.word(spot + Vector3(0, king.tall + 1.4, 0), "KING!", Color("ffd84a"))
	battle.snd("magic", spot, 0.7)
	# a few teammates stand guard round the King (never more than half the
	# army, so a small one still goes on the attack)
	var near: Array = members.filter(func(u: B3Unit) -> bool:
		return is_instance_valid(u) and not u.dead and not (u is B3Vehicle) and not u.flying and not u.player \
			and u.position.distance_to(spot) < 30.0)
	near.sort_custom(func(a: B3Unit, b: B3Unit) -> bool: return a.position.distance_to(spot) < b.position.distance_to(spot))
	for i in mini(mini(GUARDS, floori(members.size() / 2.0)), near.size()):
		var g: B3Unit = near[i]
		var a := king.facing + (i - 1) * 0.9
		g.set_meta("guard", g.pers_choice)
		g.set_personality("defend")
		var gp := spot + Vector3(sin(a), 0, cos(a)) * (2.4 + king.radius)
		g.home = Vector3(gp.x, battle.world.height_at(gp.x, gp.z), gp.z)


func _king_fell(t: String, k) -> void:
	kings.erase(t)
	if not fallen.has(t):
		fallen.append(t)
	var at := Vector3.ZERO
	if k != null and is_instance_valid(k):
		at = (k as B3Unit).center()
		battle.fx.word(at + Vector3(0, 2.0, 0), "KING DOWN!", Color("ffd84a"))
	battle.snd("whistle", null, 0.8)
	_toast("👑 Oh no! %s's King is down! %s is out!" % [team_name(t), team_name(t)])
	_rout(t)


## 👑 How much health a King of `k` gets: KING_HP times its kind's usual,
## but no more than KING_MAX_HP (or 1.5 times its usual, for the biggest).
static func king_hp(k: String) -> float:
	var base := float(B3Defs.unit_def(k).hp)
	return minf(base * KING_HP, maxf(base * 1.5, KING_MAX_HP))


## 🏳️ `t`'s King fell: its army panics. Fighters drop everything and run for
## home, arms waving (vehicles and aircraft just stop shooting and head off),
## and a few seconds later they're gone with a poof. Nobody left fighting
## for a team that's already out (no surprise draws, no stolen wins).
func _rout(t: String) -> void:
	var said := 0
	var n := 0
	for u: B3Unit in battle.units:
		if not is_instance_valid(u) or u.dead or u.team != t or u.routed or u.player:
			continue
		n += 1
	if n == 0:
		return
	for u: B3Unit in battle.units:
		if not is_instance_valid(u) or u.dead or u.team != t or u.routed or u.player:
			continue
		u.routed = true
		u.cheer = false
		u.remove_meta("guard")
		if u.act == "aim" or u.act == "bow" or u.act == "throw":
			u.act = ""         # (drops what it was about to shoot or throw)
			u._hide_laser()
		if u is B3Vehicle:
			u.set_personality("peaceful")      # (stops shooting and wanders off)
		else:
			u.set_personality("coward")
			u.fleeing = true                   # runs away from whoever's closest
		if said < 4 and battle.rng.randf() < 0.6:
			said += 1
			var w: String = ["RUN!", "RETREAT!", "EEK!", "HOME TIME!"][battle.rng.randi() % 4]
			battle.fx.word(u.position + Vector3(0, u.tall + 0.8, 0), w, Color.WHITE)
		_routing.append([u, battle.time + ROUT_T + battle.rng.randf() * 1.5])
	_toast("🏳️ %s's army runs away!" % team_name(t), "rout:" + t)


## Teams that ran off: each fighter is gone (poof!) once its time is up.
func _routed_gone() -> void:
	if _routing.is_empty():
		return
	var i := 0
	while i < _routing.size():
		var e: Array = _routing[i]
		var u = e[0]
		if u == null or not is_instance_valid(u) or (u as B3Unit).dead:
			_routing.remove_at(i)
		elif battle.time >= float(e[1]) and not (u as B3Unit).player:
			_routing.remove_at(i)
			battle.remove_unit(u as B3Unit)
		else:
			i += 1


## 👑 Nobody hurt for STALL_T seconds (guards and Kings staring at each other
## across the field): everyone guarding charges the enemy King instead.
func _king_calm(step: float) -> void:
	if _charged:
		return
	var s := 0.0
	for u: B3Unit in battle.units:
		if is_instance_valid(u) and not u.dead:
			s += u.hp
	if _hp_sum < 0.0 or s < _hp_sum - 0.5:
		_calm_t = 0.0
	else:
		_calm_t += step
	_hp_sum = s
	if _calm_t < STALL_T:
		return
	_charged = true
	var n := 0
	for u: B3Unit in battle.units:
		if is_instance_valid(u) and not u.dead and not u.routed and not u.player and u.team != "wild" and u.pers == "defend" \
				and not (u is B3Vehicle and not (u as B3Vehicle).mobile):
			u.set_personality("attack")
			u.remove_meta("guard")
			n += 1
	if n > 0:
		battle.snd("charge", null, 0.8)
		_toast("📣 CHARGE! The guards and Kings march on the enemy!")


func _update_king_view() -> void:
	var v: Array = []
	for t in B3Defs.TEAM_ORDER:
		if kings.has(t):
			var k = kings[t]      # (untyped: it may have been cleared away under the winner banner)
			if is_instance_valid(k):
				var ku := k as B3Unit
				v.append([t, clampf(ku.hp / maxf(1.0, ku.max_hp), 0.0, 1.0), true])
		elif fallen.has(t):
			v.append([t, 0.0, false])
	king_view = v


## A clear spot near `p` to put a King: dry, not in lava, not inside a
## building (yours, or a house in 🏘️ Town), a tree or on top of someone.
func _free_spot(p: Vector3) -> Vector3:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.1
	q.shape = sph
	q.collision_mask = B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_SCENERY
	for r in [0.0, 2.0, 3.5, 5.0, 7.0, 9.0, 12.0, 15.0]:
		for i in (1 if r == 0.0 else 8):
			var a := TAU * i / 8.0
			var x: float = p.x + sin(a) * float(r)
			var z: float = p.z + cos(a) * float(r)
			if absf(x) > B3Defs.BOUNDS - 10.0 or absf(z) > B3Defs.BOUNDS - 10.0:
				continue
			var y: float = battle.world.height_at(x, z)
			var s := Vector3(x, y, z)
			if battle.world.water_depth(x, z) > 0.3 or battle.hazard_at(s, 2.0) != null:
				continue
			q.transform = Transform3D(Basis.IDENTITY, s + Vector3(0, 1.4, 0))
			if battle.space().intersect_shape(q, 1).is_empty():
				return s
	return Vector3(p.x, battle.world.height_at(p.x, p.z), p.z)


# ---------------------------------------------------------- 🚩 the hill
func _hill_tick(dt: float) -> void:
	_tick_t -= dt
	if not battle.fighting:
		# before Fight!: the circle shows where it will be (it follows the armies)
		if _tick_t <= 0.0:
			_tick_t = 1.0
			if battle.units.is_empty():
				_remove_hill()
			else:
				var p := _hill_spot(_fight_middle())
				if hill_node == null or Vector2(p.x - hill_pos.x, p.z - hill_pos.z).length() > 1.0:
					hill_pos = p
					_make_hill()
		return
	if not hill_on:
		_place_hill()
	if _tick_t > 0.0:
		return
	if hill_won != "" or battle.winner != "":
		_tick_t = 0.2      # (the clock doesn't run on under the winner banner: no catching up later)
		return
	var step := minf(0.2 - _tick_t, 0.3)
	_tick_t = 0.2
	var inside := {}
	for u: B3Unit in battle.units:
		if not is_instance_valid(u) or u.dead or u.down or u.flying:
			continue
		var d := Vector2(u.position.x - hill_pos.x, u.position.z - hill_pos.z).length()
		if d <= hill_r and absf(u.position.y - hill_pos.y) < 4.0:
			inside[team_key(u)] = true
	var was := holder
	if inside.size() == 1:
		holder = String(inside.keys()[0])
		scores[holder] = minf(HILL_WIN, float(scores.get(holder, 0.0)) + HILL_RATE * step)
		if float(scores[holder]) >= HILL_WIN:
			hill_won = holder
			_toast("🚩 %s held the hill to 100!" % team_name(holder))
		elif float(scores[holder]) >= 75.0:
			_toast("🚩 %s is almost there! Push them off the hill!" % team_name(holder), "near:" + holder)
	elif inside.size() > 1:
		holder = "+"
	else:
		holder = ""
	if holder != was:
		_set_hill_tint()
		if holder != "" and holder != "+" and _toast_t <= 0.0:
			_toast_t = 4.0
			_toast("🚩 %s is on the hill!" % team_name(holder))
		elif holder == "+" and _toast_t <= 0.0:
			_toast_t = 6.0
			_toast("⚔️ Fight for the hill! Nobody scores while two teams are in it.", "")


## Where the fighting will be: halfway between the armies (each team's middle).
func _fight_middle() -> Vector3:
	var sums := {}
	for u: B3Unit in battle.units:
		if not is_instance_valid(u) or u.dead or u.flying:
			continue
		var k := team_key(u)
		var e: Array = sums.get(k, [Vector3.ZERO, 0])
		e[0] = (e[0] as Vector3) + u.position
		e[1] = int(e[1]) + 1
		sums[k] = e
	if sums.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for k in sums:
		var e: Array = sums[k]
		c += (e[0] as Vector3) / float(e[1])
	return c / float(sums.size())


## The circle's spot near `c`: the top of a hill close by, if there is one
## (at least a metre higher), otherwise `c`. Never in water or lava (even a
## pool up on a hill), or on top of a building, a house or a tree.
func _hill_spot(c: Vector3) -> Vector3:
	var w = battle.world
	var h0: float = w.height_at(c.x, c.z)
	var cands: Array = []        # [score, Vector3(x, hilltop height, z)]
	var step := 2.0
	var n := int(HILL_LOOK / step)
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var x := c.x + ix * step
			var z := c.z + iz * step
			var d := Vector2(x - c.x, z - c.z).length()
			if d > HILL_LOOK or not _hill_ok(x, z):
				continue
			# a hilltop: the ground all round the circle, not just one bump
			var h: float = (float(w.height_at(x, z)) * 2.0 + float(w.height_at(x + 2.5, z)) + float(w.height_at(x - 2.5, z))
				+ float(w.height_at(x, z + 2.5)) + float(w.height_at(x, z - 2.5))) / 6.0
			cands.append([h - d * 0.06, Vector3(x, h, z)])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	# the best spot with nothing built on it (only the few best get looked at)
	var best_p := c
	var found := false
	for i in mini(cands.size(), 40):
		var p: Vector3 = cands[i][1]
		if _hill_clear(Vector3(p.x, float(w.height_at(p.x, p.z)), p.z)):
			best_p = p
			found = true
			break
	var flat_ok := _hill_ok(c.x, c.z) and _hill_clear(Vector3(c.x, h0, c.z))
	if not found or (flat_ok and best_p.y - h0 < 1.0):
		best_p = c
	return Vector3(best_p.x, float(w.height_at(best_p.x, best_p.z)), best_p.z)


## The hill can go round (x, z): on the field, dry, and no lava or acid
## close by (at the ground's height there, so a pool up on a hill counts).
func _hill_ok(x: float, z: float) -> bool:
	var w = battle.world
	if absf(x) >= B3Defs.BOUNDS - 20.0 or absf(z) >= B3Defs.BOUNDS - 20.0 or float(w.water_depth(x, z)) >= 0.05:
		return false
	return battle.hazard_at(Vector3(x, float(w.height_at(x, z)), z), HILL_R + 1.0) == null


## Nothing built in the circle at `p` (on the ground): no wall, tower or
## bunker, no house, no tree.
func _hill_clear(p: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = HILL_R * 0.8
	sh.height = 3.0
	q.shape = sh
	q.collision_mask = B3Defs.L_STRUCT | B3Defs.L_SCENERY
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.8, 0))
	return battle.space().intersect_shape(q, 1).is_empty()


func _place_hill() -> void:
	hill_pos = _hill_spot(_fight_middle())
	hill_on = true
	_make_hill()


func _remove_hill() -> void:
	hill_on = false
	if hill_node and is_instance_valid(hill_node):
		hill_node.queue_free()
	hill_node = null
	_hill_mats.clear()


func _set_hill_tint() -> void:
	if holder == "" or holder == "+":
		_hill_tint = Color(1.0, 0.92, 0.55)
	else:
		_hill_tint = B3Defs.team_col(holder if not holder.begins_with("wild:") else "wild").lightened(0.15)
	if hill_node and is_instance_valid(hill_node):
		var flag := hill_node.get_node_or_null("Pennant") as MeshInstance3D
		if flag:
			flag.material_override = B3Mats.mat(_hill_tint, 0.6)


## The glowing circle: a see-through disc that lies on the ground, a bright
## rim, a soft column of light (so you can find it in first person) and a
## pole with a pennant in the holding team's colour.
func _make_hill() -> void:
	if hill_node and is_instance_valid(hill_node):
		hill_node.queue_free()
	_hill_mats.clear()
	var w = battle.world
	var n := Node3D.new()
	n.name = "Hill"
	battle.add_child(n)
	n.position = hill_pos
	hill_node = n
	var segs := 56
	var gy := func(x: float, z: float) -> float:
		return float(w.height_at(hill_pos.x + x, hill_pos.z + z)) - hill_pos.y
	# the disc (rings of triangles that follow the ground)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 7
	for i in rings:
		var r0 := hill_r * i / rings
		var r1 := hill_r * (i + 1) / rings
		var a0 := lerpf(0.16, 0.34, float(i) / rings)
		var a1 := lerpf(0.16, 0.34, float(i + 1) / rings)
		for j in segs:
			var t0 := TAU * j / segs
			var t1 := TAU * (j + 1) / segs
			var p := [Vector3(sin(t0) * r0, 0, cos(t0) * r0), Vector3(sin(t1) * r0, 0, cos(t1) * r0),
				Vector3(sin(t0) * r1, 0, cos(t0) * r1), Vector3(sin(t1) * r1, 0, cos(t1) * r1)]
			for k in 4:
				var v: Vector3 = p[k]
				v.y = float(gy.call(v.x, v.z)) + 0.1
				p[k] = v
			for idx in [0, 2, 1, 1, 2, 3]:
				st.set_color(Color(1, 1, 1, a0 if idx < 2 else a1))
				st.add_vertex(p[idx])
	_hill_mesh(n, st.commit())
	# the rim
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in segs:
		var t0 := TAU * j / segs
		var t1 := TAU * (j + 1) / segs
		var q: Array[Vector3] = []
		for rr: float in [hill_r - 0.45, hill_r + 0.05]:
			for tt: float in [t0, t1]:
				var v := Vector3(sin(tt) * rr, 0, cos(tt) * rr)
				v.y = float(gy.call(v.x, v.z)) + 0.16
				q.append(v)
		for idx in [0, 2, 1, 1, 2, 3]:
			st.set_color(Color.WHITE)
			st.add_vertex(q[idx])
	_hill_mesh(n, st.commit())
	# the column of light
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in segs:
		var t0 := TAU * j / segs
		var t1 := TAU * (j + 1) / segs
		var b0 := Vector3(sin(t0) * hill_r, 0, cos(t0) * hill_r)
		var b1 := Vector3(sin(t1) * hill_r, 0, cos(t1) * hill_r)
		b0.y = float(gy.call(b0.x, b0.z)) + 0.1
		b1.y = float(gy.call(b1.x, b1.z)) + 0.1
		var u0 := b0 + Vector3(0, 7.0, 0)
		var u1 := b1 + Vector3(0, 7.0, 0)
		var pts := [b0, b1, u0, u1]
		for idx in [0, 2, 1, 1, 2, 3]:
			st.set_color(Color(1, 1, 1, 0.22 if idx < 2 else 0.0))
			st.add_vertex(pts[idx])
	_hill_mesh(n, st.commit())
	# a pole with a pennant in the middle
	var pole := B3Mats.add(n, B3Mats.cyl(0.07, 0.09, 4.2, 8), B3Mats.mat(Color("e8e2d0"), 0.5), Vector3(0, 2.1, 0))
	pole.name = "Pole"
	B3Mats.add(n, B3Mats.sphere(0.16, 10), B3Mats.mat(Color("ffd84a"), 0.3, 0.5), Vector3(0, 4.25, 0))
	var flag := B3Mats.add(n, B3Mats.prism(Vector3(1.0, 1.3, 0.05)), B3Mats.mat(Color.WHITE, 0.6), Vector3(0.72, 3.6, 0), Vector3(0, 0, -90))
	flag.name = "Pennant"
	_set_hill_tint()


func _hill_mesh(n: Node3D, mesh: Mesh) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = _hill_tint
	_hill_mats.append(m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)


# ------------------------------------------------------ 🌊 Wave Defense
## Wave Defense was just set up (B3Scenarios): waiting to start at `first`.
func begin_waves(first := 1) -> void:
	_switch("waves")
	start_wave = maxi(1, first)
	phase = "build"
	wave = start_wave - 1
	wave_units.clear()
	_bounty = {}
	_siege_dps = {}
	left = 0
	budget_at_fight = -1
	_owns_budget = true
	_new_keep()


## What wave `n` brings: {name, units: [[kind, count]...], boss}.
static func wave_def(n: int) -> Dictionary:
	var i := n - 1
	var k := 1.0
	if i >= WAVES.size():
		# round the last five again, with more of everything
		var extra := i - WAVES.size()
		i = WAVES.size() - 5 + extra % 5
		k = 1.0 + 0.3 * (floori(extra / 5.0) + 1)
	var d: Dictionary = WAVES[i]
	var units: Array = []
	for e: Array in d.units:
		units.append([String(e[0]), maxi(1, roundi(int(e[1]) * k))])
	var boss := String(d.get("boss", ""))
	var name_s := String(d.name)
	if n > WAVES.size() and n % 5 == 0:
		boss = String(BOSSES[(floori(n / 5.0) - 1) % BOSSES.size()])
		name_s = "A HUGE " + String(B3Defs.unit_def(boss).name)
	return {"name": name_s, "units": units, "boss": boss}


## How much tougher wave `n`'s attackers are.
static func wave_hp(n: int) -> float:
	return minf(1.0 + 0.04 * (n - 1), 3.0)


## Points for holding the fort through wave `n`.
static func wave_bonus(n: int) -> int:
	return 5 + 2 * n


## 🪙 Points for knocking out an attacker of `kind_s`: half its price (at
## least 1), so a tank pays more than a stick figure; a boss at least 10.
static func bounty(kind_s: String, boss := false) -> int:
	var c := B3Defs.cost(kind_s)
	return maxi(10, c) if boss else maxi(1, floori(c / 2.0))


## 👀 What's coming in wave `n`, for the panel: [[icon, count]...] (most
## first), then the boss's icon and name (or "", "").
static func wave_preview(n: int) -> Array:
	var d := wave_def(n)
	var by := {}
	var order: Array[String] = []
	for e: Array in d.units:
		var k := String(e[0])
		if not by.has(k):
			order.append(k)
		by[k] = int(by.get(k, 0)) + int(e[1])
	order.sort_custom(func(a: String, b: String) -> bool: return int(by[a]) > int(by[b]))
	var out: Array = []
	for k in order:
		out.append([String(B3Defs.unit_def(k).icon), int(by[k])])
	var boss := String(d.boss)
	if boss != "":
		out.append([String(B3Defs.unit_def(boss).icon), String(B3Defs.unit_def(boss).name)])
	return out


## 🚩 How hard attacker `u` hits the keep, a second (a boss much harder).
static func siege_dps(u: B3Unit, boss := false) -> float:
	var d := 0.0
	if u is B3Vehicle:
		d = 22.0 if u.kind == "tank" else 12.0
	else:
		d = clampf(float(u.melee.dmg) / maxf(0.3, float(u.melee.cd)), 6.0, 30.0) * 0.6
	return d * (3.0 if boss else 1.0)


func _start_wave(n: int) -> void:
	wave = n
	phase = "wave"
	wave_t = 0.0
	wave_kos = 0
	wave_units.clear()
	_mark_fought()
	var d := wave_def(n)
	var kinds: Array[String] = []
	for e: Array in d.units:
		for i in int(e[1]):
			kinds.append(String(e[0]))
	var hpk := wave_hp(n)
	var foot: Array[String] = []
	var wheels: Array[String] = []
	var air: Array[String] = []
	for k in kinds:
		if bool(B3Defs.unit_def(k).get("flying", false)):
			air.append(k)
		elif B3Defs.is_vehicle(k):
			wheels.append(k)
		else:
			foot.append(k)
	# rows across the far side: fighters in front, vehicles behind, aircraft further back
	var row := 0
	for gi in 2:
		var group: Array[String] = foot if gi == 0 else wheels
		var per := 8 if gi == 0 else 4
		var gap := 3.2 if gi == 0 else 7.0
		var i := 0
		while i < group.size():
			var n_row := mini(per, group.size() - i)
			for j in n_row:
				var x := (j - (n_row - 1) * 0.5) * gap
				_attacker(group[i + j], Vector3(x, 0, SPAWN_Z - row * 3.5 - gi * 2.0), hpk)
			i += n_row
			row += 1
	for j in air.size():
		_attacker(air[j], Vector3((j - (air.size() - 1) * 0.5) * 9.0, 0, SPAWN_Z - 16.0), hpk)
	var boss := String(d.boss)
	if boss != "":
		var bu := _attacker(boss, Vector3(0, 0, SPAWN_Z - row * 3.5 - 6.0), 1.0, BOSS_SIZE)
		if bu:
			bu.max_hp = float(B3Defs.unit_def(boss).hp) * BOSS_HP * minf(wave_hp(n), 1.6)
			bu.hp = bu.max_hp
			bu.set_meta("boss", true)
	left = wave_units.size()
	battle.snd("alarm", null, 0.6)
	battle.snd("battle_start", null, 0.8)
	if boss != "":
		_toast("👹 BOSS WAVE %d: %s is coming!" % [n, String(d.name)])
	else:
		_toast("🌊 Wave %d: %s!" % [n, String(d.name)])


func _attacker(kind_s: String, p: Vector3, hpk: float, size := 1.0) -> B3Unit:
	var w = battle.world
	var x := p.x
	var z := p.z
	for k in 6:
		if float(w.water_depth(x, z)) < 0.3:
			break
		x += 6.0 if x >= 0.0 else -6.0      # off the water
	var at := Vector3(x, float(w.height_at(x, z)), z)
	var u: B3Unit = battle.spawn_unit(kind_s, "blue", at, "attack", 0.0, size)
	if u == null:
		return null
	if hpk != 1.0:
		u.max_hp *= hpk
		u.hp = u.max_hp
	u.set_meta("wave", wave)
	if keep_up:
		u.home = keep_pos      # (with nobody to fight, even aircraft drift over the keep)
	wave_units.append(u)
	var id := u.get_instance_id()
	_bounty[id] = bounty(kind_s, size > 1.0)      # a boss is worth more
	_siege_dps[id] = siege_dps(u, size > 1.0)
	u.tree_exiting.connect(_attacker_gone.bind(id, u), CONNECT_ONE_SHOT)
	return u


## An attacker left the battle: knocked out (not just erased) gives its 🪙 points.
func _attacker_gone(id: int, u: B3Unit) -> void:
	_siege_dps.erase(id)
	if not _bounty.has(id):
		return      # from an earlier wave, or the battle was reset
	var pts := int(_bounty[id])
	_bounty.erase(id)
	if not is_inside_tree() or battle == null or not is_instance_valid(battle) or battle.is_queued_for_deletion():
		return
	if u.hp <= 0.0 and u.team == "blue" and int(battle.budget) >= 0:
		wave_kos += 1
		battle.budget = int(battle.budget) + pts
		battle.budget_changed.emit()


func _waves_tick(dt: float) -> void:
	if not battle.fighting or phase == "lost" or phase == "" or phase == "build":
		siege = false
		return
	# (knocked-out attackers give their points as they go: _attacker_gone).
	# Only real attackers count: one that somehow joined your side isn't one.
	wave_units = wave_units.filter(func(u) -> bool: return u != null and is_instance_valid(u) and not (u as B3Unit).dead and (u as B3Unit).team == "blue")
	left = wave_units.size()
	# knocked-out attackers don't come back (♾️ Reinforcements is for your side)
	if not battle._respawns.is_empty():
		battle._respawns = battle._respawns.filter(func(r: Dictionary) -> bool: return String(r.team) != "blue")
	siege = phase == "wave" and keep_up
	match phase:
		"wave":
			wave_t += dt
			_keep_t -= dt
			if _keep_t <= 0.0 and keep_up:
				_keep_t = 0.25
				_siege_tick(0.25)
				if phase == "lost":
					return
			if left == 0:
				_wave_cleared()
			elif wave_t > 75.0 + wave * 3.0 and left <= 2:
				# the last few wandered off somewhere: they give up
				for u in wave_units:
					if is_instance_valid(u):
						(u as B3Unit).remove_meta("wave")      # (not an attacker any more: it can go)
						battle.remove_unit(u as B3Unit)
				wave_units.clear()
				left = 0
				_toast("🏃 The last attackers ran away!")
				_wave_cleared()
		"break":
			break_t -= dt
			if break_t <= 0.0:
				_start_wave(wave + 1)


func _wave_cleared() -> void:
	var bonus := wave_bonus(wave)
	if int(battle.budget) >= 0:
		battle.budget = int(battle.budget) + bonus
		battle.budget_changed.emit()
	var new_best := wave > best
	if new_best:
		best = wave
		save_best()
	phase = "break"
	break_t = BREAK
	siege = false
	_patch_up()
	battle.snd("victory", null, 0.7)
	_toast("🎉 Wave %d beaten! +%d 🪙 for holding the fort%s" % [wave, bonus, "  ⭐ New best!" if new_best else ""])
	_toast("💚 Your army gets patched up and the keep mended. 👀 Wave %d: %s is coming!" % [wave + 1, String(wave_def(wave + 1).name)])


## Between waves: your fighters still standing get some health back, and the
## keep is mended a little.
func _patch_up() -> void:
	var n := 0
	for u: B3Unit in battle.units:
		if not is_instance_valid(u) or u.dead or u.team != "red" or u.hp >= u.max_hp:
			continue
		u.hp = minf(u.max_hp, u.hp + u.max_hp * HEAL_BREAK)
		u.hurt_t = 0.0      # (the health bar shows it going up)
		if n < 24:
			n += 1
			battle.fx.heal(u.center() + Vector3(0, 0.6, 0))
	if n > 0:
		battle.snd("heal", null, 0.7)
	if keep_up:
		keep_hp = minf(keep_max, keep_hp + keep_max * KEEP_FIX)
		_keep_bar_show()


func _lose() -> void:
	phase = "lost"
	siege = false
	left = wave_units.size()
	_toast("💥 The keep fell!  ⭐ Your best: wave %d" % maxi(best, 0))


# --------------------------------------------------------- 🚩 the Fort Keep
## A fresh keep at the back of the fort, at full health (host).
func _new_keep() -> void:
	var gx := KEEP_AT.x
	var gz := KEEP_AT.y
	keep_pos = Vector3(gx, float(battle.world.height_at(gx, gz)), gz)
	keep_max = KEEP_HP
	keep_hp = keep_max
	keep_up = true
	_make_keep()


func _remove_keep() -> void:
	keep_up = false
	siege = false
	keep_hp = 0.0
	if keep_node and is_instance_valid(keep_node):
		keep_node.queue_free()
	keep_node = null
	_keep_bar = null
	_keep_tower = null
	_keep_flag = null
	_keep_fall = -1.0


## 🌊 Hurts the keep (host). Attackers with nobody to fight hit it
## (_siege_tick), and their booms going off close by do too (keep_blast).
func hurt_keep(dmg: float) -> void:
	if not keep_up or dmg <= 0.0 or battle.puppet:
		return
	var was := keep_hp
	keep_hp = maxf(0.0, keep_hp - dmg / maxf(0.1, float(battle.r_tough)))
	_keep_bar_show()
	_keep_hit_t -= 1.0
	if _keep_hit_t <= 0.0 and keep_node:
		_keep_hit_t = 4.0
		battle.fx.dust(keep_pos + Vector3(0, 1.2, 0), KEEP_R + 0.8)
		battle.snd("crumble", keep_pos, 0.35)
	if phase == "wave":
		_toast("🚩 The attackers are at the keep! Stop them!", "keep_hit:%d" % wave)
		if keep_hp < keep_max * 0.3 and was >= keep_max * 0.3:
			_toast("⚠️ The keep is about to fall! Defend it!", "keep_low:%d" % wave)
	if keep_hp <= 0.0:
		_keep_fell()


## Every attacker standing by the keep with no defender close by hits it.
## Aircraft count from further off (they bomb and strafe it).
func _siege_tick(step: float) -> void:
	var dmg := 0.0
	for o in wave_units:
		var u := o as B3Unit
		if u.down:
			continue
		var dx := u.position.x - keep_pos.x
		var dz := u.position.z - keep_pos.z
		var gap := sqrt(dx * dx + dz * dz) - KEEP_R - u.radius
		var reach := 1.8
		if u.flying:
			reach = 30.0
		elif u is B3Vehicle:
			reach = 4.0
		if gap > reach:
			continue
		var t := u.target
		if t != null and is_instance_valid(t) and not t.dead and not t.down \
				and Vector2(t.position.x - u.position.x, t.position.z - u.position.z).length() < SIEGE_NEAR:
			continue      # busy with a defender
		dmg += float(_siege_dps.get(u.get_instance_id(), 8.0)) * step
	if dmg > 0.0:
		hurt_keep(dmg)


## 🌊 A blast at `pos` (B3Battle.explode): the attackers' booms (a tank shell,
## a bomb) hurt the keep if it's close; yours don't.
func keep_blast(pos: Vector3, r: float, dmg: float, team: String) -> void:
	if not keep_up or team != "blue" or phase != "wave" or r <= 0.0:
		return
	var gap := Vector2(pos.x - keep_pos.x, pos.z - keep_pos.z).length() - KEEP_R
	if gap > r or pos.y > keep_pos.y + 9.0:
		return
	hurt_keep(dmg * clampf(1.0 - maxf(0.0, gap) / r, 0.0, 1.0) * 0.5)


## 💥 The keep falls: it crumbles, the flag comes down, and the wave's lost.
func _keep_fell() -> void:
	keep_up = false
	siege = false
	keep_hp = 0.0
	_crumble_keep()
	battle.shake(0.5, keep_pos)
	battle.snd("crumble", keep_pos, 1.0)
	_lose()


## The look of the keep falling (host and friends): dust, and it sinks.
func _crumble_keep(at_once := false) -> void:
	if keep_node == null:
		return
	_keep_fall = 1.0 if at_once else 0.0
	_keep_bar_show()
	if not at_once:
		battle.fx.dust(keep_pos + Vector3(0, 1.0, 0), KEEP_R + 3.0)
		battle.fx.poof(keep_pos + Vector3(0, 3.0, 0), 3.0)
	_keep_anim(0.0)


func _keep_bar_show() -> void:
	if _keep_bar and is_instance_valid(_keep_bar):
		_keep_bar.visible = keep_up
		_keep_bar.set_instance_shader_parameter("hp", clampf(keep_hp / maxf(1.0, keep_max), 0.0, 1.0))


## The flag waves; a fallen keep sinks into a heap with its flag down.
func _keep_anim(dt: float) -> void:
	if not is_instance_valid(keep_node):
		keep_node = null
		return
	_pulse += dt
	if _keep_fall >= 0.0 and _keep_fall < 1.0:
		_keep_fall = minf(1.0, _keep_fall + dt * 0.9)
	var f := maxf(0.0, _keep_fall)
	if _keep_tower:
		var k := f * f
		_keep_tower.scale = Vector3(1.0 + 0.25 * k, 1.0 - 0.72 * k, 1.0 + 0.25 * k)
		_keep_tower.rotation = Vector3(0.12 * k, 0, -0.08 * k)
	if _keep_flag:
		if f > 0.0:
			_keep_flag.rotation = Vector3(0, 0, -1.45 * f)
		else:
			_keep_flag.rotation = Vector3(0, sin(_pulse * 2.3) * 0.25, 0)


## The 🚩 Fort Keep: a round stone tower with battlements, a door at the
## back, a tall flag in your team's colour and a health bar over it. It's
## solid (fighters walk round it and can stand on top) but it isn't a
## building you can blast apart: it has health instead (hurt_keep).
func _make_keep() -> void:
	if keep_node and is_instance_valid(keep_node):
		keep_node.queue_free()
	var n := Node3D.new()
	n.name = "Keep"
	battle.add_child(n)
	n.position = keep_pos
	keep_node = n
	_keep_fall = -1.0
	var stone := B3Mats.mat(Color("b9b2a3"), 0.95)
	var dark := B3Mats.mat(Color("8f887b"), 0.95)
	var red := B3Defs.team_col("red")
	# solid: a stone cylinder (on the buildings' layer, so things stand on it)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = B3Defs.L_STRUCT
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = KEEP_R
	cyl.height = 5.0
	cs.shape = cyl
	cs.position.y = 2.5
	body.add_child(cs)
	n.add_child(body)
	B3Mats.add(n, B3Mats.cyl(KEEP_R + 0.45, KEEP_R + 0.6, 0.6, 20), dark, Vector3(0, 0.25, 0))
	var tower := Node3D.new()
	tower.name = "Tower"
	n.add_child(tower)
	_keep_tower = tower
	B3Mats.add(tower, B3Mats.cyl(KEEP_R, KEEP_R + 0.12, 4.4, 20), stone, Vector3(0, 2.4, 0))
	B3Mats.add(tower, B3Mats.cyl(KEEP_R + 0.22, KEEP_R + 0.22, 0.4, 20), dark, Vector3(0, 4.6, 0))
	for i in 10:
		var a := TAU * i / 10.0
		B3Mats.add(tower, B3Mats.box(Vector3(0.75, 0.7, 0.45)), stone, Vector3(sin(a) * (KEEP_R + 0.05), 5.15, cos(a) * (KEEP_R + 0.05)), Vector3(0, rad_to_deg(a), 0))
	# a red band, the door (at the back, where you come in) and arrow slits
	B3Mats.add(tower, B3Mats.cyl(KEEP_R + 0.03, KEEP_R + 0.03, 0.3, 20), B3Mats.mat(red, 0.7), Vector3(0, 3.7, 0))
	B3Mats.add(tower, B3Mats.box(Vector3(1.3, 2.0, 0.3)), B3Mats.mat(Color("6b4426"), 0.85), Vector3(0, 1.1, KEEP_R + 0.02))
	B3Mats.add(tower, B3Mats.box(Vector3(1.5, 0.22, 0.34)), dark, Vector3(0, 2.15, KEEP_R + 0.04))
	for a: float in [-0.6, 0.6, PI - 0.5, PI + 0.5, PI]:
		B3Mats.add(tower, B3Mats.box(Vector3(0.24, 0.8, 0.2)), B3Mats.mat(Color("3a3530"), 1.0),
			Vector3(sin(a) * (KEEP_R + 0.03), 2.9, cos(a) * (KEEP_R + 0.03)), Vector3(0, rad_to_deg(a), 0))
	# the flag on a tall pole
	B3Mats.add(tower, B3Mats.cyl(0.07, 0.09, 3.4, 8), B3Mats.mat(Color("e8e2d0"), 0.5), Vector3(0, 6.4, 0))
	B3Mats.add(tower, B3Mats.sphere(0.17, 10), B3Mats.mat(Color("ffd84a"), 0.3, 0.5), Vector3(0, 8.2, 0))
	var flag := Node3D.new()
	flag.name = "Flag"
	flag.position = Vector3(0, 7.9, 0)
	tower.add_child(flag)
	_keep_flag = flag
	B3Mats.add(flag, B3Mats.box(Vector3(1.7, 1.05, 0.06)), B3Mats.mat(red, 0.6), Vector3(0.92, -0.5, 0))
	B3Mats.add(flag, B3Mats.box(Vector3(0.5, 0.5, 0.08)), B3Mats.mat(Color("ffd84a"), 0.4), Vector3(0.95, -0.5, 0), Vector3(0, 0, 45))
	# its health bar, always showing while it stands
	var bar := MeshInstance3D.new()
	bar.mesh = B3Mats.quad(Vector2(0.9, 0.13))
	bar.material_override = B3Mats.shader_mat("hpbar")
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position.y = 8.8
	bar.scale = Vector3.ONE * 3.4
	bar.set_instance_shader_parameter("team", red)
	n.add_child(bar)
	_keep_bar = bar
	_keep_bar_show()
	_keep_anim(0.0)


## 🌊 Booms from the Toy Box cost points too, and only go in the fort
## (B3Battle.drop). False if not (with a message why).
func pay_boom(id: String, pos: Vector3) -> bool:
	if kind != "waves" or battle.puppet or int(battle.budget) < 0 or battle.get("puzzle") != null:
		return true      # (a friend's copy: the host checks)
	var why: String = battle.can_place(id, pos)
	if why != "":
		if battle.ui:
			battle.ui.toast(why, false)
		battle.snd("nope", pos, 0.6)
		return false
	battle.spent = int(battle.spent) + B3Defs.cost(id)
	battle.budget_changed.emit()
	return true


## ▶ Next wave (or ▶ Start, before wave 1). It starts right away, even if
## the battle was paused (that's un-paused too).
func next_wave() -> void:
	if kind != "waves" or battle.puppet:
		return
	if phase == "build" and not battle.fighting:
		battle.toggle_play()
	elif phase == "break" and battle.fighting:
		if battle.paused:
			battle.set_paused(false)
		_start_wave(wave + 1)


## 🪙 Erasing `node` gives its points back during a fight (B3Battle._refund):
## in a 🌊 break, for whatever you bought since the last wave.
func can_refund(node: Node) -> bool:
	return kind == "waves" and phase == "break" and not battle.puppet and node != null and is_instance_valid(node) \
		and not node.has_meta("fought")


## A wave starts: what you've bought so far has fought (no more refunds).
func _mark_fought() -> void:
	for arr: Array in [battle.units, battle.structs, battle.hazards, battle.props]:
		for o in arr:
			if is_instance_valid(o) and (o as Node).has_meta("cost"):
				(o as Node).set_meta("fought", true)


static func load_best() -> void:
	if best >= 0:
		return
	best = 0
	var c := ConfigFile.new()
	if c.load(best_file) == OK:
		best = maxi(0, int(c.get_value("waves", "best", 0)))


static func save_best() -> void:
	if Settings.testing and best_file == BEST_PATH:
		return      # tests and screenshots never write your real best
	var c := ConfigFile.new()
	c.set_value("waves", "best", best)
	c.save(best_file)


# ------------------------------------------------------------ 👥 friends
## What friends need for the HUD and the hill (the host's snapshot "md").
func net_state() -> Array:
	match kind:
		"king":
			return ["king", king_view]
		"hill":
			return ["hill", hill_on or hill_node != null, hill_pos, hill_r, holder, scores, hill_won]
		"waves":
			# ..., the 🚩 keep: health (0..1), where, 0 none / 1 standing / 2 fallen
			var ks := 0 if keep_node == null else (1 if keep_up else 2)
			return ["waves", wave, phase, break_t, best, left, keep_hp / maxf(1.0, keep_max), keep_pos, ks]
	return [""]


## A friend's copy: shows the host's state. Anything odd is left out.
func apply_net(md: Variant) -> void:
	if not (md is Array) or (md as Array).is_empty() or not ((md as Array)[0] is String):
		return
	var a: Array = md
	var k := String(a[0])
	if not _net_ok(k, a):
		return
	if k != kind:
		if kind == "hill":
			_remove_hill()
		if kind == "waves":
			_remove_keep()
		kind = k
		_clear_goal()
	match k:
		"king":
			var v: Array = []
			for e in (a[1] as Array).slice(0, 5):
				if e is Array and (e as Array).size() == 3 and e[0] is String and B3Defs.TEAM.has(e[0]) and NetCommon.num_ok(e[1]) and e[2] is bool:
					v.append([String(e[0]), clampf(float(e[1]), 0.0, 1.0), bool(e[2])])
			king_view = v
		"hill":
			var sc := {}
			for t in (a[5] as Dictionary):
				if t is String and _key_ok(t) and NetCommon.num_ok((a[5] as Dictionary)[t]):
					sc[t] = clampf(float((a[5] as Dictionary)[t]), 0.0, HILL_WIN)
			scores = sc
			hill_won = String(a[6]) if _key_ok(String(a[6])) else ""
			var h := String(a[4])
			var new_holder := h if h == "" or h == "+" or _key_ok(h) else ""
			var p: Vector3 = a[2]
			var r := clampf(float(a[3]), 1.0, 20.0)
			if not bool(a[1]):
				_remove_hill()
			elif hill_node == null or p.distance_to(hill_pos) > 0.3 or absf(r - hill_r) > 0.01:
				hill_pos = p
				hill_r = r
				_make_hill()
			if new_holder != holder:
				holder = new_holder
				_set_hill_tint()
		"waves":
			wave = clampi(int(a[1]), 0, 9999)
			phase = String(a[2])
			break_t = clampf(float(a[3]), 0.0, 999.0)
			left = clampi(int(a[5]), 0, 9999)
			# (the host's best, for the HUD; your own saved best stays yours)
			_host_best = clampi(int(a[4]), 0, 9999)
			if a.size() >= 9:
				_net_keep(clampf(float(a[6]), 0.0, 1.0), a[7] as Vector3, clampi(int(a[8]), 0, 2))


## A friend's copy of the 🚩 keep: built where the host's is, with its
## health, crumbling when the host's falls (and back up after ⏮).
func _net_keep(frac: float, p: Vector3, ks: int) -> void:
	if ks == 0:
		if keep_node != null:
			_remove_keep()
		return
	keep_max = KEEP_HP
	keep_hp = frac * keep_max
	var up := ks == 1
	if keep_node == null or not is_instance_valid(keep_node) or p.distance_to(keep_pos) > 0.3 or (up and not keep_up):
		keep_pos = p
		keep_up = up
		_make_keep()
		if not up:
			_crumble_keep(true)      # (joined after it fell)
		return
	if keep_up and not up:
		keep_up = false
		_crumble_keep()
		return
	_keep_bar_show()


## True if the host's state `a` for `k` has the right shape (checked before
## anything changes, so a broken packet changes nothing).
static func _net_ok(k: String, a: Array) -> bool:
	match k:
		"":
			return true
		"king":
			return a.size() >= 2 and a[1] is Array
		"hill":
			return a.size() >= 7 and a[1] is bool and NetCommon.vec3_ok(a[2]) and NetCommon.num_ok(a[3], 50.0) \
				and a[4] is String and a[5] is Dictionary and (a[5] as Dictionary).size() <= 16 and a[6] is String
		"waves":
			if a.size() < 6 or not (a[2] is String) or not String(a[2]) in ["", "build", "wave", "break", "lost"]:
				return false
			for j in [1, 3, 4, 5]:
				if not NetCommon.num_ok(a[j], 100000.0):
					return false
			if a.size() >= 9:
				# the 🚩 keep: health, a place on the field, 0..2
				return NetCommon.num_ok(a[6], 1.5) and NetCommon.vec3_ok(a[7], 1000.0) and NetCommon.num_ok(a[8], 2.0)
			return true
	return false


## The best wave to show: the host's when you're in a friend's battle.
func shown_best() -> int:
	if battle and battle.puppet and _host_best >= 0:
		return _host_best
	return maxi(best, 0)


static func _key_ok(k: String) -> bool:
	if k.begins_with("wild:"):
		return B3Defs.UNITS.has(k.substr(5))
	return B3Defs.TEAM.has(k)

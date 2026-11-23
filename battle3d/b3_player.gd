class_name B3Player
## Playing as a fighter or vehicle in 3D Battle. Each played unit has a
## B3Ctl (its controls): `me` is this computer's, friends' come over the
## network. The unit's _physics_process calls control() instead of its AI.
##  - Overhead view: WASD moves (turned to match the camera), the mouse aims
##    at the ground, click (or hold) to attack, Space to jump.
##  - First person (👀, V key): the mouse looks around, W walks where you're
##    looking, the crosshair is where shots go. Knocked out? You jump into the
##    nearest teammate and keep going (B3Tools.player_lost).
## Vehicles do their own driving/flying from the same controls (player_drive).
##
## Right-click powers (`fire2`, see power()) for fighters, animals and
## dinosaurs. Each has a cooldown (B3Unit.power_cd) so it can't be spammed.
## Vehicles use right-click for their second gun instead.
##   shield  - hold: shield up. Blocks much better and wider from the front,
##             but you walk at half speed. Block or swing, not both: a raised
##             shield can't swing (let go to attack), and while a swing is
##             going the shield stays down (it comes back up after).
##   scope   - sniper. First person: right-click puts the scope in and out
##             (zoom, slower mouse look; B3Tools, B3Cam). Overhead: hold for a
##             steady aim (a red laser, dead-on shots, a quicker aim, slower walk).
##   bayonet - musket line infantry: a quick stab with the bayonet, even while reloading.
##   charge  - bulls, triceratops, mammoths and horsemen charge where you aim
##             (in first person you steer with the mouse).
##   pounce  - raptor: leaps at where you aim and claws whoever it lands on.
##   heal    - medic: a green pulse that heals teammates nearby (and you a little).
##   swoop   - dragon and pterodactyl: dive at where you aim and bite.
##   gorilla - an enemy close by (or aiming close): ground pound. Otherwise
##             throw a boulder where you aim. Feet on the ground for both.
##   roar    - T-Rex (and the elephant's trumpet): pushes back and stuns enemies
##             nearby (from the ground, not in mid-jump).
##   shove   - everyone else: a kick (people) or a shove (animals) that pushes
##             the enemy in front back a little.
## Powers run on the host like everything else, so friends' work too.

const POWERS := {
	"shield": {"cd": 0.0}, "scope": {"cd": 0.0}, "bayonet": {"cd": 1.0}, "shove": {"cd": 1.2},
	"charge": {"cd": 4.5}, "pounce": {"cd": 1.8}, "heal": {"cd": 6.0}, "swoop": {"cd": 3.5},
	"gorilla": {"cd": 3.5}, "roar": {"cd": 6.0},
}
const BOULDER_CD := 5.0      # the gorilla's boulder (its ground pound is POWERS.gorilla)
const HEAL_R := 7.0          # how far the medic's pulse reaches
const HEAL_FRIEND := 35.0    # ...and how much it heals each teammate
const HEAL_SELF := 15.0
const ROAR_R := 9.0
const GUARD_SLOW := 0.5      # walking speed with the shield up (or a sniper steadying)

static var me := B3Ctl.new()        # this computer's controls
static var unit: B3Unit = null      # the fighter or vehicle this computer is playing
## True from start() until stop(), even after `unit` is knocked out and freed
## (a freed node reads as null, so `unit != null` can't tell "never played"
## from "just got knocked out").
static var playing := false
static var what := ""               # its name, for the "you got knocked out" message
static var was_vehicle := false
static var kind := ""
static var team := ""               # whose side you were on (first person jumps to a teammate)
static var last_pos := Vector3.ZERO # where you were (the nearest teammate takes over)

const MASK := B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_PROP | B3Defs.L_SCENERY
## Attacks that take a moment before the shot or throw goes off: sniper and
## Robot aim, bazooka aim, bow draw, Wizard spell, grenade throw.
const WINDUPS := ["aim", "bow", "cast", "throw"]


static func active() -> bool:
	return unit != null and is_instance_valid(unit) and not unit.dead


## This computer takes `u`.
static func start(u: B3Unit) -> void:
	stop()
	if u == null or not is_instance_valid(u) or u.dead:
		return
	unit = u
	playing = true
	what = String(u.def.name)
	was_vehicle = u.is_vehicle()
	kind = u.kind
	team = u.team
	last_pos = u.global_position
	me.clear_buttons()
	me.peer = 0
	me.look_yaw = u.facing
	me.look_pitch = 0.0
	attach(u, me)


static func stop() -> void:
	if unit != null and is_instance_valid(unit) and unit.ctl == me:
		detach(unit)
	unit = null
	playing = false
	me.clear_buttons()


## What to say when the fighter or vehicle you were playing is gone.
static func lost_msg() -> String:
	if was_vehicle:
		return "💥 Your %s got wrecked! Pick something else to play." % what
	return "💫 You got knocked out! Pick another fighter to play."


## Hands `u` to the controls `c` (this computer's or a friend's).
static func attach(u: B3Unit, c: B3Ctl) -> void:
	if u.ctl != null and u.ctl != c and u == unit:
		unit = null
	u.ctl = c
	u.player = true
	u.target = null
	u.fleeing = false
	c.aim = u.position + u.forward() * 3.0
	if u.has_method("on_player_start"):
		u.call("on_player_start", c)


## Gives `u` back to the computer.
static func detach(u: B3Unit) -> void:
	if not is_instance_valid(u):
		return
	if u.has_method("on_player_stop"):
		u.call("on_player_stop")
	u.ctl = null
	u.player = false
	u.target = null
	u.shield_up = false
	if u.power_t > 0.0 and u._swoop:
		u._swoop = false
		u._alt = u.power_alt
	u.power_t = 0.0


## Called from B3Unit._physics_process while it's being played.
static func control(u: B3Unit, dt: float) -> void:
	var c := u.ctl
	if c == null:
		u.player = false
		return
	if u.has_method("player_drive"):
		u.call("player_drive", c, dt)      # vehicles: drive, fly, turn the turret, shoot
		return
	if c.fp:
		u.facing = c.look_yaw              # you turn exactly with the mouse
		u.look = Vector3(sin(c.look_yaw), 0, cos(c.look_yaw))
	else:
		var to := u._flat(c.aim - u.position)
		var dist := to.length()
		u.look = to / dist if dist > 0.4 else Vector3.ZERO
	u.want = c.move * u.speed * 1.1
	if _power_tick(u, c, dt):
		return      # charging or swooping: it carries on by itself for a moment
	if c.jump:
		c.jump = false
		if u._grounded and not u.flying and u.stun_t <= 0.0:
			u.linear_velocity.y = 7.0
			u.battle.snd("whoosh", u.position, 0.4, 1.3)
	if u.flying and c.lift != 0.0:
		u._alt = clampf(u._alt + c.lift * dt * 6.0, 2.0, 30.0)
	var locked := false
	if c.windup != "":
		if u.act == c.windup:
			# overhead: still winding up, so stay on the enemy you clicked even if the mouse moves off it
			locked = not c.fp and is_instance_valid(u.target) and (c.windup == "throw" or not u.target.down)
		else:
			# the wind-up is over. The fighter shot at its enemy if it still had one;
			# if not (it moved off, or there never was one), the shot goes where you're aiming.
			if c.windup != "throw" and u.act == "" and u.act_t >= u.act_len and not _had_target(u):
				_shoot_at(u, c, u.act_w, false)
			c.windup = ""
	if not locked:
		u.target = _pick_target(u, c)
	# (a raised shield can't swing: let go of right-click first. Hits you land
	# flash the first-person hit marker from B3Unit.hurt.)
	if c.fire and u.cd <= 0.0 and u.act == "" and not u.shield_up:
		_attack(u, c)


## The test the fighter itself makes when a wind-up ends (B3Unit._act_update):
## true if it has an enemy to shoot at.
static func _had_target(u: B3Unit) -> bool:
	return is_instance_valid(u.target) and not u.target.down


## The enemy under the cursor or crosshair, or (for melee) whoever is right in front.
## (Only fighters close enough are looked at, from the fighters' map; equal
## distances go to the one first in battle.units, as if all were looked at.)
static func _pick_target(u: B3Unit, c: B3Ctl) -> B3Unit:
	var best: B3Unit = null
	var bd := 1e9
	for o: B3Unit in u.battle.units_near(c.aim, 2.2 if not c.fp else 1.2, 1.0):
		if o == u or o.down or o.dead or not u.is_enemy(o):
			continue
		var d := u._flat(o.position - c.aim).length()
		if d < maxf(2.2 if not c.fp else 1.2, o.radius + (1.6 if not c.fp else 0.6)) and (d < bd or (d == bd and o.grid_i < best.grid_i)):
			bd = d
			best = o
	if best != null or String(u.wpn.type) != "melee":
		return best
	var fwd := u.forward()
	for o: B3Unit in u.battle.units_near(u.position, (u.radius + float(u.wpn.range) * u.size * 0.6) * 1.3, 1.3):
		if o == u or o.down or o.dead or not u.is_enemy(o):
			continue
		var off := u._flat(o.position - u.position)
		var d2 := off.length()
		if d2 < u._reach(u.wpn, o) * 1.3 and fwd.dot(off / maxf(d2, 0.01)) > 0.2 and (d2 < bd or (d2 == bd and o.grid_i < best.grid_i)):
			bd = d2
			best = o
	return best


static func _attack(u: B3Unit, c: B3Ctl) -> void:
	var w: Dictionary = u.wpn
	var ty := String(w.type)
	var spell := String(w.get("proj", "")) == "fireball"
	if not (ty in ["gun", "proj", "throw"]) or (u.target != null and not c.fp) or spell:
		# melee, a Wizard's spell (it always waves its staff first), or overhead
		# with an enemy under the mouse: the fighter attacks by itself, wind-up and all
		u._attack(w)
		if u.act in WINDUPS:
			c.windup = u.act
			if u.act == "aim" and steady(u, c):
				u.act_len *= 0.5      # a steady sniper takes aim twice as fast
		return
	_shoot_at(u, c, w, true)


## Shoots exactly at the spot you're aiming at (first person: the crosshair;
## overhead: the ground under the mouse). `start_cd` is false after a wind-up
## (its cooldown started with it).
static func _shoot_at(u: B3Unit, c: B3Ctl, w: Dictionary, start_cd: bool) -> void:
	var aim_at := c.aim
	match String(w.type):
		"gun":
			_fire_at(u, w, aim_at if c.fp else aim_at + Vector3(0, 0.9, 0))
		"proj":
			_proj_at(u, w, aim_at, start_cd)
		"throw":
			_throw_at(u, w, aim_at)


static func _fire_at(u: B3Unit, w: Dictionary, point: Vector3) -> void:
	var from := u._muzzle_pos()
	var dir := (point - from).normalized()
	var s := float(w.get("spread", 0.03))
	if u.ctl and u.ctl.fp:
		s *= 0.5        # aiming down the sights
	if u.ctl and u.ctl.fire2 and power(u) == "scope":
		s *= 0.1        # through the scope, or steadied overhead: dead on
	dir =(dir + Vector3(u.rng.randf_range(-s, s), u.rng.randf_range(-s, s) * 0.6, u.rng.randf_range(-s, s))).normalized()
	var to := from + dir * (float(w.range) * 1.6)
	var hit: Dictionary = u.shot_ray(from, to)      # flies past teammates, like the computer's shots
	var end := to
	if not hit.is_empty():
		end = hit.position
		u.battle.shot_hit(hit, w, dir, u)
	if w.has("beam"):
		# the Robot's laser: a fat glowing beam, the same as when it fires by itself (B3Special)
		var bc: Color = w.get("tracer", Color(5, 1, 1))
		u.battle.fx.beam(from, end, bc, float(w.beam), 0.22)
		u.battle.fx.beam(from, end, Color(2.6, 1.6, 1.6), float(w.beam) * 0.3, 0.16)
		u.battle.fx.muzzle(from, dir, 1.4)
		u.battle.snd(String(w.get("snd", "gun_laser")), from, 0.85)
		if u.rig:
			u.rig.recoil = 1.0
		u.act = "shoot"
		u.act_t = 0.0
		u.act_len = 0.15
		u.cd = float(w.cd)
		return
	var tc: Color = w.get("tracer", Color(4, 3, 1))
	u.battle.fx.tracer(from, end, tc, 0.08)
	if w.has("smoke") and u.has_method("musket_smoke"):
		u.musket_smoke(from, dir)      # muskets: a big puff of smoke
	else:
		u.battle.fx.muzzle(from, dir)
	u.battle.snd(String(w.get("snd", "gun_rifle")), from, 0.7)
	if u.rig:
		u.rig.recoil = 1.0
	u.act = "shoot"
	u.act_t = 0.0
	u.act_len = 0.12
	if w.has("burst"):
		u.burst += 1
		if u.burst >= int(w.burst):
			u.burst = 0
			u.cd = float(w.reload)
		else:
			u.cd = float(w.cd)
	else:
		u.cd = float(w.cd)


static func _proj_at(u: B3Unit, w: Dictionary, point: Vector3, start_cd := true) -> void:
	var from := u._muzzle_pos()
	var sp := float(w.get("speed", 20.0))
	var kind_s := String(w.get("proj", "rocket"))
	var vel: Vector3
	# B3Proj.lob aims for the Gravity rule, so shots land where you point in Moon gravity too
	if kind_s == "arrow":
		var tt := maxf(u._flat(point - from).length() / sp, 0.15)
		vel = B3Proj.lob(from, point, tt, kind_s)
	else:
		var p := point + (Vector3(0, 0.3, 0) if not (u.ctl and u.ctl.fp) else Vector3.ZERO)
		vel = B3Proj.lob(from, p, maxf(from.distance_to(p) / sp, 0.05), kind_s)
	u.battle.spawn_proj(kind_s, from, vel, u, w)
	u.battle.snd(String(w.get("snd", "bazooka")), from, 0.8)
	if kind_s == "rocket":
		u.battle.fx.muzzle(from, vel.normalized(), 1.8)
	elif kind_s == "fireball":
		u.battle.fx.muzzle(from, vel.normalized(), 1.3)
	if u.rig:
		u.rig.recoil = 1.0
	if start_cd:
		u.cd = float(w.cd)


static func _throw_at(u: B3Unit, w: Dictionary, point: Vector3) -> void:
	var from := u.position + Vector3(0, u.aim_y + 0.5, 0) + u.forward() * 0.3
	var tt := clampf(u._flat(point - from).length() / 9.0, 0.6, 1.5)
	var kind_s := String(w.get("proj", "grenade"))
	var vel := B3Proj.lob(from, point, tt, kind_s)
	var p = u.battle.spawn_proj(kind_s, from, vel, u, w)
	if p and "fuse" in p:
		p.fuse = tt + 0.5
	u.battle.snd("swing", from, 0.5)
	u._start_act("throw", 0.4, w)
	u.act_fired = true
	u.cd = float(w.cd)      # the same as when the Grenadier throws by itself


# ------------------------------------------------------- right-click powers
## Which right-click power `u` has (see the top of this file). "" for
## vehicles: right-click fires their second gun (player_drive).
static func power(u: B3Unit) -> String:
	if u == null or not is_instance_valid(u) or u.is_vehicle():
		return ""
	match u.kind:
		"sniper":
			return "scope"
		"medic":
			return "heal"
		"gorilla":
			return "gorilla"
		"trex", "elephant":
			return "roar"
	var d: Dictionary = u.def
	if bool(d.get("flying", false)):
		return "swoop"
	if bool(d.get("charge", false)):
		return "charge"       # bulls, triceratops, mammoths, horsemen (the mounted knight too)
	if bool(d.get("pounce", false)):
		return "pounce"
	if bool(d.get("bayonet", false)):
		return "bayonet"
	if B3Rig.shield_kind(d) != "":
		return "shield"
	return "shove"


## What right-click does for `u`, for the help line at the top while you
## play it (B3UI.controls_help). "" for vehicles: their own help says it.
static func power_help(u: B3Unit) -> String:
	if u == null or not is_instance_valid(u):
		return ""
	var icon := String(u.def.get("icon", ""))
	match power(u):
		"shield":
			return "hold right-click 🛡️ block (let go to swing)"
		"scope":
			return "right-click 🔭 scope" if me.fp else "hold right-click 🎯 steady aim"
		"bayonet":
			return "right-click 🗡️ bayonet"
		"charge":
			return "right-click %s charge!" % icon
		"pounce":
			return "right-click %s pounce" % icon
		"heal":
			return "right-click 💚 heal friends"
		"swoop":
			return "right-click %s swoop" % icon
		"gorilla":
			return "right-click 🦍 ground pound up close (far: 🪨 boulder)"
		"roar":
			return "right-click %s %s" % [icon, "trumpet" if u.kind == "elephant" else "roar"]
		"shove":
			return "right-click 👟 kick" if kicks(u) else "right-click 💥 shove"
	return ""


## The power's short name, for the pill that shows its cooldown overhead
## (B3UI): "👟 Kick", "🐂 Charge"...
static func power_name(u: B3Unit) -> String:
	if u == null or not is_instance_valid(u):
		return ""
	var icon := String(u.def.get("icon", ""))
	match power(u):
		"shield":
			return "🛡️ Shield"
		"scope":
			return "🔭 Scope"
		"bayonet":
			return "🗡️ Bayonet"
		"charge":
			return "%s Charge" % icon
		"pounce":
			return "%s Pounce" % icon
		"heal":
			return "💚 Heal"
		"swoop":
			return "%s Swoop" % icon
		"gorilla":
			return "🦍 Pound / 🪨 Boulder"
		"roar":
			return "%s %s" % [icon, "Trumpet" if u.kind == "elephant" else "Roar"]
		"shove":
			return "👟 Kick" if kicks(u) else "💥 Shove"
	return ""


## How ready `u`'s power is: 0 just used, 1 ready again. The cooldown ring
## round the first-person crosshair and the pill under "You're the ..." show
## it (B3UI). Only the host really knows: a friend's copy reads the power_cd
## and power_len the host sends along, or what set_net_gauges was given.
static func power_ready(u: B3Unit) -> float:
	if u == null or not is_instance_valid(u):
		return 1.0
	if u.has_meta("net_gauges") and u.battle != null and u.battle.puppet:
		return _net_gauge(u, 0)
	if u.power_cd <= 0.0:
		return 1.0
	return clampf(1.0 - u.power_cd / maxf(u.power_len, 0.01), 0.0, 1.0)


## True if `u`'s power has a cooldown to show (holding up a shield or a
## sniper's scope doesn't: they're held, not used up).
static func power_has_cd(u: B3Unit) -> bool:
	var pw := power(u)
	return pw != "" and float(POWERS.get(pw, {}).get("cd", 0.0)) > 0.0


## A reload shorter than this is just the time between swings or shots: the
## reload bar (and reload_ready) leave it out.
const RELOAD_MIN := 0.6


## How far `u`'s main weapon has reloaded: 0 just fired, 1 ready. Short
## waits between shots (and every melee swing) read 1, so only real reloads
## show: the musket, sniper, bazooka, bow, a machine gun's new belt, a tank's
## shell... The first-person reload bar shows it (B3UI). On the host it
## remembers how long the wait was when it started (meta "cd_full"); a
## friend's copy reads what the host sent (set_net_gauges), or 1.
static func reload_ready(u: B3Unit) -> float:
	if u == null or not is_instance_valid(u):
		return 1.0
	if u.has_meta("net_gauges") and u.battle != null and u.battle.puppet:
		return _net_gauge(u, 1)
	var cd := u.cd
	var full: float = u.get_meta("cd_full", 0.0)
	if cd > float(u.get_meta("cd_prev", 0.0)) + 0.001:
		full = cd      # a new wait just started
		u.set_meta("cd_full", full)
	u.set_meta("cd_prev", cd)
	if cd <= 0.0 or full < RELOAD_MIN or (not u.is_vehicle() and String(u.wpn.get("type", "")) == "melee"):
		return 1.0
	return clampf(1.0 - cd / full, 0.0, 1.0)


## 👥 For friends' screens (B3Net). Only the host runs the battle, so only it
## knows how far a power or a reload has got. For each unit a friend plays,
## the host can send net_gauges(u) (two numbers 0..1: power, reload; a byte
## each is plenty) and the friend's copy passes them to set_net_gauges(u, a).
## power_ready and reload_ready then read them there. (Sending power_cd and
## power_len themselves works for the power too: power_ready reads those
## when it hasn't been given gauges.)
static func net_gauges(u: B3Unit) -> PackedFloat32Array:
	return PackedFloat32Array([power_ready(u), reload_ready(u)])


static func set_net_gauges(u: B3Unit, a: Variant) -> void:
	if u == null or not is_instance_valid(u) or not (a is PackedFloat32Array or a is Array):
		return
	var src: Array = Array(a)
	var g := PackedFloat32Array([1.0, 1.0])
	for i in mini(2, src.size()):
		var v: Variant = src[i]
		if (v is float or v is int) and is_finite(float(v)):
			g[i] = clampf(float(v), 0.0, 1.0)
	u.set_meta("net_gauges", g)


static func _net_gauge(u: B3Unit, i: int) -> float:
	if not u.has_meta("net_gauges"):
		return 1.0
	var g: Variant = u.get_meta("net_gauges")
	if g is PackedFloat32Array and (g as PackedFloat32Array).size() > i:
		return (g as PackedFloat32Array)[i]
	return 1.0


## Right-click held on a shield carrier with no swing going: the shield
## goes up (B3Unit.shield_up). Swinging lowers it, and a raised shield can't
## swing (control), so it's block or swing, not both at once.
static func guard_wanted(u: B3Unit, c: B3Ctl) -> bool:
	return c != null and c.fire2 and u.act == "" and not u.down and power(u) == "shield"


## A sniper looking through its scope (first person, right-click toggled on).
## Knocked down, the scope comes out (B3Cam drops it).
static func scoped(u: B3Unit, c: B3Ctl) -> bool:
	return c != null and c.fp and c.fire2 and is_instance_valid(u) and not u.down and power(u) == "scope"


## A sniper holding right-click in the overhead view: a steady aim.
static func steady(u: B3Unit, c: B3Ctl) -> bool:
	return c != null and not c.fp and c.fire2 and is_instance_valid(u) and not u.down and power(u) == "scope"


## People and robots kick; animals shove.
static func kicks(u: B3Unit) -> bool:
	var body := String(u.def.body)
	return body == "human" or body == "robot"


## Right-click, every physics step while `u` is played. Returns true while a
## charge or a swoop carries it along (it steers itself; no attacking then).
static func _power_tick(u: B3Unit, c: B3Ctl, dt: float) -> bool:
	var pw := power(u)
	var up := guard_wanted(u, c)
	if up != u.shield_up:
		u.shield_up = up
		if up:
			u.battle.snd("clink", u.position, 0.5, 0.75)
	if u.shield_up or steady(u, c) or scoped(u, c):
		u.want *= GUARD_SLOW
	if u.charge_t > 0.0:
		if u.power_t > 0.0:
			_steer_charge(u, c, dt)
			c.jump = false      # (no surprise jump once it's over)
			return true
		u.charge_t = 0.0      # the computer's own charge stops when you take over
		if u.act == "charge":
			u.act = ""
	if u.power_t > 0.0:
		if u._swoop:
			_swoop_tick(u, dt)
			c.jump = false
			return true
		u.power_t = 0.0
	if u.act == "pound" or u.act == "hurl" or u.act == "roar":
		u.want *= 0.3         # big moves plant the feet
	if c.fire2 and u.power_cd <= 0.0 and u.act == "":
		_use_power(u, c, pw)
	return false


static func _use_power(u: B3Unit, c: B3Ctl, pw: String) -> void:
	var b = u.battle
	var info: Dictionary = POWERS.get(pw, {})
	var cd := float(info.get("cd", 0.0))
	match pw:
		"bayonet":
			u._start_act("thrust", 0.4, u.melee)
			b.snd("swing", u.position, 0.5, 1.3)
		"shove":
			u._start_act("kick", 0.4, B3Defs.weapon("kick" if kicks(u) else "shove"))
			b.snd("swing", u.position, 0.45, 1.5)
		"charge":
			if not u._grounded:
				return
			u._start_charge(_power_dir(u, c))
			u.power_t = u.charge_t
			b.fx.dust(u.position, 1.4)
			b.fx.word(u.position + Vector3(0, u.tall + 0.6, 0), "CHARGE!", Color("ffd34d"))
		"pounce":
			if not u._grounded:
				return
			u._pounce(_power_dir(u, c))
			b.fx.dust(u.position, 0.9)
		"heal":
			_heal_pulse(u)
		"swoop":
			_start_swoop(u, c)
		"gorilla":
			if not u._grounded:
				return      # (feet on the ground first: no pounding the air)
			if pound_close(u, c):
				u._start_act("pound", 0.95, B3Defs.weapon("gorilla_pound"))
				b.snd("growl", u.position, 0.7)
			else:
				u._start_act("hurl", 1.15, B3Defs.weapon("boulder"))     # B3Special._hurl throws it where you aim
				b.snd("growl", u.position, 0.6)
				cd = BOULDER_CD
		"roar":
			if not u._grounded:
				return
			_roar(u)
		_:
			return       # shield and scope are held, not used up
	u.power_cd = cd
	u.power_len = cd


const POUND_AIM := 6.5       # the gorilla aiming closer than this pounds (farther: a boulder)
const POUND_NEAR := 1.6      # ...and it always pounds with an enemy this close past its blast

## The gorilla's right-click: a ground pound if an enemy is close enough for
## its blast to reach (or you aim at the ground close by), otherwise a
## boulder thrown where you aim. In first person the crosshair usually points
## far ahead, so it's whoever's close that counts.
static func pound_close(u: B3Unit, c: B3Ctl) -> bool:
	if u._flat(c.aim - u.position).length() <= POUND_AIM:
		return true
	var r := float(B3Defs.weapon("gorilla_pound").get("aoe", 3.8)) * clampf(u.size, 0.6, 2.5) + POUND_NEAR
	var fwd := u.forward()
	for o: B3Unit in u.battle.units_near(u.position, r, 2.0):
		if o == u or o.down or o.dead or not u.is_enemy(o) or u._height_gap(o) > 2.5:
			continue
		var off := u._flat(o.position - u.position)
		var d := off.length()
		# (the pound lands in front: an enemy right behind you doesn't count)
		if d < r + o.radius and (d < 1.0 or fwd.dot(off / d) > -0.2):
			return true
	return false


## Where a charge, pounce or swoop goes: where you look (first person) or
## towards the mouse (overhead).
static func _power_dir(u: B3Unit, c: B3Ctl) -> Vector3:
	if c.fp:
		return Vector3(sin(c.look_yaw), 0, cos(c.look_yaw))
	var to := u._flat(c.aim - u.position)
	return to.normalized() if to.length() > 0.5 else u.forward()


## A charge you started. In first person it turns (slowly) to where you look.
static func _steer_charge(u: B3Unit, c: B3Ctl, dt: float) -> void:
	if c.fp:
		var a := rotate_toward(atan2(u.charge_dir.x, u.charge_dir.z), c.look_yaw, dt * 1.6)
		u.charge_dir = Vector3(sin(a), 0, cos(a))
	u._charging(dt)
	u.power_t = u.charge_t
	u._power_fx -= dt
	if u._power_fx <= 0.0 and u._grounded:
		u._power_fx = 0.15
		u.battle.fx.dust(u.position - u.charge_dir * u.radius, 0.5)


## Dragon and pterodactyl: dive at the spot you aim at (not too far).
static func _start_swoop(u: B3Unit, c: B3Ctl) -> void:
	var to := u._flat(c.aim - u.position)
	var d := to.length()
	var dir := to / d if d > 0.5 else u.forward()
	var p := u.position + dir * clampf(d, 4.0, 20.0)
	var gy: float = u.battle.world.height_at(p.x, p.z)
	u.power_at = Vector3(p.x, maxf(gy, c.aim.y) if d <= 20.0 else gy, p.z)
	u.power_t = 3.0
	u.power_alt = u._alt
	u._swoop = true
	u.battle.snd("screech" if u.kind == "ptero" else "roar", u.position, 0.6, 1.2)
	u.battle.snd("whoosh", u.position, 0.8, 0.8)


static func _swoop_tick(u: B3Unit, dt: float) -> void:
	u.power_t -= dt
	var to := u._flat(u.power_at - u.position)
	var d := to.length()
	var gh: float = u.battle.world.height_at(u.position.x, u.position.z)
	u._alt = move_toward(u._alt, maxf(0.7, u.power_at.y - gh + 0.5), dt * 10.0)
	u.want = Vector3.ZERO
	if d > 0.8:
		u.want = to / d * u.speed * 1.6
		u.look = to / d
	var bite: B3Unit = null      # (the first in battle.units it reaches)
	for o: B3Unit in u.battle.units_near(u.position, u.radius + 1.0, 1.0):
		if o != u and not o.down and not o.dead and u.is_enemy(o) and u.center().distance_to(o.center()) < u.radius + o.radius + 1.0 and (bite == null or o.grid_i < bite.grid_i):
			bite = o
	if bite:
		_swoop_bite(u, bite)
		return
	if u.power_t <= 0.0 or d < 1.0:
		_end_swoop(u)


static func _swoop_bite(u: B3Unit, o: B3Unit) -> void:
	var big := u.kind == "dragon"
	var dir := (u._flat(o.position - u.position).normalized() + Vector3.UP * 0.6).normalized()
	u._start_act("attack", 0.4, u.melee)
	u.act_fired = true
	u.battle.fx.dust(o.position, 1.0)
	u.battle.snd("snap" if big else "screech", u.position, 0.9)
	o.hurt(30.0 if big else float(u.wpn.dmg) * 1.5, dir, 9.0 if big else float(u.wpn.knock) * 1.2, u)
	_end_swoop(u)


static func _end_swoop(u: B3Unit) -> void:
	u._swoop = false
	u.power_t = 0.0
	u._alt = maxf(u.power_alt, 3.0)


## The medic's pulse: heals every teammate close by (and the medic a little).
static func _heal_pulse(u: B3Unit) -> void:
	var b = u.battle
	u._start_act("pulse", 0.6, u.wpn)
	b.fx.ring(u.position + Vector3(0, 0.3, 0), 0.5, HEAL_R, 0.6, Color(0.35, 1.0, 0.45, 0.85))
	b.snd("heal", u.position, 1.0)
	var c := u.center()
	for o: B3Unit in b.units:
		if o.dead or o.is_vehicle() or o.team != u.team or u.is_enemy(o) or o.center().distance_to(c) > HEAL_R:
			continue
		o.hp = minf(o.max_hp, o.hp + (HEAL_SELF if o == u else HEAL_FRIEND))
		o.hurt_t = 0.0        # shows their health bar filling up
		b.fx.heal(o.center() + Vector3(0, 0.5, 0))


## T-Rex roar (or elephant trumpet): enemies close by get pushed back and
## stand stunned for a moment. It doesn't hurt anyone.
static func _roar(u: B3Unit) -> void:
	var b = u.battle
	u._start_act("roar", 1.2, u.wpn)
	var r := ROAR_R * clampf(u.size, 0.6, 2.0)
	b.snd(String(u.def.get("voice", "roar")), u.position, 1.0)
	b.shake(0.3, u.position)
	b.fx.ring(u.position + Vector3(0, 0.6, 0), 1.0, r, 0.55, Color(1.0, 0.95, 0.8, 0.7))
	b.fx.word(u.position + Vector3(0, u.tall + 0.8, 0), "TOOT!" if u.kind == "elephant" else "ROAR!", Color("ffb347"))
	for o: B3Unit in b.units.duplicate():
		if o == u or o.down or o.dead or o.is_vehicle() or not u.is_enemy(o) or u._height_gap(o) > 3.0:
			continue
		var off := u._flat(o.position - u.position)
		var d := off.length()
		if d > r + o.radius:
			continue
		var f := 1.0 - 0.5 * clampf(d / r, 0.0, 1.0)
		o.hurt(0.0, (off / maxf(d, 0.01) + Vector3.UP * 0.3).normalized(), 7.0 * f, u, "blast")
		if is_instance_valid(o) and not o.dead and not o.down:
			o.stun_t = maxf(o.stun_t, 0.6)
			if o.pers == "coward":
				o.fleeing = true


# ----------------------------------------------------- first-person gauges
## ✈️ Where a bomb let go from fighter plane `u` right now would land on the
## ground (Vector3.INF if `u` isn't a plane). It works it out the way the bomb
## flies: it leaves the bomb rack with 95% of the plane's velocity `vel` plus
## 1 m/s down (B3Aircraft._drop_bomb) and falls under the 🌍 Gravity rule
## (B3Proj.gravity("bomb")), a physics step at a time like B3Proj, so the
## marker is right in Moon gravity too. (A friend's copy passes the speed it
## sees its copy of the plane gliding at.) Buildings and trees aren't counted.
static func bomb_landing(u: B3Unit, vel: Vector3) -> Vector3:
	if u == null or not is_instance_valid(u) or not u.is_plane():
		return Vector3.INF
	var vr := u.rig as B3VRig
	var p0: Vector3 = vr.bomb_node.global_position if vr != null and vr.bomb_node != null else u.global_position + Vector3(0, 0.4, 0)
	var v0 := vel * 0.95 + Vector3(0, -1.0, 0)
	var g := B3Proj.gravity("bomb")
	var h := 1.0 / maxf(1.0, float(Engine.physics_ticks_per_second))
	var w = u.battle.world
	# B3Proj takes off g*h from the speed and then moves, every step: after
	# time t that's p0 + v0*t - g*t*(t + h)/2 down. Coarse steps find where it
	# goes under the ground, then halving narrows it down.
	var t0 := 0.0
	var t1 := 0.0
	var found := false
	for i in 160:
		t1 = t0 + 0.1
		var q := p0 + v0 * t1 - Vector3(0, 0.5 * g * t1 * (t1 + h), 0)
		if q.y <= float(w.height_at(q.x, q.z)):
			found = true
			break
		t0 = t1
	if not found:
		return Vector3.INF
	for i in 7:
		var tm := (t0 + t1) * 0.5
		var qm := p0 + v0 * tm - Vector3(0, 0.5 * g * tm * (tm + h), 0)
		if qm.y <= float(w.height_at(qm.x, qm.z)):
			t1 = tm
		else:
			t0 = tm
	var hit := p0 + v0 * t1 - Vector3(0, 0.5 * g * t1 * (t1 + h), 0)
	return Vector3(hit.x, float(w.height_at(hit.x, hit.z)), hit.z)


## The plane's bomb is loaded (its model shows it under the plane; a
## friend's copy gets that from the host too).
static func bomb_ready(u: B3Unit) -> bool:
	var vr: B3VRig = null
	if u != null and is_instance_valid(u):
		vr = u.rig as B3VRig
	return vr != null and vr.bomb_node != null and vr.bomb_node.visible


## The fighter plane's throttle, 0..1 (W/S). A friend's copy works it out
## from how fast the propeller spins, which follows the throttle.
static func throttle_of(u: B3Unit) -> float:
	if u == null or not is_instance_valid(u) or not (u is B3Aircraft):
		return 0.0
	var a := u as B3Aircraft
	if u.battle != null and u.battle.puppet:
		return clampf((a.rotor - 0.55) / 0.45, 0.0, 1.0)
	return clampf(a.throttle, 0.0, 1.0)


## How high `u` is over the ground under it (m).
static func altitude_of(u: B3Unit) -> float:
	if u == null or not is_instance_valid(u):
		return 0.0
	var p := u.global_position
	return maxf(0.0, p.y - float(u.battle.world.height_at(p.x, p.z)))

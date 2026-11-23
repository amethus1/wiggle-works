class_name B3Unit
extends RigidBody3D
## One fighter: soldier, animal or dinosaur. While standing it is a single
## upright physics body (rotation locked) steered by a small brain; its model
## (B3Rig) is animated by code. A big hit turns it into a B3Ragdoll; if it
## still has health it climbs back up once the ragdoll stops tumbling.

static var _pmat: PhysicsMaterial = null
static var _next_uid := 0

const MASK := B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_PROP | B3Defs.L_SCENERY
const LAUNCH := 6.5       # knock speed (after stability) that turns a unit into a ragdoll
const MELEE_UP := 1.0     # melee hits and charges reach about this far over your head (or under your feet)
const FORM_R := 4.5       # shield walls and musket lines keep in line with mates this close (_formation)
const FORM_GAP := 1.7     # ...a loose line: about this far apart, not a huddle
const COVER_R := 7.0      # a shooter under fire runs to cover no further than this (_seek_cover)
const LOS_EVERY := 0.4    # looks for a clear shot (rockets, tank shells) at most this often (clear_shot)

var battle = null
var kind := ""
var def: Dictionary = {}
var wpn: Dictionary = {}
var melee: Dictionary = {}
var act_w: Dictionary = {}
var team := "red"
var pers := "attack"
var pers_choice := "auto"
var hp := 100.0
var max_hp := 100.0
var speed := 4.0
var armor := 0.0
var size := 1.0
var radius := 0.3
var tall := 1.9
var aim_y := 1.2
var stab := 1.0
var flying := false
var heals := false
var rig: B3Rig = null
var disc: MeshInstance3D = null
var bar: MeshInstance3D = null
var laser: MeshInstance3D = null
var home := Vector3.ZERO
var target: B3Unit = null
var ally: B3Unit = null
var down := false
var dead := false
var ragdoll: B3Ragdoll = null
var down_t := 0.0
var facing := 0.0
var want := Vector3.ZERO
var look := Vector3.ZERO
var sep := Vector3.ZERO
var think_t := 0.0
var cd := 0.0
var act := ""
var act_t := 0.0
var act_len := 0.0
var act_fired := false
var burst := 0
var stuck_t := 0.0
var side_t := 0.0
var side_dir := Vector3.ZERO
var wander_t := 0.0
var wander_to := Vector3.ZERO
var fleeing := false
var hurt_t := 99.0
var burn_t := 0.0
var stun_t := 0.0
var charge_t := 0.0
var charge_cd := 1.0
var charge_dir := Vector3.ZERO
var charge_hit := {}
var voice_t := 0.0
var cheer := false
var uid := 0
var kills := 0
var held := false
var player := false              # steered by a person (see B3Player); `ctl` holds their controls
var ctl: B3Ctl = null
var size_mult := 1.0             # Toy Box size (tiny .. huge); set before setup()
# right-click powers while someone plays it (B3Player.power)
var shield_up := false           # shield held up (blocks better from the front; friends see it)
var power_cd := 0.0              # until the power can be used again
var power_len := 1.0             # ...out of this long
var power_t := 0.0               # a charge or swoop you started still going
var power_at := Vector3.ZERO     # where a swoop dives to
var power_alt := 6.0             # the height to climb back to after a swoop
var king := false                # 👑 a team's King (B3Modes, Defend the King): wears a crown
var routed := false              # 🏳️ its King fell: running off home, arms waving (B3Modes._rout)
var grid_i := 0                  # its place in battle.units (B3Battle's fighters' map)
var rng := RandomNumberGenerator.new()
var _hz_t := 0.0
var _spd := 0.0
var _grounded := true
var _swoop := false
var _alt := 6.0
var _cheer_t := 0.0
var _heal_fx := 0.0
var _burn_fx := 0.0
var _bar_hp := -1.0
var _turn := 9.0
var _power_fx := 0.0
var _block_t := 0.0
var _steady := false
var _world: B3World = null       # battle.world (typed, for speed)
# tactics (see _tactics)
var _form := ""                  # keeps a loose line with its mates: "shield" (shield wall), "line" (musket volleys) or ""
var _form_v := Vector3.ZERO      # ...a push sideways, to keep that spacing
var _form_k := 1.0               # ...and how fast to walk to stay in line (slower ahead of it, faster behind)
var _los_t := -99.0              # (battle time) when it last looked for a clear shot (clear_shot)
var _los_uid := -1               # ...at which enemy
var _los_ok := true              # ...and whether it had one
var _fire_t := 99.0              # seconds since it was last shot at or blasted (cover)
var _cover := Vector3.ZERO       # the spot behind cover it's running to (or holding)
var _cover_on := false
var _cover_next := 0.0           # (battle time) when to look for cover again
var _hack: B3Piece = null        # the post it's chopping to bring down the tower an enemy stands on (_chop)
var _hacking := false            # this swing is at _hack


static func unit_pmat() -> PhysicsMaterial:
	if _pmat == null:
		_pmat = PhysicsMaterial.new()
		_pmat.friction = 0.0
		_pmat.bounce = 0.0
	return _pmat


func setup(b, k: String, t: String, p: String, seed_: int) -> void:
	battle = b
	_world = b.world
	kind = k
	team = t
	rng.seed = seed_
	_next_uid += 1
	uid = _next_uid
	def = B3Defs.unit_def(k)
	wpn = B3Defs.weapon(String(def.weapon))
	if String(wpn.type) == "melee":
		melee = wpn
	else:
		melee = B3Defs.weapon("bash" if String(def.body) == "human" else "bite")
	if bool(def.get("bayonet", false)):
		melee = B3Defs.weapon("bayonet")
	act_w = wpn
	max_hp = float(def.hp)
	hp = max_hp
	speed = float(def.speed) * rng.randf_range(0.93, 1.07)
	armor = float(def.armor)
	size = float(def.size)
	stab = float(def.stab)
	flying = bool(def.get("flying", false))
	heals = bool(def.get("heals", false))
	set_personality(p)
	mass = float(def.mass)
	if size_mult != 1.0:
		# bigger fighters are tougher, heavier and harder to knock over
		size *= size_mult
		max_hp *= size_mult * size_mult
		hp = max_hp
		mass *= size_mult * size_mult * size_mult
		stab *= size_mult
		speed *= clampf(sqrt(size_mult), 0.75, 1.35)
	lock_rotation = true
	can_sleep = false
	physics_material_override = unit_pmat()
	collision_layer = B3Defs.L_UNIT
	collision_mask = MASK
	gravity_scale = 0.0 if flying else 1.6
	_make_rig()
	_turn = clampf(11.0 / sqrt(maxf(1.0, radius * 2.5)), 2.5, 11.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(tall * (0.55 if flying else 1.0), radius * 2.0 + 0.02)
	cs.shape = cap
	cs.position.y = cap.height * 0.5 + 0.02
	add_child(cs)
	disc = MeshInstance3D.new()
	disc.mesh = B3Mats.cyl(1.0, 1.0, 0.02, 20)
	disc.material_override = B3Mats.flat(Color(B3Defs.team_col(team), 0.42))
	disc.scale = Vector3(radius * 1.35 + 0.1, 1.0, radius * 1.35 + 0.1)
	disc.position.y = 0.05
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	bar = MeshInstance3D.new()
	bar.mesh = B3Mats.quad(Vector2(0.9, 0.13))
	bar.material_override = B3Mats.shader_mat("hpbar")
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position.y = tall + 0.35
	bar.scale = Vector3.ONE * clampf(sqrt(size * radius * 3.0), 1.0, 2.2)
	bar.visible = false
	bar.set_instance_shader_parameter("team", B3Defs.team_col(team))
	add_child(bar)
	think_t = rng.randf() * 0.3
	_alt = rng.randf_range(5.5, 7.5)
	voice_t = rng.randf_range(0.0, 2.0)
	if b is Node:
		B3Fire.of(b)      # (🔥 the battle's fire keeper: wood and trees catch fire)


func _make_rig() -> void:
	rig = B3Rig.new()
	rig.size_mult = size_mult
	rig.build(kind, team, rng)
	add_child(rig)
	rig.rotation.y = facing
	radius = rig.radius
	tall = rig.height
	aim_y = rig.reach_y
	if king:
		rig.add_crown()      # (it's rebuilt after getting up, or changing team)


## 👑 Makes this fighter its team's King (B3Modes): a crown, and `hp_k` times
## the health. A friend's copy (👥) just gets the crown (hp_k 1): its health
## comes from the host.
func make_king(hp_k := 1.0) -> void:
	if king:
		return
	king = true
	if hp_k != 1.0:
		max_hp *= hp_k
		hp = max_hp
		stab *= 1.6       # harder to knock over, too
	if rig:
		rig.add_crown()
	if bar:
		bar.position.y = tall + 0.95      # the health bar floats over the crown


func set_personality(p: String) -> void:
	pers_choice = p
	pers = String(def.pers) if p == "auto" or p == "" else p
	fleeing = false
	target = null
	_form = _form_group()


## Who keeps in a loose line with their mates instead of a crowd: people
## with a shield and a hand weapon (a shield wall) and musket men (volley
## ranks). Not when they're berserk, scared or peaceful.
func _form_group() -> String:
	if String(def.get("body", "")) != "human" or pers == "berserk" or pers == "coward" or pers == "peaceful":
		return ""
	if wpn.has("volley"):
		return "line"
	if def.get("shield", false) and String(wpn.get("type", "")) == "melee":
		return "shield"
	return ""


func set_team(t: String) -> void:
	if t == team or dead:
		return
	team = t
	target = null
	battle.foes_changed()
	disc.material_override = B3Mats.flat(Color(B3Defs.team_col(team), 0.42))
	bar.set_instance_shader_parameter("team", B3Defs.team_col(team))
	if rig and not down:
		rig.queue_free()
		_make_rig()


func center() -> Vector3:
	if down and ragdoll and is_instance_valid(ragdoll):
		return ragdoll.center()
	return position + Vector3(0, aim_y, 0)


func forward() -> Vector3:
	return Vector3(sin(facing), 0, cos(facing))


## Where the first-person camera sits while someone plays this fighter: at
## its eyes, looking where the mouse points.
func eye_xform(c: B3Ctl) -> Transform3D:
	var p := get_global_transform_interpolated().origin
	if down and ragdoll and is_instance_valid(ragdoll):
		p = ragdoll.center() + Vector3(0, 0.4, 0)
	else:
		p += Vector3(0, tall * 0.9, 0) + forward() * radius * 0.6
	return Transform3D(Basis.from_euler(Vector3(c.look_pitch, c.look_yaw + PI, 0.0)), p)


func is_enemy(u: B3Unit) -> bool:
	if u.team != team:
		return true
	if team == "wild":
		return u.kind != kind
	return false


## What sort of unit this is, for code that treats them differently. Plain
## fighters say no to all of these; B3Vehicle (tanks, jeeps, cars, guns) and
## B3Aircraft (helicopters and fighter planes) say yes to theirs.
func is_vehicle() -> bool:
	return false


## A helicopter or a fighter plane (B3Aircraft).
func is_aircraft() -> bool:
	return false


## A fighter plane (not a helicopter).
func is_plane() -> bool:
	return false


## An aircraft that's been shot down and is on its way to the ground.
func going_down() -> bool:
	return false


# ------------------------------------------------------------------ physics
func _physics_process(dt: float) -> void:
	if dt <= 0.0 or dead:
		return
	if down:
		_down_tick(dt)
		return
	hurt_t += dt
	_fire_t += dt
	cd -= dt
	voice_t -= dt
	stun_t -= dt
	charge_cd -= dt
	power_cd -= dt
	_block_t -= dt
	var p := position
	if p.y < -20.0 or absf(p.x) > B3Defs.BOUNDS + 10.0 or absf(p.z) > B3Defs.BOUNDS + 10.0:
		battle.remove_unit(self, false)
		return
	_hazards(dt)
	if dead or down:
		return
	if burn_t > 0.0:
		burn_t -= dt
		hp -= dt * 7.0 * _env_share(true)
		_burn_fx -= dt
		if _burn_fx <= 0.0:
			_burn_fx = 0.12
			battle.fx.flame(p + Vector3(rng.randf_range(-0.2, 0.2), aim_y + rng.randf_range(-0.3, 0.4), rng.randf_range(-0.2, 0.2)))
		if hp <= 0.0:
			_ko(Vector3.UP * 2.0, null)
			return
	if act != "":
		act_t += dt
		_act_update()
	if held:
		want = Vector3.ZERO
	elif player:
		B3Player.control(self, dt)
	elif battle.fighting:
		think_t -= dt
		if think_t <= 0.0:
			think_t = battle.think_period + rng.randf() * 0.12
			_think()
		_decide(dt)
	else:
		want = Vector3.ZERO
		look = Vector3.ZERO
	_move(dt)


func _move(dt: float) -> void:
	var v := linear_velocity
	var p := position
	var gh := _world.height_at(p.x, p.z)
	# on the ground, or standing still on something (a tower, a crate). Just
	# moving slowly up or down isn't enough: that's the top of every jump.
	var gap: float = p.y - gh
	_grounded = flying or gap < 0.2 or (absf(v.y) < 0.9 and _feet_on_something(0.25))
	var ctrl := 1.0 if _grounded else 0.12
	if stun_t > 0.0:
		ctrl *= 0.12
	var accel := 24.0 if not flying else 12.0
	if charge_t > 0.0:
		accel = 30.0
	var hv := Vector3(v.x, 0.0, v.z)
	hv = hv.move_toward(want * battle.r_speed, accel * ctrl * dt)
	var vy := v.y
	if flying:
		vy = lerpf(vy, clampf((gh + _alt - p.y) * 2.2, -10.0, 7.0), minf(1.0, dt * 4.0))
	linear_velocity = Vector3(hv.x, vy, hv.z)
	_spd = hv.length()
	var f := look
	if f == Vector3.ZERO and want.length_squared() > 0.3:
		f = want
	if f != Vector3.ZERO:
		facing = rotate_toward(facing, atan2(f.x, f.z), dt * _turn)
	if rig and rig.rotation.y != facing:
		rig.rotation.y = facing      # (setting it moves every part of the model: only when it changed)


func _is_grounded_now() -> bool:
	return _grounded


## True if something solid (a building, a crate, a rock, another fighter) is
## right under its feet, no more than `below` metres down.
func _feet_on_something(below: float) -> bool:
	var hit: Dictionary = battle.raycast(position + Vector3(0, 0.3, 0), position - Vector3(0, below, 0), MASK, [get_rid()])
	return not hit.is_empty()


# -------------------------------------------------------------------- brain
func _think() -> void:
	if not battle.grid_on():
		_think_everyone()
		_tactics()
		return
	var my := position
	# keep a little apart from anyone standing right next to us
	var sx := 0.0
	var sz := 0.0
	for u: B3Unit in battle.units_near(my, radius + 0.45, 1.0):
		if u == self or u.down or u.dead:
			continue
		var dx := u.position.x - my.x
		var dz := u.position.z - my.z
		var d2 := dx * dx + dz * dz
		var rr := radius + u.radius + 0.45
		if d2 < rr * rr and d2 > 0.0001:
			var d := sqrt(d2)
			var push := (rr - d) / rr
			sx -= dx / d * push
			sz -= dz / d * push
	sep = Vector3(sx, 0.0, sz)
	# a medic: the nearest hurt teammate (closer than 22 m)
	var hurt_u: B3Unit = null
	if heals:
		var hd := 22.0 * 22.0
		for u: B3Unit in battle.units_near(my, 22.0):
			if u == self or u.down or u.dead or is_enemy(u) or u.team != team or u.hp >= u.max_hp * 0.92:
				continue
			var dx := u.position.x - my.x
			var dz := u.position.z - my.z
			var d2 := dx * dx + dz * dz
			if d2 < hd or (d2 == hd and hurt_u != null and u.grid_i < hurt_u.grid_i):
				hd = d2
				hurt_u = u
	var best := _nearest_enemy(my)
	if best != target:
		target = best
		if target and voice_t <= 0.0 and pers != "peaceful":
			_voice()
	ally = hurt_u
	_tactics()


## The enemy to go after: the nearest one anywhere on the field (or, for a
## guard, near its post), with the one we've already got counting a bit
## closer and, for fighters that can't reach up, ones in the air a lot further
## (see _enemy_score). Searches the fighters' map outwards from `my` square
## by square and stops as soon as nobody further out could beat the best so
## far. Equal scores go to the fighter first in `battle.units`, as if every
## fighter had been looked at in turn.
func _nearest_enemy(my: Vector3) -> B3Unit:
	var guard := pers == "defend"
	var guard_r := guard_radius()
	var melee_only := String(wpn.type) == "melee" or pers == "berserk"
	var best: B3Unit = null
	var bd := 1e18
	var rings: int = battle.grid_rings(my)
	var pool: Array[B3Unit]
	if guard or rings < 0:
		pool = battle.units_near(home, guard_r) if guard else battle.everyone()
		for u in pool:
			var s := _enemy_score(u, my, guard, guard_r, melee_only)
			if s >= 0.0 and (s < bd or (s == bd and u.grid_i < best.grid_i)):
				bd = s
				best = u
		return best
	# start from the enemy we've got: only someone closer can beat it
	if target != null and is_instance_valid(target):
		var s0 := _enemy_score(target, my, false, 0.0, melee_only)
		if s0 >= 0.0:
			bd = s0
			best = target
	if best == null and not battle.foes_standing(self):
		return null       # (nobody to find)
	var cap: int = battle.grid_ring_cap()
	var ring := 0
	while ring <= rings:
		if ring > 0:
			var lb := (ring - 1) * B3Grid.CELL
			if lb * lb > bd:
				break      # (only the one we've got scores lower than its distance)
		var all := ring > cap
		pool = battle.units if all else battle.grid_ring(my, ring)
		for u in pool:
			var s := _enemy_score(u, my, false, 0.0, melee_only)
			if s >= 0.0 and (s < bd or (s == bd and u.grid_i < best.grid_i)):
				bd = s
				best = u
		if all:
			break
		ring += 1
	return best


## How much `u` is worth going after (lower is better: its distance squared,
## less for the enemy we've got, more for one we can't reach: in the air, or
## up on a tower out of a sword's reach), or -1 if it isn't an enemy we'd go after.
func _enemy_score(u: B3Unit, my: Vector3, guard: bool, guard_r: float, melee_only: bool) -> float:
	if u == self or u.down or u.dead or not is_enemy(u):
		return -1.0
	if guard:
		var hx := u.position.x - home.x
		var hz := u.position.z - home.z
		if hx * hx + hz * hz > guard_r * guard_r:
			return -1.0
	var dx := u.position.x - my.x
	var dz := u.position.z - my.z
	var score := dx * dx + dz * dz
	if u == target:
		score *= 0.55
	if u.flying and melee_only and not flying:
		score = score * 4.0 + 400.0
	elif melee_only and not flying and u.position.y - my.y > tall + MELEE_UP + 0.5 and _high_above(u, my):
		score = score * 4.0 + 400.0
	return score


## True if `u` stands up on a building (a tower) too high over a fighter at
## `my` for its sword or claws to reach (see _height_gap), not just higher up
## the same hill. Fighters that only hit up close go after someone else first,
## and if there's nobody else they chop at the tower's legs (_chop).
func _high_above(u: B3Unit, my: Vector3) -> bool:
	return u.position.y - my.y > tall + MELEE_UP + 0.5 and u.position.y - _world.height_at(u.position.x, u.position.z) > 1.2


## _think when there's no fighters' map (a small battle): one look at every
## fighter for all three (neighbours, enemy, friend to heal).
func _think_everyone() -> void:
	var my := position
	var best: B3Unit = null
	var bd := 1e18
	var hurt_u: B3Unit = null
	var hd := 1e18
	var sx := 0.0
	var sz := 0.0
	var guard := pers == "defend"
	var guard_r := guard_radius()
	var melee_only := String(wpn.type) == "melee" or pers == "berserk"
	for u: B3Unit in battle.units:
		if u == self or u.down:
			continue
		var dx := u.position.x - my.x
		var dz := u.position.z - my.z
		var d2 := dx * dx + dz * dz
		var rr := radius + u.radius + 0.45
		if d2 < rr * rr and d2 > 0.0001:
			var d := sqrt(d2)
			var push := (rr - d) / rr
			sx -= dx / d * push
			sz -= dz / d * push
		if is_enemy(u):
			if guard:
				var hx := u.position.x - home.x
				var hz := u.position.z - home.z
				if hx * hx + hz * hz > guard_r * guard_r:
					continue
			var score := d2
			if u == target:
				score *= 0.55
			if u.flying and melee_only and not flying:
				score = score * 4.0 + 400.0
			elif melee_only and not flying and u.position.y - my.y > tall + MELEE_UP + 0.5 and _high_above(u, my):
				score = score * 4.0 + 400.0
			if score < bd:
				bd = score
				best = u
		elif heals and u.team == team and u.hp < u.max_hp * 0.92:
			if d2 < hd:
				hd = d2
				hurt_u = u
	sep = Vector3(sx, 0.0, sz)
	if best != target:
		target = best
		if target and voice_t <= 0.0 and pers != "peaceful":
			_voice()
	ally = hurt_u if hd < 22.0 * 22.0 else null


## 🚩 King of the Hill (B3Modes): with no enemy close by (`dist` to the
## target), walk (or drive) to the glowing circle, or stand in it. Sets `want`
## (and `look` for fighters who'd rather face the way they walk) and returns
## true; false if it should just fight as usual. Fighters you set to 🛡️
## Defend (and a King's guards) stay at their posts; ones that guard by
## nature (hoplites, elephants, stegosaurs...) guard the hill instead.
## 🌊 In Wave Defense the attackers head for the 🚩 Fort Keep (_siege).
func _hill_pull(dist: float, spd: float) -> bool:
	var m = battle.modes
	if m == null:
		return false
	if bool(m.siege) and team == "blue":
		return _siege(m, dist, spd)
	if not bool(m.hill_on) or pers_choice == "defend" or pers == "peaceful" or flying:
		return false
	if pers == "defend":
		home = m.hill_pos      # (its post is the hill now)
	if dist < 10.0:
		return false      # an enemy close by: fight it
	var hp_: Vector3 = m.hill_pos
	var hr: float = m.hill_r
	var to := _flat(hp_ - position)
	var d := to.length()
	if d > hr * 0.55:
		want = to / maxf(d, 0.001) * spd
		if String(wpn.type) == "melee" or dist == INF:
			look = Vector3.ZERO
	else:
		want = Vector3.ZERO      # hold the hill
	return true


## 🌊 An attacker with no defender close by (`dist` to its target) heads for
## the 🚩 Fort Keep and bashes it (B3Modes does the damage, _siege_tick).
## Fliers circle over it. False if there's a defender to fight first.
func _siege(m, dist: float, spd: float) -> bool:
	if dist < B3Modes.SIEGE_NEAR:
		return false
	var kp: Vector3 = m.keep_pos
	var to := _flat(kp - position)
	var d := to.length()
	var dir := to / maxf(d, 0.001)
	var stand := B3Modes.KEEP_R + radius + (0.6 if not flying else 3.0)
	if d > stand:
		want = dir * spd
		if String(wpn.type) == "melee" or dist == INF:
			look = Vector3.ZERO
		return true
	if flying:
		want = Vector3(-dir.z, 0, dir.x) * speed * 0.5      # round and round it
		return true
	want = Vector3.ZERO
	look = dir
	if cd <= 0.0 and act == "" and _facing_ok(dir) and String(def.body) != "vehicle":
		_start_act("attack", clampf(float(melee.cd) * 0.6, 0.25, 0.75), melee)
		cd = float(melee.cd)
	return true


func guard_radius() -> float:
	var r := 9.0
	if String(wpn.type) != "melee":
		r = float(wpn.range) + 2.0
	return r


func _voice() -> void:
	voice_t = rng.randf_range(6.0, 11.0)
	var v := String(def.get("voice", ""))
	if v == "":
		return
	if kind == "trex" and act == "" and _grounded:
		_start_act("roar", 1.3, wpn)
		battle.shake(0.25, position)
		for u: B3Unit in battle.units:
			if u.pers == "coward" and is_enemy(u) and u.position.distance_to(position) < 14.0:
				u.fleeing = true
	battle.snd(v, position, 1.0 if size > 1.5 or kind == "trex" else 0.7)


func _decide(dt: float) -> void:
	want = Vector3.ZERO
	look = Vector3.ZERO
	if cheer:
		_cheer(dt)
		return
	if charge_t > 0.0:
		_charging(dt)
		return
	if act == "heal" and not (heals and ally and is_instance_valid(ally) and not ally.down and not ally.dead):
		act = ""
	if act == "roar" or act == "throw" or act == "aim" or act == "bow":
		if target and is_instance_valid(target):
			look = _flat(target.position - position).normalized()
		return
	if pers == "coward" and hp < max_hp * 0.5:
		fleeing = true
	if burn_t > 0.0 and pers != "berserk":
		if wander_t <= 0.0 or wander_to == Vector3.ZERO:
			wander_to = position + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
			wander_t = 0.6
		wander_t -= dt
		want = _flat(wander_to - position).normalized() * speed * 1.2
		_unstick(dt)
		return
	if pers == "peaceful":
		if hurt_t < 2.5 and target and is_instance_valid(target):
			_flee(dt)
		else:
			_wander(dt, 0.45)
		return
	if heals and ally and is_instance_valid(ally) and not ally.down and not fleeing:
		var threat := target != null and is_instance_valid(target) and position.distance_to(target.position) < 5.0
		if not threat:
			_heal(dt)
			return
	if fleeing:
		_flee(dt)
		return
	if target == null or not is_instance_valid(target) or target.down or target.dead:
		target = null
		if _hill_pull(INF, speed):
			want = _safe(want + sep * speed * 0.9)
			_unstick(dt)
		elif pers == "defend":
			_go_home()
		elif battle.enemies_left(self):
			_wander(dt, 0.25)
		return
	if flying:
		_fly(dt)
		return
	var w := melee if pers == "berserk" else wpn
	var to := _flat(target.position - position)
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	if bool(def.get("bayonet", false)) and dist < radius + target.radius + 2.0:
		w = melee         # too close to shoot: stab with the bayonet
	var reach := _reach(w, target)
	var ranged := String(w.type) != "melee"
	look = dir
	var spd := speed * (1.4 if pers == "berserk" else 1.0)
	if _hill_pull(dist, spd):
		# 🚩 off to the hill (or holding it), shooting anyone in range on the way
		want = _safe(want + sep * speed * 0.9)
		_unstick(dt)
		if dist <= reach and cd <= 0.0 and act == "" and _facing_ok(dir) and _volley_ok(w) and _shot_clear(w):
			_hacking = false
			_attack(w)
		return
	if not ranged and _hack != null and _high_above(target, position) and _chop(dt, w, spd):
		return      # 🪓 can't reach it up there: chop the tower's legs
	if not ranged and dist < 7.0 and String(def.body) == "rider" and _bayonet_wall(target):
		# horses shy away from a hedge of bayonets: ride round it instead
		var round_dir := Vector3(-dir.z, 0, dir.x) * (1.0 if uid % 2 == 0 else -1.0)
		want = _safe((round_dir + dir * (0.25 if dist > 5.0 else -0.6)).normalized() * spd * 0.8 + sep * speed * 0.9)
		look = Vector3.ZERO
		_unstick(dt)
		return
	if ranged and pers == "attack":
		# charge in, shooting on the way
		if dist > maxf(3.0, reach * 0.4):
			want = dir * spd
		if _los_blocked():
			want = _flank(dir, spd)       # a wall in the way of the rocket: go round it
	elif ranged:
		var near := maxf(3.5, reach * 0.35)
		if _cover_on:
			# 🧱 under fire: get behind the sandbags (or low wall) and shoot from there
			var tc := _flat(_cover - position)
			if tc.length() > 0.45:
				want = tc.normalized() * spd
		elif dist > reach * 0.9:
			want = dir * spd
		elif dist < near and pers != "defend":
			want = -dir * spd * 0.75
		else:
			var side := Vector3(-dir.z, 0, dir.x)
			want = side * sin(battle.time * 0.7 + uid) * 0.6
		if _los_blocked():
			want = _flank(dir, spd)
	else:
		if dist > reach * 0.8:
			want = dir * spd
		if bool(def.get("charge", false)) and charge_cd <= 0.0 and dist > 5.0 and dist < 18.0 and _grounded and act == "" and not (String(def.body) == "rider" and _bayonet_wall(target)):
			_start_charge(dir)
			return
		if bool(def.get("pounce", false)) and cd <= 0.0 and dist > 2.5 and dist < 7.5 and _grounded and act == "":
			_pounce(dir)
			return
	if pers == "defend":
		var off := _flat(position - home)
		if off.length() > guard_radius() + 1.5 and dist > reach:
			_go_home()
			return
	if _form != "" and dist > 6.0:
		# 🛡️ a shield wall or a musket line: keep in a loose line with the mates
		want = want * _form_k + _form_v * speed * 0.7
	want += sep * speed * 0.9
	want = _safe(want)
	_unstick(dt)
	if dist <= reach and cd <= 0.0 and act == "" and _facing_ok(dir) and _volley_ok(w) and _shot_clear(w) \
			and (ranged or not _high_above(target, position)):
		_hacking = false
		_attack(w)


## Horses won't charge into a steady line of bayonets (why squares worked):
## `u` has a bayonet and at least two friends with bayonets right beside it.
func _bayonet_wall(u: B3Unit) -> bool:
	if not bool(u.def.get("bayonet", false)):
		return false
	var n := 0
	for o: B3Unit in battle.units_near(u.position, 2.5):
		if o != u and not o.dead and o.team == u.team and not o.down and bool(o.def.get("bayonet", false)) and o.position.distance_squared_to(u.position) < 6.25:
			n += 1
			if n >= 2:
				return true
	return false


## Muskets fire in volleys: everyone on a team who's loaded shoots in the same
## short window, every `volley` seconds.
func _volley_ok(w: Dictionary) -> bool:
	if not w.has("volley"):
		return true
	var period := float(w.volley)
	return fposmod(battle.time + float(absi(team.hash()) % 97) * 0.31, period) < 0.8


# ------------------------------------------------------------------ tactics
## The thinking behind keeping in line, taking cover and chopping a tower
## down (B3Unit._think, every quarter second or so). Each part is only for
## the fighters that do it, and the searches are spread out in time.
func _tactics() -> void:
	if target == null or not is_instance_valid(target) or player:
		_cover_on = false
		_form_v = Vector3.ZERO
		_form_k = 1.0
		_hack = null
		return
	if _form != "":
		_formation()
	if _wants_cover():
		_seek_cover()
	elif _cover_on:
		_cover_on = false
	# 🪓 an enemy up on a tower that a sword can't reach: chop its legs
	var melee_only := String(wpn.type) == "melee" or pers == "berserk"
	if melee_only and not flying and not target.flying and String(def.body) != "vehicle" and _high_above(target, position) \
			and _flat(target.position - position).length() < 9.0:
		if _hack == null or not is_instance_valid(_hack) or _hack.is_queued_for_deletion():
			_hack = _find_hack()
	else:
		_hack = null


## 🛡️ Shield walls and musket lines (_form) keep a loose line while they
## advance: no closer than FORM_GAP to a mate (_form_v pushes apart), and
## nobody running far ahead or lagging behind the mates around it (_form_k).
## In the thick of the fight (closer than 6 m) it's every one for themselves.
func _formation() -> void:
	_form_v = Vector3.ZERO
	_form_k = 1.0
	var my := position
	var tx := target.position.x - my.x
	var tz := target.position.z - my.z
	var dist := sqrt(tx * tx + tz * tz)
	if dist < 6.0:
		return
	tx /= dist
	tz /= dist
	var sx := 0.0
	var sz := 0.0
	var along := 0.0
	var n := 0
	for u: B3Unit in battle.units_near(my, FORM_R):
		if u == self or u.down or u.dead or u.team != team or u._form != _form:
			continue
		var dx := u.position.x - my.x
		var dz := u.position.z - my.z
		var d2 := dx * dx + dz * dz
		if d2 > FORM_R * FORM_R or d2 < 0.0001:
			continue
		n += 1
		along += dx * tx + dz * tz
		if d2 < FORM_GAP * FORM_GAP:
			var d := sqrt(d2)
			var push := (FORM_GAP - d) / FORM_GAP
			sx -= dx / d * push
			sz -= dz / d * push
	if n == 0:
		return
	along /= n
	if along < -1.0:
		_form_k = 0.55          # ahead of the line: wait for the others
	elif along > 1.5:
		_form_k = 1.15          # behind it: catch up
	_form_v = Vector3(sx, 0.0, sz).limit_length(1.0)


## 🧱 Shooters (not the musket lines, which stand in their ranks) that are
## being shot at look for cover.
func _wants_cover() -> bool:
	return _fire_t < 2.5 and not heals and (pers == "ranged" or pers == "defend") and String(def.body) == "human" \
		and String(wpn.type) != "melee" and _form != "line" and not flying


## 🧱 Under fire: the nearest spot behind sandbags, a crate or a low wall
## (cover_points), on the far side from the enemy, that's no more than
## COVER_R away and still in range of it. It looks again at most once a second.
func _seek_cover() -> void:
	var reach := _reach(wpn, target) * 0.95
	if _cover_on and _flat(target.position - _cover).length() > reach:
		_cover_on = false       # the enemy's moved out of range of it
	var now: float = battle.time
	if now < _cover_next:
		return
	_cover_next = now + 1.0
	var pts := cover_points(battle)
	var threat := target.position
	var best := Vector3.ZERO
	var bd := COVER_R
	var found := false
	var gr := guard_radius() + 1.0
	for p in pts:
		if absf(p.x - position.x) > COVER_R or absf(p.z - position.z) > COVER_R:
			continue
		var ax := p.x - threat.x
		var az := p.z - threat.z
		var al := sqrt(ax * ax + az * az)
		if al < 1.0:
			continue
		var off := p.y + radius + 0.3
		var spot := Vector3(p.x + ax / al * off, p.w, p.z + az / al * off)
		var d := _flat(spot - position).length()
		if d >= bd or _flat(threat - spot).length() > reach:
			continue
		if pers == "defend" and _flat(spot - home).length() > gr:
			continue
		bd = d
		best = spot
		found = true
	_cover_on = found
	if found:
		_cover = best


## Every bit of low cover on the field, worked out at most every 2 seconds
## and shared by everyone: [x, half its thickness, z, ground height] for each
## sandbag, crate and building piece from knee to shoulder high (sandbags,
## low walls, earthworks, blocks). Posts, stakes, rails, ramps and tall walls
## don't count.
static func cover_points(b) -> PackedVector4Array:
	var t: float = b.time
	if b.has_meta("ai_cover") and absf(t - float(b.get_meta("ai_cover_t", -99.0))) < 2.0:
		return b.get_meta("ai_cover")
	var pts := PackedVector4Array()
	var w: B3World = b.world
	for s: B3Struct in b.structs:
		if not is_instance_valid(s):
			continue
		for pc in s.pieces:
			if not is_instance_valid(pc) or pc.wedge or maxf(pc.size.x, pc.size.z) < 0.5 or minf(pc.size.x, pc.size.z) < 0.3:
				continue
			var bx := pc.world_aabb()
			var c := bx.get_center()
			var gy := w.height_at(c.x, c.z)
			var top := bx.end.y - gy
			if bx.position.y > gy + 0.5 or top < 0.6 or top > 1.7:
				continue
			pts.append(Vector4(c.x, minf(bx.size.x, bx.size.z) * 0.5, c.z, gy))
	for p: B3Prop in b.props:
		if is_instance_valid(p) and (p.kind == "sandbag" or p.kind == "crate") and not p.is_queued_for_deletion():
			var q := p.global_position
			pts.append(Vector4(q.x, 0.4, q.z, w.height_at(q.x, q.z)))
	b.set_meta("ai_cover", pts)
	b.set_meta("ai_cover_t", t)
	return pts


## Rockets blow up on the first wall in the way: only fire one with a clear
## shot (see clear_shot). Other weapons don't need to look.
func _shot_clear(w: Dictionary) -> bool:
	if String(w.get("proj", "")) != "rocket" or target == null or not is_instance_valid(target):
		return true
	return clear_shot(_muzzle_pos(), target, float(w.get("radius", 3.0)))


## True if nothing solid (a wall, a building, a hill) is between `from` and
## `u` for an exploding shot with blast radius `blast`: a wall right next to
## `u` is fine, the blast still gets it. It looks along the shot at most every
## LOS_EVERY seconds per enemy, and remembers the answer in between.
func clear_shot(from: Vector3, u: B3Unit, blast: float) -> bool:
	var now: float = battle.time
	if u.uid == _los_uid and now - _los_t < LOS_EVERY and now >= _los_t:
		return _los_ok
	_los_uid = u.uid
	_los_t = now
	var aim := u.center()
	var hit: Dictionary = battle.raycast(from, aim, B3Defs.L_TERRAIN | B3Defs.L_STRUCT)
	_los_ok = hit.is_empty() or (hit.position as Vector3).distance_to(aim) < blast * 0.6
	return _los_ok


## It just found a wall between it and its enemy (clear_shot), so it moves to
## get a clear shot instead of firing into the wall.
func _los_blocked() -> bool:
	return not _los_ok and target != null and is_instance_valid(target) and target.uid == _los_uid \
		and battle.time - _los_t < 1.5 and battle.time >= _los_t


## Round the side of whatever's in the way (and a little closer).
func _flank(dir: Vector3, spd: float) -> Vector3:
	var side := Vector3(-dir.z, 0, dir.x) * (1.0 if uid % 2 == 0 else -1.0)
	return (side + dir * 0.4).normalized() * spd * 0.85


## 🪓 The piece of the building its enemy stands on to chop at: the one
## nearest to it that it can reach from the ground (a tower's leg).
func _find_hack() -> B3Piece:
	var tp := target.position
	var hit: Dictionary = battle.raycast(tp + Vector3(0, 0.4, 0), tp - Vector3(0, 8.0, 0), B3Defs.L_STRUCT)
	if hit.is_empty() or not (hit.collider is B3Piece):
		return null
	var st: Variant = (hit.collider as B3Piece).structure
	if st == null or not is_instance_valid(st) or not (st is B3Struct):
		return null
	var best: B3Piece = null
	var bd := INF
	var foot := position.y
	for pc in (st as B3Struct).pieces:
		if not is_instance_valid(pc) or pc.is_queued_for_deletion():
			continue
		var bx := pc.world_aabb()
		if bx.position.y > foot + 1.2 or bx.end.y < foot + 0.4:
			continue      # (not something it can hit standing here)
		var c := bx.get_center()
		var d := Vector2(c.x - position.x, c.z - position.z).length()
		if d < bd:
			bd = d
			best = pc
	return best


## 🪓 Walks up to the tower's leg and hacks at it (the swing lands in
## _melee_hit). False if there's nothing to chop.
func _chop(dt: float, w: Dictionary, spd: float) -> bool:
	if not is_instance_valid(_hack) or _hack.is_queued_for_deletion():
		_hack = null
		return false
	var c := _hack.world_aabb().get_center()
	var to := _flat(c - position)
	var d := to.length()
	var dir := to / maxf(d, 0.001)
	var half := maxf(_hack.size.x, _hack.size.z) * 0.5
	look = dir
	if d > radius + half + 0.5 + float(w.range) * size * 0.4:
		want = _safe(dir * spd + sep * speed * 0.9)
		_unstick(dt)
		return true
	want = sep * speed * 0.5
	if cd <= 0.0 and act == "" and _facing_ok(dir):
		_attack(melee)
		_hacking = true
	return true


## A chop at building piece `pc`: chips of wood fly, and enough of them
## bring it down (B3Battle.break_piece; anything left floating falls).
func _hit_piece(pc: B3Piece, dmg: float) -> void:
	pc.hp -= dmg
	var at := pc.world_aabb().get_center()
	at.y = minf(at.y, position.y + aim_y)
	battle.fx.dust(at, 0.4)
	battle.snd("chop", at, 0.6)
	if pc.hp <= 0.0:
		# it topples over in one piece (chopped through), and whatever it held up falls
		var st: Variant = pc.structure
		battle.break_piece(pc, (_flat(pc.global_position - position).normalized() + Vector3.UP * 0.3) * 3.0, true)
		if st is B3Struct and is_instance_valid(st):
			battle.combat.settle_soon(st as B3Struct)
		_hack = null


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## How far apart two bodies are up and down (0 when they overlap): a sword
## can't reach someone on top of a tower or a helicopter overhead.
func _height_gap(u: B3Unit) -> float:
	var lo := position.y
	var ulo := u.position.y
	return maxf(0.0, maxf(ulo - (lo + tall), lo - (ulo + u.tall)))


func _reach(w: Dictionary, u: B3Unit) -> float:
	var r := float(w.range)
	if String(w.type) == "melee":
		return radius + u.radius + r * size * 0.6
	return r * (1.0 + 0.2 * _high_k(u))


## ⛰️ Shooting down from up high (a tower, a hilltop): 0 on the level, up to 1
## from 5 m or more above `u`. It shoots up to a fifth further (_reach) and
## steadier (_fire_gun, _shoot_proj) from up there.
func _high_k(u: B3Unit) -> float:
	return clampf((position.y - u.position.y - 1.0) / 4.0, 0.0, 1.0)


func _facing_ok(dir: Vector3) -> bool:
	return forward().dot(dir) > 0.75


func _go_home() -> void:
	var to := _flat(home - position)
	if to.length() > 1.2:
		want = to.normalized() * speed * 0.8
		want = _safe(want)
	else:
		look = Vector3.ZERO


func _wander(dt: float, f: float) -> void:
	wander_t -= dt
	if wander_t <= 0.0:
		wander_t = rng.randf_range(1.5, 4.0)
		if rng.randf() < 0.3:
			wander_to = position
		else:
			wander_to = home + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
		if kind == "chicken" and rng.randf() < 0.35:
			wander_t = 0.8
			f = 1.3
			battle.snd("cluck", position, 0.5)
	var to := _flat(wander_to - position)
	if to.length() > 0.6:
		want = to.normalized() * speed * (f if kind != "chicken" else 0.8)
	want = _safe(want + sep * speed * 0.5)
	_unstick(dt)


func _flee(dt: float) -> void:
	var threat: B3Unit = target
	if threat == null or not is_instance_valid(threat):
		return
	var away := _flat(position - threat.position)
	var d := away.length()
	if d > 17.0:
		want = Vector3.ZERO
		look = -away.normalized()
		return
	want = away.normalized() * speed * 1.15
	want = _safe(want + sep * speed * 0.5)
	_unstick(dt)


func _heal(dt: float) -> void:
	var to := _flat(ally.position - position)
	var d := to.length()
	look = to.normalized()
	if d > 2.2:
		want = _safe(look * speed)
		_unstick(dt)
		if act == "heal":
			act = ""
		return
	if act == "":
		_start_act("heal", 0.5, wpn)
	ally.hp = minf(ally.max_hp, ally.hp + 24.0 * dt)
	ally.hurt_t = 0.0
	_heal_fx -= dt
	if _heal_fx <= 0.0:
		_heal_fx = 0.22
		battle.fx.heal(ally.position + Vector3(rng.randf_range(-0.3, 0.3), ally.aim_y + rng.randf_range(0.0, 0.6), rng.randf_range(-0.3, 0.3)))
		if rng.randf() < 0.15:
			battle.snd("heal", position, 0.5)


func _cheer(dt: float) -> void:
	_cheer_t -= dt
	if _cheer_t <= 0.0 and _grounded and not flying:
		linear_velocity.y = 4.0 + rng.randf() * 1.5
		_cheer_t = rng.randf_range(0.7, 1.6)


## Steer around lava/acid and (if not reckless) don't walk off high edges.
func _safe(w: Vector3) -> Vector3:
	if w == Vector3.ZERO or pers == "berserk" or flying:
		return w
	var n := w.normalized()
	for hz in battle.hazards:
		var h: B3Hazard = hz
		var ahead := position + n * (1.6 + radius)
		var dx := ahead.x - h.position.x
		var dz := ahead.z - h.position.z
		var r := h.radius + radius + 0.7
		if dx * dx + dz * dz < r * r:
			var out := _flat(position - h.position).normalized()
			if out == Vector3.ZERO:
				out = Vector3.RIGHT
			var tan := Vector3(-out.z, 0, out.x)
			if tan.dot(n) < 0.0:
				tan = -tan
			return (tan + out * 0.6).normalized() * w.length()
	# walk along the shore rather than into deep water (B3World)
	if not _world.waters.is_empty():
		var dry: Vector3 = _world.steer_dry(position, w, radius)
		if dry != w:
			return dry
	if pers != "attack" and _grounded:
		var gh := _world.height_at(position.x, position.z)
		if position.y - gh > 1.2:
			var ahead2 := position + n * (radius + 0.8)
			var sy: float = battle.surface_y(ahead2 + Vector3(0, 0.5, 0))
			if position.y - sy > 1.3:
				return Vector3.ZERO
	return w


func _unstick(dt: float) -> void:
	if want.length_squared() < 1.0:
		stuck_t = 0.0
		return
	if side_t > 0.0:
		side_t -= dt
		want = (want.normalized() * 0.35 + side_dir).normalized() * want.length()
		return
	if _spd < 0.45:
		stuck_t += dt
	else:
		stuck_t = maxf(0.0, stuck_t - dt)
	if stuck_t > 0.55:
		stuck_t = 0.0
		side_t = rng.randf_range(0.6, 1.1)
		var n := want.normalized()
		side_dir = Vector3(-n.z, 0, n.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		if _grounded and size < 1.6 and radius < 0.8:
			linear_velocity.y = 5.2


# ------------------------------------------------------------------ attacks
func _start_act(a: String, length: float, w: Dictionary) -> void:
	act = a
	act_t = 0.0
	act_len = length
	act_fired = false
	act_w = w


func _attack(w: Dictionary) -> void:
	var ty := String(w.type)
	var bers := pers == "berserk"
	_hacking = false      # (a chop at a tower's leg sets it again: _chop)
	match ty:
		"melee":
			_start_act("attack", clampf(float(w.cd) * 0.6, 0.25, 0.75), w)
			cd = float(w.cd) * (0.75 if bers else 1.0)
			if rig and rig.hold == "fists":
				rig.punch_side = 1 - rig.punch_side
			if float(w.dmg) >= 30.0:
				battle.snd("swing", position, 0.6)
		"gun":
			if w.has("aim"):
				_start_act("aim", float(w.aim), w)
				cd = float(w.cd)
				battle.snd("reload", position, 0.3)
				return
			_fire_gun(w)
		"proj":
			if String(w.proj) == "arrow":
				_start_act("bow", 0.5, w)
			else:
				_start_act("aim", 0.3, w)
			cd = float(w.cd)
		"throw":
			_start_act("throw", 0.75, w)
			cd = float(w.cd)


func _act_update() -> void:
	var k := act_t / maxf(act_len, 0.01)
	match act:
		"attack":
			if not act_fired and k >= 0.5:
				act_fired = true
				_melee_hit(act_w)
		"aim":
			if String(act_w.type) == "gun":
				_update_laser()
			if k >= 1.0:
				_hide_laser()
				act = ""
				if target and is_instance_valid(target) and not target.down:
					if String(act_w.type) == "gun":
						_fire_gun(act_w)
					else:
						_shoot_proj(act_w)
				return
		"bow":
			if k >= 1.0:
				act = ""
				if target and is_instance_valid(target) and not target.down:
					_shoot_proj(act_w)
				return
		"throw":
			if not act_fired and k >= 0.62:
				act_fired = true
				_throw(act_w)
		"pounce":
			if not act_fired:
				var v := _pounce_victim()
				if v != null:
					act_fired = true
					v.hurt(float(wpn.dmg) * 1.5, (_flat(v.position - position).normalized() + Vector3.UP * 0.5).normalized(), 7.0, self)
					battle.snd("slash", position, 0.8)
		"kick", "thrust":
			# right-click powers (B3Player): a kick, a shove or a bayonet stab
			if not act_fired and k >= 0.45:
				act_fired = true
				power_hit(act_w)
		"heal":
			if k >= 1.0:
				act_t = 0.0
			return
	if k >= 1.0:
		act = ""


func _melee_hit(w: Dictionary) -> void:
	var dmg := float(w.dmg)
	var knock := float(w.knock)
	battle.snd(String(w.snd), position, 0.8 if size < 1.5 else 1.0)
	if _hacking:
		_hacking = false
		if _hack != null and is_instance_valid(_hack) and not _hack.is_queued_for_deletion():
			_hit_piece(_hack, dmg * (size if String(def.body) == "human" else 1.0))
		return
	if w.has("aoe"):
		var fwd := forward()
		var reach := float(w.range) * (size if String(def.body) == "human" else 1.0)
		var c := position + fwd * (reach * 0.6 + radius)
		var r := float(w.aoe) * (size if String(def.body) == "human" else 1.0)
		if String(w.anim) == "tail":
			c = position
			r = float(w.aoe) + radius
		var hits: Array[B3Unit] = []
		for u: B3Unit in battle.units_near(c, r, 1.0):
			if _aoe_reaches(u, c, r):
				hits.append(u)
		for u: B3Unit in _in_order(hits):
			if not _aoe_reaches(u, c, r):
				continue      # (knocked down by an earlier hit: a tank blowing up...)
			var d := _flat(u.position - c).length()
			# weaker towards the edge, but never less than that (a big tank
			# whose middle is past the edge still gets hit, not healed)
			var f := clampf(d / r, 0.0, 1.0)
			var dir := (_flat(u.position - position).normalized() + Vector3.UP * 0.7).normalized()
			u.hurt(dmg * (1.0 - 0.35 * f), dir, knock * (1.0 - 0.3 * f), self)
		battle.blast_props(c, r, knock * 0.5)
		battle.fx.dust(c, r)
		battle.shake(float(w.get("shake", 0.1)), c)
		if String(w.anim) == "stomp" or String(w.anim) == "slam":
			battle.snd("stomp", c, 1.0)
		return
	if target == null or not is_instance_valid(target) or target.down:
		return
	var d2 := _flat(target.position - position).length()
	if d2 > _reach(w, target) * 1.35 or _height_gap(target) > MELEE_UP:
		return
	var up := 0.95 if w.has("toss") else 0.35
	var dir2 := (_flat(target.position - position).normalized() + Vector3.UP * up).normalized()
	target.hurt(dmg, dir2, knock * (1.5 if w.has("toss") else 1.0), self)
	if w.has("shake"):
		battle.shake(float(w.shake), position)


## A stomp or tail swipe centred on `c` with radius `r` reaches `u`.
func _aoe_reaches(u: B3Unit, c: Vector3, r: float) -> bool:
	if u == self or u.down or u.dead or not is_enemy(u) or _height_gap(u) > MELEE_UP:
		return false
	return _flat(u.position - c).length() < r + u.radius


## Fighters found on the fighters' map put in `battle.units` order, so hits
## land in the same order as if every fighter had been looked at in turn.
## (Callers test each one again just before hitting it: an earlier hit can
## knock others down, never the other way round.)
func _in_order(near: Array[B3Unit]) -> Array[B3Unit]:
	if near.size() > 1:
		near.sort_custom(func(a: B3Unit, b: B3Unit) -> bool: return a.grid_i < b.grid_i)
	return near


## Who a pounce lands on: its enemy, or (when a person is playing it and
## pounced at a spot) any enemy it reaches.
func _pounce_victim() -> B3Unit:
	if target and is_instance_valid(target) and not target.down and _pounce_reaches(target):
		return target
	if not player:
		return null
	var best: B3Unit = null
	for u: B3Unit in battle.units_near(position, radius + 1.0, 1.0):
		if u != self and not u.dead and not u.down and is_enemy(u) and _pounce_reaches(u) and (best == null or u.grid_i < best.grid_i):
			best = u
	return best


func _pounce_reaches(u: B3Unit) -> bool:
	return center().distance_to(u.center()) < radius + u.radius + 1.0


## A right-click kick, shove or bayonet stab (B3Player powers): hits the
## nearest enemy right in front (no need to have aimed at it) and pushes it
## back a little. Barrels and knocked-over fighters in the way get a nudge.
func power_hit(w: Dictionary) -> void:
	var fwd := forward()
	var best: B3Unit = null
	var bd := INF
	var melee_w := String(w.type) == "melee"
	var far := (radius + float(w.range) * size * 0.6) * 1.2 if melee_w else float(w.range) * 1.2
	for u: B3Unit in battle.units_near(position, far, 1.2 if melee_w else 0.0):
		if u == self or u.down or u.dead or not is_enemy(u) or _height_gap(u) > MELEE_UP:
			continue
		var off := _flat(u.position - position)
		var d := off.length()
		if (d < bd or (d == bd and u.grid_i < best.grid_i)) and d < _reach(w, u) * 1.2 and fwd.dot(off / maxf(d, 0.01)) > 0.25:
			bd = d
			best = u
	battle.blast_props(position + fwd * (radius + 0.7 * size) + Vector3(0, 0.4, 0), 0.9 * size, 4.0)
	if best == null:
		return
	var dir := (_flat(best.position - position).normalized() + Vector3.UP * 0.35).normalized()
	battle.snd(String(w.snd), position, 0.8)
	if w.has("word"):
		battle.fx.word(best.position + Vector3(0, best.tall + 1.2, 0), String(w.word), Color("ffd34d"))      # (above the damage number)
	# a kick from a giant (or a Huge fighter) sends people flying
	best.hurt(float(w.dmg) * size, dir, float(w.knock) * clampf(size, 1.0, 2.5), self)


func _muzzle_pos() -> Vector3:
	if rig and rig.muzzle and is_instance_valid(rig.muzzle):
		return rig.muzzle.global_position
	return position + Vector3(0, aim_y + 0.15, 0) + forward() * (radius + 0.3)


func _fire_gun(w: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var from := _muzzle_pos()
	var aim := target.center()
	var dir := (aim - from).normalized()
	var s := float(w.get("spread", 0.03))
	if player and B3Player.steady(self, ctl):
		s *= 0.1      # a sniper you're holding steady (right-click)
	s *= 1.0 - 0.45 * _high_k(target)      # ⛰️ steadier shooting down from up high
	dir = (dir + Vector3(rng.randf_range(-s, s), rng.randf_range(-s, s) * 0.6, rng.randf_range(-s, s))).normalized()
	var to := from + dir * (float(w.range) * 1.4)
	var hit := shot_ray(from, to)
	var end := to
	if not hit.is_empty():
		end = hit.position
		battle.shot_hit(hit, w, dir, self)
	var tc: Color = w.get("tracer", Color(4, 3, 1))
	battle.fx.tracer(from, end, tc, 0.06 if String(def.weapon) != "sniper" else 0.12)
	battle.fx.muzzle(from, dir)
	if w.has("smoke"):
		musket_smoke(from, dir)
	battle.snd(String(w.snd), from, 0.55 if String(w.snd) == "gun_mg" else 0.75)
	if rig:
		rig.recoil = 1.0
	act = "shoot"
	act_t = 0.0
	act_len = 0.12
	if w.has("burst"):
		burst += 1
		if burst >= int(w.burst):
			burst = 0
			cd = float(w.reload)
		else:
			cd = float(w.cd)
	else:
		cd = float(w.cd) * rng.randf_range(0.9, 1.15)


## Where a bullet from `from` towards `to` hits. Like arrows, bullets fly
## past friends (musket lines fire past their kneeling front rank, a gunner
## past the teammate in front of it): only enemies, walls and things stop them.
func shot_ray(from: Vector3, to: Vector3) -> Dictionary:
	var skip: Array = [get_rid()]
	var hit: Dictionary = battle.raycast(from, to, MASK, skip)
	while skip.size() < 6 and not hit.is_empty() and hit.collider is B3Unit and not is_enemy(hit.collider as B3Unit):
		skip.append((hit.collider as B3Unit).get_rid())
		hit = battle.raycast(from, to, MASK, skip)
	return hit


## A musket's big flash and puff of white smoke.
func musket_smoke(from: Vector3, dir: Vector3) -> void:
	battle.fx.muzzle(from, dir, 2.2)
	var at := from + dir * 0.5
	if rng.randf() < 0.5:
		battle.fx.steam(at, 1.1)
	else:
		battle.fx.poof(at, 0.9)


func _lead(from: Vector3, speed_: float) -> Vector3:
	var aim := target.center()
	var t := from.distance_to(aim) / maxf(speed_, 1.0)
	return aim + Vector3(target.linear_velocity.x, 0, target.linear_velocity.z) * t * 0.7


func _shoot_proj(w: Dictionary) -> void:
	var from := _muzzle_pos()
	var sp := float(w.speed)
	var aim := _lead(from, sp)
	var kind_s := String(w.proj)
	var vel: Vector3
	if kind_s == "arrow":
		var flat := _flat(aim - from)
		var tt := maxf(flat.length() / sp, 0.15)
		vel = B3Proj.lob(from, aim, tt, kind_s)
		var wob := 1.0 - 0.45 * _high_k(target)      # ⛰️ steadier from up high
		vel += Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.5, 0.5)) * wob
	else:
		# rockets and fireballs fly nearly straight: aim a little high for the
		# sag on the way (fireballs don't sag)
		aim.y = target.position.y + 0.3
		vel = B3Proj.lob(from, aim, maxf(from.distance_to(aim) / sp, 0.05), kind_s)
	battle.spawn_proj(kind_s, from, vel, self, w)
	battle.snd(String(w.snd), from, 0.8)
	if kind_s == "rocket":
		battle.fx.muzzle(from, vel.normalized(), 1.8)
		if rig:
			rig.recoil = 1.0


func _throw(w: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var from := position + Vector3(0, aim_y + 0.5, 0) + forward() * 0.3
	var aim := target.position + Vector3(target.linear_velocity.x, 0, target.linear_velocity.z) * 0.6
	var flat := _flat(aim - from)
	var tt := clampf(flat.length() / 9.0, 0.6, 1.5)
	var vel := B3Proj.lob(from, aim, tt, "grenade")
	var p = battle.spawn_proj("grenade", from, vel, self, w)
	p.fuse = tt + 0.5
	battle.snd("swing", from, 0.5)


func _update_laser() -> void:
	if target == null or not is_instance_valid(target):
		return
	_laser_line(_muzzle_pos(), target.center())


## The red aiming laser from `a` to `b`.
func _laser_line(a: Vector3, b: Vector3) -> void:
	if laser == null:
		laser = MeshInstance3D.new()
		laser.mesh = B3Mats.box(Vector3(0.025, 0.025, 1.0))
		laser.material_override = B3Mats.glow(Color(1.0, 0.15, 0.1, 0.8), 3.0)
		laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		battle.fx.add_child(laser)
	var l := a.distance_to(b)
	if l < 0.1:
		return
	laser.visible = true
	laser.global_transform = Transform3D(Basis.looking_at((b - a) / l, Vector3.UP).scaled(Vector3(1, 1, l)), (a + b) * 0.5)


func _hide_laser() -> void:
	if laser:
		laser.visible = false


func _start_charge(dir: Vector3) -> void:
	charge_t = 2.2
	charge_dir = dir
	charge_hit.clear()
	_start_act("charge", 2.2, wpn)
	battle.snd(String(def.get("voice", "charge")), position, 0.9)
	battle.snd("charge", position, 0.8)


func _charging(dt: float) -> void:
	charge_t -= dt
	want = charge_dir * speed * 2.6
	look = charge_dir
	var w := wpn
	var hits: Array[B3Unit] = []
	for u: B3Unit in battle.units_near(position, radius + 0.5, 1.0):
		if _charge_hits(u):
			hits.append(u)
	for u: B3Unit in _in_order(hits):
		if not _charge_hits(u):
			continue
		charge_hit[u.uid] = true
		var dir := (charge_dir + Vector3.UP * 0.8).normalized()
		u.hurt(float(w.get("charge_dmg", 30.0)), dir, float(w.get("charge_knock", 15.0)), self)
		battle.shake(0.15, position)
		battle.snd("thud", position, 0.9)
	battle.blast_props(position + charge_dir * radius, radius + 0.5, 6.0)
	if charge_t <= 0.0 or (charge_t < 1.8 and _spd < 1.0):
		charge_t = 0.0
		act = ""
		charge_cd = rng.randf_range(3.5, 5.5)
		stun_t = 0.25


## A charge runs into `u` (not hit by this charge yet).
func _charge_hits(u: B3Unit) -> bool:
	if u == self or u.down or u.dead or not is_enemy(u) or charge_hit.has(u.uid) or _height_gap(u) > MELEE_UP:
		return false
	return _flat(u.position - position).length() < radius + u.radius + 0.5


func _pounce(dir: Vector3) -> void:
	linear_velocity = dir * 10.5 + Vector3.UP * 4.5
	_start_act("pounce", 0.7, wpn)
	cd = 1.2
	stun_t = 0.5
	battle.snd("screech", position, 0.6)


func _fly(dt: float) -> void:
	var to := _flat(target.position - position)
	var d := to.length()
	var dir := to / maxf(d, 0.001)
	look = dir
	var gh: float = battle.world.height_at(position.x, position.z)
	if cd <= 0.0 and d < 14.0 and act == "":
		_swoop = true
	if _swoop:
		_alt = maxf(0.6, target.position.y - gh + target.aim_y - 0.2)
		want = dir * speed * 1.25
		if center().distance_to(target.center()) < radius + target.radius + 0.8:
			_swoop = false
			_start_act("attack", 0.4, wpn)
			act_fired = true
			var hdir := (dir + Vector3.UP * 0.6).normalized()
			target.hurt(float(wpn.dmg), hdir, float(wpn.knock), self)
			battle.snd("screech", position, 0.7)
			cd = float(wpn.cd)
			_alt = rng.randf_range(5.5, 7.5)
		elif d > 16.0:
			_swoop = false
			_alt = rng.randf_range(5.5, 7.5)
	else:
		_alt = rng.randf_range(5.5, 7.5) if _alt < 3.0 else _alt
		if d < 9.0:
			want = Vector3(-dir.z, 0, dir.x) * speed * 0.9 + dir * 1.0
		else:
			want = dir * speed
	want += sep * speed * 0.5


# --------------------------------------------------------------- damage etc
## dir: push direction (unit vector). knock: push speed for a normal unit.
func hurt(dmg: float, dir: Vector3, knock: float, by: B3Unit = null, how := "hit") -> void:
	if dead:
		return
	dmg = maxf(dmg, 0.0) / battle.r_tough      # Battle Rules: toughness and knockback (a hit never heals)
	knock *= battle.r_knock
	if down:
		var dd := dmg * (1.0 - armor)
		hp -= dd
		if dd > 0.0:
			battle.player_hit(by, self)      # (finishing off a downed enemy shows the hit marker too)
		if ragdoll and is_instance_valid(ragdoll):
			ragdoll.push(dir * knock / stab * 0.6)
		if hp <= 0.0:
			_credit_ko(by)
			_die(by)
		return
	if def.has("dodge") and how != "blast" and how != "fire" and rng.randf() < float(def.dodge):
		battle.fx.poof(position + Vector3(0, 0.8, 0), 0.6)
		battle.snd("whoosh", position, 0.6)
		var side := Vector3(-dir.z, 0, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		linear_velocity += side * 6.0 + Vector3.UP * 2.0
		return
	var d := dmg * (1.0 - armor)
	if rig and rig.shield and how != "blast" and how != "fire":
		var from := _flat(-dir).normalized()
		# held up with right-click (B3Player), the shield covers more and stops more
		if forward().dot(from) > (-0.2 if shield_up else 0.25):
			d *= 0.1 if shield_up else 0.35
			knock *= 0.2 if shield_up else 0.5
			battle.snd("clang", position, 0.7)
			battle.fx.sparks(position + Vector3(0, 1.0, 0) + forward() * 0.4, 6)
			if shield_up and _block_t <= 0.0:
				_block_t = 0.6
				battle.fx.word(position + Vector3(0, tall + 1.2, 0), "BLOCK!", Color("9fd8ff"))
	hp -= d
	battle.player_hit(by, self)      # first-person hit marker, if it was you
	hurt_t = 0.0
	if how == "shot" or how == "blast":
		_fire_t = 0.0      # (under fire: shooters look for cover)
	if rig:
		rig.flash()
	if d >= 1.0:
		battle.fx.number(position + Vector3(0, tall + 0.5, 0), d)
	if by and is_instance_valid(by) and by != self and is_enemy(by) and pers != "peaceful" and not by.down:
		if target == null or not is_instance_valid(target) or position.distance_squared_to(by.position) < position.distance_squared_to(target.position) * 0.5:
			target = by
	if pers == "coward" and hp < max_hp * 0.5 and not fleeing:
		fleeing = true
		battle.snd("oof%d" % (rng.randi() % 3 + 1), position, 0.6)
	var kv := knock / stab
	if hp <= 0.0:
		_credit_ko(by)
		_ko(dir * maxf(kv, 3.0) + Vector3.UP * 2.0, by)
		return
	if kv > LAUNCH:
		knock_down(dir * kv)
		if String(def.body) == "human" and rng.randf() < 0.6:
			battle.snd("oof%d" % (rng.randi() % 3 + 1), position, 0.7)
	else:
		linear_velocity += dir * kv
		stun_t = maxf(stun_t, 0.1 + kv * 0.04)
		if String(def.body) == "human" and d > 8.0 and rng.randf() < 0.25:
			battle.snd("oof%d" % (rng.randi() % 3 + 1), position, 0.5)


## `by` knocked this one out: a knock-out for it, if it's an enemy. Knocking
## out a teammate (🤝 Blasts hurt teammates) or yourself (your own grenade)
## doesn't count. B3Battle.on_unit_ko adds it to its team's and the 🏆
## scoreboard's (by the same test).
func _credit_ko(by: B3Unit) -> void:
	if by != null and is_instance_valid(by) and by != self and by.is_enemy(self):
		by.kills += 1


func _ko(vel: Vector3, by: B3Unit) -> void:
	knock_down(vel)
	_die(by)


## Turns into a ragdoll flying off with `vel`.
func knock_down(vel: Vector3) -> void:
	if dead:
		return
	if down:
		if ragdoll and is_instance_valid(ragdoll):
			ragdoll.push(vel * 0.7)
		return
	if rig == null:
		return
	down = true
	down_t = 0.0
	act = ""
	charge_t = 0.0
	if power_t > 0.0 and _swoop:
		_alt = power_alt      # a swoop you started: fly back up there after getting up
	power_t = 0.0
	_swoop = false
	shield_up = false
	_hide_laser()
	var rd := B3Ragdoll.new()
	rd.battle = battle
	rd.unit = self
	battle.ragdoll_root.add_child(rd)
	var inherit := linear_velocity * 0.6
	rd.build(rig, vel + inherit, 3.0 + vel.length() * 0.4, rng)
	rig.queue_free()
	rig = null
	ragdoll = rd
	battle.ragdolls.append(rd)
	freeze = true
	collision_layer = 0
	collision_mask = 0
	disc.visible = false
	bar.visible = false
	rd.show_stars(99.0)
	if vel.length() > 12.0:
		battle.snd("whoosh", position, 0.7)


func _die(by: B3Unit = null) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	_hide_laser()
	if ragdoll and is_instance_valid(ragdoll):
		ragdoll.set_dead()
	battle.on_unit_ko(self, by)
	if laser:
		laser.queue_free()
	queue_free()


func _down_tick(dt: float) -> void:
	if ragdoll == null or not is_instance_valid(ragdoll):
		battle.remove_unit(self, false)
		return
	down_t += dt
	var c := ragdoll.center()
	global_position = c
	if c.y < -20.0 or absf(c.x) > B3Defs.BOUNDS + 10.0 or absf(c.z) > B3Defs.BOUNDS + 10.0:
		_die(null)
		return
	if ragdoll.sinking > 0.0:
		if ragdoll.sinking > 0.6:
			_die(null)
		return
	if held:
		down_t = 0.0
		return
	if down_t > 2.0 and ragdoll.is_settled():
		get_up()


func get_up() -> void:
	if not down or dead or ragdoll == null:
		return
	var c := ragdoll.center()
	var gy: float = battle.surface_y(c + Vector3(0, 1.0, 0))
	freeze = false
	collision_layer = B3Defs.L_UNIT
	collision_mask = MASK
	global_position = Vector3(c.x, gy + 0.08, c.z)
	linear_velocity = Vector3(0, 3.0, 0)
	_make_rig()
	battle.ragdolls.erase(ragdoll)
	ragdoll.queue_free()
	ragdoll = null
	down = false
	battle.grid_add(self, false)
	stun_t = 0.35
	disc.visible = true
	reset_physics_interpolation()
	battle.snd("boing", position, 0.5, 1.2)
	battle.fx.dust(position, 0.8)


func _hazards(dt: float) -> void:
	_hz_t -= dt
	if _hz_t > 0.0:
		return
	_hz_t = 0.1
	var h: B3Hazard = battle.hazard_at(position, 0.0)
	if h == null:
		return
	if flying and position.y > h.surface + 1.0:
		return
	var fire := h.kind == "lava" or h.kind == "fire"
	var k := _env_share(fire)
	if k <= 0.0:
		return       # a dragon doesn't mind lava or flames
	hp -= h.dps * 0.1 * k
	hurt_t = 0.0
	if rig:
		rig.flash()
	if fire:
		burn_t = 2.5
	if h.kind != "fire" and _grounded and rng.randf() < 0.5:
		linear_velocity.y = 3.5
	if rng.randf() < 0.3:
		battle.snd("sizzle" if h.kind != "acid" else "fizz", position, 0.6)
	if hp <= 0.0:
		_ko(Vector3.UP * 2.5, null)
		if h.kind != "fire" and ragdoll:
			pass


## How much of lava, acid, flame or burning damage gets through: like any
## hit, the Toughness rule and armour count, and dragons don't mind fire.
func _env_share(fire: bool) -> float:
	if fire and kind == "dragon":
		return 0.0
	return (1.0 - armor) / battle.r_tough


func _process(dt: float) -> void:
	if rig == null:
		return
	var mood := ""
	if cheer:
		mood = "cheer"
	elif burn_t > 0.0 or (routed and _spd >= 0.6):
		mood = "flail"      # (on fire, or running off with its arms waving: 🏳️ its King fell)
	elif fleeing and _spd < 0.6 and battle.fighting:
		mood = "cower"
	var aiming: bool = battle.fighting and target != null and String(wpn.type) != "melee" and pers != "berserk" and not fleeing and not cheer
	if not aiming and player and B3Player.steady(self, ctl):
		aiming = true      # a sniper you hold steady shoulders its rifle
	var a := act
	if _swoop:
		a = "swoop"
	match a:
		"thrust":
			a = "attack"      # the bayonet stab is the musket's jab
		"pulse":
			a = "heal"        # the medic's pulse: both hands out
		"kick":
			if not B3Player.kicks(self):
				a = "attack"  # animals shove with a head-butt
	rig.animate(dt, _spd, a, act_t / maxf(act_len, 0.01), aiming, mood)
	_power_pose()
	_steady_laser()
	if hurt_t < 3.0 and hp < max_hp and not battle.cam.too_close(position):
		bar.visible = true
		var f := clampf(hp / max_hp, 0.0, 1.0)
		if absf(f - _bar_hp) > 0.004:
			_bar_hp = f
			bar.set_instance_shader_parameter("hp", f)
	elif bar.visible:
		bar.visible = false


## Right-click power poses on top of the normal animation (on friends'
## copies too): the shield held up in front, a kick.
func _power_pose() -> void:
	if cheer or not (String(def.body) == "human" or String(def.body) == "robot"):
		return
	if shield_up and rig.shield:
		var al: Node3D = rig.pv.get("arm_l")
		if al:
			al.rotation = Vector3(-1.45, -0.85, 0.1)
	if act == "kick":
		var leg: Node3D = rig.pv.get("leg_r")
		if leg:
			leg.rotation = Vector3(-1.5 * sin(clampf(act_t / maxf(act_len, 0.01), 0.0, 1.0) * PI), 0, 0)


## A sniper held steady overhead (right-click): a red laser to where you're
## aiming. Only on the computer of the person playing it.
func _steady_laser() -> void:
	var on := B3Player.unit == self and not down and B3Player.steady(self, B3Player.me)
	if on:
		var a := _muzzle_pos()
		var b: Vector3 = B3Player.me.aim + Vector3(0, 0.9, 0)
		if _flat(b - a).length() > 0.5:
			_laser_line(a, b)
			_steady = true
			return
	if _steady:
		_steady = false
		if act != "aim":
			_hide_laser()

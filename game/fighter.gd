class_name Fighter
extends Node2D
## A person, animal or dinosaur that fights. Standing: one upright physics body
## with drawn, animated limbs (robust walking and AI). Knocked over, grabbed or
## KO'd: a ragdoll of real jointed parts that flies and tumbles. Gets back up
## if it's only knocked down.

const LAYER := 16
const MAX_BEND_SPEED := 14.0  # rad/s: the fastest a ragdoll joint is pushed back inside its limits
const RAG_PARTS := ["head", "torso", "uarm_b", "larm_b", "thigh_b", "shin_b", "thigh_f", "shin_f", "uarm_f", "larm_f"]
const METAL_HELMETS := ["army", "knight", "viking"]
const TUMBLE_WIND := 430.0    # px/s: wind this strong blows a standing fighter off its feet
const MAX_FREEZE := 4.0       # fighters only stay frozen this long (then the ice pops)
# A knocked-out ragdoll that has come to a stop lies still: its bodies are
# frozen in place, so a heap of them costs nothing until something moves them
# (see _rest_check and wake). Left alone they never quite stopped: their
# joints, the ground and their neighbours kept nudging each other, and every
# bump made a puff of dust. (Their speed jumps about too much to go by, so it
# goes by how far they get.)
const REST_BODY := 15.0       # px: the torso stays this close to where it was...
const REST_LIMB := 30.0       # ...and every other part this close...
const REST_AFTER := 1.0       # ...for this long, and it lies still.
const REST_ROAM := 80.0       # Or the torso stays this close (a limb that won't stop
const REST_STUBBORN := 3.0    # twitching, or a heap that keeps jostling) for this long.
const REST_GRAVITY := 100.0   # no lying still in (nearly) zero-G: it would hang in mid-air
const REST_CHECK := 0.5       # s: how often one lying still checks it's still lying on something

var uid := 0
var world: Node = null
var type := "stick"
var def := {}
var beast := false
var team := "red"
var pers := "attack"
var size := 1.0
var hp := 100.0
var max_hp := 100.0
var armor := 0.0
var helmet := ""
var body_armor := false
var shield := false
var weapon_id := ""
var weapon_toy: Toy = null
var state := "stand"            # stand | ragdoll | dead
var body: FighterPart = null
var parts := {}                 # ragdoll parts by name
var pins: Array = []
var limits: Array = []          # [part_a, part_b, min, max]
var facing := 1.0
var aim := 0.0                  # world angle the fighter aims at
var walk := 0.0
var move := 0.0
var swing := 0.0                # melee swing time left
var swing_hit := false
var cool := 0.0
var ammo := 0
var reload_t := 0.0
var target = null
var home := Vector2.ZERO
var down_t := 0.0
var think_t := 0.0
var stuck_t := 0.0
var stuck_x := 0.0             # where we were when the stuck timer started
var wander_t := 0.0
var wander_dir := 0.0
var flash := 0.0
var burning := 0.0
var acid := 0.0
var mood := "calm"              # calm angry scared hurt ko
var t := 0.0
var player_id := -1
var move_input := 0.0
var want_jump := false
var want_attack := false
var aim_point := Vector2.ZERO
var kos := 0
var puppet := false
var net := {}                   # puppet pose from the host
var grounded := false
var paint := Color(0, 0, 0, 0)
var charge_t := 0.0
var held_by := {}               # player id -> true while grabbed
var dead_t := 0.0
var hair := Color("3b2a1a")
var _voice_t := 0.0
var hit_t := 0.0               # melee: time until the swing lands
var _hit_wd := {}              # melee: the weapon that swing is with
# What toys and Wiggly powers are doing to us. A friend's screen only gets
# `mood`, so these ride along in it too ("angry+ice+wet", see _show_status).
var frozen_t := 0.0            # stuck in an ice block (Frosty, Freeze Bomb)
var bubble_t := 0.0            # floating up in a bubble (Bubble Maker, Bubble Bomb)
var stun_t := 0.0              # zapped: twitching, can't do anything (Zappy)
var goo_t := 0.0               # gummed up and slow (Gummy, Glue Bomb)
var lift_t := 0.0              # carried off by a tractor beam
var wet := 0.0                 # water and rain: puts fire out, zaps hurt more
var wind := Vector2.ZERO       # how fast fans, Big Wind and magnets push us this step (px/s)
var _wind_next := Vector2.ZERO
var yank_t := 0.0              # a magnet tugging at our metal weapon (1 = it flies off)
var _thud_t := -1.0            # when a soft bump last hurt our ragdoll
var _soft := false             # knocked over by a toy or power: bumps hurt less until we're up
var _launch_t := -1.0          # when a driving car last flipped us
var _jelly_t := -1.0           # when a Wiggly last bumped into us
var _blind_t := 0.0            # how long a wall has blocked our shot
var _resting := false          # knocked out and lying still: our bodies are frozen
var _rest_t := 0.0             # how long every part has stayed put
var _still_t := 0.0            # how long the torso has stayed put
var _rest_at := {}             # where each part was when it started staying put
var _roam_at := Vector2.INF    # where the torso was when it started staying put
var _support_t := 0.0          # lying still: time until we check we're still lying on something
static var _touch_q: PhysicsShapeQueryParameters2D = null


func setup(w: Node, fighter_type: String, pos: Vector2, team_id := "", personality := "", s := 1.0) -> void:
	world = w
	type = fighter_type
	def = Catalog.fighter(type)
	beast = String(def.get("kind", "person")) == "beast"
	team = team_id if team_id != "" else String(def.get("team", "red"))
	pers = personality if personality != "" else String(def.get("pers", "attack"))
	size = s * float(def.get("scale", 1.0))
	max_hp = float(def.get("hp", 100.0)) * size * size
	hp = max_hp
	armor = float(def.get("armor", 0.0))
	helmet = String(def.get("helmet", ""))
	shield = bool(def.get("shield", false))
	home = pos
	position = Vector2.ZERO
	facing = 1.0 if randf() < 0.5 else -1.0
	hair = [Color("3b2a1a"), Color("e1b12c"), Color("8c3b1e"), Color("1e1e1e"), Color("7f8c8d")][randi() % 5]
	t = randf() * 10.0
	z_index = 3
	set_meta("spawn_pos", pos)


func alive() -> bool:
	return state != "dead"


func display_name() -> String:
	return String(def.get("name", type))


func team_color() -> Color:
	return paint if paint.a > 0.0 else Catalog.team_color(team)


func center() -> Vector2:
	if puppet:
		return net.get("c", global_position)
	if state == "stand" and is_instance_valid(body):
		return body.global_position
	var tp = parts.get("torso")
	if tp and is_instance_valid(tp):
		return tp.global_position
	return global_position


func radius() -> float:
	if beast:
		var b: Vector2 = def.body
		return maxf(b.x, b.y + float(def.legs)) * 0.5 * size
	return 46.0 * size


func half_size() -> Vector2:
	if beast:
		var b: Vector2 = def.body
		return Vector2(b.x * 0.5, (b.y + float(def.legs)) * 0.5) * size
	return Vector2(13.0, 46.0) * size


func hit_test(p: Vector2, pad := 0.0) -> bool:
	if puppet or state == "stand":
		var l := p - center()
		var hs := half_size()
		return absf(l.x) <= hs.x + pad + 4.0 and absf(l.y) <= hs.y + pad
	for part in parts.values():
		if is_instance_valid(part):
			var l: Vector2 = part.to_local(p)
			if part.round_part:
				if l.length() <= part.half.x + pad + 4.0:
					return true
			elif absf(l.x) <= part.half.x + pad + 4.0 and absf(l.y) <= part.half.y + pad + 4.0:
				return true
	return false


## The physics body nearest to `p` (for grabbing and tying ropes).
func body_near(p: Vector2) -> PhysicsBody2D:
	if state == "stand":
		return body
	var best: PhysicsBody2D = null
	var bd := INF
	for part in parts.values():
		if is_instance_valid(part):
			var d: float = part.global_position.distance_squared_to(p)
			if d < bd:
				bd = d
				best = part
	return best


func all_bodies() -> Array:
	if state == "stand":
		return [body] if is_instance_valid(body) else []
	return parts.values().filter(func(b): return is_instance_valid(b))


# ------------------------------------------------------------ bodies
func _mat(fric: float, bounce: float) -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.friction = fric
	pm.bounce = bounce
	return pm


func make_standing(at: Vector2, vel := Vector2.ZERO) -> void:
	body = FighterPart.new()
	body.fighter = self
	body.part = "body"
	var hs := half_size()
	body.half = hs
	if beast:
		var rect := RectangleShape2D.new()
		rect.size = hs * 2.0
		var cs := CollisionShape2D.new()
		cs.shape = rect
		body.add_child(cs)
		var b: Vector2 = def.body
		body.mass = maxf(1.0, b.x * b.y / 900.0) * size * size
	else:
		var cap := CapsuleShape2D.new()
		cap.radius = 12.0 * size
		cap.height = 92.0 * size
		var cs := CollisionShape2D.new()
		cs.shape = cap
		body.add_child(cs)
		body.mass = 3.0 * size * size
	body.lock_rotation = true
	body.physics_material_override = _mat(0.3, 0.0)
	body.collision_layer = LAYER
	body.collision_mask = Toy.LAYER_GROUND | Toy.LAYER_TOYS   # (Wigglies: see World._wigglies_vs_fighters)
	# FighterPart._integrate_forces reads the contacts straight from the physics
	# state, which only needs max_contacts_reported. (contact_monitor would also
	# keep a list of touching bodies and hook up to each one's signals as it
	# comes and goes: nothing here uses it, and with piles of ragdolls it's slow.)
	body.max_contacts_reported = 4
	body.can_sleep = false
	body.global_position = world.lift_out_of_ground(at, minf(hs.x, hs.y) * 0.9) if not puppet else at
	body.linear_velocity = vel
	if def.get("flies", false):
		body.gravity_scale = 0.0
		body.linear_damp = 1.5
	world.bodies.add_child(body)
	state = "stand" if hp > 0.0 else "dead"


func free_bodies() -> void:
	_resting = false
	if is_instance_valid(body):
		body.queue_free()
	body = null
	for j in pins:
		if is_instance_valid(j):
			j.queue_free()
	pins.clear()
	limits.clear()
	for p in parts.values():
		if is_instance_valid(p):
			p.queue_free()
	parts.clear()


## Joint positions of the standing pose (local, facing right; flip x for facing left).
func pose() -> Dictionary:
	var s := size
	var o := {}
	if beast:
		return o
	var moving := clampf(absf(move), 0.0, 1.0) if grounded else 0.6
	var hip := Vector2(0, 6) * s
	var sh := Vector2(0, -22) * s
	var legs := {}
	for side in ["f", "b"]:
		var ph := walk + (0.0 if side == "f" else PI)
		var a := sin(ph) * 0.6 * moving + (0.08 if side == "f" else -0.08)
		var k := maxf(0.0, -cos(ph)) * 0.9 * moving + (0.0 if grounded else 0.5)
		var knee := hip + Vector2(sin(a), cos(a)) * 19.0 * s
		var foot := knee + Vector2(sin(a - k), cos(a - k)) * 19.0 * s
		legs[side] = [knee, foot]
	o.hip = hip
	o.shoulder = sh
	o.neck = Vector2(0, -26) * s
	o.head = Vector2(0, -36 + sin(walk * 2.0) * 0.8 * moving) * s
	o.knee_f = legs.f[0]
	o.foot_f = legs.f[1]
	o.knee_b = legs.b[0]
	o.foot_b = legs.b[1]
	# arms
	var wt := _wtype()
	var la := aim
	if facing < 0.0:
		la = PI - aim   # aim in the unflipped frame
	la = wrapf(la, -PI, PI)
	var fdir := Vector2.from_angle(la)
	if wt in ["gun", "launcher", "bow", "flame"]:
		var hand := sh + fdir * 26.0 * s
		o.elbow_f = sh + fdir * 14.0 * s + Vector2(0, 3) * s
		o.hand_f = hand
		o.elbow_b = sh + fdir * 10.0 * s + Vector2(-2, 6) * s
		o.hand_b = sh + fdir * 18.0 * s + Vector2(0, 2) * s
	else:
		var arm_a := 0.55   # resting: down-forward
		if swing > 0.0:
			var k2 := 1.0 - swing / _swing_time()
			arm_a = lerpf(-2.4, 1.0, ease(k2, 0.4))
		elif wt == "throw" and cool > _rate() - 0.3:
			arm_a = -2.2
		var d := Vector2(cos(arm_a), sin(arm_a))
		o.elbow_f = sh + d * 15.0 * s
		o.hand_f = o.elbow_f + Vector2(cos(arm_a + 0.25), sin(arm_a + 0.25)) * 14.0 * s
		var swing_b := sin(walk) * 0.5 * moving
		var db := Vector2(sin(swing_b) * 0.6 + 0.15, cos(swing_b))
		o.elbow_b = sh + db.normalized() * 15.0 * s
		o.hand_b = o.elbow_b + Vector2(sin(swing_b - 0.3), cos(swing_b - 0.3)) * 14.0 * s
	return o


func flipped(v: Vector2) -> Vector2:
	return Vector2(v.x * facing, v.y)


## Turns the fighter into a floppy ragdoll (knocked over, grabbed, or KO).
## `soft`: knocked over by a toy or a Wiggly power (not a blast or a blow), so
## landing and tumbling only hurt a little until we're back up.
func ragdoll(impulse := Vector2.ZERO, soft := false) -> void:
	if state != "stand" or puppet:
		return
	_soft = soft
	# knocked over: the ice cracks and the bubble pops
	if frozen_t > 0.0:
		thaw(true)
	if bubble_t > 0.0:
		pop_bubble(false)
	var c := body.global_position if is_instance_valid(body) else center()
	var v := body.linear_velocity if is_instance_valid(body) else Vector2.ZERO
	var held := weapon_toy
	_drop_weapon(v + impulse * 0.6)
	if is_instance_valid(body):
		body.queue_free()
	body = null
	if beast:
		_beast_ragdoll(c, v, impulse)
	else:
		_person_ragdoll(c, v, impulse)
	# The weapon we just let go of starts out in our hand, right inside our
	# arm: it mustn't push against our own limbs. (It used to get wedged among
	# them, and a knocked-out fighter's arms and legs never stopped twitching.)
	if held and is_instance_valid(held):
		for p in parts.values():
			held.add_collision_exception_with(p)
	state = "ragdoll" if hp > 0.0 else "dead"
	down_t = 0.0
	swing = 0.0
	hit_t = 0.0


func _part(name: String, pos: Vector2, rot: float, half: Vector2, round_p: bool, m: float, vel: Vector2) -> FighterPart:
	var p := FighterPart.new()
	p.fighter = self
	p.part = name
	p.half = half
	p.round_part = round_p
	var cs := CollisionShape2D.new()
	if round_p:
		var c := CircleShape2D.new()
		c.radius = half.x
		cs.shape = c
	else:
		var r := RectangleShape2D.new()
		r.size = half * 2.0
		cs.shape = r
	p.add_child(cs)
	p.mass = m
	p.angular_damp = 1.0       # a little joint friction, so limbs settle instead of spinning on
	p.physics_material_override = _mat(0.8, 0.05)
	p.collision_layer = LAYER
	p.collision_mask = Toy.LAYER_GROUND | Toy.LAYER_TOYS | Toy.LAYER_WIGGLIES | LAYER
	p.max_contacts_reported = 3   # (no contact_monitor: see make_standing)
	p.angular_damp = 1.2
	p.linear_damp = 0.1
	p.global_position = pos
	p.rotation = rot
	p.linear_velocity = vel
	world.bodies.add_child(p)
	parts[name] = p
	return p


func _seg(c: Vector2, a: Vector2, b: Vector2) -> Array:
	# world centre and rotation of a limb from local points a->b
	var wa := c + flipped(a)
	var wb := c + flipped(b)
	return [(wa + wb) * 0.5, (wb - wa).angle() - PI * 0.5, wa.distance_to(wb)]


func _person_ragdoll(c: Vector2, v: Vector2, imp: Vector2) -> void:
	var o := pose()
	var s := size
	var m := 3.0 * s * s
	var spin := randf_range(-4.0, 4.0)
	var vel := v + imp
	_part("head", c + flipped(o.head), 0.0, Vector2(11, 11) * s, true, m * 0.13, vel * 1.1)
	var tor := _seg(c, o.shoulder, o.hip)
	_part("torso", tor[0], tor[1], Vector2(7, maxf(8.0, tor[2] * 0.5 + 4.0 * s)) * Vector2(s, 1.0), false, m * 0.4, vel)
	for side in ["f", "b"]:
		var ua := _seg(c, o.shoulder, o["elbow_" + side])
		_part("uarm_" + side, ua[0], ua[1], Vector2(3.0 * s, ua[2] * 0.5), false, m * 0.06, vel * 1.15)
		var la := _seg(c, o["elbow_" + side], o["hand_" + side])
		_part("larm_" + side, la[0], la[1], Vector2(2.6 * s, la[2] * 0.5), false, m * 0.05, vel * 1.2)
		var th := _seg(c, o.hip, o["knee_" + side])
		_part("thigh_" + side, th[0], th[1], Vector2(3.6 * s, th[2] * 0.5), false, m * 0.1, vel * 0.95)
		var sn := _seg(c, o["knee_" + side], o["foot_" + side])
		_part("shin_" + side, sn[0], sn[1], Vector2(3.2 * s, sn[2] * 0.5), false, m * 0.08, vel * 0.9)
	for p in parts.values():
		p.angular_velocity = spin
	_join("torso", "head", c + flipped(o.neck), -0.7, 0.7)
	for side in ["f", "b"]:
		# arms flail almost all the way round, but not quite: with no gap at
		# all, nothing ever slowed a spinning arm and it whirled like a helicopter
		_join("torso", "uarm_" + side, c + flipped(o.shoulder), -2.7, 2.7)
		_join("uarm_" + side, "larm_" + side, c + flipped(o["elbow_" + side]), -2.4, 0.2)
		_join("torso", "thigh_" + side, c + flipped(o.hip), -1.6, 1.6)
		_join("thigh_" + side, "shin_" + side, c + flipped(o["knee_" + side]), -0.1, 2.4)
	_no_self_collide()


func _beast_ragdoll(c: Vector2, v: Vector2, imp: Vector2) -> void:
	var b: Vector2 = def.body * size
	var bc := c + Vector2(0, -float(def.legs) * size * 0.5)
	var m := maxf(1.0, def.body.x * def.body.y / 900.0) * size * size
	var vel := v + imp
	_part("torso", bc, 0.0, Vector2(b.x * 0.45, b.y * 0.42 + float(def.legs) * size * 0.25), false, m * 0.75, vel)
	var hr := float(def.head) * size
	var neck_len := float(def.neck) * size
	var hp_pos := bc + Vector2(facing * (b.x * 0.48 + neck_len * 0.6 + hr * 0.6), -b.y * 0.35 - neck_len * (0.9 if def.get("long_neck", false) else 0.5))
	_part("head", hp_pos, 0.0, Vector2(hr * 0.8, hr * 0.8), true, m * 0.12, vel * 1.1)
	_join("torso", "head", bc + Vector2(facing * b.x * 0.45, -b.y * 0.2), -0.8, 0.8)
	var tl := float(def.tail) * size
	if tl > 14.0:
		var tp := bc + Vector2(-facing * (b.x * 0.45 + tl * 0.45), -b.y * 0.05)
		_part("tail", tp, 0.0, Vector2(tl * 0.45, maxf(3.0, b.y * 0.12)), false, m * 0.1, vel)
		_join("torso", "tail", bc + Vector2(-facing * b.x * 0.42, -b.y * 0.05), -0.9, 0.9)
	for p in parts.values():
		p.angular_velocity = randf_range(-3.0, 3.0)
	_no_self_collide()


func _join(a: String, b: String, at: Vector2, lo: float, hi: float) -> void:
	var pa: FighterPart = parts.get(a)
	var pb: FighterPart = parts.get(b)
	if pa == null or pb == null:
		return
	var j := PinJoint2D.new()
	world.pin_parent.add_child(j)
	j.global_position = at
	j.disable_collision = true
	j.softness = 0.0
	j.node_a = j.get_path_to(pa)
	j.node_b = j.get_path_to(pb)
	pins.append(j)
	var ref := pb.rotation - pa.rotation
	if facing < 0.0:
		var t2 := lo
		lo = -hi
		hi = -t2
	limits.append([pa, pb, ref + lo, ref + hi])


func _no_self_collide() -> void:
	var ps := parts.values()
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			ps[i].add_collision_exception_with(ps[j])


## Keeps ragdoll joints inside their limits (Godot's own 2D joint limits are too soft).
func _solve_limits(dt: float) -> void:
	for l in limits:
		var a: FighterPart = l[0]
		var b: FighterPart = l[1]
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		# Measure the bend from the middle of the allowed range. Measured from
		# zero, an angle that wraps past ±PI looked like a huge error and the
		# fix-up spun the limb round and round like a helicopter.
		var lo: float = l[2]
		var hi: float = l[3]
		var half := (hi - lo) * 0.5
		var rel := wrapf(b.rotation - a.rotation - (lo + hi) * 0.5, -PI, PI)
		var err := 0.0
		if rel < -half:
			err = rel + half
		elif rel > half:
			err = rel - half
		if err == 0.0:
			continue
		var sa := PhysicsServer2D.body_get_direct_state(a.get_rid())
		var sb := PhysicsServer2D.body_get_direct_state(b.get_rid())
		if sa == null or sb == null:
			continue
		var ia := sa.inverse_inertia
		var ib := sb.inverse_inertia
		if ia + ib <= 0.0:
			continue
		var wrel := sb.angular_velocity - sa.angular_velocity
		# Bend back towards the limit, but not too hard: a limb far past its
		# limit used to be flung back at 100+ rad/s, overshoot, and whirl
		# round like a helicopter.
		var desired := clampf(-err * 0.3 / dt, -MAX_BEND_SPEED, MAX_BEND_SPEED)
		if (err > 0.0 and wrel > desired) or (err < 0.0 and wrel < desired):
			var imp := (desired - wrel) / (ia + ib)
			sa.angular_velocity -= imp * ia
			sb.angular_velocity += imp * ib


func stand_up() -> void:
	if state != "ragdoll" or hp <= 0.0:
		return
	_resting = false
	var c := center()
	var v: Vector2 = parts.torso.linear_velocity if parts.has("torso") and is_instance_valid(parts.torso) else Vector2.ZERO
	for j in pins:
		if is_instance_valid(j):
			j.queue_free()
	pins.clear()
	limits.clear()
	for p in parts.values():
		if is_instance_valid(p):
			p.queue_free()
	parts.clear()
	make_standing(c + Vector2(0, -10), v * 0.3)
	_soft = false
	_pickup_near(160.0)
	world.fx_event("getup", {"p": c})


# ---------------------------------------------------------------- weapons
func _wdef() -> Dictionary:
	if beast:
		return {"type": "beast", "dmg": def.get("dmg", 10.0), "reach": def.get("reach", 30.0), "rate": def.get("rate", 1.0), "knock": def.get("knock", 400.0)}
	if weapon_id == "":
		return {"type": "melee", "dmg": 9.0 * size, "reach": 34.0 * size, "rate": 0.45, "knock": 220.0 * size, "sound": "punch", "fists": true}
	return Catalog.toy(weapon_id).get("weapon", {})


func _wtype() -> String:
	return String(_wdef().get("type", "melee"))


func _rate() -> float:
	return float(_wdef().get("rate", 0.6))


func _swing_time() -> float:
	return clampf(_rate() * 0.6, 0.18, 0.5)


func _reach() -> float:
	var wd := _wdef()
	match String(wd.get("type", "melee")):
		"gun", "launcher", "bow", "throw", "flame":
			return float(wd.get("range", 600.0))
	return float(wd.get("reach", 40.0)) * (size if not beast else 1.0)


func equip(toy: Toy) -> bool:
	if beast or toy == null or not alive():
		return false
	if toy.def.has("armor"):
		var a: Dictionary = toy.def.armor
		# one of each: a second helmet, vest or shield doesn't add more armor
		match String(a.slot):
			"helmet":
				if helmet != "":
					return false
				helmet = "army"
			"body":
				if body_armor:
					return false
				body_armor = true
			"shield":
				if shield:
					return false
				shield = true
		armor = minf(0.7, armor + float(a.value))
		world.remove(toy.uid, false)
		world.fx_event("equip", {"p": center()})
		return true
	if not toy.def.has("weapon"):
		return false
	_drop_weapon(Vector2(0, -120))
	weapon_id = toy.id
	weapon_toy = toy
	toy.extra.held_by = uid
	toy.collision_layer = 0
	toy.collision_mask = 0
	toy.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	toy.freeze = true
	toy.z_index = 6
	ammo = int(toy.def.weapon.get("burst", 0))
	world.fx_event("equip", {"p": center()})
	return true


func _drop_weapon(vel: Vector2) -> void:
	if weapon_toy and is_instance_valid(weapon_toy):
		var t2 := weapon_toy
		t2.extra.erase("held_by")
		t2.collision_layer = Toy.LAYER_TOYS
		t2.collision_mask = Toy.LAYER_GROUND | Toy.LAYER_TOYS | Toy.LAYER_WIGGLIES | LAYER
		t2.z_index = 1
		t2.freeze = false
		t2.update_freeze()
		t2.linear_velocity = vel + Vector2(randf_range(-80, 80), -60)
		t2.angular_velocity = randf_range(-10, 10)
		t2.set_meta("dropped_by", uid)
	weapon_toy = null


func _pickup_near(r: float) -> void:
	if beast or weapon_toy != null:
		return
	var best: Toy = null
	var bd := r
	for t2 in world.toys():
		if t2.def.has("weapon") and not t2.extra.has("held_by"):
			var d: float = t2.global_position.distance_to(center())
			if d < bd and (weapon_id == "" or t2.id == weapon_id or int(t2.get_meta("dropped_by", -1)) == uid):
				bd = d
				best = t2
	if best:
		equip(best)
	elif weapon_id != "" and weapon_toy == null:
		weapon_id = ""   # lost it


func _hand_world() -> Vector2:
	var o := pose()
	if o.is_empty():
		return center()
	return center() + flipped(o.hand_f)


# --------------------------------------------------------------- damage
func hurt(amount: float, knock := Vector2.ZERO, from = null) -> void:
	if puppet or amount <= 0.0 and knock == Vector2.ZERO:
		return
	if state == "dead":
		wake()
		for p in all_bodies():
			p.apply_central_impulse(knock * p.mass * 0.6)
		return
	var dmg := amount * (1.0 - armor)
	if frozen_t > 0.0:
		# the ice block soaks up half of it, and a big hit smashes it
		dmg *= 0.5
		if amount >= 40.0 or knock.length() > 450.0:
			thaw(true)
	if shield and from != null and is_instance_valid(from) and signf(from.center().x - center().x) == facing:
		dmg *= 0.5
		world.fx_event("clang", {"p": center() + Vector2(facing * 16.0 * size, -10)})
	hp -= dmg
	if dmg > 0.5:
		world.quiet_t = 0.0      # the battle's still going (see World.brave)
	flash = 1.0
	if dmg > 4.0 and t - _voice_t > 0.35 and not beast:
		_voice_t = t
		world.fx_event("oof", {"p": center()})
	if from != null and is_instance_valid(from) and from is Fighter and from != self and target == null and pers != "peaceful":
		target = from
	if pers == "peaceful":
		mood = "scared"
		_show_status()   # keep the ice, bubble… flags for a friend's screen
	var heavy := 260.0 * (maxf(1.0, def.body.x * def.body.y / 1500.0) if beast else size * size)
	if hp <= 0.0:
		hp = 0.0
		_ko(knock, from)
	elif knock.length() > 380.0 + heavy:
		if state == "stand":
			ragdoll(knock / sqrt(maxf(1.0, _mass_k())))
		else:
			for p in all_bodies():
				p.apply_central_impulse(knock * p.mass * 0.5)
	elif state == "stand" and is_instance_valid(body):
		body.linear_velocity += knock * 0.35 / _mass_k()
	elif state == "ragdoll":
		for p in all_bodies():
			p.apply_central_impulse(knock * p.mass * 0.4)


func _mass_k() -> float:
	return maxf(1.0, def.body.x * def.body.y / 1500.0) if beast else size * size


func _ko(knock: Vector2, from) -> void:
	if frozen_t > 0.0:
		thaw(true)
	if state == "stand":
		ragdoll(knock / sqrt(_mass_k()))
	stun_t = 0.0
	lift_t = 0.0
	goo_t = 0.0
	state = "dead"
	mood = "ko"
	dead_t = 0.0
	world.fx_event("ko", {"p": center(), "beast": beast})
	if from != null and is_instance_valid(from) and from is Fighter:
		from.kos += 1
		if from.player_id >= 0 and from.kos >= 5:
			Settings.award("hero")
	world.on_fighter_ko(self)


func revive() -> void:
	hp = max_hp
	burning = 0.0
	acid = 0.0
	if frozen_t > 0.0:
		thaw()
	if bubble_t > 0.0:
		pop_bubble(false)
	stun_t = 0.0
	goo_t = 0.0
	if state == "dead":
		state = "ragdoll"
	mood = "calm"
	stand_up()


## `hit`: how fast the other thing was coming at us, pointing at us (its own
## speed, so walking into a resting bowling ball doesn't knock us over).
func on_part_impact(_p: FighterPart, other, closing: float, at: Vector2, hit := Vector2.ZERO) -> void:
	if puppet or _resting:
		return   # (lying still: a bump from just before we froze)
	if bubble_t > 0.0 and closing > 200.0:
		pop_bubble()   # bumped into something: pop!
	if state == "stand":
		# a really fast smack hurts whatever it is (landing from high up, a cannon
		# ball, a body thrown by a blast), but not the flailing arms of someone a
		# toy or a Wiggly just knocked over
		var fast := minf((closing - 1050.0) * 0.06, 30.0) if closing > 1050.0 else 0.0
		if other is FighterPart and other.fighter and other.fighter._soft:
			fast = 0.0
		var m := _hitter_mass(other)
		if m > 0.0:
			_bump(other, m, hit, fast)
		elif fast > 0.0:
			hurt(fast, Vector2(0, -closing * 0.3))
		return
	if other is Toy and hit.length() > 30.0 and world.vision_time - _launch_t > 0.6 and other.driving():
		# a driving go-kart or monster truck flips us up and over, BONK!
		_launch_t = world.vision_time
		var ride: Toy = world.things.get(other.parent_uid) if other.parent_uid != 0 and world.things.get(other.parent_uid) is Toy else other
		_soft = true
		for b in all_bodies():
			b.linear_velocity = Vector2(ride.linear_velocity.x * 0.4, -620.0)
	if closing > 520.0:
		if _soft or other is Toy:
			# knocked over by a toy or a Wiggly power (not a blast or a blow), or
			# squashed under a monster truck's wheel: only a little at a time,
			# not a bit for every arm and leg on every bump
			if closing > 600.0 and world.vision_time - _thud_t > 0.5:
				_thud_t = world.vision_time
				hurt(minf((closing - 520.0) * 0.035, 4.0))
		else:
			hurt((closing - 520.0) * 0.035)
		if closing > 700.0:
			world.fx_event("thud", {"p": at, "v": closing, "m": 2.0})
	if other is Toy and other.id == "landmine":
		ToyLogic.trigger(world, other)


## How heavy the thing that hit us is (0 = the ground, a platform or anything
## nailed down). A ride counts with its wheels, a flying ragdoll with its whole body.
func _hitter_mass(other) -> float:
	if other is Toy:
		if other.freeze or other.extra.has("proj") or other.def.has("weapon") or other.def.has("armor"):
			return 0.0   # nailed or frozen; bullets and blades have their own rules
		var m: float = other.mass
		if other.parent_uid != 0:
			var ride = world.things.get(other.parent_uid)
			if ride is Toy:
				m += ride.mass + other.mass   # a wheel brings the whole car with it
		elif String(other.def.get("build", "")) == "car":
			m *= 1.4
		return m
	if other is FighterPart and other.fighter and is_instance_valid(other.fighter) and other.fighter != self:
		return other.fighter.weight()
	return 0.0


## Something heavy and fast ran into us while we were standing: the heavier and
## faster it is (and the lighter we are), the harder the shove. Big enough and
## we go flying; it only hurts a bit.
func _bump(other, m: float, hit: Vector2, fast: float) -> void:
	var spd := hit.length()
	var need := knock_speed()
	var car: bool = other is Toy and spd > 0.0 and other.driving()
	if car:
		spd = maxf(spd, 320.0)   # a go-kart or monster truck that's driving bowls people over
	if other is FighterPart and spd > 0.0:
		# a flailing arm isn't a flying body: go by how fast its middle is coming
		var tor = other.fighter.parts.get("torso", other)
		spd = maxf(0.0, (tor.linear_velocity as Vector2).dot(hit / spd)) if is_instance_valid(tor) else 0.0
		need *= 1.6   # only a body really flying (from a blast) knocks others down, not one just falling over
	var dv := spd * m / (m + weight())
	var dmg := maxf(fast, clampf((dv - 100.0) * 0.08, 0.0, 35.0))
	if dv < need:
		if dmg > 0.0:
			hurt(dmg)
		return
	var dir := hit.normalized() if hit != Vector2.ZERO else Vector2(-facing, 0)
	if car:
		# up and over the bonnet, and the car drives on underneath
		_launch_t = world.vision_time
		var ride: Toy = world.things.get(other.parent_uid) if other.parent_uid != 0 and world.things.get(other.parent_uid) is Toy else other
		shove(Vector2(ride.linear_velocity.x * 0.4, -620.0), dmg)
	else:
		shove((dir + Vector2(0, -0.5)).normalized() * dv * 1.1, dmg)
	world.fx_event("bowled", {"p": center(), "v": dv})


## A Wiggly rolling or flying into us while we stand (World._wigglies_vs_fighters):
## `rel` is how fast it's coming at us along `dir`. Big and fast bowls us over,
## anything else is a soft bump that bounces it off. It hardly hurts: jelly is soft.
func jelly_bump(w: Wiggly, rel: float, dir: Vector2) -> void:
	if puppet or state != "stand" or not is_instance_valid(body) or world.vision_time - _jelly_t < 0.4:
		return
	_jelly_t = world.vision_time
	var m := float(w.def.mass) * Wiggly.N * w.size * w.size
	var dv := rel * m / (m + weight())
	if dv >= knock_speed() * 1.4:
		shove((dir + Vector2(0, -0.5)).normalized() * dv * 1.1, clampf((dv - 100.0) * 0.025, 0.0, 10.0))
		world.fx_event("bowled", {"p": center(), "v": dv})
	elif frozen_t <= 0.0:
		body.linear_velocity += Vector2(dir.x, minf(dir.y, 0.0)) * dv * 0.6
	# the Wiggly loses some of its speed to us and bounces off a little
	w.add_velocity(-dir * rel * minf(1.0, weight() / (m + weight()) * 1.6))


# ------------------------------------------------------- toys and powers
## Body weight (the same as the standing body's mass).
func weight() -> float:
	if beast:
		var b: Vector2 = def.body
		return maxf(1.0, b.x * b.y / 900.0) * size * size
	return 3.0 * size * size


## How fast a shove has to be to knock us off our feet (beasts stand firmer).
func knock_speed() -> float:
	return 200.0 if beast else 150.0


## How much metal we wear: magnets pull it and zaps love it.
func metal() -> float:
	var m := 0.0
	if helmet in METAL_HELMETS:
		m += 1.0
	if body_armor:
		m += 1.0
	if shield:
		m += 1.0
	return m


## Frozen, floating, zapped or carried off: no walking or fighting just now.
func helpless() -> bool:
	return frozen_t > 0.0 or bubble_t > 0.0 or stun_t > 0.0 or lift_t > 0.0


## Thrown by a toy, a Wiggly or a ground pound: `dv` is how fast it throws us.
## Fast enough and we fall over (heavy beasts barely budge); `dmg` hurts a bit.
func shove(dv: Vector2, dmg := 0.0, from = null) -> void:
	if puppet:
		return
	if frozen_t > 0.0:
		if dv.length() < 300.0:
			return
		thaw(true)
	if dmg > 0.0:
		hurt(dmg, Vector2.ZERO, from)
	if state == "stand" and is_instance_valid(body):
		if dv.length() >= knock_speed():
			ragdoll(dv, true)
		else:
			body.linear_velocity += dv * 0.5
	else:
		_soft = true
		wake()
		for p in all_bodies():
			p.linear_velocity += dv * 0.8


## Fans, Big Wind and magnets: `push` is how fast the air (or the pull) would
## carry a person. Lighter fighters go faster, a T-Rex hardly moves.
func blow(push: Vector2, dt: float) -> void:
	if puppet or frozen_t > 0.0:
		return
	var k := clampf(3.0 / weight(), 0.15, 2.5)
	if state == "stand":
		_wind_next += push * k
	else:
		_soft = true
		wake()
		for p in all_bodies():
			p.linear_velocity += push * k * dt * 3.0


## Hover Saucer's tractor beam: drifts us toward `want` (heavy dinos rise slower).
func beam(want: Vector2, dt: float) -> void:
	if puppet or frozen_t > 0.0:
		return
	if alive():
		lift_t = 0.15
		if state == "stand":
			swing = 0.0
			hit_t = 0.0
			charge_t = 0.0
	if state != "stand":
		_soft = true   # (dropped from up there: a soft landing)
		wake()
	var lift := clampf(sqrt(6.0 / weight()), 0.35, 1.0)
	var to := Vector2(want.x, want.y * lift)
	var g: Vector2 = world.gravity_vec() * dt
	for b in all_bodies():
		b.linear_velocity = b.linear_velocity.lerp(to, minf(1.0, dt * 4.0)) - g


## Frosty or a Freeze Bomb: an ice block, right where we are (even in mid-air).
func set_frozen(sec: float) -> void:
	if puppet or not alive() or sec <= 0.0:
		return
	if bubble_t > 0.0:
		pop_bubble(false)
	frozen_t = minf(sec, MAX_FREEZE)
	burning = 0.0
	stun_t = 0.0
	swing = 0.0
	hit_t = 0.0
	charge_t = 0.0
	move = 0.0
	for b in all_bodies():
		b.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		b.freeze = true
	mood = "frozen"
	_show_status()


## The ice melts (or gets smashed): we drop out with a crack.
func thaw(smash := false) -> void:
	var was := frozen_t > 0.0
	frozen_t = 0.0
	for b in all_bodies():
		if b.freeze:
			b.freeze = false
	if not was:
		return
	if alive():
		mood = "calm"
	_show_status()
	world.fx_event("ice_pop", {"p": center(), "r": radius(), "smash": smash})


## Caught in a bubble: floats up, helpless, until it pops.
func set_bubble(sec: float) -> void:
	if puppet or state != "stand" or not alive() or frozen_t > 0.0 or not is_instance_valid(body):
		return
	bubble_t = sec
	body.gravity_scale = 0.0
	body.linear_velocity = Vector2(body.linear_velocity.x * 0.3, minf(body.linear_velocity.y * 0.1, -40.0))
	swing = 0.0
	hit_t = 0.0
	charge_t = 0.0
	mood = "scared"
	_show_status()


## Pop! `fall`: tumble down as a ragdoll and get back up after.
func pop_bubble(fall := true) -> void:
	if bubble_t <= 0.0:
		return
	bubble_t = 0.0
	if is_instance_valid(body):
		body.gravity_scale = 0.0 if def.get("flies", false) else 1.0
	if alive():
		mood = "calm"
	_show_status()
	world.fx_event("pop_bubble", {"p": center(), "r": radius() * 1.3})
	if fall and state == "stand":
		ragdoll(Vector2(0, -60), true)   # a long way down: a soft landing


## Zappy: a shock that stuns us for a moment. Wet fighters and ones in metal
## armor get it worse.
func zap(power := 1.0) -> void:
	if puppet or not alive() or frozen_t > 0.0:
		return
	var k := 1.0 + (0.8 if wet > 0.2 else 0.0) + 0.3 * minf(2.0, metal())
	stun_t = maxf(stun_t, 0.9 + 0.5 * k)
	swing = 0.0
	hit_t = 0.0
	charge_t = 0.0
	flash = 1.0
	if bubble_t > 0.0:
		pop_bubble()
	if state == "stand" and is_instance_valid(body):
		body.linear_velocity.y = minf(body.linear_velocity.y, -140.0)   # a little jolt
	hurt(9.0 * k * power)
	if alive():
		mood = "zapped"
		_show_status()


## Blaze and fire: catch fire, unless we're wet (then it just steams).
func ignite(sec: float) -> void:
	if puppet or not alive():
		return
	if frozen_t > 0.0:
		thaw()
		return
	if wet > 0.2:
		wet = maxf(0.0, wet - 0.5)
		world.fx_event("steam", {"p": center()})
		return
	burning = maxf(burning, sec)
	if bubble_t > 0.0:
		pop_bubble()


## Gummy or a Glue Bomb: sticky and slow for a while.
func stick(sec: float) -> void:
	if puppet or not alive():
		return
	goo_t = maxf(goo_t, sec)
	charge_t = 0.0
	_show_status()


## A magnet `k` (0..1) close by: metal armor gets pulled toward it, and a
## metal weapon gets tugged until it flies out of our hands.
func magnetize(at: Vector2, k: float, dt: float) -> void:
	if puppet or frozen_t > 0.0:
		return
	var to := at - center()
	var m := metal()
	if m > 0.0 and to.length() > 50.0:
		# dragged over to it (and held there), but not pulled off our feet
		blow(to.normalized() * minf(300.0 * k * minf(m, 2.5), TUMBLE_WIND - 50.0), dt)
	if weapon_toy and is_instance_valid(weapon_toy) and weapon_toy.def.get("metal", false):
		yank_t += dt * (0.6 + k * 2.4)
		if yank_t >= 1.0:
			yank_t = 0.0
			var w := weapon_toy
			_drop_weapon((at - w.global_position).normalized() * 520.0)
			weapon_id = ""
			world.fx_event("yoink", {"p": w.global_position})


## Counts down what toys and powers did to us (every physics step).
func _effects_step(dt: float) -> void:
	if wet > 0.0:
		wet = maxf(0.0, wet - dt * 0.07)
		if burning > 0.0 and wet > 0.15:
			burning = 0.0
			wet -= 0.25   # putting the fire out dries us off a bit
			world.fx_event("steam", {"p": center()})
	if frozen_t > 0.0:
		frozen_t -= dt
		if frozen_t <= 0.0:
			frozen_t = 0.01
			thaw()
	if stun_t > 0.0:
		stun_t -= dt
		if stun_t <= 0.0 and alive():
			mood = "calm"
	if bubble_t > 0.0:
		bubble_t -= dt
		if bubble_t <= 0.0:
			bubble_t = 0.01
			pop_bubble()
	goo_t = maxf(0.0, goo_t - dt)
	if lift_t > 0.0:
		lift_t -= dt
		if lift_t <= 0.0 and alive():
			mood = "calm"
	yank_t = maxf(0.0, yank_t - dt * 0.4)


## A friend's screen only gets `mood`: add on what's happening to us
## ("angry+ice+wet") so their copy shows the ice, bubble, sparks and goo too.
func _show_status() -> void:
	var s := mood.get_slice("+", 0)
	if frozen_t > 0.0:
		s += "+ice"
	if bubble_t > 0.0:
		s += "+bubble"
	if stun_t > 0.0:
		s += "+zap"
	if goo_t > 0.0:
		s += "+goo"
	if wet > 0.3:
		s += "+wet"
	mood = s


## True if `flag` (ice, bubble, zap, goo, wet) is showing, here or on a friend's screen.
func shows(flag: String) -> bool:
	var m: String = String(net.get("mood", mood)) if puppet else mood
	return m.contains("+" + flag)


## The face part of the mood (angry, scared, frozen, zapped…).
func face() -> String:
	var m: String = String(net.get("mood", mood)) if puppet else mood
	return m.get_slice("+", 0)


# ------------------------------------------------------------------- AI
func enemy_of(o) -> bool:
	if o == self or not (o is Fighter) or not o.alive():
		return false
	if team == "wild" and o.team == "wild":
		return o.type != type and not (o.pers == "peaceful" and pers == "peaceful")
	return o.team != team


func physics_step(dt: float) -> void:
	if mood.contains("+"):
		mood = mood.get_slice("+", 0)
	wind = _wind_next
	_wind_next = Vector2.ZERO
	_step(dt)
	if frozen_t > 0.0 or bubble_t > 0.0 or stun_t > 0.0 or goo_t > 0.0 or wet > 0.3:
		_show_status()


func _step(dt: float) -> void:
	if frozen_t <= 0.0:
		t += dt   # (frozen: the tail and wings stop wagging too)
	flash = maxf(0.0, flash - dt * 4.0)
	cool = maxf(0.0, cool - dt)
	swing = maxf(0.0, swing - dt)
	reload_t = maxf(0.0, reload_t - dt)   # reloading goes on between fights too
	_effects_step(dt)
	if burning > 0.0:
		burning -= dt
		hurt(12.0 * dt)
		if randf() < 0.3:
			world.fx_event("burn", {"p": center() + Vector2(randf_range(-8, 8), randf_range(-30, 10)) * size})
	if acid > 0.0:
		acid -= dt
		hurt(18.0 * dt)
	match state:
		"dead":
			dead_t += dt
			if dead_t > 90.0 and world.auto_clean:
				world.remove(uid, false)
				return
			if _resting:
				# lying still: nothing to do until something moves us (wake), but now and
				# then check that whatever we lie on is still there
				_support_t -= dt
				if _support_t <= 0.0:
					_support_t = REST_CHECK
					if not _supported():
						wake()
				return
			_solve_limits(dt)
			_rest_check(dt)
			return
		"ragdoll":
			if frozen_t > 0.0:
				return   # an ice block: nothing moves
			_solve_limits(dt)
			down_t += dt
			var tor = parts.get("torso")
			var slow: bool = tor != null and is_instance_valid(tor) and tor.linear_velocity.length() < 70.0
			if held_by.is_empty() and down_t > 1.5 and slow and lift_t <= 0.0:
				stand_up()
			return
	if not is_instance_valid(body) or frozen_t > 0.0:
		return
	if wind.length() > TUMBLE_WIND:
		ragdoll(wind * 0.5, true)   # blown clean off our feet
		return
	if hit_t > 0.0:
		hit_t -= dt
		if hit_t <= 0.0:
			_melee_hit(_hit_wd)
			# the blow can knock ourselves over (a barrel right next to us)
			if state != "stand" or not is_instance_valid(body):
				return
	_ground_check()
	if weapon_toy and is_instance_valid(weapon_toy):
		var hand := _hand_world()
		var rot := aim if _wtype() in ["gun", "launcher", "flame"] else (aim if swing <= 0.0 else aim + (PI * 0.5 - _swing_angle()) * facing)
		var flip := 1.0 if cos(rot) >= 0.0 else -1.0
		weapon_toy.set_facing(flip)
		var xf := Transform2D(rot if flip > 0.0 else rot + PI, hand)
		weapon_toy.global_transform = xf
		PhysicsServer2D.body_set_state(weapon_toy.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, xf)
	elif weapon_id != "":
		weapon_id = ""
	if bubble_t > 0.0:
		# floating off in a bubble, paddling helplessly
		var rise := -85.0 * clampf(sqrt(4.0 / weight()), 0.5, 1.0)
		var drift := Vector2(sin(world.vision_time * 1.7 + uid) * 40.0, rise) + wind * 0.5
		body.linear_velocity = body.linear_velocity.lerp(drift, minf(1.0, dt * 2.5))
		walk += dt * 9.0
		move = 0.0
		return
	if lift_t > 0.0:
		walk += dt * 12.0   # legs kicking in the tractor beam
		move = 0.0
		mood = "scared"
		return
	if stun_t > 0.0:
		move = 0.0
		if randf() < dt * 8.0:
			flash = 0.8
		_locomote(dt)
		return
	if player_id >= 0:
		_player(dt)
	elif world.battle_on:
		think_t -= dt
		if think_t <= 0.0:
			think_t = randf_range(0.12, 0.22)
			_think()
		_act(dt)
	else:
		move = move_toward(move, 0.0, dt * 4.0)
	_locomote(dt)


## Knocked out: once we've come to a stop (and nothing's holding, burning,
## beaming or tying us, and we aren't lying on something that moves), our
## bodies freeze where they are until wake().
func _rest_check(dt: float) -> void:
	if puppet or not held_by.is_empty() or burning > 0.0 or acid > 0.0 or lift_t > 0.0 or frozen_t > 0.0 \
			or parts.is_empty() or not parts.has("torso") or world.gravity_vec().length() < REST_GRAVITY:
		_rest_t = 0.0
		_still_t = 0.0
		_rest_at.clear()
		_roam_at = Vector2.INF
		return
	var calm := _rest_at.size() == parts.size()
	var on_moving := false
	for k in parts:
		var p = parts[k]
		if not is_instance_valid(p):
			continue
		if p.on_moving:
			on_moving = true
		if calm and p.global_position.distance_to(_rest_at[k]) > (REST_BODY if k == "torso" else REST_LIMB):
			calm = false
	if on_moving:
		# lying on (or against) a Wiggly: it could hop out from under us
		_rest_t = 0.0
		_still_t = 0.0
		_rest_at.clear()
		_roam_at = Vector2.INF
		return
	if calm:
		_rest_t += dt
	else:
		_rest_t = 0.0
		_rest_at.clear()
		for k in parts:
			if is_instance_valid(parts[k]):
				_rest_at[k] = parts[k].global_position
	var tor := center()
	if _roam_at == Vector2.INF or tor.distance_to(_roam_at) > REST_ROAM:
		_roam_at = tor
		_still_t = 0.0
	else:
		_still_t += dt
	if (_rest_t >= REST_AFTER or _still_t >= REST_STUBBORN) and world.links_of(uid).is_empty():
		_resting = true
		for k in parts:
			if is_instance_valid(parts[k]):
				_rest_at[k] = parts[k].global_position
		_support_t = REST_CHECK * (0.5 + float(uid % 7) / 7.0)   # (spread out over the steps)
		for p in parts.values():
			if is_instance_valid(p):
				p.linear_velocity = Vector2.ZERO
				p.angular_velocity = 0.0
				p.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
				p.freeze = true


## Lying still: is any of our parts still touching the ground, a platform, a
## toy or someone else (a couple of pixels in the direction of gravity)?
## If what we lay on went (a toy knocked away, a Wiggly hopping off), we fall.
func _supported() -> bool:
	if _touch_q == null:
		_touch_q = PhysicsShapeQueryParameters2D.new()
		_touch_q.collision_mask = Toy.LAYER_GROUND | Toy.LAYER_TOYS | Toy.LAYER_WIGGLIES | LAYER
	var down: Vector2 = world.gravity_vec().normalized() * 3.0
	var mine: Array[RID] = []
	for p in parts.values():
		if is_instance_valid(p):
			mine.append(p.get_rid())
	_touch_q.exclude = mine
	var space: PhysicsDirectSpaceState2D = world.get_world_2d().direct_space_state
	for p in parts.values():
		if not is_instance_valid(p) or p.get_child_count() == 0:
			continue
		var cs := p.get_child(0) as CollisionShape2D
		if cs == null or cs.shape == null:
			continue
		_touch_q.shape = cs.shape
		_touch_q.transform = p.global_transform.translated(down)
		if not space.intersect_shape(_touch_q, 1).is_empty():
			return true
	return false


## Something hit us while we lay still (World._handle_impacts): wake up and
## take some of the blow, as if we'd been loose all along. `from` is where it
## came from, `m` how heavy it is.
func knocked_while_resting(from: Vector2, closing: float, m: float) -> void:
	wake()
	var dir := (center() - from).normalized()
	var dv := dir * closing * m / (m + weight())
	for p in all_bodies():
		p.linear_velocity += dv


## A knocked-out ragdoll lying still moves again: a blast or a bump, a fan,
## a beam, a grab, the gravity changing, the ground (or whatever it lay on)
## going. Frozen bodies don't feel any of that by themselves, so everything
## that can move them calls this first (see also World.wake_resting and
## World._handle_impacts).
func wake(and_neighbours := true) -> void:
	if not _resting:
		return
	_resting = false
	_rest_t = 0.0
	_still_t = 0.0
	_rest_at.clear()
	_roam_at = Vector2.INF
	for p in parts.values():
		if is_instance_valid(p):
			p.freeze = false
	# anyone lying on (or right next to) us moves too; further into a heap,
	# _supported() notices soon enough if we were holding someone up
	if and_neighbours:
		world.wake_resting(center(), radius() * 1.5, false)


func is_resting() -> bool:
	return _resting


func _swing_angle() -> float:
	var k := 1.0 - swing / _swing_time()
	return lerpf(-2.4, 1.0, ease(k, 0.4))


func _ground_check() -> void:
	grounded = false
	var hs := half_size()
	var from := body.global_position + Vector2(0, hs.y - 6.0)
	var q := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 16.0 * maxf(1.0, size)), Toy.LAYER_GROUND | Toy.LAYER_TOYS)
	q.exclude = [body.get_rid()]
	if weapon_toy and is_instance_valid(weapon_toy):
		q.exclude = [body.get_rid(), weapon_toy.get_rid()]
	var hit: Dictionary = world.get_world_2d().direct_space_state.intersect_ray(q)
	grounded = not hit.is_empty()


func _locomote(dt: float) -> void:
	# attacking can knock ourselves over (a barrel right next to us), so check again
	if state != "stand" or not is_instance_valid(body):
		return
	var speed := float(def.get("speed", 150.0)) * (1.3 if pers == "berserk" else 1.0) * (1.7 if charge_t > 0.0 else 1.0)
	speed *= minf(1.0, sqrt(size))
	if world.in_liquid(center()) != "":
		speed *= 0.5
	if goo_t > 0.0:
		speed *= 0.4   # gummed up
		charge_t = 0.0
	charge_t = maxf(0.0, charge_t - dt)
	var v := body.linear_velocity
	if def.get("flies", false):
		var want := Vector2(move * speed, 0) + wind
		if target and is_instance_valid(target):
			var dy: float = target.center().y - 60.0 - body.global_position.y
			if absf(target.center().x - body.global_position.x) < 120.0:
				dy = target.center().y - body.global_position.y   # swoop
			want.y = clampf(dy * 2.0, -200.0, 260.0)
		else:
			want.y = clampf((home.y - 220.0 - body.global_position.y) * 1.5, -150.0, 150.0)
		body.linear_velocity = v.lerp(want, minf(1.0, dt * 3.0))
		walk += dt * 12.0
		return
	var accel := (1400.0 if grounded else 450.0) * dt
	# fans and wind carry us along (walking into the wind gets us nowhere)
	v.x = move_toward(v.x, move * speed + wind.x, accel + absf(wind.x) * dt * 2.0)
	v.y += wind.y * dt * 3.0
	body.linear_velocity = v
	if absf(move) > 0.05:
		facing = signf(move) if target == null or player_id >= 0 or pers == "coward" and mood == "scared" else facing
		walk += dt * speed / (22.0 * size)
	else:
		walk = lerpf(walk, roundf(walk / PI) * PI, dt * 6.0)
	# Stuck? Judge by how far we actually got, not by speed: pushing a barrel or
	# jostling in a crowd at a wall gives little bumps of speed but no progress.
	if absf(move) > 0.3 and grounded and player_id < 0:
		stuck_t += dt
		if stuck_t >= 0.45:
			if absf(body.global_position.x - stuck_x) < 12.0 * size:
				want_jump = true
			stuck_t = 0.0
			stuck_x = body.global_position.x
	else:
		stuck_t = 0.0
		stuck_x = body.global_position.x
	if want_jump and grounded:
		want_jump = false
		stuck_t = 0.0
		var jv := 560.0 * (1.15 if def.get("jumpy", false) else 1.0) * (0.8 if beast else 1.0) * (0.6 if goo_t > 0.0 else 1.0)
		body.linear_velocity.y = -jv * sqrt(maxf(0.6, size))
		world.fx_event("jump", {"p": body.global_position + Vector2(0, half_size().y)})


func _think() -> void:
	# medics look after hurt teammates first
	if def.get("heals", false):
		var hurt_ally = _nearest(func(o): return o != self and o is Fighter and o.alive() and o.team == team and o.hp < o.max_hp * 0.75, 700.0)
		if hurt_ally:
			set_meta("heal_target", hurt_ally)
		else:
			remove_meta("heal_target")
	if pers == "peaceful":
		target = null
		return
	var guard: bool = pers == "defend" and not world.brave      # 📣 CHARGE!: guards leave their post too
	if target == null or not is_instance_valid(target) or not target.alive() or (guard and target.center().distance_to(center()) > 1500.0):
		# defenders watch as far as their weapon reaches (a sniper sees a long way)
		var watch := 1400.0 if not guard else maxf(900.0, _reach() * 1.05)
		target = _nearest(func(o): return enemy_of(o), watch)
		# nobody close by: everyone except guards goes looking for a fight, so a
		# battle never stalls with two armies waiting at opposite ends
		if target == null and not guard:
			target = _nearest(func(o): return enemy_of(o), INF)
	elif pers != "defend" and target.center().distance_to(center()) > 600.0:
		# chasing someone far away: switch if somebody closer shows up
		var closer = _nearest(func(o): return enemy_of(o), target.center().distance_to(center()) * 0.6)
		if closer:
			target = closer


func _nearest(pred: Callable, max_d: float):
	var best = null
	var bd := max_d
	for o in world.fighters():
		if pred.call(o):
			var d: float = o.center().distance_to(center())
			if d < bd:
				bd = d
				best = o
	return best


func _act(dt: float) -> void:
	var c := center()
	if has_meta("heal_target"):
		var ally = get_meta("heal_target")
		if is_instance_valid(ally) and ally.alive():
			var d: Vector2 = ally.center() - c
			move = clampf(d.x / 60.0, -1.0, 1.0) if absf(d.x) > 50.0 else 0.0
			if d.length() < 90.0:
				ally.hp = minf(ally.max_hp, ally.hp + 25.0 * dt)
				if ally.state == "ragdoll":
					ally.down_t = 99.0
				if randf() < dt * 3.0:
					world.fx_event("heal", {"p": ally.center()})
			return
	if target == null or not is_instance_valid(target):
		_wander(dt)
		mood = "calm"
		return
	var tc: Vector2 = target.center()
	var d := tc - c
	var dist := d.length()
	var wt := _wtype()
	var reach := _reach()
	var ranged := wt in ["gun", "launcher", "bow", "throw", "flame"]
	mood = "angry"
	facing = signf(d.x) if absf(d.x) > 4.0 else facing
	aim = _aim_at(tc, wt)
	# where do we want to stand?
	var want := 0.0
	var scared := pers == "coward" and hp < max_hp * 0.5
	if scared:
		mood = "scared"
		want = -signf(d.x)
	elif pers == "defend" and home.distance_to(tc) > 420.0:
		# guard the spot: go home, keep watch
		want = clampf((home.x - c.x) / 80.0, -1.0, 1.0) if absf(home.x - c.x) > 40.0 else 0.0
	elif ranged:
		var near := reach * (0.35 if wt == "flame" else 0.45)
		var far := reach * (0.75 if pers != "ranged" else 0.65)
		if dist > far or _blind_t > 2.0:
			# too far, or a wall's been in the way for a while: go round (or hop over)
			want = signf(d.x)
		elif dist < near and pers == "ranged":
			want = -signf(d.x)
	else:
		if absf(d.x) > reach * 0.7:
			want = signf(d.x)
	if world.brave:
		# 📣 a stand-off: charge right up to them (off towers, over walls)
		want = signf(d.x) if absf(d.x) > minf(reach * 0.5, 60.0) else 0.0
	# spread out a little from teammates so armies don't stack into one blob
	var push := 0.0
	for o in world.fighters():
		if o != self and o.team == team and o.state == "stand":
			var dx: float = c.x - o.center().x
			if absf(dx) < 26.0 * size and absf(c.y - o.center().y) < 60.0:
				push += (1.0 if dx >= 0.0 else -1.0) * (1.0 - absf(dx) / (26.0 * size))
	# the spreading nudge never cancels walking toward the enemy
	var nudge := clampf(push * 0.6, -0.5, 0.5)
	if want != 0.0 and signf(nudge) != signf(want):
		nudge *= 0.25
	move = clampf(want + nudge, -1.0, 1.0)
	if wt == "beast" and String(def.get("attack", "")) == "charge" and dist < 420.0 and dist > reach and cool <= 0.0:
		charge_t = 0.8
	if scared:
		return
	# attack when in range
	if dist <= reach + radius() * 0.6 + target.radius() * 0.5 and cool <= 0.0:
		if ranged and not _clear_shot(tc):
			_blind_t += dt
			if randf() < 0.1:
				want_jump = true
			return
		_blind_t = 0.0
		_attack(tc, wt)


func _wander(dt: float) -> void:
	wander_t -= dt
	if wander_t <= 0.0:
		wander_t = randf_range(1.0, 3.0)
		wander_dir = 0.0 if randf() < 0.4 else (-1.0 if randf() < 0.5 else 1.0)
		if pers == "defend" and center().distance_to(home) > 60.0:
			wander_dir = signf(home.x - center().x)
	move = wander_dir * (0.5 if pers != "defend" else 0.8)


func _aim_at(tc: Vector2, wt: String) -> float:
	var from := center() + Vector2(0, -20.0 * size)
	var d := tc - from
	if wt == "bow" or wt == "throw":
		var v := 900.0 if wt == "bow" else 620.0
		var g := 980.0
		var x := absf(d.x)
		var y := -d.y
		var v2 := v * v
		var disc := v2 * v2 - g * (g * x * x + 2.0 * y * v2)
		if disc >= 0.0 and x > 1.0:
			var ang := atan((v2 - sqrt(disc)) / (g * x))
			return (-ang if d.x >= 0.0 else PI + ang)
		return (-PI * 0.25 if d.x >= 0.0 else -PI * 0.75)
	return d.angle()


func _clear_shot(tc: Vector2) -> bool:
	var from := center() + Vector2(0, -20.0 * size)
	var q := PhysicsRayQueryParameters2D.create(from, tc, Toy.LAYER_GROUND)
	return world.get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _attack(tc: Vector2, wt: String) -> void:
	var wd := _wdef()
	match wt:
		"melee", "beast":
			cool = _rate()
			swing = _swing_time()
			swing_hit = false
			if beast and String(def.get("voice", "")) != "" and randf() < 0.4:
				world.fx_event("voice", {"p": center(), "v": String(def.voice)})
			world.fx_event("swing", {"p": center(), "fists": wd.get("fists", false), "beast": beast})
			# the blow lands halfway through the swing (counted in physics steps, so ⏸ pause stops it)
			hit_t = _swing_time() * 0.5
			_hit_wd = wd
		"gun":
			if int(wd.get("burst", 0)) > 0:
				if reload_t > 0.0:
					cool = reload_t   # still reloading: try again when it's done
					return
				ammo -= 1
				if ammo <= 0:
					ammo = int(wd.burst)
					reload_t = float(wd.get("reload", 1.5))
					world.fx_event("reload", {"p": center()})
			cool = _rate() * randf_range(0.9, 1.2)
			var muzzle := _muzzle()
			for i in int(wd.get("pellets", 1)):
				var ang := aim + randf_range(-1.0, 1.0) * float(wd.get("spread", 0.03))
				world.shoot(self, muzzle, ang, float(wd.get("range", 800.0)), float(wd.get("dmg", 15.0)), float(wd.get("knock", 120.0)), bool(wd.get("laser", false)))
			world.fx_event("shot", {"p": muzzle, "a": aim, "s": String(wd.get("sound", "gun_pistol")), "laser": wd.get("laser", false)})
		"launcher":
			cool = _rate()
			world.launch(self, "rocket", _muzzle(), aim + randf_range(-0.04, 0.04), 950.0)
			world.fx_event("shot", {"p": _muzzle(), "a": aim, "s": "bazooka"})
		"bow":
			cool = _rate()
			world.launch(self, "arrow", _muzzle(), aim + randf_range(-0.03, 0.03), 900.0)
			world.fx_event("bow", {"p": _muzzle()})
		"throw":
			cool = _rate()
			world.launch(self, "grenade", _hand_world(), aim + randf_range(-0.05, 0.05), 620.0)
			world.fx_event("pin", {"p": center()})
		"flame":
			cool = _rate()
			world.flame(self, _muzzle(), aim, float(wd.get("range", 220.0)), float(wd.get("dmg", 40.0)) * _rate())


func _muzzle() -> Vector2:
	var hand := _hand_world()
	var len := 26.0
	if weapon_toy and is_instance_valid(weapon_toy):
		len = weapon_toy.w * 0.5 * weapon_toy.size_scale
	return hand + Vector2.from_angle(aim) * len


func _melee_hit(wd: Dictionary) -> void:
	if state != "stand" or puppet:
		return
	var reach := float(wd.get("reach", 40.0)) * (size if not beast else 1.0)
	# A beast decides to attack counting its own body (see _act), so it hits
	# from there too. Otherwise big or resized beasts swung at thin air.
	var body_x := radius() * 0.6 if beast else 0.0
	var c := center()
	var front := c + Vector2(facing * (reach * 0.6 + body_x), -10.0 * size)
	var kind := String(def.get("attack", "bite")) if beast else "melee"
	var hit_any := false
	for o in world.fighters():
		if not enemy_of(o) and not (team == "wild" and o.team == "wild" and o != self and o.type != type):
			continue
		var oc: Vector2 = o.center()
		var d := oc - c
		var in_front: bool = signf(d.x) == facing or absf(d.x) < o.radius()
		var area: bool = absf(d.x) < reach + body_x + o.radius() * 0.8 and absf(d.y) < reach * 0.7 + o.radius()
		if kind == "stomp":
			area = d.length() < reach + body_x + o.radius() * 0.5
			in_front = true
		elif kind == "tail":
			area = absf(d.x) < reach + body_x + o.radius() * 0.8 and absf(d.y) < reach * 0.6 + o.radius()
			in_front = true
		if area and in_front:
			var knock_dir := Vector2(signf(d.x) if d.x != 0.0 else facing, -0.55).normalized()
			o.hurt(float(wd.get("dmg", 10.0)), knock_dir * float(wd.get("knock", 300.0)), self)
			hit_any = true
	# hit toys and Wigglies too
	for t2 in world.things.values():
		if t2 is Toy and not t2.extra.has("held_by") and not t2.freeze and t2.global_position.distance_to(front) < reach * 0.8:
			t2.linear_velocity += Vector2(facing, -0.4).normalized() * float(wd.get("knock", 300.0)) * clampf(2.0 / t2.mass, 0.1, 1.5)
			if t2.def.has("breaks"):
				ToyLogic.impact(world, t2, null, 9999.0, t2.global_position)
			elif t2.id == "barrel":
				ToyLogic.trigger(world, t2)
		elif t2 is Wiggly and t2.com.distance_to(front) < reach:
			t2.add_velocity(Vector2(facing, -0.6).normalized() * float(wd.get("knock", 300.0)))
	if kind == "stomp":
		world.fx_event("stomp", {"p": c + Vector2(0, half_size().y), "r": reach})
	elif kind == "charge" and hit_any:
		charge_t = 0.0
	if hit_any:
		world.fx_event("hit", {"p": front, "s": String(wd.get("sound", "punch")), "beast": beast})


func _player(dt: float) -> void:
	move = move_input
	aim = (aim_point - (center() + Vector2(0, -20.0 * size))).angle()
	if absf(aim_point.x - center().x) > 6.0:
		facing = signf(aim_point.x - center().x)
	if want_attack and cool <= 0.0:
		var wt := _wtype()
		if wt == "bow" or wt == "throw":
			aim = _aim_at(aim_point, wt)
		_attack(aim_point, wt)
	mood = "angry" if want_attack else "calm"


# --------------------------------------------------------------- drawing
func _process(_d: float) -> void:
	if puppet and not shows("ice"):
		t += _d
	queue_redraw()


func _draw() -> void:
	FighterArt.draw(self)

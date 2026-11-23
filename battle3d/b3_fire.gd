class_name B3Fire
extends Node3D
## 🔥 Wooden buildings and trees catch fire. Napalm, fireball patches and
## dragon fire set the wood they touch alight (a fireball hitting a wooden
## tower does too, B3Proj._fire_burst); it burns with big cartoon flames,
## slowly turns charcoal-black, sets fighters touching it on fire, spreads to
## wood and trees close by, and then collapses: a burning building piece
## breaks into (charred) chunks when it's burnt through, a burning tree falls
## over after TREE_LIFE seconds. Stone, concrete, sandbags and rocks don't burn.
##
## One per battle, made the first time something needs it (B3Fire.of). It
## only burns while the battle is on (Fight!). On a friend's computer (👥) the
## host says what catches fire ("burn" events, B3Net); the breaking and
## falling come over as the usual "brk" and "uproot" events, and the flames
## are made here from that (nothing more is sent while it burns).

## Buildings made of wood (B3Struct kinds; History fences and stakes too).
const WOOD_BUILDINGS := ["tower", "ramp", "bridge", "fence", "stakes"]
## Scenery (B3World "scenery" kinds) that burns.
const TREES := ["tree", "pine", "pine_snow", "deadtree", "palm", "olive"]
const CHAR := Color("2a2019")        # charcoal
const MAX_BURNING := 24              # no more than this many fires at once
const PIECE_DPS := 10.0              # health a burning piece loses each second
const TREE_LIFE := 7.0               # seconds a tree burns before it falls over
const SPREAD_R := 2.0                # fire jumps to wood this far from the edge of a fire...
const SPREAD_P := 0.3                # ...with this chance each second
const NET_LIFE := 40.0               # a friend's copy: flames go out after this long anyway

class Burn:
	var node: Node3D = null
	var tree := false
	var t := 0.0
	var fx: CPUParticles3D = null
	var spread_t := 1.0
	var hot_t := 0.0
	var step := 0
	var box := AABB()

var battle = null
var burning: Array[Burn] = []
var _dying: Array = []           # [flames, seconds left]: going out (the last flames still rising)
var _scan_t := 0.0
var _q := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()
var _rng := RandomNumberGenerator.new()


## The battle's fire keeper (made the first time it's asked for).
static func of(b) -> B3Fire:
	var f: Node = b.get_node_or_null("B3Fire")
	if f is B3Fire and is_instance_valid(f) and not f.is_queued_for_deletion():
		return f as B3Fire
	var nf := B3Fire.new()
	nf.name = "B3Fire"
	nf.battle = b
	nf._rng.seed = 7177
	b.add_child(nf)
	return nf


## True if `n` is wood that can catch fire: a piece of a wooden building or
## a tree that's still standing.
static func flammable(n: Object) -> bool:
	if n == null or not is_instance_valid(n) or (n as Node).is_queued_for_deletion():
		return false
	if n is B3Piece:
		var pc := n as B3Piece
		if pc.has_meta("wood"):
			return true
		var s: Variant = pc.structure
		return s is B3Struct and is_instance_valid(s) and WOOD_BUILDINGS.has(String((s as B3Struct).kind))
	if n is StaticBody3D and (n as Node).has_meta("scenery") and not (n as Node).has_meta("gone"):
		return TREES.has(String((n as Node).get_meta("scenery")))
	return false


func _ready() -> void:
	_q.shape = _sphere
	_q.collision_mask = B3Defs.L_STRUCT | B3Defs.L_SCENERY
	_q.collide_with_areas = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func is_burning(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.has_meta("burning")


## Sets `n` alight (if it's wood, not burning already and there aren't too
## many fires). On the host it's sent to friends. True if it caught.
func ignite(n: Node) -> bool:
	if not flammable(n) or n.has_meta("burning") or burning.size() >= MAX_BURNING:
		return false
	n.set_meta("burning", true)
	var bn := Burn.new()
	bn.node = n as Node3D
	bn.tree = not (n is B3Piece)
	bn.spread_t = 0.8 + _rng.randf() * 0.4
	bn.box = _box(bn)
	bn.fx = _flames(bn.box)
	burning.append(bn)
	if battle.net and not _remote():
		if bn.tree:
			var sid: int = battle.world.scenery_index(n)
			if sid >= 0:
				battle.net.rec_event(["burn", "t", sid])
		else:
			var pc := n as B3Piece
			var s: Variant = pc.structure
			if s is B3Struct and is_instance_valid(s):
				battle.net.rec_event(["burn", "p", (s as Node).get_instance_id(), int(pc.get_meta("pi", -1))])
	if _rng.randf() < 0.5:
		battle.snd("crackle", bn.box.get_center(), 0.6)
	return true


## Sets alight every bit of wood within `r` of `p` (a fireball hitting a tower).
func ignite_near(p: Vector3, r: float) -> int:
	var n := 0
	for o in _wood_near(p, r):
		if ignite(o):
			n += 1
	return n


func _wood_near(p: Vector3, r: float) -> Array[Node]:
	var out: Array[Node] = []
	_sphere.radius = r
	_q.transform = Transform3D(Basis.IDENTITY, p)
	for hit in battle.space().intersect_shape(_q, 32):
		var c: Object = hit.collider
		if c != null and flammable(c) and not (c as Node).has_meta("burning"):
			out.append(c as Node)
	return out


## Where the flames go: a building piece's box, or a tree's leafy top.
func _box(bn: Burn) -> AABB:
	if not bn.tree:
		return (bn.node as B3Piece).world_aabb()
	var ks := float(bn.node.get_meta("ks", 1.0))
	var p := bn.node.global_position
	var top := 2.4 if String(bn.node.get_meta("scenery", "tree")) != "palm" else 3.8
	return AABB(p + Vector3(-1.0, top * 0.55, -1.0) * ks, Vector3(2.0, top * 0.75, 2.0) * ks)


func _flames(box: AABB) -> CPUParticles3D:
	var e: CPUParticles3D = battle.fx.make_particles("fire")
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var h := box.size * 0.5
	e.emission_box_extents = Vector3(clampf(h.x, 0.15, 1.6), clampf(h.y, 0.1, 1.4), clampf(h.z, 0.15, 1.6))
	e.amount = int(clampf(box.size.length() * 6.0, 10, 30))
	e.scale_amount_min = 0.45
	e.scale_amount_max = 1.0
	e.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(e)
	e.global_position = box.get_center()
	e.emitting = true
	return e


func _remote() -> bool:
	return battle != null and battle.get("puppet") == true


func _physics_process(dt: float) -> void:
	if dt <= 0.0 or battle == null:
		return
	var k := 0
	while k < _dying.size():
		var d: Array = _dying[k]
		d[1] = float(d[1]) - dt
		if float(d[1]) <= 0.0:
			if is_instance_valid(d[0]):
				(d[0] as Node).queue_free()
			_dying.remove_at(k)
			continue
		k += 1
	var remote := _remote()
	if not battle.fighting:
		if not burning.is_empty():
			put_out()      # (⏮ reset, cleared, or a new battle being set up)
		return
	if not remote:
		_scan_t -= dt
		if _scan_t <= 0.0:
			_scan_t = 0.5
			_scan_hazards()
	var i := 0
	while i < burning.size():
		var bn := burning[i]
		if not _tick(bn, dt, remote):
			_end(bn)
			burning.remove_at(i)
			continue
		i += 1


## Patches of fire (napalm, fireballs, dragon fire) set the wood they touch
## alight. Lava doesn't: a bridge over a lava moat (🧩 Hold the Bridge) or
## the volcano's trees would just burn down before anyone had a fight.
func _scan_hazards() -> void:
	for h: B3Hazard in battle.hazards:
		if not is_instance_valid(h) or h.kind != "fire":
			continue
		for o in _wood_near(h.global_position + Vector3(0, 0.6, 0), h.radius + 0.5):
			ignite(o)


## One burning thing for one step. False when it's over (burnt through,
## fallen, or gone some other way).
func _tick(bn: Burn, dt: float, remote: bool) -> bool:
	var n := bn.node
	if n == null or not is_instance_valid(n) or n.is_queued_for_deletion() or n.has_meta("gone"):
		return false
	bn.t += dt
	var life := TREE_LIFE
	if not bn.tree:
		var pc := n as B3Piece
		life = bn.t + maxf(pc.hp, 0.0) / PIECE_DPS
	_char(bn, clampf(bn.t / maxf(life, 0.1), 0.0, 1.0))
	if remote:
		return bn.t < NET_LIFE
	# fighters touching it catch fire too
	bn.hot_t -= dt
	if bn.hot_t <= 0.0:
		bn.hot_t = 0.5
		_scorch_fighters(bn)
	# it spreads to wood close by
	bn.spread_t -= dt
	if bn.spread_t <= 0.0:
		bn.spread_t = 1.0
		var c := bn.box.get_center()
		for o in _wood_near(c, bn.box.size.length() * 0.5 + SPREAD_R):
			if _rng.randf() < SPREAD_P:
				ignite(o)
	if bn.tree:
		if bn.t >= TREE_LIFE:
			_fell(bn)
			return false
		return true
	var pc2 := n as B3Piece
	pc2.hp -= PIECE_DPS * dt
	if pc2.hp <= 0.0:
		# burnt through: it falls in one charred piece (sent to friends), and
		# whatever it held up falls too
		var v := Vector3(_rng.randf_range(-1.5, 1.5), 0.6, _rng.randf_range(-1.5, 1.5))
		var st: Variant = pc2.structure
		battle.break_piece(pc2, v, true)
		if st is B3Struct and is_instance_valid(st):
			battle._settle_soon(st as B3Struct)
		return false
	return true


## Fighters standing in (or on) a burning thing start burning (dragons
## don't mind; B3Unit's burn hurts by the usual Battle Rules).
func _scorch_fighters(bn: Burn) -> void:
	var box := bn.box
	var c := box.get_center()
	for u: B3Unit in battle.units_near(c, maxf(box.size.x, box.size.z) * 0.5 + 0.5, 1.0):
		if u.down or u.dead or u.kind == "dragon":
			continue
		var q := u.position
		var dx := q.x - clampf(q.x, box.position.x, box.end.x)
		var dz := q.z - clampf(q.z, box.position.z, box.end.z)
		var r := u.radius + 0.25
		if dx * dx + dz * dz < r * r and q.y + u.tall > box.position.y and q.y < box.end.y + 0.25:
			u.burn_t = maxf(u.burn_t, 2.0)


## A tree that's burnt through falls over, black (the fall is sent to friends).
func _fell(bn: Burn) -> void:
	var sb := bn.node as StaticBody3D
	var a := _rng.randf() * TAU
	var vel := Vector3(cos(a), 0.4, sin(a)) * 2.5
	var sid: int = battle.world.scenery_index(sb)
	if battle.net and sid >= 0:
		battle.net.rec_event(["uproot", sid, vel])
	battle.world.uproot(sb, vel, battle)
	battle.fx.poof(bn.box.get_center(), 1.0)
	battle.snd("wood_crunch", sb.global_position, 0.7)


## Darkens it towards charcoal as it burns (in a few steps, so there are
## only a few colours to make).
func _char(bn: Burn, k: float) -> void:
	var step := int(k * 4.0)
	if step <= bn.step:
		return
	bn.step = step
	var f := minf(0.85, step * 0.22)
	var n := bn.node
	if n.has_meta("mm"):
		var mm: MultiMesh = n.get_meta("mm")
		var mi: int = n.get_meta("mi")
		if not n.has_meta("tint0"):
			n.set_meta("tint0", n.get_meta("tint", Color.WHITE))
		var t0: Color = n.get_meta("tint0")
		var tc := t0.lerp(CHAR, f)
		n.set_meta("tint", tc)       # (a tree that falls keeps the colour, B3World.uproot)
		if mi >= 0 and mi < mm.instance_count:
			mm.set_instance_color(mi, tc)
		return
	_char_meshes(n, f)


func _char_meshes(n: Node, f: float) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var m := mi.material_override as StandardMaterial3D
			if m == null:
				continue
			if not mi.has_meta("col0"):
				mi.set_meta("col0", m.albedo_color)
			var c0: Color = mi.get_meta("col0")
			mi.material_override = B3Mats.mat(Color(c0.lerp(CHAR, f), c0.a), 0.95)


func _end(bn: Burn) -> void:
	if bn.fx != null and is_instance_valid(bn.fx):
		bn.fx.emitting = false
		_dying.append([bn.fx, 1.2])
	if bn.node != null and is_instance_valid(bn.node):
		bn.node.remove_meta("burning")


## Every fire goes out (the battle stopped).
func put_out() -> void:
	for bn in burning:
		_end(bn)
	burning.clear()


## 👥 A friend's copy: the host says thing `n` caught fire.
func net_ignite(n: Node) -> void:
	if n != null and is_instance_valid(n):
		ignite(n)

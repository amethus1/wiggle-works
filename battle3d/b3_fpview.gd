class_name B3FPView
extends Node3D
## What you see in your hands in first person: a copy of the played fighter's
## weapon (gun, sword, bow, staff...) in the lower right of the view. It bobs
## while you walk, kicks back when you shoot and swings when you hit.
## Shield carriers also get their shield, which comes up on the left while
## you hold right-click (B3Player "shield"; it drops while you swing). Looking through a sniper's scope
## hides the rifle. Animals, dinosaurs and vehicles don't get one.

var unit: B3Unit = null
var model: Node3D = null
var shield: Node3D = null
var hold := "none"
var _bob := 0.0
var _base := Transform3D.IDENTITY
var _guard := 0.0
# the shield in camera space (x right, y up, -z forward): its face (+y in the
# rig's shield space) to the front and its top (-z there) up
const SHIELD_BASIS := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))
const SHIELD_DOWN := Vector3(-0.4, -0.66, -0.55)
const SHIELD_UP := Vector3(-0.36, -0.24, -0.55)


func setup(u: B3Unit) -> void:
	unit = u
	if u == null or u.rig == null or u is B3Vehicle:
		return
	var rig: B3Rig = u.rig
	hold = rig.hold
	if rig.shield and B3Player.power(u) == "shield":
		_add_shield(rig)
	var arm_name := "arm_l" if hold == "bow" else "arm_r"
	var arm: Node3D = rig.pv.get(arm_name)
	if arm == null:
		return
	var hand := arm.get_node_or_null("Hand") as Node3D
	if hand != null:
		model = hand.duplicate() as Node3D
	else:
		model = _arm_end(arm)      # the Robot: its laser cannon is built onto its arm
		if model == null:
			return
	model.transform = Transform3D.IDENTITY
	add_child(model)
	_in_view(model)
	# camera space: x right, y up, -z forward. The weapon's own forward is +z.
	match hold:
		"gun":
			_base = Transform3D(Basis(Vector3.UP, PI), Vector3(0.26, -0.24, -0.42))
		"bow":
			_base = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.FORWARD, 0.25), Vector3(-0.2, -0.18, -0.55))
		"staff":
			_base = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.25), Vector3(0.36, -0.95, -0.7))
		"melee", "slam":
			_base = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.9) * Basis(Vector3.FORWARD, 0.35), Vector3(0.36, -0.42, -0.55))
		"throw":
			_base = Transform3D(Basis(Vector3.UP, PI), Vector3(0.3, -0.3, -0.45))
		_:
			model.queue_free()
			model = null
			return
	model.scale = Vector3.ONE * 0.8
	transform = _base


## A copy of the shield on the fighter's left arm, held low (out of view)
## until you raise it.
func _add_shield(rig: B3Rig) -> void:
	var al: Node3D = rig.pv.get("arm_l")
	var src := al.get_node_or_null("Shield") as Node3D if al else null
	if src == null:
		return
	shield = src.duplicate() as Node3D
	add_child(shield)
	_in_view(shield)
	shield.visible = false


## A copy of part of the model, drawn by the first-person camera without
## shadows. The model's shadow-only meshes (see B3Rig._merge) aren't needed.
func _in_view(n: Node3D) -> void:
	for c in n.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi is GeometryInstance3D and (vi as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			vi.free()
			continue
		vi.layers = 1
		if vi.has_meta("fp_layers"):
			vi.remove_meta("fp_layers")
		if vi is GeometryInstance3D:
			(vi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A copy of what's built onto the end of an arm (past the forearm), turned
## to point forward like a held weapon. For fighters without a "Hand", like
## the Robot with its laser cannon. Null if there's nothing there.
func _arm_end(arm: Node3D) -> Node3D:
	var n := Node3D.new()
	# the arm hangs down its -y; a held weapon points along +z
	var turn := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.7))
	for c in arm.get_children():
		if c is VisualInstance3D and (c as Node3D).position.y < -0.65 and not (c is GeometryInstance3D and (c as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY):
			var m := (c as Node3D).duplicate() as Node3D
			m.transform = turn * (c as Node3D).transform
			n.add_child(m)
	if n.get_child_count() == 0:
		n.free()
		return null
	return n


func _process(dt: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if model == null:
		if shield:
			visible = not unit.down
			_shield_tick(dt, transform, Vector3.ZERO)
		return
	visible = not unit.down
	model.visible = not B3Player.scoped(unit, B3Player.me)      # (the scope is right at your eye)
	var spd := unit._spd
	if spd > 0.5:
		_bob += dt * (6.0 + spd * 1.2)
	var bob := Vector3(sin(_bob) * 0.012, absf(cos(_bob)) * 0.014, 0.0) * clampf(spd / 3.0, 0.0, 1.0)
	var rec: float = unit.rig.recoil if unit.rig else 0.0
	var xf := _base
	xf.origin += bob + Vector3(0, 0.02 * rec, 0.07 * rec)
	var k := clampf(unit.act_t / unit.act_len, 0.0, 1.0) if unit.act_len > 0.0 else 0.0
	var s := 0.0
	if unit.act in ["attack", "throw"] and hold in ["melee", "slam", "throw"]:
		s = sin(k * PI)
	if s > 0.0:
		xf.basis = xf.basis * Basis(Vector3.RIGHT, s * 1.2) * Basis(Vector3.UP, -s * 0.5)
		xf.origin += Vector3(-0.12 * s, 0.05 * s, -0.12 * s)
	elif unit.act == "thrust":
		xf.origin += Vector3(-0.05, 0.03, -0.3) * sin(k * PI)      # the bayonet jabs forward
	elif unit.act == "kick":
		xf.origin += Vector3(0.0, -0.07, 0.04) * sin(k * PI)      # leaning back for a kick
	elif rec > 0.0:
		xf.basis = xf.basis * Basis(Vector3.RIGHT, -rec * 0.12)
	transform = xf
	_shield_tick(dt, xf, bob)


## The shield comes up on the left while right-click is held (or a friend's
## copy says it's up), and drops back out of view when let go, or while you
## swing (B3Player.guard_wanted: block or swing, not both).
func _shield_tick(dt: float, xf: Transform3D, bob: Vector3) -> void:
	if shield == null:
		return
	var up := unit.shield_up or (B3Player.unit == unit and B3Player.guard_wanted(unit, B3Player.me))
	_guard = move_toward(_guard, 1.0 if up else 0.0, dt * 7.0)
	shield.visible = _guard > 0.02
	if not shield.visible:
		return
	var g := smoothstep(0.0, 1.0, _guard)
	var at := SHIELD_DOWN.lerp(SHIELD_UP, g) + bob * 0.6
	var want := Transform3D((Basis(Vector3.FORWARD, -0.15 * g) * SHIELD_BASIS).scaled(Vector3.ONE * 0.48), at)
	shield.transform = xf.affine_inverse() * want      # it's ours to move, not the weapon's

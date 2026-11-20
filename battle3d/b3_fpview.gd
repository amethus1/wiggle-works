class_name B3FPView
extends Node3D
## What you see in your hands in first person: a copy of the played fighter's
## weapon (gun, sword, bow, staff...) in the lower right of the view. It bobs
## while you walk, kicks back when you shoot and swings when you hit.
## Animals, dinosaurs and vehicles don't get one.

var unit: B3Unit = null
var model: Node3D = null
var hold := "none"
var _bob := 0.0
var _base := Transform3D.IDENTITY


func setup(u: B3Unit) -> void:
	unit = u
	if u == null or u.rig == null or u is B3Vehicle:
		return
	var rig: B3Rig = u.rig
	hold = rig.hold
	var arm_name := "arm_l" if hold == "bow" else "arm_r"
	var arm: Node3D = rig.pv.get(arm_name)
	if arm == null:
		return
	var hand := arm.get_node_or_null("Hand") as Node3D
	if hand == null:
		return
	model = hand.duplicate() as Node3D
	model.transform = Transform3D.IDENTITY
	add_child(model)
	for c in model.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		vi.layers = 1
		if vi.has_meta("fp_layers"):
			vi.remove_meta("fp_layers")
		if vi is GeometryInstance3D:
			(vi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


func _process(dt: float) -> void:
	if model == null or unit == null or not is_instance_valid(unit):
		return
	visible = not unit.down
	var spd := unit._spd
	if spd > 0.5:
		_bob += dt * (6.0 + spd * 1.2)
	var bob := Vector3(sin(_bob) * 0.012, absf(cos(_bob)) * 0.014, 0.0) * clampf(spd / 3.0, 0.0, 1.0)
	var rec: float = unit.rig.recoil if unit.rig else 0.0
	var xf := _base
	xf.origin += bob + Vector3(0, 0.02 * rec, 0.07 * rec)
	var s := 0.0
	if unit.act != "" and unit.act != "shoot" and unit.act_len > 0.0 and hold in ["melee", "slam", "throw"]:
		s = sin(clampf(unit.act_t / unit.act_len, 0.0, 1.0) * PI)
	if s > 0.0:
		xf.basis = xf.basis * Basis(Vector3.RIGHT, s * 1.2) * Basis(Vector3.UP, -s * 0.5)
		xf.origin += Vector3(-0.12 * s, 0.05 * s, -0.12 * s)
	elif rec > 0.0:
		xf.basis = xf.basis * Basis(Vector3.RIGHT, -rec * 0.12)
	transform = xf

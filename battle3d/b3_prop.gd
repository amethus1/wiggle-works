class_name B3Prop
extends RigidBody3D
## Physical things that aren't fighters: crates, boom barrels, dynamite, C4,
## landmines and sandbags. They fly around in blasts; the explosive ones go
## off when shot, blasted, stepped on (mines) or detonated (C4).

static var _pmat: PhysicsMaterial = null

var battle = null
var kind := "crate"
var hp := 40.0
var fuse := -1.0
var lit := false
var led: MeshInstance3D = null
var spark: MeshInstance3D = null
var age := 0.0
var sinking := 0.0
var _t := 0.0
var _trig_t := 0.0


static func pmat() -> PhysicsMaterial:
	if _pmat == null:
		_pmat = PhysicsMaterial.new()
		_pmat.friction = 0.7
		_pmat.bounce = 0.1
	return _pmat


func setup(b, k: String) -> void:
	battle = b
	kind = k
	collision_layer = B3Defs.L_PROP
	collision_mask = B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_RAGDOLL | B3Defs.L_PROP | B3Defs.L_SCENERY
	physics_material_override = pmat()
	angular_damp = 0.8
	var cs := CollisionShape3D.new()
	match kind:
		"crate":
			mass = 25.0
			hp = 45.0
			var wood := B3Mats.mat(Color("c08a4e"))
			B3Mats.add(self, B3Mats.box(Vector3(1, 1, 1)), wood)
			var dark := B3Mats.mat(Color("8a5a30"))
			for a in [Vector3(0, 0, 0), Vector3(0, 90, 0), Vector3(90, 0, 0)]:
				B3Mats.add(self, B3Mats.box(Vector3(1.02, 0.14, 1.02)), dark, Vector3.ZERO, a, Vector3(1, 1, 1), false)
			var bs := BoxShape3D.new()
			bs.size = Vector3(1, 1, 1)
			cs.shape = bs
		"xbarrel":
			mass = 40.0
			hp = 25.0
			B3Mats.add(self, B3Mats.cyl(0.42, 0.42, 1.1, 16), B3Mats.mat(Color("e0392b"), 0.5))
			for y in [-0.32, 0.32]:
				B3Mats.add(self, B3Mats.cyl(0.43, 0.43, 0.1, 16), B3Mats.mat(Color("2a2a30"), 0.4), Vector3(0, y, 0), Vector3.ZERO, Vector3.ONE, false)
			B3Mats.add(self, B3Mats.cyl(0.43, 0.43, 0.22, 16), B3Mats.mat(Color("ffcc1a")), Vector3(0, 0.0, 0), Vector3.ZERO, Vector3.ONE, false)
			B3Mats.add(self, B3Mats.cyl(0.36, 0.36, 0.04, 16), B3Mats.mat(Color("b02a20")), Vector3(0, 0.56, 0), Vector3.ZERO, Vector3.ONE, false)
			var c := CylinderShape3D.new()
			c.radius = 0.42
			c.height = 1.1
			cs.shape = c
		"dynamite":
			mass = 4.0
			hp = 999.0
			for i in 3:
				var x := (i - 1) * 0.13
				B3Mats.add(self, B3Mats.cyl(0.065, 0.065, 0.55, 10), B3Mats.mat(Color("e03a2e"), 0.6), Vector3(x, 0, 0))
			B3Mats.add(self, B3Mats.box(Vector3(0.42, 0.08, 0.15)), B3Mats.mat(Color("3a2a20")), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE, false)
			B3Mats.add(self, B3Mats.cyl(0.012, 0.012, 0.25, 4), B3Mats.mat(Color("2a2a2a")), Vector3(0, 0.38, 0), Vector3(0, 0, 20), Vector3.ONE, false)
			spark = B3Mats.add(self, B3Mats.sphere(0.06, 6), B3Mats.glow(Color(1.0, 0.8, 0.3), 5.0), Vector3(0.04, 0.5, 0), Vector3.ZERO, Vector3.ONE, false)
			var bs2 := BoxShape3D.new()
			bs2.size = Vector3(0.42, 0.55, 0.15)
			cs.shape = bs2
			fuse = 3.0
			lit = true
		"c4":
			mass = 3.0
			hp = 999.0
			B3Mats.add(self, B3Mats.box(Vector3(0.45, 0.14, 0.32)), B3Mats.mat(Color("b8a77a"), 0.8))
			B3Mats.add(self, B3Mats.box(Vector3(0.47, 0.05, 0.08)), B3Mats.mat(Color("2a2a30")), Vector3(0, 0.0, 0.08), Vector3.ZERO, Vector3.ONE, false)
			B3Mats.add(self, B3Mats.box(Vector3(0.14, 0.04, 0.1)), B3Mats.mat(Color("222226")), Vector3(0.1, 0.09, -0.05), Vector3.ZERO, Vector3.ONE, false)
			led = B3Mats.add(self, B3Mats.sphere(0.04, 6), B3Mats.glow(Color(1.0, 0.15, 0.1), 6.0), Vector3(-0.12, 0.09, -0.05), Vector3.ZERO, Vector3.ONE, false)
			var bs3 := BoxShape3D.new()
			bs3.size = Vector3(0.45, 0.14, 0.32)
			cs.shape = bs3
		"mine":
			mass = 6.0
			hp = 999.0
			B3Mats.add(self, B3Mats.cyl(0.36, 0.4, 0.12, 16), B3Mats.mat(Color("4a4f45"), 0.6))
			B3Mats.add(self, B3Mats.cyl(0.12, 0.12, 0.06, 10), B3Mats.mat(Color("8a8f85"), 0.4), Vector3(0, 0.08, 0), Vector3.ZERO, Vector3.ONE, false)
			led = B3Mats.add(self, B3Mats.sphere(0.035, 6), B3Mats.glow(Color(1.0, 0.2, 0.1), 5.0), Vector3(0.2, 0.07, 0), Vector3.ZERO, Vector3.ONE, false)
			var c2 := CylinderShape3D.new()
			c2.radius = 0.4
			c2.height = 0.12
			cs.shape = c2
		"sandbag":
			mass = 30.0
			hp = 999.0
			B3Mats.add(self, B3Mats.box(Vector3(0.95, 0.42, 0.5)), B3Mats.mat(Color("d4bb86"), 0.95))
			var bs4 := BoxShape3D.new()
			bs4.size = Vector3(0.95, 0.42, 0.5)
			cs.shape = bs4
	add_child(cs)
	if kind == "mine" or kind == "c4":
		freeze = true


func damage(d: float) -> void:
	if kind == "dynamite" or kind == "c4" or kind == "mine":
		if d >= 4.0:
			trigger(randf_range(0.08, 0.3))
		return
	hp -= d
	if hp > 0.0:
		return
	if kind == "xbarrel":
		trigger(randf_range(0.15, 0.45))
	elif kind == "crate":
		battle.break_crate(self)


## Goes off after `t` seconds (chain reactions use a short random delay).
func trigger(t: float) -> void:
	if lit and fuse >= 0.0 and fuse <= t:
		return
	lit = true
	fuse = t
	if kind == "mine":
		battle.snd("pin", global_position, 0.8)
	if kind == "xbarrel":
		battle.snd("fizz", global_position, 0.6)


func _boom() -> void:
	var d: Dictionary = B3Defs.BOOMS.get(kind, B3Defs.BOOMS.grenade)
	var p := global_position
	var opts := {}
	if kind == "mine":
		opts["up"] = 1.6
	battle.remove_prop(self, false)
	battle.explode(p, float(d.radius), float(d.power), float(d.dmg), opts)


func _physics_process(dt: float) -> void:
	if dt <= 0.0:
		return
	age += dt
	_t += dt
	if sinking > 0.0:
		sinking += dt
		global_position.y -= dt * 0.5
		if sinking > 2.2:
			battle.remove_prop(self, false)
		return
	if lit and fuse >= 0.0:
		fuse -= dt
		if kind == "xbarrel" and int(_t * 20.0) % 2 == 0:
			battle.fx.flame(global_position + Vector3(randf_range(-0.2, 0.2), 0.6, randf_range(-0.2, 0.2)))
		if fuse <= 0.0:
			_boom()
			return
	if kind == "mine" and not lit:
		_trig_t -= dt
		if _trig_t <= 0.0 and age > 1.0:
			_trig_t = 0.1
			var at := global_position
			for u: B3Unit in battle.units_near(at, 1.1):
				if u.down or u.dead or u.flying:
					continue
				var dx := u.position.x - at.x
				var dz := u.position.z - at.z
				if dx * dx + dz * dz < 1.2 and absf(u.position.y - at.y) < 1.2:
					trigger(0.25)
					break
	if absf(global_position.x) > B3Defs.BOUNDS + 10.0 or absf(global_position.z) > B3Defs.BOUNDS + 10.0 or global_position.y < -20.0:
		battle.remove_prop(self, false)


func _process(_dt: float) -> void:
	if led:
		var on := int(_t * (2.0 if not lit else 12.0)) % 2 == 0
		led.visible = on
	if spark:
		spark.scale = Vector3.ONE * randf_range(0.7, 1.4)
		spark.position.y = 0.5 - (3.0 - maxf(fuse, 0.0)) * 0.03

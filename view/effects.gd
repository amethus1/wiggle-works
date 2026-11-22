class_name Effects
extends CanvasLayer
## Turns game events into particles, comic text pops, shockwave rings, lights,
## screen shake, flashes and sounds. Lives on its own layer that follows the
## camera, so fireworks and sparks stay bright at night.

const MAX_P := 2600
# Particle kinds (what _draw_part draws).
const KINDS := {"soft": 0, "dot": 1, "spark": 2, "streak": 3, "confetti": 4, "shard": 5, "star": 6, "bubble": 7,
	"note": 8, "heart": 9, "line": 10, "plus": 11, "plane": 12, "bolt": 13}
const _BUF := MAX_P * 2

var world: Node = null
var view_rect := Rect2(-800, -500, 1600, 1000)
var shake := 0.0
var flash := Color(1, 1, 1, 0)
# The particles, oldest first, one array per property (no dictionary per
# particle). They live in slots _head.._tail-1; a particle that dies leaves a
# hole (_dead) until the slots are packed together again, and when there are
# MAX_P the oldest makes room for the next.
var _n := 0
var _head := 0
var _tail := 0
var _dead := PackedByteArray()
var _pp := PackedVector2Array()     # position
var _pv := PackedVector2Array()     # velocity
var _life := PackedFloat64Array()
var _max := PackedFloat64Array()
var _pr := PackedFloat64Array()     # size
var _col := PackedColorArray()
var _kind := PackedInt32Array()     # KINDS (-1: not drawn)
var _grav := PackedFloat64Array()
var _glows := PackedByteArray()
var _drag := PackedFloat64Array()
var _rot := PackedFloat64Array()
var _spin := PackedFloat64Array()
var _to := PackedVector2Array()     # the far end of a tracer or bolt
var _has_to := PackedByteArray()
var rings: Array = []
var pops: Array = []         # comic text
var weather := {}            # rain / snow / wind seconds left
var trails := {}             # uid -> seconds (flying fireworks)
var _glow: Node2D
var _norm: Node2D
var _flash_rect: ColorRect
var _lights: Array = []


func _init() -> void:
	# (packed arrays are values: resize each one itself, not a copy in a loop)
	_dead.resize(_BUF)
	_pp.resize(_BUF)
	_pv.resize(_BUF)
	_life.resize(_BUF)
	_max.resize(_BUF)
	_pr.resize(_BUF)
	_col.resize(_BUF)
	_kind.resize(_BUF)
	_grav.resize(_BUF)
	_glows.resize(_BUF)
	_drag.resize(_BUF)
	_rot.resize(_BUF)
	_spin.resize(_BUF)
	_to.resize(_BUF)
	_has_to.resize(_BUF)


func _ready() -> void:
	layer = 5
	follow_viewport_enabled = true
	_norm = Node2D.new()
	_norm.draw.connect(_draw_norm)
	add_child(_norm)
	_glow = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	var fl := CanvasLayer.new()
	fl.layer = 15
	add_child(fl)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	fl.add_child(_flash_rect)


func clear() -> void:
	_n = 0
	_head = 0
	_tail = 0
	rings.clear()
	pops.clear()
	weather.clear()
	trails.clear()


# ---------------------------------------------------------------- spawning
func _p(pos: Vector2, vel: Vector2, life: float, r: float, col: Color, kind := "soft", g := 0.0, glow := false, drag := 1.2) -> void:
	if _n >= MAX_P:
		# full: the oldest one goes
		while _dead[_head] != 0:
			_head += 1
		_head += 1
		_n -= 1
	if _tail >= _BUF:
		_pack()
	var i := _tail
	_tail += 1
	_n += 1
	_dead[i] = 0
	_pp[i] = pos
	_pv[i] = vel
	_life[i] = life
	_max[i] = life
	_pr[i] = r
	_col[i] = col
	_kind[i] = int(KINDS.get(kind, -1))
	_grav[i] = g
	_glows[i] = 1 if glow else 0
	_drag[i] = drag
	_rot[i] = randf() * TAU
	_spin[i] = randf_range(-8, 8)
	_has_to[i] = 0


## The newest particle (a tracer or a bolt) reaches over to `to`.
func _last_to(to: Vector2) -> void:
	_to[_tail - 1] = to
	_has_to[_tail - 1] = 1


func particle_count() -> int:
	return _n


## Closes up the holes left by particles that died (keeping their order).
func _pack() -> void:
	var w := 0
	for i in range(_head, _tail):
		if _dead[i] != 0:
			continue
		if i != w:
			_dead[w] = 0
			_pp[w] = _pp[i]
			_pv[w] = _pv[i]
			_life[w] = _life[i]
			_max[w] = _max[i]
			_pr[w] = _pr[i]
			_col[w] = _col[i]
			_kind[w] = _kind[i]
			_grav[w] = _grav[i]
			_glows[w] = _glows[i]
			_drag[w] = _drag[i]
			_rot[w] = _rot[i]
			_spin[w] = _spin[i]
			_to[w] = _to[i]
			_has_to[w] = _has_to[i]
		w += 1
	_head = 0
	_tail = w


func burst(pos: Vector2, n: int, speed: Vector2, life: Vector2, r: Vector2, col: Color, kind := "soft", g := 0.0, glow := false, vary := 0.0) -> void:
	for i in n:
		var a := randf() * TAU
		var c := col
		if vary > 0.0:
			c = Color.from_hsv(fposmod(col.h + randf_range(-vary, vary), 1.0), col.s, col.v, col.a)
		_p(pos, Vector2.from_angle(a) * randf_range(speed.x, speed.y), randf_range(life.x, life.y), randf_range(r.x, r.y), c, kind, g, glow)


func cone(pos: Vector2, dir: Vector2, spread: float, n: int, speed: Vector2, life: Vector2, r: Vector2, col: Color, kind := "soft", g := 0.0, glow := false) -> void:
	for i in n:
		var a := dir.angle() + randf_range(-spread, spread)
		_p(pos, Vector2.from_angle(a) * randf_range(speed.x, speed.y), randf_range(life.x, life.y), randf_range(r.x, r.y), col, kind, g, glow)


func ring(pos: Vector2, rad: float, col: Color, life := 0.45, width := 6.0) -> void:
	rings.append({"p": pos, "r": rad, "col": col, "life": life, "max": life, "w": width})


func pop(pos: Vector2, txt: String, col: Color, size := 34) -> void:
	for q in pops:
		if q.t == txt and q.p.distance_to(pos) < 120.0 and q.life > q.max - 0.4:
			return   # don't stack the same word on top of itself
	pops.append({"p": pos, "t": txt, "col": col, "life": 0.9, "max": 0.9, "s": size, "rot": randf_range(-0.25, 0.25)})


func light(pos: Vector2, col: Color, energy: float, scale_f: float, life: float) -> void:
	if world == null:
		return
	var l := PointLight2D.new()
	l.texture = Art.light_texture()
	l.color = col
	# lights matter at night; by day they would just wash everything out
	energy *= 1.0 if world.night else 0.25
	l.texture_scale = scale_f
	l.position = pos
	l.energy = energy
	l.blend_mode = Light2D.BLEND_MODE_ADD
	world.add_child(l)
	_lights.append({"n": l, "life": life, "max": life, "e": energy})
	if _lights.size() > 14:
		var old: Dictionary = _lights.pop_front()
		if is_instance_valid(old.n):
			old.n.queue_free()


func add_shake(v: float) -> void:
	shake = maxf(shake, v)


func do_flash(c: Color, a: float) -> void:
	flash = Color(c.r, c.g, c.b, maxf(flash.a, a))


# ----------------------------------------------------------------- events
func handle(name: String, a: Dictionary) -> void:
	var p: Vector2 = a.get("p", Vector2.ZERO)
	match name:
		"spawn":
			burst(p, 14, Vector2(60, 200), Vector2(0.3, 0.6), Vector2(3, 6), Color(1.6, 1.5, 0.9), "star", 0.0, true)
			ring(p, 50.0, Color(1, 1, 1, 0.8), 0.3, 4.0)
			Sfx.play("spawn", p)
		"poof":
			burst(p, 12, Vector2(30, 120), Vector2(0.35, 0.7), Vector2(10, 20), Color(1, 1, 1, 0.7), "soft", -0.1)
			Sfx.play("poof", p)
		"hop":
			burst(p, 6, Vector2(30, 110), Vector2(0.25, 0.45), Vector2(5, 10), Color(0.85, 0.8, 0.7, 0.55), "soft", -0.1)
			Sfx.play("hop", p, 0.7, 1.2 / maxf(0.5, float(a.get("s", 1.0))))
			if randf() < 0.25:
				Sfx.play("giggle%d" % (1 + randi() % 3), p, 0.6, 1.1 / maxf(0.5, float(a.get("s", 1.0))))
		"squish":
			var k := String(a.get("k", "bloop"))
			var col: Color = Catalog.WIGGLIES.get(k, Catalog.WIGGLIES.bloop).color
			var v := float(a.get("v", 300.0))
			burst(p, int(clampf(v / 120.0, 2, 10)), Vector2(40, 180), Vector2(0.25, 0.5), Vector2(3, 6), col, "dot", 0.8)
			Sfx.play("squish", p, clampf(v / 700.0, 0.25, 1.0), 1.1 / maxf(0.5, float(a.get("s", 1.0))))
		"thud", "clink", "boing", "tink":
			var v := float(a.get("v", 300.0))
			var s := clampf(v / 800.0, 0.2, 1.2)
			if name == "clink" and v > 450.0:
				burst(p, 6, Vector2(80, 260), Vector2(0.12, 0.3), Vector2(1.5, 3), Color(2.0, 1.7, 0.8), "dot", 0.6, true)
			elif v > 400.0:
				burst(p, 5, Vector2(30, 120), Vector2(0.3, 0.5), Vector2(6, 12), Color(0.85, 0.8, 0.7, 0.45), "soft", -0.1)
			if a.get("big", false):
				Sfx.play("boing_big", p, 1.0)
				pop(p + Vector2(0, -30), "BOING!", Color("00cec9"), 26)
			else:
				Sfx.play(name, p, s)
			if v > 1100.0 and float(a.get("m", 1.0)) > 5.0:
				add_shake(6.0)
		"ding":
			_p(p + Vector2(0, -30), Vector2(30, -80), 1.0, 12.0, Color(1.5, 1.3, 0.5), "note", -0.05, true)
			Sfx.play("ding", p)
		"click":
			Sfx.play("click", p, 0.6, 1.2 if a.get("on", true) else 0.9)
		"tick":
			Sfx.play("tick", p, 0.35)
		"grab":
			Sfx.play("grab", p, 0.35)
		"nail":
			ring(p, 18.0, Color(1, 1, 1, 0.8), 0.25, 3.0)
			Sfx.play("click", p, 0.7, 0.7)
		"link":
			burst(p, 8, Vector2(40, 140), Vector2(0.2, 0.4), Vector2(2, 4), Color(1.6, 1.5, 0.9), "star", 0.0, true)
			Sfx.play("link", p)
		"snap":
			Sfx.play("snap", p)
		"paint":
			burst(p, 12, Vector2(60, 220), Vector2(0.3, 0.6), Vector2(3, 7), a.get("c", Color.WHITE), "dot", 0.9)
			Sfx.play("paint", p)
		"fuse":
			Sfx.play("fuse", p)
		"special":
			_special(String(a.get("k", "")), p, float(a.get("r", 30.0)))
		"zap":
			for h in a.get("hits", []):
				_bolt(p, h)
			ring(p, float(a.get("r", 180.0)), Color(1.2, 1.8, 2.2, 0.8), 0.35, 5.0)
			light(p, Color(0.6, 0.9, 1.0), 2.0, 2.5, 0.35)
			pop(p + Vector2(0, -50), "ZAP!", Color("ffd43b"))
			Sfx.play("zap", p)
		"heat":
			cone(p, Vector2.UP, PI, 40, Vector2(60, 260), Vector2(0.3, 0.6), Vector2(6, 14), Color(2.2, 1.1, 0.3), "soft", -0.4, true)
			light(p, Color(1.0, 0.6, 0.3), 2.0, 2.5, 0.5)
			Sfx.play("flame", p)
		"freeze":
			var r := float(a.get("r", 160.0))
			burst(p, 40, Vector2(40, r * 1.6), Vector2(0.4, 0.8), Vector2(3, 6), Color(1.2, 1.7, 2.0), "star", 0.0, true)
			ring(p, r, Color(0.8, 0.95, 1.0, 0.9), 0.5, 6.0)
			Sfx.play("freeze", p)
		"thaw":
			burst(p, 6, Vector2(20, 60), Vector2(0.3, 0.6), Vector2(2, 4), Color(0.7, 0.9, 1.0), "dot", 1.0)
			Sfx.play("thaw", p, 0.6)
		"ice_pop":
			# a frozen fighter breaks out of its ice block
			var ir := clampf(float(a.get("r", 40.0)), 20.0, 140.0)
			for i in int(10 + ir * 0.15):
				_p(p + Vector2(randf_range(-ir, ir) * 0.5, randf_range(-ir, ir) * 0.6), Vector2(randf_range(-280, 280), randf_range(-360, -40)), randf_range(0.5, 1.0), randf_range(4, 9), Color(0.8, 0.95, 1.0, 0.9), "shard", 1.0)
			ring(p, ir * 1.2, Color(0.85, 0.97, 1.0, 0.9), 0.3, 4.0)
			pop(p + Vector2(0, -ir - 20), "CRACK!" if a.get("smash", false) else "POP!", Color("8fe8ff"), 28)
			Sfx.play("glass" if a.get("smash", false) else "thaw", p, 0.8, 1.2)
		"zap_chain":
			# Zappy's zap jumping from soldier to soldier
			for pr in a.get("pairs", []):
				if pr is Array and pr.size() == 2 and pr[0] is Vector2 and pr[1] is Vector2:
					_bolt(pr[0], pr[1])
					burst(pr[1], 4, Vector2(60, 200), Vector2(0.1, 0.25), Vector2(1.5, 3), Color(1.6, 2.0, 2.6), "spark", 0.4, true)
			Sfx.play("zap", p, 0.5, 1.3)
		"spark":
			burst(p, 8, Vector2(60, 220), Vector2(0.1, 0.3), Vector2(1.5, 3), Color(2.4, 2.0, 0.9), "spark", 0.5, true)
			Sfx.play("zap", p, 0.35, 1.6)
		"yoink":
			# a magnet pulls a weapon out of someone's hands
			burst(p, 6, Vector2(40, 160), Vector2(0.2, 0.4), Vector2(1.5, 3), Color(2.0, 0.8, 0.8), "dot", 0.0, true)
			pop(p + Vector2(0, -30), "YOINK!", Color("e74c3c"), 26)
			Sfx.play("clink", p, 0.8, 1.3)
		"bowled":
			# something heavy knocked a fighter flat
			pop(p + Vector2(0, -50), ["BONK!", "WHAM!", "BOWLED!"][randi() % 3], Color("ffd43b"), 28)
			burst(p, 6, Vector2(60, 200), Vector2(0.2, 0.4), Vector2(3, 5), Color(2.0, 1.8, 0.6), "star", 0.2, true)
			Sfx.play("bonk", p, clampf(float(a.get("v", 300.0)) / 500.0, 0.4, 1.0))
		"pound":
			ring(p, float(a.get("r", 220.0)), Color(0.95, 0.9, 0.8, 0.8), 0.45, 10.0)
			cone(p, Vector2.UP, PI * 0.5, 22, Vector2(80, 300), Vector2(0.4, 0.8), Vector2(10, 20), Color(0.8, 0.75, 0.65, 0.5), "soft", 0.2)
			add_shake(12.0)
			pop(p + Vector2(0, -60), "POUND!", Color("9aa3b5"))
			Sfx.play("pound", p)
		"warp":
			var bp: Vector2 = a.get("b", p)
			for q in [a.get("a", p), bp]:
				burst(q, 26, Vector2(60, 260), Vector2(0.35, 0.7), Vector2(3, 6), Color(1.6, 1.2, 2.2), "star", 0.0, true, 0.15)
			ring(bp, 70.0, Color(1.4, 1.0, 2.0), 0.4, 5.0)
			Sfx.play("warp", bp)
		"split":
			var col: Color = Catalog.WIGGLIES.get(String(a.get("k", "bloop")), Catalog.WIGGLIES.bloop).color
			burst(p, 22, Vector2(60, 300), Vector2(0.3, 0.7), Vector2(4, 8), col, "dot", 0.9)
			pop(p + Vector2(0, -40), "POP!", col.lightened(0.2))
			Sfx.play("split", p)
		"merge":
			_p(p + Vector2(0, -40), Vector2(0, -60), 1.1, 14.0, Color(2.0, 0.7, 1.0), "heart", 0.0, true)
			burst(p, 16, Vector2(40, 160), Vector2(0.3, 0.6), Vector2(3, 5), Color(1.8, 1.2, 1.6), "star", 0.0, true)
			Sfx.play("merge", p)
		"boom", "mega_boom":
			_explode(p, float(a.get("r", 240.0)), name == "mega_boom")
		"confetti":
			var dir: Vector2 = a.get("dir", Vector2.UP)
			for i in 70:
				var ang := dir.angle() + randf_range(-0.55, 0.55)
				_p(p, Vector2.from_angle(ang) * randf_range(250, 750), randf_range(1.2, 2.2), randf_range(3, 6), Catalog.PAINT[randi() % 8], "confetti", 0.35, false, 1.6)
			pop(p + dir * 40.0, "POP!", Color("ff9ff3"))
			Sfx.play("confetti", p)
		"firework_launch":
			trails[int(a.get("uid", 0))] = 1.3
			Sfx.play("firework_launch", p)
		"firework_burst":
			var c1: Color = a.get("c", Color.RED)
			var c2: Color = a.get("c2", Color.YELLOW)
			for i in 140:
				var ang := randf() * TAU
				var sp := randf_range(120, 520) * (1.0 if i % 3 else 0.6)
				var c := c1 if i % 2 == 0 else c2
				_p(p, Vector2.from_angle(ang) * sp, randf_range(1.0, 1.8), randf_range(2.5, 4.5), Color(c.r * 2.2, c.g * 2.2, c.b * 2.2), "spark", 0.18, true, 1.6)
			ring(p, 90.0, Color(c1.r * 2.0, c1.g * 2.0, c1.b * 2.0, 0.8), 0.4, 4.0)
			light(p, c1.lightened(0.3), 3.0, 5.0, 0.9)
			Sfx.play("firework_burst", p, 1.2)
		"paint_splat":
			var c: Color = a.get("c", Color.MAGENTA)
			burst(p, 46, Vector2(120, float(a.get("r", 200.0)) * 2.4), Vector2(0.4, 0.9), Vector2(5, 12), c, "dot", 1.0)
			ring(p, float(a.get("r", 200.0)), Color(c.r, c.g, c.b, 0.7), 0.4, 8.0)
			pop(p + Vector2(0, -40), "SPLAT!", c)
			Sfx.play("splat", p)
		"bubble_burst":
			for i in 30:
				_p(p + Vector2(randf_range(-40, 40), randf_range(-30, 30)), Vector2(randf_range(-160, 160), randf_range(-260, -40)), randf_range(1.0, 2.2), randf_range(6, 16), Color(0.8, 0.95, 1.0, 0.85), "bubble", -0.15)
			pop(p + Vector2(0, -40), "BLOOP!", Color("74d7ff"))
			Sfx.play("bubble", p, 1.0)
		"bubble":
			var dir: Vector2 = a.get("dir", Vector2.RIGHT)
			for i in 3:
				_p(p, dir * randf_range(100, 220) + Vector2(0, randf_range(-60, -20)), randf_range(1.2, 2.4), randf_range(6, 14), Color(0.8, 0.95, 1.0, 0.85), "bubble", -0.1)
			Sfx.play("bubble", p, 0.35, randf_range(0.9, 1.3))
		"pop_bubble":
			ring(p, float(a.get("r", 40.0)), Color(0.85, 1.0, 1.0, 0.9), 0.2, 3.0)
			burst(p, 8, Vector2(60, 160), Vector2(0.2, 0.4), Vector2(2, 3), Color(0.85, 1.0, 1.0, 0.9), "dot", 0.8)
			Sfx.play("bubble_pop", p)
		"glue", "glue_splat":
			burst(p, 18 if name == "glue_splat" else 5, Vector2(40, 220), Vector2(0.4, 0.8), Vector2(4, 9), Color(1.0, 0.86, 0.35), "dot", 1.0)
			if name == "glue_splat":
				pop(p + Vector2(0, -40), "SPLURT!", Color("fdcb6e"))
			Sfx.play("glue", p)
		"shatter":
			var c: Color = a.get("c", Color(0.8, 0.95, 1.0))
			for i in 16:
				_p(p + Vector2(randf_range(-10, 10), randf_range(-20, 20)), Vector2(randf_range(-260, 260), randf_range(-320, 40)), randf_range(0.6, 1.2), randf_range(4, 9), Color(c.r, c.g, c.b, 0.9), "shard", 1.0)
			Sfx.play("glass" if a.get("glass", false) else "tink", p, 1.0, 0.8)
		"steam":
			burst(p, 14, Vector2(20, 90), Vector2(0.6, 1.2), Vector2(10, 22), Color(1, 1, 1, 0.55), "soft", -0.3)
			Sfx.play("steam", p)
		"splash":
			var s := clampf(float(a.get("s", 1.0)), 0.4, 2.5)
			cone(p, Vector2.UP, 0.9, int(14 * s), Vector2(120, 380 * s), Vector2(0.4, 0.8), Vector2(2.5, 5), Color(0.75, 0.9, 1.0, 0.9), "dot", 1.0)
			ring(p, 40.0 * s, Color(0.85, 0.97, 1.0, 0.8), 0.35, 3.0)
			Sfx.play("splash", p, clampf(s, 0.4, 1.0))
		"cannon":
			var dir: Vector2 = a.get("dir", Vector2.RIGHT)
			cone(p, dir, 0.4, 12, Vector2(60, 220), Vector2(0.3, 0.7), Vector2(8, 16), Color(0.9, 0.9, 0.9, 0.6), "soft", -0.1)
			cone(p, dir, 0.3, 8, Vector2(100, 300), Vector2(0.1, 0.2), Vector2(4, 8), Color(2.0, 1.4, 0.5), "soft", 0.0, true)
			light(p, Color(1.0, 0.8, 0.5), 1.5, 1.5, 0.15)
			Sfx.play("cannon", p)
		"thrust":
			cone(p, a.get("dir", Vector2.LEFT), 0.25, 2, Vector2(160, 320), Vector2(0.15, 0.3), Vector2(5, 10), Color(2.2, 1.2, 0.35), "soft", 0.0, true)
		"exhaust":
			cone(p, a.get("dir", Vector2.LEFT), 0.4, 1, Vector2(30, 90), Vector2(0.4, 0.8), Vector2(5, 10), Color(0.7, 0.7, 0.7, 0.4), "soft", -0.2)
		"wind":
			var dir: Vector2 = a.get("dir", Vector2.RIGHT)
			_p(p + dir.orthogonal() * randf_range(-20, 20), dir * randf_range(300, 500), 0.5, 18.0, Color(1, 1, 1, 0.5), "streak", 0.0)
		"magnet":
			burst(p, 2, Vector2(20, 60), Vector2(0.2, 0.4), Vector2(1.5, 2.5), Color(2.0, 0.8, 0.8), "dot", 0.0, true)
		"balloon_pop":
			burst(p, 10, Vector2(80, 240), Vector2(0.3, 0.6), Vector2(3, 6), a.get("c", Color.RED), "shard", 1.0)
			pop(p, "POP!", a.get("c", Color.RED))
			Sfx.play("pop", p)
		"magic":
			_magic(String(a.get("id", "")), float(a.get("dir", 1.0)))
		"magic_end":
			weather.erase(String(a.get("id", "")))
		"tracer":
			var ta: Vector2 = a.get("a", p)
			var tb: Vector2 = a.get("b", p)
			var lz: bool = a.get("laser", false)
			_p(ta, Vector2.ZERO, 0.12 if lz else 0.07, 3.0 if lz else 2.0, Color(1.6, 0.8, 2.8) if lz else Color(2.6, 2.3, 1.2), "line", 0.0, true)
			_last_to(tb)
		"shot":
			var ang := float(a.get("a", 0.0))
			cone(p, Vector2.from_angle(ang), 0.35, 4, Vector2(80, 220), Vector2(0.05, 0.1), Vector2(4, 8), Color(2.6, 2.0, 0.8), "soft", 0.0, true)
			cone(p, Vector2.from_angle(ang), 0.5, 2, Vector2(30, 80), Vector2(0.3, 0.6), Vector2(5, 9), Color(0.8, 0.8, 0.8, 0.4), "soft", -0.2)
			light(p, Color(1.0, 0.85, 0.5), 1.2, 0.8, 0.06)
			Sfx.play(String(a.get("s", "gun_pistol")), p, 0.8)
		"bullet_hit":
			if a.get("flesh", false):
				burst(p, 5, Vector2(60, 180), Vector2(0.15, 0.3), Vector2(2, 3.5), Color(2.0, 1.6, 0.6), "star", 0.4, true)
			else:
				burst(p, 5, Vector2(80, 240), Vector2(0.1, 0.25), Vector2(1.5, 3), Color(2.2, 1.9, 1.0), "spark", 0.7, true)
				if a.get("ground", false):
					burst(p, 3, Vector2(20, 80), Vector2(0.3, 0.6), Vector2(4, 8), Color(0.7, 0.65, 0.55, 0.5), "soft", -0.1)
		"swing":
			Sfx.play("punch" if a.get("fists", false) else ("growl" if a.get("beast", false) and randf() < 0.15 else "swing"), p, 0.45)
		"hit":
			burst(p, 7, Vector2(60, 220), Vector2(0.15, 0.35), Vector2(2.5, 4.5), Color(2.2, 2.0, 0.9), "star", 0.3, true)
			Sfx.play(String(a.get("s", "punch")), p, 0.8)
			if randf() < 0.35:
				pop(p + Vector2(0, -30), ["POW!", "BAM!", "WHACK!", "BONK!"][randi() % 4], Color("ffd43b"), 26)
		"oof":
			Sfx.play("oof%d" % (1 + randi() % 3), p, 0.6, randf_range(0.9, 1.2))
		"ko":
			burst(p, 14, Vector2(60, 200), Vector2(0.4, 0.8), Vector2(3, 5), Color(2.0, 1.8, 0.6), "star", 0.2, true)
			pop(p + Vector2(0, -50), "KO!", Color("ff6b6b"), 30)
			Sfx.play("ko", p, 0.7)
		"getup":
			burst(p, 5, Vector2(20, 70), Vector2(0.3, 0.5), Vector2(5, 9), Color(0.85, 0.8, 0.7, 0.4), "soft", -0.1)
		"jump":
			burst(p, 4, Vector2(20, 70), Vector2(0.25, 0.4), Vector2(4, 7), Color(0.85, 0.8, 0.7, 0.4), "soft", -0.1)
		"equip":
			burst(p, 10, Vector2(40, 140), Vector2(0.3, 0.5), Vector2(2.5, 4), Color(1.8, 1.7, 0.8), "star", 0.0, true)
			Sfx.play("reload", p, 0.6)
		"heal":
			_p(p + Vector2(randf_range(-10, 10), -20), Vector2(0, -60), 0.9, 9.0, Color(0.8, 2.0, 1.0), "plus", 0.0, true)
			Sfx.play("heal", p, 0.4)
		"burn":
			_p(p, Vector2(randf_range(-20, 20), randf_range(-90, -40)), randf_range(0.3, 0.6), randf_range(5, 10), Color(2.4, 1.1, 0.3), "soft", -0.3, true)
			if randf() < 0.3:
				_p(p, Vector2(randf_range(-10, 10), -40), 0.9, 10.0, Color(0.3, 0.3, 0.32, 0.4), "soft", -0.25)
		"flame":
			var fa := float(a.get("a", 0.0))
			var fr := float(a.get("r", 220.0))
			for i in 4:
				var ang2 := fa + randf_range(-0.22, 0.22)
				_p(p, Vector2.from_angle(ang2) * randf_range(fr * 1.4, fr * 2.2), randf_range(0.3, 0.5), randf_range(7, 14), Color(2.4, randf_range(0.8, 1.4), 0.3), "soft", -0.2, true, 2.0)
			if randf() < 0.25:
				Sfx.play("flame", p, 0.5)
		"stomp":
			ring(p, float(a.get("r", 100.0)), Color(0.9, 0.85, 0.7, 0.8), 0.4, 8.0)
			cone(p, Vector2.UP, PI * 0.5, 14, Vector2(60, 220), Vector2(0.4, 0.7), Vector2(8, 16), Color(0.8, 0.75, 0.65, 0.5), "soft", 0.2)
			add_shake(8.0)
			Sfx.play("stomp", p)
		"clang":
			burst(p, 6, Vector2(60, 200), Vector2(0.1, 0.25), Vector2(1.5, 3), Color(2.2, 2.0, 1.2), "spark", 0.6, true)
			Sfx.play("clang", p, 0.7)
		"reload":
			Sfx.play("reload", p, 0.5)
		"pin":
			Sfx.play("pin", p, 0.6)
		"bow":
			Sfx.play("bow", p, 0.7)
		"arrow_hit":
			Sfx.play("arrow_hit", p, 0.7)
		"build":
			burst(p, 10, Vector2(40, 160), Vector2(0.3, 0.6), Vector2(6, 12), Color(0.85, 0.8, 0.7, 0.5), "soft", -0.1)
			Sfx.play("thud", p, 0.6)
		"crumble":
			burst(p, 16, Vector2(60, 240), Vector2(0.4, 0.8), Vector2(3, 7), Color(0.6, 0.55, 0.5), "shard", 1.0)
			Sfx.play("crumble", p)
		"sizzle":
			burst(p, 4 if not a.get("big", false) else 14, Vector2(20, 90), Vector2(0.4, 0.9), Vector2(6, 14), Color(0.4, 0.38, 0.38, 0.45), "soft", -0.3)
			Sfx.play("sizzle", p, 0.6)
		"fizz":
			burst(p, 5 if not a.get("big", false) else 14, Vector2(20, 90), Vector2(0.3, 0.7), Vector2(3, 7), Color(0.5, 1.6, 0.4, 0.8), "bubble", -0.2)
			Sfx.play("fizz", p, 0.6)
		"napalm":
			var nr := float(a.get("r", 200.0))
			burst(p, 50, Vector2(100, nr * 2.2), Vector2(0.5, 1.0), Vector2(10, 20), Color(2.4, 1.0, 0.25), "soft", 0.3, true)
			light(p, Color(1.0, 0.55, 0.2), 3.0, 4.0, 1.5)
			Sfx.play("flame", p, 1.2)
		"acid_splash":
			var ar := float(a.get("r", 190.0))
			burst(p, 40, Vector2(100, ar * 2.0), Vector2(0.4, 0.9), Vector2(4, 9), Color(0.5, 1.7, 0.35), "dot", 0.9)
			ring(p, ar, Color(0.5, 1.6, 0.4, 0.8), 0.4, 8.0)
			pop(p + Vector2(0, -40), "SPLOOSH!", Color("7bed9f"))
			Sfx.play("fizz", p, 1.2)
			Sfx.play("splat", p, 0.8)
		"erupt":
			cone(p, Vector2.UP, 0.5, 40, Vector2(200, 700), Vector2(0.6, 1.2), Vector2(8, 18), Color(2.4, 1.0, 0.25), "soft", 0.5, true)
			cone(p, Vector2.UP, 0.4, 20, Vector2(80, 260), Vector2(1.0, 2.0), Vector2(18, 34), Color(0.35, 0.3, 0.3, 0.5), "soft", -0.2)
			add_shake(10.0)
			Sfx.play("rumble", p, 1.0)
		"plane":
			var dir := float(a.get("dir", 1.0))
			_p(Vector2(float(a.get("x0", view_rect.position.x)) - dir * 200.0, float(a.get("y", view_rect.position.y))), Vector2(dir * (float(a.get("w", 2000.0)) + 400.0) / 2.6, 0), 2.8, 40.0, Color(0.6, 0.65, 0.7), "plane", 0.0)
			Sfx.play("plane", null, 1.0)
		"alarm":
			Sfx.play("alarm", null, 0.5)
		"whistle":
			Sfx.play("whistle", null, 0.3)
		"victory":
			var team := String(a.get("team", ""))
			var tc := Catalog.team_color(team)
			var c := view_rect.get_center()
			pop(c + Vector2(0, -view_rect.size.y * 0.25), "%s TEAM WINS! 🏆" % Catalog.TEAMS.get(team, {"name": team}).name.to_upper(), tc.lightened(0.2), 60)
			pops[pops.size() - 1]["life"] = 3.0
			pops[pops.size() - 1]["max"] = 3.0
			for i in 5:
				var x := lerpf(view_rect.position.x + 120, view_rect.end.x - 120, i / 4.0)
				for j in 24:
					_p(Vector2(x, view_rect.position.y + 30), Vector2(randf_range(-220, 220), randf_range(0, 260)), randf_range(2.0, 3.2), randf_range(3, 6), [tc, Color.WHITE, Color("ffd43b")][j % 3], "confetti", 0.25, false, 1.4)
			Sfx.play("victory", null, 1.0)
		"battle_start":
			pop(view_rect.get_center() + Vector2(0, -view_rect.size.y * 0.25), "⚔️ FIGHT!", Color("ffd43b"), 64)
			Sfx.play("battle_start", null, 1.0)
		"charge_all":
			pop(view_rect.get_center() + Vector2(0, -view_rect.size.y * 0.25), "📣 CHARGE!", Color("ff8a3d"), 56)
			Sfx.play("battle_start", null, 0.8, 1.2)
		"nuke":
			var r := float(a.get("r", 1000.0))
			do_flash(Color(1, 0.98, 0.9), 1.0)
			add_shake(42.0)
			for k in 3:
				ring(p, r * (0.5 + k * 0.3), Color(2.0, 1.8, 1.4, 0.9), 0.8 + k * 0.3, 16.0)
			burst(p, 80, Vector2(150, 900), Vector2(0.6, 1.4), Vector2(18, 40), Color(2.6, 1.4, 0.4), "soft", -0.15, true)
			for i in 26:
				# the mushroom stem and cap
				var up := float(i) / 26.0
				_p(p + Vector2(randf_range(-30, 30), 0), Vector2(randf_range(-20, 20), -180.0 - up * 260.0), 3.6, randf_range(26, 46), Color(0.55, 0.42, 0.38, 0.75), "soft", -0.02, false, 0.25)
			for i in 30:
				var ang := randf_range(-PI, 0.0)
				_p(p + Vector2(0, -420), Vector2.from_angle(ang) * randf_range(80, 260) + Vector2(0, -120), 4.2, randf_range(40, 70), Color(0.62, 0.48, 0.42, 0.7), "soft", -0.01, false, 0.35)
			light(p, Color(1.0, 0.85, 0.6), 6.0, 14.0, 2.0)
			pop(p + Vector2(0, -260), "KA-BOOOOM!", Color("ffd43b"), 90)
			Sfx.play("nuke", null, 1.6)
		"voice":
			Sfx.play(String(a.get("v", "wee")), p, 0.7, 1.1 / maxf(0.5, float(a.get("s", 1.0))))
		"undo":
			Sfx.play("undo", null, 0.6)
		"nope":
			Sfx.play("nope", null, 0.6)


func _special(k: String, p: Vector2, r: float) -> void:
	match k:
		"bloop":
			ring(p, r * 2.0, Color(0.6, 0.9, 1.6), 0.35, 5.0)
			Sfx.play("boing_big", p)
		"gummy":
			burst(p, 12, Vector2(40, 140), Vector2(0.3, 0.6), Vector2(3, 6), Color(0.6, 1.6, 0.6), "dot", 0.9)
			pop(p + Vector2(0, -50), "STICKY!", Color("5ad66a"), 26)
			Sfx.play("glue", p)
		"puffy":
			burst(p, 18, Vector2(40, 160), Vector2(0.4, 0.8), Vector2(8, 16), Color(1, 0.85, 0.95, 0.8), "soft", -0.2)
			Sfx.play("puff", p)
		"boulder":
			Sfx.play("whoosh", p)


func _bolt(a: Vector2, b: Vector2) -> void:
	_p(a, Vector2.ZERO, 0.25, 2.5, Color(1.6, 2.0, 2.6), "bolt", 0.0, true)
	_last_to(b)


func _explode(p: Vector2, r: float, mega: bool) -> void:
	var k := 2.0 if mega else 1.0
	ring(p, r, Color(2.0, 1.6, 1.0, 0.9), 0.45, 10.0 * k)
	ring(p, r * 0.6, Color(1, 1, 1, 0.8), 0.3, 6.0 * k)
	burst(p, int(36 * k), Vector2(80, 520 * k), Vector2(0.25, 0.6), Vector2(10, 22) * k, Color(2.4, 1.2, 0.35), "soft", -0.2, true)
	burst(p, int(26 * k), Vector2(40, 260 * k), Vector2(0.7, 1.4), Vector2(14, 30) * k, Color(0.45, 0.42, 0.48, 0.55), "soft", -0.25)
	burst(p, int(22 * k), Vector2(200, 700 * k), Vector2(0.3, 0.8), Vector2(2, 4), Color(2.2, 1.8, 0.8), "spark", 0.6, true)
	burst(p, int(20 * k), Vector2(150, 500 * k), Vector2(0.8, 1.6), Vector2(3, 6), Catalog.PAINT[randi() % 8], "confetti", 0.6, false, 0.4)
	light(p, Color(1.0, 0.7, 0.35), 3.5 * k, 4.0 * k, 0.6)
	add_shake(26.0 if mega else 14.0)
	if mega:
		do_flash(Color(1, 0.95, 0.85), 0.75)
	pop(p + Vector2(0, -r * 0.3), "KA-BOOM!" if mega else "BOOM!", Color("ffd43b"), 56 if mega else 40)
	Sfx.play("mega_boom" if mega else "boom", p, 1.4)


func _magic(id: String, dir: float) -> void:
	var c := view_rect.get_center()
	match id:
		"party":
			for i in 6:
				var x := lerpf(view_rect.position.x + 100, view_rect.end.x - 100, i / 5.0)
				for j in 30:
					_p(Vector2(x, view_rect.position.y + 40), Vector2(randf_range(-240, 240), randf_range(0, 300)), randf_range(2.0, 3.5), randf_range(3, 6), Catalog.PAINT[randi() % 8], "confetti", 0.25, false, 1.4)
			Sfx.play("party", null, 1.0)
		"wind":
			weather.wind = 5.0
			weather.wind_dir = dir
			Sfx.play("wind", null, 1.0)
		"rain":
			weather.rain = 10.0
			Sfx.play("rain", null, 0.8)
		"snow":
			weather.snow = 12.0
			Sfx.play("magic", null, 0.8)
		"wobble":
			weather.wobble = 4.0
			Sfx.play("rumble", null, 1.0)
		"float", "rainbow", "ball_rain":
			burst(c, 60, Vector2(100, 600), Vector2(0.6, 1.2), Vector2(3, 6), Color(1.8, 1.6, 2.0), "star", 0.0, true, 0.5)
			Sfx.play("magic", null, 1.0)


# ----------------------------------------------------------------- update
func _process(dt: float) -> void:
	shake = maxf(0.0, shake - dt * 28.0)
	if weather.has("wobble"):
		shake = maxf(shake, 7.0)
	flash.a = maxf(0.0, flash.a - dt * 1.9)
	_flash_rect.color = flash
	for k in weather.keys():
		if k == "wind_dir":
			continue
		weather[k] -= dt
		if weather[k] <= 0.0:
			weather.erase(k)
	_weather(dt)
	_trails(dt)
	for i in range(_head, _tail):
		if _dead[i] != 0:
			continue
		var life := _life[i] - dt
		if life <= 0.0:
			_dead[i] = 1
			_n -= 1
			continue
		_life[i] = life
		var v := _pv[i]
		v.y += 980.0 * _grav[i] * dt
		v *= maxf(0.0, 1.0 - _drag[i] * dt)
		_pv[i] = v
		_pp[i] += v * dt
		_rot[i] += _spin[i] * dt
	if _tail - _head > _n * 2 + 64:
		_pack()   # mostly holes: close them up
	rings = rings.filter(func(r):
		r.life -= dt
		return r.life > 0.0)
	pops = pops.filter(func(r):
		r.life -= dt
		r.p.y -= 40.0 * dt
		return r.life > 0.0)
	for l in _lights:
		l.life -= dt
		if is_instance_valid(l.n):
			l.n.energy = l.e * maxf(0.0, l.life / l.max)
	var keep: Array = []
	for l in _lights:
		if l.life <= 0.0:
			if is_instance_valid(l.n):
				l.n.queue_free()
		else:
			keep.append(l)
	_lights = keep
	_norm.queue_redraw()
	_glow.queue_redraw()


func _weather(dt: float) -> void:
	var v := view_rect
	if weather.has("rain"):
		for i in int(60.0 * dt * 10.0):
			_p(Vector2(randf_range(v.position.x - 100, v.end.x + 100), v.position.y - 20), Vector2(-60, 900), 1.3, 12.0, Color(0.7, 0.85, 1.0, 0.55), "streak", 0.3, false, 0.0)
	if weather.has("snow"):
		for i in int(30.0 * dt * 10.0):
			_p(Vector2(randf_range(v.position.x - 100, v.end.x + 100), v.position.y - 20), Vector2(randf_range(-30, 30), 90), 6.0, randf_range(2.5, 5.0), Color(1, 1, 1, 0.9), "dot", 0.02, false, 0.0)
	if weather.has("wind"):
		var d := float(weather.get("wind_dir", 1.0))
		for i in 3:
			_p(Vector2(v.position.x if d > 0 else v.end.x, randf_range(v.position.y, v.end.y)), Vector2(d * randf_range(700, 1100), 0), 2.0, 26.0, Color(1, 1, 1, 0.35), "streak", 0.0, false, 0.0)


func _trails(dt: float) -> void:
	if world == null:
		return
	for uid in trails.keys():
		trails[uid] -= dt
		var t = world.things.get(uid)
		if trails[uid] <= 0.0 or t == null:
			trails.erase(uid)
			continue
		var pos: Vector2 = t.global_position + Vector2(0, 26)
		for i in 3:
			_p(pos, Vector2(randf_range(-40, 40), randf_range(60, 160)), randf_range(0.3, 0.6), randf_range(2, 4), Color(2.4, 1.8, 0.7), "spark", 0.4, true)


# ---------------------------------------------------------------- drawing
func _draw_norm() -> void:
	for i in range(_head, _tail):
		if _dead[i] == 0 and _glows[i] == 0:
			_draw_part(_norm, i)
	for r in rings:
		var k: float = 1.0 - r.life / r.max
		var rad: float = r.r * (1.0 - pow(1.0 - k, 3.0))
		var c: Color = r.col
		_norm.draw_arc(r.p, maxf(1.0, rad), 0, TAU, 48, Color(c.r, c.g, c.b, c.a * (1.0 - k)), r.w * (1.0 - k * 0.6), true)
	for t in pops:
		var k: float = t.life / t.max
		var sc := 1.0 + 0.35 * maxf(0.0, (k - 0.75) * 4.0)
		var a := clampf(k * 3.0, 0.0, 1.0)
		_norm.draw_set_transform(t.p, t.rot, Vector2(sc, sc))
		var fs: int = t.s
		var sz := Art.font.get_string_size(t.t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var at := Vector2(-sz.x * 0.5, fs * 0.35)
		_norm.draw_string_outline(Art.font, at, t.t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color(0.1, 0.08, 0.2, a))
		_norm.draw_string(Art.font, at, t.t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(t.col.r, t.col.g, t.col.b, a))
		_norm.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_glow() -> void:
	for i in range(_head, _tail):
		if _dead[i] == 0 and _glows[i] != 0:
			_draw_part(_glow, i)


func _draw_part(ci: CanvasItem, i: int) -> void:
	var k: float = _life[i] / _max[i]
	var c: Color = _col[i]
	var col := Color(c.r, c.g, c.b, c.a * minf(1.0, k * 2.0))
	var p: Vector2 = _pp[i]
	var r: float = _pr[i]
	var kind := _kind[i]
	match kind:
		0:   # soft
			var rr := r * (1.4 - k * 0.4)
			ci.draw_texture_rect(Art.dot_texture(), Rect2(p - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, col)
		1:   # dot
			ci.draw_circle(p, r * (0.5 + 0.5 * k), col, true, -1.0, true)
		2:   # spark
			ci.draw_line(p, p - _pv[i] * 0.03, col, r * 0.8, true)
		3:   # streak
			ci.draw_line(p, p - _pv[i].normalized() * r * 2.0, col, 2.0, true)
		4, 5:   # confetti, shard
			var rot: float = _rot[i]
			ci.draw_set_transform(p, rot, Vector2(1.0, absf(sin(rot * 2.0)) * 0.8 + 0.2) if kind == 4 else Vector2.ONE)
			if kind == 5:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(-r, -r * 0.4), Vector2(r * 0.8, -r * 0.6), Vector2(r * 0.2, r)]), col)
			else:
				ci.draw_rect(Rect2(-r, -r * 0.55, r * 2.0, r * 1.1), col)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		6:   # star
			Art._star(ci, p, r * (0.6 + 0.6 * k), col, _rot[i])
		7:   # bubble
			ci.draw_circle(p, r, Color(0.8, 0.95, 1.0, 0.12 * k), true, -1.0, true)
			ci.draw_arc(p, r, 0, TAU, 20, col, 1.5, true)
			ci.draw_circle(p + Vector2(-r * 0.35, -r * 0.35), r * 0.2, Color(1, 1, 1, 0.8 * k), true, -1.0, true)
		8:   # note
			ci.draw_circle(p, r * 0.45, col, true, -1.0, true)
			ci.draw_line(p + Vector2(r * 0.4, 0), p + Vector2(r * 0.4, -r * 1.4), col, 2.5, true)
			ci.draw_line(p + Vector2(r * 0.4, -r * 1.4), p + Vector2(r * 0.9, -r * 1.0), col, 2.5, true)
		9:   # heart
			var hp := PackedVector2Array()
			for j in 24:
				var tt := TAU * j / 24.0
				hp.append(p + Vector2(16.0 * pow(sin(tt), 3.0), -(13.0 * cos(tt) - 5.0 * cos(2.0 * tt) - 2.0 * cos(3.0 * tt) - cos(4.0 * tt))) * r / 16.0)
			ci.draw_colored_polygon(hp, col)
		10:   # line
			var to2: Vector2 = _to[i] if _has_to[i] != 0 else p
			ci.draw_line(p, to2, col, r, true)
		11:   # plus
			ci.draw_rect(Rect2(p - Vector2(r * 0.25, r), Vector2(r * 0.5, r * 2.0)), col)
			ci.draw_rect(Rect2(p - Vector2(r, r * 0.25), Vector2(r * 2.0, r * 0.5)), col)
		12:   # plane
			var vx: float = _pv[i].x
			var fl := signf(vx) if vx != 0.0 else 1.0
			ci.draw_set_transform(p, 0.0, Vector2(fl, 1.0))
			ci.draw_colored_polygon(Art.rr(Rect2(-60, -10, 120, 20), 10.0), Color("7f8c8d"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-10, 0), Vector2(20, 0), Vector2(-20, 34)]), Color("636e72"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-60, -8), Vector2(-44, -8), Vector2(-58, -30)]), Color("636e72"))
			ci.draw_circle(Vector2(40, -3), 6.0, Color("a5f3ff"))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		13:   # bolt
			var to: Vector2 = _to[i] if _has_to[i] != 0 else p
			var pts := PackedVector2Array([p])
			var d := to - p
			var n := d.normalized().orthogonal()
			for j in range(1, 7):
				pts.append(p + d * (j / 7.0) + n * randf_range(-14, 14))
			pts.append(to)
			ci.draw_polyline(pts, col, 3.0, true)
			ci.draw_polyline(pts, Color(2.5, 2.5, 2.5, col.a), 1.2, true)

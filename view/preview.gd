class_name Preview
## Pictures of spawnable things: toy-box thumbnails and the see-through
## "ghost" that follows the mouse while placing.

static var _toys := {}
static var _fighters := {}


static func clear() -> void:
	for t in _toys.values():
		if is_instance_valid(t):
			t.free()
	_toys.clear()
	for f in _fighters.values():
		if is_instance_valid(f):
			f.free()
	_fighters.clear()
	Art._light_tex = null
	Art._dot_tex = null


static func _toy(id: String) -> Toy:
	if not _toys.has(id):
		var t := Toy.new()
		t.setup(id, Catalog.toy(id), Vector2.ZERO)
		if id == "abc_block":
			t.letter = "A"
			t.color = Color("ffcf4a")
		if id in ["lamp", "rocket", "fan", "saucer"]:
			t.on = true
		_toys[id] = t
	return _toys[id]


static func _fighter(type: String) -> Fighter:
	if not _fighters.has(type):
		var f := Fighter.new()
		f.setup(null, type, Vector2.ZERO)
		f.facing = 1.0
		f.puppet = true
		f.net = {"c": Vector2.ZERO, "st": "stand"}
		f.grounded = true
		f.hair = Color("3b2a1a")
		f.t = 0.0
		_fighters[type] = f
	return _fighters[type]


## Box around a standing fighter, relative to its centre.
static func _fighter_box(f: Fighter) -> Rect2:
	var s: float = f.size
	if not f.beast:
		var r := Rect2(Vector2(-26, -58) * s, Vector2(52, 110) * s)
		if f.def.has("weapon"):
			r = r.expand(Vector2(70, -10) * s)
		return r
	var d: Dictionary = f.def
	var b: Vector2 = d.body * s
	var legs := float(d.get("legs", 20)) * s
	var head := float(d.get("head", 14)) * s
	var neck := float(d.get("neck", 0)) * s
	var tail := float(d.get("tail", 0)) * s
	var top := -legs * 0.5 - b.y * 0.5 - maxf(neck * 0.9, head * 0.6) - head
	var bottom := (b.y + legs) * 0.5 + 6.0 * s
	return Rect2(Vector2(-b.x * 0.5 - tail * 0.8, top), Vector2(b.x + tail * 0.8 + head * 2.2 + neck * 0.35, bottom - top))


static func _platform_rects(id: String) -> Array:
	var d := Catalog.platform_def(id)
	var w := float(d.w)
	var h := float(d.h)
	match id:
		"tower":
			return [[Rect2(-w * 0.3, -h * 0.5, w * 0.6, h), "stone"], [Rect2(-w * 0.5, -h * 0.5 - 16, w, 16), "wood"],
				[Rect2(-w * 0.5, -h * 0.5 - 46, 10, 30), "wood"], [Rect2(w * 0.5 - 10, -h * 0.5 - 46, 10, 30), "wood"]]
		"bunker":
			return [[Rect2(-w * 0.5, -h * 0.5, w, 22), "concrete"], [Rect2(-w * 0.5, -h * 0.5, 22, h), "concrete"],
				[Rect2(w * 0.5 - 22, -h * 0.5, 22, h * 0.45), "concrete"]]
	return [[Rect2(-w * 0.5, -h * 0.5, w, h), String(d.style)]]


static func _draw_fighter(ci: CanvasItem, type: String, at: Vector2, k: float, alpha := 1.0) -> void:
	var f := _fighter(type)
	FighterArt.canvas = ci
	FighterArt.outer = Transform2D(0.0, Vector2(k, k), 0.0, at)
	ci.draw_set_transform_matrix(FighterArt.outer)
	if f.beast:
		FighterArt._beast(f)
	else:
		FighterArt._person(f)
	FighterArt.canvas = null
	FighterArt.outer = Transform2D.IDENTITY
	var wid := String(f.def.get("weapon", ""))
	if wid != "" and not f.beast:
		var hand: Vector2 = f.flipped(f.pose().hand_f)
		var wt := _toy(wid)
		var grip := float(Catalog.toy(wid).get("w", 30)) * 0.25
		Art.draw_toy(ci, wt, at + (hand + Vector2(grip, 0)) * k, k)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_platform(ci: CanvasItem, id: String, at: Vector2, k: float) -> void:
	for pr in _platform_rects(id):
		var r: Rect2 = pr[0]
		var st := Worlds.platform_style(String(pr[1]))
		var rr := Rect2(at + r.position * k, r.size * k)
		ci.draw_rect(rr, st.fill)
		ci.draw_rect(Rect2(rr.position, Vector2(rr.size.x, minf(rr.size.y, maxf(2.0, float(st.top_w) * k)))), st.top)
		ci.draw_rect(rr, Color(st.fill2).darkened(0.35), false, 1.5)


## Size of a spawnable thing, for fitting it in a box.
static func extent(id: String) -> Vector2:
	if id.begins_with("w:"):
		return Vector2(64, 64)
	if id.begins_with("f:"):
		return _fighter_box(_fighter(id.substr(2))).size
	if id.begins_with("plat:"):
		var d := Catalog.platform_def(id.substr(5))
		return Vector2(float(d.w), float(d.h) + (46.0 if id == "plat:tower" else 0.0))
	if id.begins_with("build:"):
		return Vector2(120, 90)
	var d := Catalog.toy(id)
	if d.get("shape", "box") == "circle":
		return Vector2.ONE * float(d.r) * 2.0
	return Vector2(float(d.get("w", 30)), float(d.get("h", 30)))


static func draw_thumb(ci: CanvasItem, id: String, r: Rect2) -> void:
	var c := r.get_center()
	if id.begins_with("w:"):
		Art.draw_wiggly_icon(ci, id.substr(2), c + Vector2(0, 2), minf(r.size.x, r.size.y) * 0.36)
		return
	if id.begins_with("build:"):
		_build_icon(ci, id.substr(6), c, minf(r.size.x, r.size.y) * 0.42)
		return
	var ext := extent(id)
	var k := minf(r.size.x * 0.8 / ext.x, r.size.y * 0.8 / ext.y)
	k = minf(k, 1.6)
	if id.begins_with("f:"):
		var box := _fighter_box(_fighter(id.substr(2)))
		_draw_fighter(ci, id.substr(2), c - box.get_center() * k, k)
		return
	if id.begins_with("plat:"):
		_draw_platform(ci, id.substr(5), c + Vector2(0, 23.0 * k if id == "plat:tower" else 0.0), k)
		return
	if Catalog.toy(id).has("tub"):
		_draw_tub(ci, id, c, minf(r.size.x * 0.85 / ext.x, r.size.y * 0.85 / ext.y))
		return
	Art.draw_toy(ci, _toy(id), c, k)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_ghost(ci: CanvasItem, id: String, at: Vector2) -> void:
	if id.begins_with("w:"):
		Art.draw_wiggly_icon(ci, id.substr(2), at, Wiggly.BASE_R)
		return
	if id.begins_with("build:"):
		_build_icon(ci, id.substr(6), at, 60.0)
		return
	if id.begins_with("f:"):
		_draw_fighter(ci, id.substr(2), at, 1.0)
		return
	if id.begins_with("plat:"):
		_draw_platform(ci, id.substr(5), at, 1.0)
		return
	if Catalog.toy(id).has("tub"):
		var d := Catalog.toy(id)
		_draw_tub(ci, id, at + Vector2(0, -float(d.h) * 0.5), 1.0)
		return
	Art.draw_toy(ci, _toy(id), at, 1.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _build_icon(ci: CanvasItem, id: String, c: Vector2, s: float) -> void:
	var wood := Color("c98a48")
	match id:
		"seesaw":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.4, s * 0.5), c + Vector2(s * 0.4, s * 0.5), c + Vector2(0, s * 0.05)]), Color("7cc1ff"))
			ci.draw_line(c + Vector2(-s, s * 0.25), c + Vector2(s, -s * 0.15), wood, s * 0.14, true)
		"trap_minefield":
			ci.draw_line(c + Vector2(-s, s * 0.45), c + Vector2(s, s * 0.45), Color("6ab04c"), s * 0.08, true)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.95, s * 0.22), Vector2(s * 0.42, s * 0.2)), Color("ffd43b"))
			for i in 3:
				var mc := c + Vector2(-s * 0.2 + i * s * 0.48, s * 0.4)
				ci.draw_colored_polygon(Art.ellipse(mc, s * 0.17, s * 0.1, 12), Color("4b5320"))
				ci.draw_circle(mc + Vector2(0, -s * 0.07), s * 0.04, Color(2.2, 0.5, 0.4))
				ci.draw_line(c + Vector2(-s * 0.74, s * 0.22), mc + Vector2(0, -s * 0.08), Color(0.4, 2.0, 0.9), maxf(1.5, s * 0.03), true)
			Art._star(ci, c + Vector2(s * 0.3, -s * 0.25), s * 0.35, Color(2.2, 1.4, 0.4))
		"disarm_gate":
			ci.draw_line(c + Vector2(-s, s * 0.5), c + Vector2(s, s * 0.5), Color("6ab04c"), s * 0.08, true)
			for i in 2:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.55 + i * s * 0.6, s * 0.3), Vector2(s * 0.5, s * 0.16)), Color("74b9ff"))
			var u := PackedVector2Array()
			for i in 13:
				var a := PI * float(i) / 12.0
				u.append(c + Vector2(cos(a) * s * 0.4, -sin(a) * s * 0.42 - s * 0.35))
			ci.draw_polyline(u, Color("e74c3c"), s * 0.2, true)
			ci.draw_arc(c + Vector2(0, -s * 0.2), s * 0.5, 0.5, PI - 0.5, 16, Color(1.2, 0.5, 0.5, 0.6), maxf(1.5, s * 0.04), true)
			ci.draw_line(c + Vector2(s * 0.3, s * 0.05), c + Vector2(s * 0.7, -s * 0.25), Color("dfe6e9"), s * 0.08, true)
		"ufo_abductor":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.15, -s * 0.35), c + Vector2(s * 0.15, -s * 0.35), c + Vector2(s * 0.5, s * 0.5), c + Vector2(-s * 0.5, s * 0.5)]), Color(0.6, 1.6, 1.2, 0.4))
			ci.draw_colored_polygon(Art.ellipse(c + Vector2(0, -s * 0.55), s * 0.25, s * 0.2, 16), Color(0.6, 0.95, 1.0, 0.9))
			ci.draw_colored_polygon(Art.ellipse(c + Vector2(0, -s * 0.42), s * 0.7, s * 0.18, 20), Color("a4b0be"))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.5), Vector2(s * 0.6, s * 0.14)), Color("2ed573"))
			ci.draw_line(c + Vector2(0, s * 0.05), c + Vector2(0, s * 0.35), Color("1e1b2e"), maxf(2.0, s * 0.06), true)
			ci.draw_circle(c + Vector2(0, -s * 0.02), s * 0.08, Color("f6d7b0"))
		"catapult":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.5, s * 0.25), Vector2(s, s * 0.3)), Color("d0573f"))
			ci.draw_line(c + Vector2(s * 0.1, s * 0.15), c + Vector2(-s * 0.8, -s * 0.6), wood, s * 0.12, true)
			ci.draw_circle(c + Vector2(-s * 0.8, -s * 0.75), s * 0.18, Color("ffd43b"))
			ci.draw_circle(c + Vector2(s * 0.1, s * 0.15), s * 0.18, Color("2d3436"))
		"ferris":
			ci.draw_circle(c, s * 0.75, Color(1, 1, 1, 0.0))
			ci.draw_arc(c, s * 0.75, 0, TAU, 32, wood, s * 0.08, true)
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				ci.draw_line(c, c + Vector2.from_angle(a) * s * 0.75, wood, s * 0.06, true)
				ci.draw_rect(Rect2(c + Vector2.from_angle(a) * s * 0.75 + Vector2(-s * 0.15, 0), Vector2(s * 0.3, s * 0.18)), Color("f2f0ff"))
			ci.draw_circle(c, s * 0.16, Color("2d3436"))
		"rocket_cart":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.1), Vector2(s * 1.2, s * 0.3)), Color("ff4757"))
			ci.draw_circle(c + Vector2(-s * 0.4, s * 0.3), s * 0.16, Color("2d3436"))
			ci.draw_circle(c + Vector2(s * 0.4, s * 0.3), s * 0.16, Color("2d3436"))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.6, -s * 0.05), c + Vector2(-s, s * 0.05), c + Vector2(-s * 0.6, s * 0.15)]), Color(2.0, 1.2, 0.4))
		"domino":
			for i in 5:
				var x := -s * 0.8 + i * s * 0.4
				ci.draw_set_transform(c + Vector2(x, 0), 0.25 * i if i < 2 else 0.0, Vector2.ONE)
				ci.draw_rect(Rect2(Vector2(-s * 0.07, -s * 0.45), Vector2(s * 0.14, s * 0.9)), Color.from_hsv(i / 5.0, 0.6, 1.0))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"lamp_show":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.9, s * 0.3), Vector2(s * 1.8, s * 0.18)), Color("9fb0c4"))
			for i in 3:
				ci.draw_circle(c + Vector2(-s * 0.5 + i * s * 0.5, 0), s * 0.2, [Color(2.0, 0.6, 0.6), Color(0.6, 2.0, 0.8), Color(0.6, 0.9, 2.2)][i])
		_:
			ci.draw_circle(c, s * 0.5, Color("ffcf4a"))


## A pit or tank of lava, acid or water.
static func _draw_tub(ci: CanvasItem, id: String, c: Vector2, k: float) -> void:
	var d := Catalog.toy(id)
	var w := float(d.w) * k
	var h := float(d.h) * k
	var kind := String(d.tub)
	var look: Dictionary = WaterView.LOOK.get(kind, WaterView.LOOK.water)
	var st := Worlds.platform_style({"lava": "rock", "acid": "steel"}.get(kind, "stone"))
	var wall := maxf(3.0, 16.0 * k)
	var top := c.y - h * 0.5
	var liq := Rect2(c.x - w * 0.5, top + h * 0.25, w, h * 0.75)
	var cols := PackedColorArray([look.top, look.top, look.deep, look.deep])
	ci.draw_polygon(PackedVector2Array([liq.position, Vector2(liq.end.x, liq.position.y), liq.end, Vector2(liq.position.x, liq.end.y)]), cols)
	ci.draw_line(liq.position, Vector2(liq.end.x, liq.position.y), look.edge, maxf(2.0, 3.0 * k), true)
	for i in 3:
		var bp := Vector2(liq.position.x + liq.size.x * (0.25 + 0.25 * i), liq.position.y + liq.size.y * (0.35 + 0.2 * (i % 2)))
		ci.draw_circle(bp, maxf(2.0, 7.0 * k), Color(look.edge.r, look.edge.g, look.edge.b, 0.6))
	for r in [Rect2(c.x - w * 0.5 - wall, top, wall, h + wall), Rect2(c.x + w * 0.5, top, wall, h + wall), Rect2(c.x - w * 0.5, c.y + h * 0.5, w, wall)]:
		ci.draw_rect(r, st.fill)
		ci.draw_rect(r, Color(st.fill2).darkened(0.35), false, 1.5)

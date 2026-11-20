class_name Art
## Draws every toy and Wiggly as crisp vector art (shading, outlines,
## highlights, glowing bits). Colors above 1.0 glow (HDR bloom).

static var font: Font = preload("res://fonts/Nunito.ttf")
static var _light_tex: Texture2D
static var _dot_tex: Texture2D

const ANIMATED := ["fan", "propeller", "motor", "rocket", "conveyor", "timer", "saucer", "lamp", "battery"]


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func light_texture() -> Texture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 256
		t.height = 256
		_light_tex = t
	return _light_tex


static func dot_texture() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.55, Color(1, 1, 1, 0.75))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_dot_tex = t
	return _dot_tex


static func animates(t) -> bool:
	return (t.id in ANIMATED and t.is_on()) or t.fuse >= 0.0 or t.electric > 0.05 or t.bubble_t > 0.0


# ------------------------------------------------------------ primitives
static func rr(r: Rect2, rad: float, seg := 5) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var corners := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	var start := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for c in 4:
		for i in seg + 1:
			var a: float = start[c] + PI * 0.5 * float(i) / seg
			pts.append(corners[c] + Vector2(cos(a), sin(a)) * rad)
	return pts


static func ellipse(c: Vector2, rx: float, ry: float, n := 28, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


static func closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	if q.size() > 0:
		q.append(q[0])
	return q


## Rounded box with a soft top highlight, bottom shade and outline.
static func panel(ci: CanvasItem, r: Rect2, rad: float, col: Color, outline := true) -> void:
	var pts := rr(r, rad)
	ci.draw_colored_polygon(pts, col)
	var hi := Rect2(r.position + Vector2(r.size.x * 0.08, r.size.y * 0.08), Vector2(r.size.x * 0.84, r.size.y * 0.32))
	ci.draw_colored_polygon(rr(hi, rad * 0.7), Color(1, 1, 1, 0.22))
	var lo := Rect2(r.position + Vector2(r.size.x * 0.06, r.size.y * 0.68), Vector2(r.size.x * 0.88, r.size.y * 0.26))
	ci.draw_colored_polygon(rr(lo, rad * 0.6), Color(0, 0, 0, 0.12))
	if outline:
		ci.draw_polyline(closed(pts), col.darkened(0.5), 2.0, true)


static func ball(ci: CanvasItem, c: Vector2, rad: float, col: Color) -> void:
	ci.draw_circle(c, rad, col, true, -1.0, true)
	ci.draw_circle(c + Vector2(rad * 0.12, rad * 0.15), rad * 0.8, col.darkened(0.12), true, -1.0, true)
	ci.draw_circle(c - Vector2(rad * 0.08, rad * 0.1), rad * 0.72, col, true, -1.0, true)


static func shine(ci: CanvasItem, c: Vector2, rad: float, a := 0.7) -> void:
	ci.draw_colored_polygon(ellipse(c + Vector2(-rad * 0.35, -rad * 0.42), rad * 0.32, rad * 0.18, 16, -0.6), Color(1, 1, 1, a))
	ci.draw_circle(c + Vector2(-rad * 0.05, -rad * 0.55), rad * 0.07, Color(1, 1, 1, a))


static func outline_circle(ci: CanvasItem, c: Vector2, rad: float, col: Color) -> void:
	ci.draw_arc(c, rad, 0, TAU, 40, col.darkened(0.5), 2.0, true)


static func text(ci: CanvasItem, s: String, center: Vector2, size: int, col: Color) -> void:
	var sz := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	ci.draw_string(font, center + Vector2(-sz.x * 0.5, sz.y * 0.32), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ------------------------------------------------------------------ toys
static var _o := Vector2.ZERO
static var _k := 1.0


## Draws toy `t` on `ci`. `origin`/`zoom` place it elsewhere (ghosts, thumbnails).
static func draw_toy(ci: CanvasItem, t, origin := Vector2.ZERO, zoom := 1.0) -> void:
	_o = origin
	_k = zoom
	var s: float = t.size_scale
	var f: float = t.facing
	ci.draw_set_transform(_o, 0.0, Vector2(s * f, s) * _k)
	var col: Color = t.shown_color()
	var w: float = t.w
	var h: float = t.h
	var r: float = t.r
	var box := Rect2(-w * 0.5, -h * 0.5, w, h)
	var tm := now()
	match t.id:
		"beach_ball":
			var cs := [col, Color.WHITE, Color("4aa8ff"), Color.WHITE, Color("ffd43b"), Color.WHITE]
			for i in 6:
				var pts := PackedVector2Array([Vector2.ZERO])
				for k in 7:
					var a := TAU * (float(i) + float(k) / 6.0) / 6.0
					pts.append(Vector2(cos(a), sin(a)) * r)
				ci.draw_colored_polygon(pts, cs[i])
			ci.draw_circle(Vector2.ZERO, r * 0.18, Color.WHITE, true, -1.0, true)
			outline_circle(ci, Vector2.ZERO, r, col)
			shine(ci, Vector2.ZERO, r)
		"bouncy_ball", "marble":
			ball(ci, Vector2.ZERO, r, col)
			ci.draw_arc(Vector2.ZERO, r * 0.55, -0.4, 2.2, 16, col.lightened(0.45), r * 0.22, true)
			outline_circle(ci, Vector2.ZERO, r, col)
			shine(ci, Vector2.ZERO, r, 0.85)
		"soccer_ball":
			ci.draw_circle(Vector2.ZERO, r, col, true, -1.0, true)
			var dark := Color("2f3542") if col.v > 0.5 else Color.WHITE
			ci.draw_colored_polygon(ellipse(Vector2.ZERO, r * 0.32, r * 0.32, 5, -PI * 0.5), dark)
			for i in 5:
				var a := -PI * 0.5 + TAU * i / 5.0
				ci.draw_colored_polygon(ellipse(Vector2.from_angle(a) * r * 0.86, r * 0.22, r * 0.22, 5, a), dark)
				ci.draw_line(Vector2.from_angle(a) * r * 0.3, Vector2.from_angle(a) * r * 0.66, dark, 1.6, true)
			outline_circle(ci, Vector2.ZERO, r, Color("95a5a6"))
			shine(ci, Vector2.ZERO, r, 0.5)
		"bowling_ball":
			ball(ci, Vector2.ZERO, r, col)
			for p in [Vector2(-0.2, -0.35), Vector2(0.15, -0.38), Vector2(0.0, -0.08)]:
				ci.draw_circle(p * r * 1.4, r * 0.11, col.darkened(0.6), true, -1.0, true)
			outline_circle(ci, Vector2.ZERO, r, col)
			shine(ci, Vector2.ZERO, r, 0.55)
		"steel_ball":
			ball(ci, Vector2.ZERO, r, col)
			ci.draw_arc(Vector2.ZERO, r * 0.7, 0.3, 1.6, 12, Color(1, 1, 1, 0.35), r * 0.15, true)
			outline_circle(ci, Vector2.ZERO, r, col)
			shine(ci, Vector2.ZERO, r, 0.9)
		"wood_block", "plank":
			panel(ci, box, 5.0, col)
			var lines := 2 if t.id == "wood_block" else 1
			for i in lines:
				var y := lerpf(-h * 0.25, h * 0.25, float(i) / maxf(1.0, lines - 1.0)) if lines > 1 else 0.0
				var pts := PackedVector2Array()
				for k in 9:
					var x := lerpf(-w * 0.4, w * 0.4, float(k) / 8.0)
					pts.append(Vector2(x, y + sin(k * 1.3 + i) * 1.5))
				ci.draw_polyline(pts, col.darkened(0.3), 1.5, true)
			if t.id == "plank":
				ci.draw_circle(Vector2(-w * 0.44, 0), 2.0, Color("7f8c8d"))
				ci.draw_circle(Vector2(w * 0.44, 0), 2.0, Color("7f8c8d"))
		"brick":
			panel(ci, box, 4.0, col)
			ci.draw_line(Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), col.darkened(0.35), 2.0)
			ci.draw_line(Vector2(0, -h * 0.5), Vector2(0, 0), col.darkened(0.35), 2.0)
			ci.draw_line(Vector2(-w * 0.25, 0), Vector2(-w * 0.25, h * 0.5), col.darkened(0.35), 2.0)
			ci.draw_line(Vector2(w * 0.25, 0), Vector2(w * 0.25, h * 0.5), col.darkened(0.35), 2.0)
		"abc_block":
			panel(ci, box, 6.0, col)
			ci.draw_colored_polygon(rr(box.grow(-6.0), 4.0), col.lightened(0.18))
			ci.draw_set_transform(_o, 0.0, Vector2(s, s) * _k)
			text(ci, t.letter, Vector2.ZERO, int(h * 0.7), col.darkened(0.55))
			ci.draw_set_transform(_o, 0.0, Vector2(s * f, s) * _k)
		"glass_pane":
			ci.draw_colored_polygon(rr(box, 3.0), col)
			ci.draw_line(Vector2(-w * 0.3, -h * 0.3), Vector2(w * 0.2, -h * 0.4), Color(1, 1, 1, 0.7), 2.0, true)
			ci.draw_line(Vector2(-w * 0.3, -h * 0.05), Vector2(w * 0.3, -h * 0.2), Color(1, 1, 1, 0.5), 1.5, true)
			ci.draw_polyline(closed(rr(box, 3.0)), Color(1, 1, 1, 0.85), 2.0, true)
		"ice_cube":
			ci.draw_colored_polygon(rr(box, 7.0), col)
			ci.draw_colored_polygon(rr(Rect2(box.position + Vector2(5, 5), Vector2(w * 0.45, h * 0.25)), 4.0), Color(1, 1, 1, 0.55))
			ci.draw_line(Vector2(w * 0.1, h * 0.3), Vector2(w * 0.32, h * 0.1), Color(1, 1, 1, 0.6), 2.0, true)
			ci.draw_polyline(closed(rr(box, 7.0)), Color(0.7, 0.92, 1.0, 1.0), 2.0, true)
		"pillow":
			ci.draw_colored_polygon(rr(box, h * 0.45, 7), col)
			ci.draw_colored_polygon(rr(Rect2(box.position + Vector2(8, 4), Vector2(w - 16, h * 0.35)), h * 0.2), Color(1, 1, 1, 0.5))
			ci.draw_circle(Vector2.ZERO, 3.0, col.darkened(0.15), true, -1.0, true)
			ci.draw_polyline(closed(rr(box, h * 0.45, 7)), col.darkened(0.3), 2.0, true)
		"ramp":
			var pts := PackedVector2Array([Vector2(-w * 0.5, h * 0.5), Vector2(w * 0.5, h * 0.5), Vector2(w * 0.5, -h * 0.5)])
			ci.draw_colored_polygon(pts, col)
			for i in 3:
				var x := lerpf(-w * 0.15, w * 0.35, float(i) / 2.0)
				ci.draw_line(Vector2(x - 8, h * 0.32), Vector2(x + 4, h * 0.2), Color(1, 1, 1, 0.6), 4.0, true)
			ci.draw_polyline(closed(pts), col.darkened(0.45), 2.0, true)
		"metal_beam":
			panel(ci, box, 3.0, col)
			var holes := int(w / 34.0)
			for i in holes:
				ci.draw_circle(Vector2(lerpf(-w * 0.4, w * 0.4, float(i) / maxf(1.0, holes - 1.0)), 0), h * 0.18, col.darkened(0.45), true, -1.0, true)
		"battery":
			panel(ci, Rect2(-w * 0.5, -h * 0.4, w, h * 0.9), 6.0, col)
			ci.draw_colored_polygon(rr(Rect2(-w * 0.22, -h * 0.5, w * 0.44, h * 0.12), 2.0), Color("b2bec3"))
			_bolt(ci, Vector2(0, h * 0.05), h * 0.22, Color(1.6, 1.6, 0.8))
		"switch":
			panel(ci, Rect2(-w * 0.5, -h * 0.1, w, h * 0.6), 5.0, Color("636e72"))
			var ang := -0.6 if t.on else 0.6
			ci.draw_line(Vector2(0, h * 0.05), Vector2(0, h * 0.05) + Vector2(sin(ang), -cos(ang)) * h * 0.6, col if not t.on else Color("2ed573"), 6.0, true)
			ci.draw_circle(Vector2(0, h * 0.05) + Vector2(sin(ang), -cos(ang)) * h * 0.6, 5.0, Color.WHITE, true, -1.0, true)
			ci.draw_circle(Vector2(w * 0.32, h * 0.2), 3.5, Color(0.4, 2.0, 0.8) if t.on else Color("2d3436"), true, -1.0, true)
		"button":
			var down: bool = t.extra.get("pressed", false)
			panel(ci, Rect2(-w * 0.5, 0, w, h * 0.5), 4.0, Color("636e72"))
			var dh := h * (0.25 if down else 0.6)
			ci.draw_colored_polygon(rr(Rect2(-w * 0.38, -dh, w * 0.76, dh + 2), 9.0), col if not down else Color(1.6, 0.5, 0.5))
			ci.draw_colored_polygon(rr(Rect2(-w * 0.3, -dh + 2, w * 0.4, 4), 2.0), Color(1, 1, 1, 0.45))
		"timer":
			panel(ci, box, 8.0, col)
			ci.draw_circle(Vector2.ZERO, w * 0.32, Color.WHITE, true, -1.0, true)
			var a := float(t.extra.get("tt", 0.0)) * PI
			ci.draw_line(Vector2.ZERO, Vector2.from_angle(a - PI * 0.5) * w * 0.25, Color("2d3436"), 2.5, true)
			var blink: bool = t.extra.get("blink", false)
			ci.draw_circle(Vector2(w * 0.32, -h * 0.32), 4.0, Color(2.0, 0.6, 0.6) if blink else Color("6c5ce7").darkened(0.4), true, -1.0, true)
		"lamp":
			var lit: bool = t.is_on()
			ci.draw_colored_polygon(rr(Rect2(-w * 0.45, h * 0.32, w * 0.9, h * 0.18), 3.0), Color("636e72"))
			ci.draw_line(Vector2(0, h * 0.32), Vector2(0, -h * 0.05), Color("b2bec3"), 3.0)
			if lit:
				ci.draw_circle(Vector2(0, -h * 0.05), w * 0.3, Color(2.4, 2.1, 1.2), true, -1.0, true)
			else:
				ci.draw_circle(Vector2(0, -h * 0.05), w * 0.26, Color("dfe6e9"), true, -1.0, true)
			var shade := PackedVector2Array([Vector2(-w * 0.5, -h * 0.05), Vector2(w * 0.5, -h * 0.05), Vector2(w * 0.3, -h * 0.5), Vector2(-w * 0.3, -h * 0.5)])
			ci.draw_colored_polygon(shade, col if not lit else col.lightened(0.3))
			ci.draw_polyline(closed(shade), col.darkened(0.45), 2.0, true)
		"bell":
			var wob := sin(tm * 30.0) * 0.12 if t.cooldown > 0.0 else 0.0
			ci.draw_set_transform(_o, wob, Vector2(s * f, s) * _k)
			var bell := PackedVector2Array()
			for i in 13:
				var a := PI + PI * float(i) / 12.0
				bell.append(Vector2(cos(a) * r * 0.75, sin(a) * r * 0.9))
			bell.append(Vector2(r, r * 0.7))
			bell.append(Vector2(-r, r * 0.7))
			ci.draw_colored_polygon(bell, col)
			ci.draw_polyline(closed(bell), col.darkened(0.45), 2.0, true)
			ci.draw_circle(Vector2(0, r * 0.75), r * 0.18, col.darkened(0.35), true, -1.0, true)
			shine(ci, Vector2(0, -r * 0.1), r * 0.8, 0.6)
		"fan":
			panel(ci, box, 6.0, col)
			ci.draw_circle(Vector2(0, -h * 0.05), w * 0.4, Color("dfe6e9"), true, -1.0, true)
			var spin := tm * 18.0 if t.is_on() else 0.3
			for i in 3:
				var a := spin + TAU * i / 3.0
				ci.draw_colored_polygon(ellipse(Vector2(0, -h * 0.05) + Vector2.from_angle(a) * w * 0.2, w * 0.18, w * 0.08, 12, a), col.darkened(0.2))
			ci.draw_circle(Vector2(0, -h * 0.05), w * 0.07, Color("2d3436"), true, -1.0, true)
			ci.draw_arc(Vector2(0, -h * 0.05), w * 0.4, 0, TAU, 32, Color("636e72"), 2.0, true)
		"magnet":
			var u := PackedVector2Array()
			for i in 13:
				var a := PI * float(i) / 12.0
				u.append(Vector2(cos(a) * w * 0.48, -sin(a) * h * 0.7 + h * 0.2))
			ci.draw_polyline(u, col, h * 0.42, true)
			ci.draw_rect(Rect2(-w * 0.5 - 1, h * 0.05, w * 0.3, h * 0.45), Color("dfe6e9"))
			ci.draw_rect(Rect2(w * 0.2 + 1, h * 0.05, w * 0.3, h * 0.45), Color("dfe6e9"))
			if t.is_on():
				for k in 3:
					var rr2 := w * (0.6 + 0.25 * k) + fmod(tm * 40.0, 20.0)
					ci.draw_arc(Vector2(0, h * 0.5), rr2, 0.3, PI - 0.3, 20, Color(1.2, 0.5, 0.5, 0.35), 2.0, true)
		"motor", "wheel":
			ci.draw_circle(Vector2.ZERO, r, col, true, -1.0, true)
			ci.draw_circle(Vector2.ZERO, r * 0.82, col.lightened(0.12), false, r * 0.12, true)
			if t.id == "wheel":
				for i in 10:
					var a := TAU * i / 10.0
					ci.draw_line(Vector2.from_angle(a) * r * 0.86, Vector2.from_angle(a) * r, col.lightened(0.25), 3.0, true)
			ci.draw_circle(Vector2.ZERO, r * 0.55, Color("b2bec3"), true, -1.0, true)
			for i in 5:
				var a := TAU * i / 5.0
				ci.draw_line(Vector2.ZERO, Vector2.from_angle(a) * r * 0.52, Color("636e72"), 3.0, true)
			ci.draw_circle(Vector2.ZERO, r * 0.16, Color("dfe6e9"), true, -1.0, true)
			if t.id == "motor":
				ci.draw_circle(Vector2(0, -r * 0.35), r * 0.09, Color(0.4, 2.0, 0.8) if t.is_on() else Color("2d3436"), true, -1.0, true)
			outline_circle(ci, Vector2.ZERO, r, col)
		"rocket":
			if t.is_on():
				var fl := 0.8 + 0.3 * sin(tm * 40.0)
				var flame := PackedVector2Array([Vector2(-w * 0.5, -h * 0.3), Vector2(-w * 0.5 - h * 1.6 * fl, 0), Vector2(-w * 0.5, h * 0.3)])
				ci.draw_colored_polygon(flame, Color(2.2, 1.2, 0.3))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.5, -h * 0.15), Vector2(-w * 0.5 - h * 0.9 * fl, 0), Vector2(-w * 0.5, h * 0.15)]), Color(2.6, 2.4, 1.6))
			panel(ci, Rect2(-w * 0.5, -h * 0.5, w * 0.75, h), h * 0.4, col)
			var nose := PackedVector2Array([Vector2(w * 0.25, -h * 0.5), Vector2(w * 0.5, 0), Vector2(w * 0.25, h * 0.5)])
			ci.draw_colored_polygon(nose, Color("ff4757"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.45, -h * 0.5), Vector2(-w * 0.3, -h * 0.5), Vector2(-w * 0.5, -h * 0.95)]), Color("ff4757"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.45, h * 0.5), Vector2(-w * 0.3, h * 0.5), Vector2(-w * 0.5, h * 0.95)]), Color("ff4757"))
			ci.draw_circle(Vector2(w * 0.05, 0), h * 0.22, Color("74b9ff"), true, -1.0, true)
		"propeller":
			panel(ci, Rect2(-w * 0.12, -h * 0.1, w * 0.24, h * 0.6), 3.0, Color("636e72"))
			var sp := cos(tm * 30.0) if t.is_on() else 1.0
			ci.draw_colored_polygon(ellipse(Vector2(0, -h * 0.25), w * 0.5 * absf(sp) + 2.0, h * 0.22, 20), col)
			ci.draw_circle(Vector2(0, -h * 0.25), 4.0, Color("2d3436"), true, -1.0, true)
		"conveyor":
			panel(ci, box, h * 0.5, Color("2d3436"))
			var off := fmod(tm * 60.0, 22.0) if t.is_on() else 0.0
			var x := -w * 0.5 + off
			while x < w * 0.45:
				ci.draw_line(Vector2(x, -h * 0.25), Vector2(x + 6, 0), Color("ffd43b"), 2.5, true)
				ci.draw_line(Vector2(x + 6, 0), Vector2(x, h * 0.25), Color("ffd43b"), 2.5, true)
				x += 22.0
			ci.draw_circle(Vector2(-w * 0.5 + h * 0.5, 0), h * 0.3, Color("b2bec3"), true, -1.0, true)
			ci.draw_circle(Vector2(w * 0.5 - h * 0.5, 0), h * 0.3, Color("b2bec3"), true, -1.0, true)
		"spring_pad":
			panel(ci, Rect2(-w * 0.5, h * 0.1, w, h * 0.4), 3.0, Color("636e72"))
			var zz := PackedVector2Array()
			for i in 7:
				zz.append(Vector2((-1.0 if i % 2 == 0 else 1.0) * w * 0.3, lerpf(h * 0.1, -h * 0.3, float(i) / 6.0)))
			ci.draw_polyline(zz, Color("dfe6e9"), 3.0, true)
			panel(ci, Rect2(-w * 0.5, -h * 0.5, w, h * 0.3), 4.0, col)
		"cannon":
			ci.draw_circle(Vector2(-w * 0.15, h * 0.25), h * 0.42, Color("8c5a2b"), true, -1.0, true)
			panel(ci, Rect2(-w * 0.45, -h * 0.4, w * 0.95, h * 0.6), h * 0.3, col)
			ci.draw_circle(Vector2(w * 0.48, -h * 0.1), h * 0.22, Color("111111"), true, -1.0, true)
			ci.draw_line(Vector2(w * 0.1, -h * 0.4), Vector2(w * 0.1, h * 0.2), col.lightened(0.25), 3.0)
			ci.draw_circle(Vector2(-w * 0.15, h * 0.25), h * 0.14, Color("dfe6e9"), true, -1.0, true)
		"bubbler":
			panel(ci, box, 8.0, col)
			ci.draw_colored_polygon(rr(Rect2(w * 0.3, -h * 0.15, w * 0.3, h * 0.3), 4.0), Color("b2bec3"))
			ci.draw_arc(Vector2(-w * 0.1, -h * 0.05), w * 0.18, 0, TAU, 20, Color(1, 1, 1, 0.9), 2.5, true)
			ci.draw_circle(Vector2(-w * 0.16, -h * 0.12), 2.5, Color.WHITE)
		"confetti":
			panel(ci, Rect2(-w * 0.5, -h * 0.35, w, h * 0.85), 4.0, col)
			for i in 4:
				ci.draw_line(Vector2(-w * 0.5, -h * 0.25 + i * h * 0.2), Vector2(w * 0.5, -h * 0.15 + i * h * 0.2), Catalog.PAINT[i * 2], 3.0, true)
			for i in 5:
				ci.draw_circle(Vector2(lerpf(-w * 0.4, w * 0.4, i / 4.0), -h * 0.42 - (i % 2) * 4.0), 2.5, Catalog.PAINT[i], true, -1.0, true)
		"firework":
			ci.draw_line(Vector2(0, h * 0.2), Vector2(0, h * 0.75), Color("c8814a"), 2.5)
			panel(ci, Rect2(-w * 0.5, -h * 0.3, w, h * 0.55), 3.0, col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.55, -h * 0.3), Vector2(w * 0.55, -h * 0.3), Vector2(0, -h * 0.55)]), Color("ffd43b"))
			ci.draw_line(Vector2(-w * 0.5, -h * 0.05), Vector2(w * 0.5, -h * 0.1), Color.WHITE, 2.0)
			if t.fuse >= 0.0:
				_sparkle(ci, Vector2(0, h * 0.75), 6.0, tm)
		"paint_bomb", "bubble_bomb", "glue_bomb", "freeze_bomb", "mega_boom":
			_bomb(ci, t, col, r, tm)
		"boom_barrel":
			panel(ci, box, 8.0, col)
			ci.draw_rect(Rect2(-w * 0.5, -h * 0.28, w, 5), col.darkened(0.4))
			ci.draw_rect(Rect2(-w * 0.5, h * 0.22, w, 5), col.darkened(0.4))
			_star(ci, Vector2(0, 0), w * 0.28, Color("ffd43b"))
			ci.draw_set_transform(_o, 0.0, Vector2(s, s) * _k)
			text(ci, "!", Vector2(0, 1), int(h * 0.4), Color("e84118"))
			ci.draw_set_transform(_o, 0.0, Vector2(s * f, s) * _k)
			if t.fuse >= 0.0:
				_sparkle(ci, Vector2(0, -h * 0.55), 7.0, tm)
		"go_kart", "monster_truck":
			var big: bool = t.id == "monster_truck"
			if big:
				var cab := PackedVector2Array([Vector2(-w * 0.25, -h * 0.5), Vector2(w * 0.2, -h * 0.5), Vector2(w * 0.32, -h * 1.25), Vector2(-w * 0.18, -h * 1.25)])
				ci.draw_colored_polygon(cab, col.darkened(0.1))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.12, -h * 0.6), Vector2(w * 0.15, -h * 0.6), Vector2(w * 0.24, -h * 1.12), Vector2(-w * 0.08, -h * 1.12)]), Color("a5f3ff"))
			else:
				ci.draw_line(Vector2(w * 0.05, -h * 0.4), Vector2(w * 0.2, -h * 1.3), Color("2d3436"), 3.0)
				ci.draw_circle(Vector2(w * 0.2, -h * 1.3), 7.0, Color("2d3436"), false, 3.0, true)
				ci.draw_colored_polygon(rr(Rect2(-w * 0.32, -h * 1.0, w * 0.26, h * 0.6), 5.0), Color("2d3436"))
			panel(ci, box, h * 0.4, col)
			ci.draw_circle(Vector2(-w * 0.05, 0), h * 0.3, Color.WHITE, true, -1.0, true)
			text(ci, "7" if not big else "M", Vector2(-w * 0.05, 0), int(h * 0.42), col.darkened(0.3))
			ci.draw_circle(Vector2(w * 0.46, -h * 0.1), h * 0.16, Color(2.2, 2.1, 1.4) if t.is_on() else Color("ffeaa7"), true, -1.0, true)
		"balloon", "envelope":
			ci.draw_colored_polygon(ellipse(Vector2(0, -r * 0.05), r * 0.92, r, 32), col)
			if t.id == "envelope":
				for k in [-0.5, 0.0, 0.5]:
					ci.draw_colored_polygon(ellipse(Vector2(k * r * 0.9, 0), r * 0.12, r * 0.95, 20), Color("ffd43b") if k == 0.0 else col.lightened(0.25))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-4, r * 0.92), Vector2(4, r * 0.92), Vector2(0, r * 1.05)]), col.darkened(0.2))
			ci.draw_polyline(closed(ellipse(Vector2(0, -r * 0.05), r * 0.92, r, 32)), col.darkened(0.4), 2.0, true)
			shine(ci, Vector2(0, -r * 0.1), r, 0.6)
		"hot_air":
			panel(ci, box, 5.0, col)
			for i in 4:
				ci.draw_line(Vector2(-w * 0.5, -h * 0.3 + i * h * 0.2), Vector2(w * 0.5, -h * 0.3 + i * h * 0.2), col.darkened(0.25), 2.0)
			for i in 6:
				ci.draw_line(Vector2(-w * 0.4 + i * w * 0.16, -h * 0.5), Vector2(-w * 0.4 + i * w * 0.16, h * 0.5), col.lightened(0.15), 2.0)
		"saucer":
			var lit: bool = t.on
			if lit:
				var beam := PackedVector2Array([Vector2(-w * 0.2, h * 0.3), Vector2(w * 0.2, h * 0.3), Vector2(w * 0.9, h * 14.0), Vector2(-w * 0.9, h * 14.0)])
				ci.draw_polygon(beam, PackedColorArray([Color(0.6, 1.6, 1.2, 0.45), Color(0.6, 1.6, 1.2, 0.45), Color(0.6, 1.6, 1.2, 0.0), Color(0.6, 1.6, 1.2, 0.0)]))
			ci.draw_colored_polygon(ellipse(Vector2(0, -h * 0.3), w * 0.24, h * 0.55, 24), Color(0.6, 0.95, 1.0, 0.85))
			ci.draw_colored_polygon(ellipse(Vector2.ZERO, w * 0.5, h * 0.32, 32), col)
			ci.draw_polyline(closed(ellipse(Vector2.ZERO, w * 0.5, h * 0.32, 32)), col.darkened(0.45), 2.0, true)
			for i in 5:
				var on_l := int(tm * 6.0 + i) % 2 == 0
				ci.draw_circle(Vector2(lerpf(-w * 0.36, w * 0.36, i / 4.0), h * 0.05), 3.5, Color(2.0, 1.8, 0.5) if on_l else Color(0.5, 1.8, 1.4), true, -1.0, true)
			shine(ci, Vector2(0, -h * 0.4), w * 0.22, 0.7)
		"boat":
			var hull := PackedVector2Array([Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5), Vector2(w * 0.32, h * 0.5), Vector2(-w * 0.38, h * 0.5)])
			ci.draw_colored_polygon(hull, col)
			ci.draw_line(Vector2(-w * 0.46, -h * 0.15), Vector2(w * 0.46, -h * 0.15), Color.WHITE, 3.0)
			ci.draw_polyline(closed(hull), col.darkened(0.45), 2.0, true)
		"sail":
			ci.draw_line(Vector2(0, h * 0.5), Vector2(0, -h * 0.5), Color("8c5a2b"), 4.0)
			var sl := PackedVector2Array([Vector2(3, -h * 0.45), Vector2(3, h * 0.35), Vector2(h * 0.55, h * 0.35)])
			ci.draw_colored_polygon(sl, col)
			ci.draw_polyline(closed(sl), col.darkened(0.25), 2.0, true)
		"sword", "katana", "laser_sword":
			var blade_c := col if t.id != "laser_sword" else Color(col.r * 2.2, col.g * 2.2, col.b * 2.6)
			var hilt := -w * 0.5 + w * 0.22
			if t.id == "laser_sword":
				ci.draw_line(Vector2(hilt, 0), Vector2(w * 0.5, 0), blade_c, h * 1.6, true)
				ci.draw_line(Vector2(hilt, 0), Vector2(w * 0.5, 0), Color(2.6, 2.6, 2.6), h * 0.6, true)
			else:
				var blade := PackedVector2Array([Vector2(hilt, -h * 0.5), Vector2(w * 0.38, -h * 0.5), Vector2(w * 0.5, 0), Vector2(w * 0.38, h * 0.5), Vector2(hilt, h * 0.5)])
				ci.draw_colored_polygon(blade, blade_c)
				ci.draw_line(Vector2(hilt, -h * 0.1), Vector2(w * 0.4, -h * 0.1), Color(1, 1, 1, 0.6), 1.5, true)
				ci.draw_polyline(closed(blade), blade_c.darkened(0.45), 1.5, true)
			ci.draw_line(Vector2(-w * 0.5, 0), Vector2(hilt, 0), Color("5d4037"), h * 1.1, true)
			if t.id != "katana":
				ci.draw_line(Vector2(hilt, -h * 1.6), Vector2(hilt, h * 1.6), Color("f1c40f"), 3.5, true)
			else:
				ci.draw_circle(Vector2(hilt, 0), h * 1.1, Color("f1c40f"), true, -1.0, true)
		"axe":
			ci.draw_line(Vector2(-w * 0.5, 0), Vector2(w * 0.42, 0), Color("8b5a2b"), h * 0.6, true)
			var head := PackedVector2Array([Vector2(w * 0.2, -h * 0.4), Vector2(w * 0.45, -h * 1.9), Vector2(w * 0.55, -h * 0.4), Vector2(w * 0.55, h * 0.4), Vector2(w * 0.45, h * 1.9), Vector2(w * 0.2, h * 0.4)])
			ci.draw_colored_polygon(head, col)
			ci.draw_polyline(closed(head), col.darkened(0.45), 1.5, true)
		"spear":
			ci.draw_line(Vector2(-w * 0.5, 0), Vector2(w * 0.38, 0), Color("a0703c"), h, true)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.36, -h * 1.3), Vector2(w * 0.5, 0), Vector2(w * 0.36, h * 1.3)]), Color("dfe6e9"))
		"hammer", "club":
			ci.draw_line(Vector2(-w * 0.5, 0), Vector2(w * 0.3, 0), Color("8b5a2b"), h * 0.5, true)
			if t.id == "hammer":
				panel(ci, Rect2(w * 0.22, -h * 1.5, w * 0.28, h * 3.0), 3.0, col)
			else:
				ci.draw_colored_polygon(ellipse(Vector2(w * 0.25, 0), w * 0.28, h * 0.75, 18), col)
		"pistol", "rifle", "shotgun", "mg", "sniper", "laser_gun":
			var dark := col.darkened(0.2)
			var barrel_y := -h * 0.15
			panel(ci, Rect2(-w * 0.32, -h * 0.5, w * 0.55, h * 0.75), 3.0, col)
			ci.draw_line(Vector2(w * 0.1, barrel_y), Vector2(w * 0.5, barrel_y), dark.darkened(0.3), h * 0.32, true)
			ci.draw_colored_polygon(rr(Rect2(-w * 0.18, h * 0.1, h * 0.55, h * 0.75), 2.0), dark)
			if t.id in ["rifle", "sniper", "shotgun", "mg"]:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.32, -h * 0.4), Vector2(-w * 0.5, -h * 0.15), Vector2(-w * 0.5, h * 0.4), Vector2(-w * 0.3, h * 0.25)]), Color("6d4c2e") if t.id != "mg" else dark)
			if t.id == "sniper":
				ci.draw_colored_polygon(rr(Rect2(-w * 0.12, -h * 1.15, w * 0.3, h * 0.5), 3.0), Color("2d3436"))
				ci.draw_circle(Vector2(w * 0.18, -h * 0.9), h * 0.22, Color(0.5, 0.9, 1.4), true, -1.0, true)
			if t.id == "mg":
				ci.draw_colored_polygon(rr(Rect2(-w * 0.05, h * 0.2, w * 0.18, h * 0.6), 2.0), Color("c9a227"))
			if t.id == "laser_gun":
				ci.draw_circle(Vector2(w * 0.05, -h * 0.1), h * 0.25, Color(1.4, 0.8, 2.6), true, -1.0, true)
				ci.draw_line(Vector2(w * 0.2, barrel_y), Vector2(w * 0.5, barrel_y), Color(1.2, 0.7, 2.2), h * 0.2, true)
		"bazooka":
			panel(ci, Rect2(-w * 0.5, -h * 0.4, w, h * 0.8), h * 0.4, col)
			ci.draw_rect(Rect2(w * 0.38, -h * 0.5, w * 0.12, h), col.darkened(0.35))
			ci.draw_colored_polygon(rr(Rect2(-w * 0.05, h * 0.3, h * 0.5, h * 0.7), 2.0), col.darkened(0.3))
		"bow":
			var arc := PackedVector2Array()
			for i in 13:
				var a := -PI * 0.5 + PI * float(i) / 12.0
				arc.append(Vector2(cos(a) * w * 0.9, sin(a) * h * 0.5))
			ci.draw_polyline(arc, col, 3.5, true)
			ci.draw_line(Vector2(0, -h * 0.5), Vector2(0, h * 0.5), Color(1, 1, 1, 0.8), 1.2, true)
		"flamethrower":
			ci.draw_circle(Vector2(-w * 0.2, h * 0.1), h * 0.6, Color("e74c3c"), true, -1.0, true)
			panel(ci, Rect2(-w * 0.1, -h * 0.35, w * 0.6, h * 0.5), 3.0, Color("636e72"))
			ci.draw_circle(Vector2(w * 0.5, -h * 0.1), h * 0.2, Color(2.2, 1.0, 0.3), true, -1.0, true)
		"grenades":
			panel(ci, box, 5.0, col)
			for i in 3:
				ball(ci, Vector2(-w * 0.25 + i * w * 0.25, -h * 0.55), h * 0.28, Color("4b5320"))
		"helmet":
			var dome := PackedVector2Array()
			for i in 13:
				var a := PI + PI * float(i) / 12.0
				dome.append(Vector2(cos(a) * w * 0.5, sin(a) * h * 1.6 + h * 0.5))
			ci.draw_colored_polygon(dome, col)
			ci.draw_line(Vector2(-w * 0.55, h * 0.45), Vector2(w * 0.55, h * 0.45), col.darkened(0.3), 3.0, true)
		"body_armor":
			panel(ci, box, 8.0, col)
			ci.draw_line(Vector2(0, -h * 0.4), Vector2(0, h * 0.4), col.darkened(0.3), 2.0, true)
			for k in [-1.0, 1.0]:
				ci.draw_circle(Vector2(k * w * 0.25, -h * 0.25), 2.5, Color("dfe6e9"), true, -1.0, true)
		"shield":
			var sp := rr(box, 6.0)
			ci.draw_colored_polygon(sp, col)
			ci.draw_polyline(closed(sp), Color("7f8c8d"), 2.5, true)
			ci.draw_circle(Vector2.ZERO, w * 0.35, Color("f1c40f"), true, -1.0, true)
		"grenade":
			ball(ci, Vector2.ZERO, r, col)
			ci.draw_line(Vector2(-r * 0.7, 0), Vector2(r * 0.7, 0), col.darkened(0.35), 1.5, true)
			ci.draw_line(Vector2(0, -r * 0.7), Vector2(0, r * 0.7), col.darkened(0.35), 1.5, true)
			ci.draw_colored_polygon(rr(Rect2(-r * 0.3, -r * 1.35, r * 0.6, r * 0.45), 1.0), Color("b2bec3"))
			if t.fuse >= 0.0:
				_sparkle(ci, Vector2(r * 0.3, -r * 1.4), 5.0, tm)
		"dynamite":
			for i in 3:
				panel(ci, Rect2(-w * 0.5 + i * w * 0.34 - w * 0.17 + w * 0.17, -h * 0.5, w * 0.34, h), 2.0, col)
			ci.draw_rect(Rect2(-w * 0.55, -h * 0.05, w * 1.1, h * 0.12), Color("2d3436"))
			ci.draw_line(Vector2(0, -h * 0.5), Vector2(w * 0.4, -h * 0.75), Color("d8c48a"), 1.5, true)
			if t.fuse >= 0.0:
				_sparkle(ci, Vector2(w * 0.4, -h * 0.75), 6.0, tm)
		"c4":
			panel(ci, box, 3.0, col)
			ci.draw_rect(Rect2(-w * 0.3, -h * 0.3, w * 0.4, h * 0.6), Color("2d3436"))
			var blink := int(tm * 3.0) % 2 == 0
			ci.draw_circle(Vector2(w * 0.3, 0), 3.0, Color(2.4, 0.4, 0.4) if blink else Color("7f1d1d"), true, -1.0, true)
			for k in 3:
				ci.draw_line(Vector2(-w * 0.45, -h * 0.35 + k * h * 0.35), Vector2(-w * 0.32, -h * 0.35 + k * h * 0.35), Color("e74c3c"), 1.5)
		"landmine":
			var dome2 := PackedVector2Array()
			for i in 13:
				var a := PI + PI * float(i) / 12.0
				dome2.append(Vector2(cos(a) * w * 0.5, sin(a) * h * 1.2 + h * 0.5))
			ci.draw_colored_polygon(dome2, col)
			ci.draw_circle(Vector2(0, -h * 0.4), 3.0, Color(2.2, 0.5, 0.4) if int(tm * 2.0) % 2 == 0 else Color("7f1d1d"), true, -1.0, true)
		"barrel":
			panel(ci, box, 8.0, col)
			ci.draw_rect(Rect2(-w * 0.5, -h * 0.28, w, 4), col.darkened(0.4))
			ci.draw_rect(Rect2(-w * 0.5, h * 0.22, w, 4), col.darkened(0.4))
			var tri := PackedVector2Array([Vector2(0, -h * 0.18), Vector2(w * 0.25, h * 0.15), Vector2(-w * 0.25, h * 0.15)])
			ci.draw_colored_polygon(tri, Color("f1c40f"))
			ci.draw_set_transform(_o, 0.0, Vector2(s, s) * _k)
			text(ci, "!", Vector2(0, 2), int(h * 0.3), Color("2d3436"))
			ci.draw_set_transform(_o, 0.0, Vector2(s * f, s) * _k)
			if t.fuse >= 0.0:
				_sparkle(ci, Vector2(0, -h * 0.55), 7.0, tm)
		"cluster", "napalm", "acid_bomb":
			ball(ci, Vector2.ZERO, r, col)
			if t.id == "cluster":
				for i in 5:
					ci.draw_circle(Vector2.from_angle(TAU * i / 5.0) * r * 0.55, r * 0.18, col.lightened(0.3), true, -1.0, true)
			elif t.id == "napalm":
				_star(ci, Vector2.ZERO, r * 0.55, Color(2.2, 1.0, 0.3))
			else:
				for i in 3:
					ci.draw_circle(Vector2(lerpf(-r * 0.4, r * 0.4, i / 2.0), r * 0.1 * (i % 2)), r * 0.2, Color(0.6, 1.8, 0.5), true, -1.0, true)
			ci.draw_colored_polygon(rr(Rect2(-r * 0.22, -r * 1.12, r * 0.44, r * 0.24), 2.0), Color("636e72"))
			if t.fuse >= 0.0:
				_sparkle(ci, Vector2(r * 0.4, -r * 1.25), 6.0, tm)
			outline_circle(ci, Vector2.ZERO, r, col)
		"nuke":
			var body2 := PackedVector2Array([Vector2(-w * 0.35, -h * 0.5), Vector2(w * 0.3, -h * 0.5), Vector2(w * 0.5, 0), Vector2(w * 0.3, h * 0.5), Vector2(-w * 0.35, h * 0.5)])
			ci.draw_colored_polygon(body2, col)
			ci.draw_polyline(closed(body2), col.darkened(0.5), 2.0, true)
			for k in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.35, k * h * 0.5), Vector2(-w * 0.5, k * h * 0.95), Vector2(-w * 0.2, k * h * 0.5)]), Color("2d3436"))
			ci.draw_circle(Vector2(0, 0), h * 0.32, Color("2d3436"), true, -1.0, true)
			for i in 3:
				var a := -PI * 0.5 + TAU * i / 3.0
				ci.draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(a - 0.45) * h * 0.3, Vector2.from_angle(a + 0.45) * h * 0.3]), col)
			if t.fuse >= 0.0:
				ci.draw_circle(Vector2(w * 0.3, -h * 0.25), 4.0, Color(2.6, 0.5, 0.4) if int(tm * 4.0) % 2 == 0 else Color("7f1d1d"), true, -1.0, true)
		"rocket":
			panel(ci, Rect2(-w * 0.5, -h * 0.5, w * 0.8, h), h * 0.5, col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.3, -h * 0.5), Vector2(w * 0.5, 0), Vector2(w * 0.3, h * 0.5)]), Color("e74c3c"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.5, -h * 0.4), Vector2(-w * 0.85, 0), Vector2(-w * 0.5, h * 0.4)]), Color(2.4, 1.3, 0.3))
		"arrow":
			ci.draw_line(Vector2(-w * 0.5, 0), Vector2(w * 0.4, 0), Color("8b5a2b"), 2.5, true)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.35, -4), Vector2(w * 0.55, 0), Vector2(w * 0.35, 4)]), Color("b2bec3"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(-w * 0.35, -5), Vector2(-w * 0.3, 0), Vector2(-w * 0.35, 5)]), Color("e74c3c"))
		"shell":
			ball(ci, Vector2.ZERO, r, col)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-r * 0.6, -r * 0.6), Vector2(-r * 1.4, -r * 0.9), Vector2(-r * 1.4, r * 0.9), Vector2(-r * 0.6, r * 0.6)]), col.lightened(0.2))
		"meteor":
			ci.draw_circle(Vector2.ZERO, r * 1.5, Color(2.4, 0.9, 0.2, 0.35), true, -1.0, true)
			ball(ci, Vector2.ZERO, r, Color("6e2c00"))
			for i in 4:
				ci.draw_circle(Vector2.from_angle(i * 1.7) * r * 0.5, r * 0.2, Color(2.4, 1.0, 0.25), true, -1.0, true)
		_:
			if t.shape_kind == "circle":
				ball(ci, Vector2.ZERO, r, col)
				shine(ci, Vector2.ZERO, r)
			else:
				panel(ci, box, 5.0, col)
	_states(ci, t, s, f, tm)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _states(ci: CanvasItem, t, s: float, f: float, tm: float) -> void:
	var he: Vector2 = Vector2(t.r, t.r) if t.shape_kind == "circle" else Vector2(t.w, t.h) * 0.5
	if t.frozen_t > 0.0:
		var ice := Rect2(-he - Vector2(6, 6), he * 2.0 + Vector2(12, 12))
		ci.draw_colored_polygon(rr(ice, 8.0), Color(0.7, 0.93, 1.0, 0.55))
		ci.draw_line(ice.position + Vector2(6, 8), ice.position + Vector2(ice.size.x * 0.4, 5), Color(1, 1, 1, 0.8), 2.5, true)
		ci.draw_polyline(closed(rr(ice, 8.0)), Color(0.85, 0.97, 1.0, 0.95), 2.0, true)
	if t.nailed:
		ci.draw_set_transform(_o, 0.0, Vector2(s, s) * _k)
		ci.draw_circle(Vector2.ZERO, 5.0, Color("b2bec3"), true, -1.0, true)
		ci.draw_circle(Vector2.ZERO, 5.0, Color("636e72"), false, 1.5, true)
		ci.draw_line(Vector2(-2.5, 0), Vector2(2.5, 0), Color("636e72"), 1.2)
		ci.draw_set_transform(_o, 0.0, Vector2(s * f, s) * _k)
	if t.electric > 0.05:
		for i in 4:
			var a := randf() * TAU
			var p0 := Vector2.from_angle(a) * he.length() * 0.8
			var p1 := p0 + Vector2(randf_range(-12, 12), randf_range(-12, 12))
			ci.draw_line(p0, p1, Color(1.4, 1.8, 2.2), 2.0, true)
	if t.bubble_t > 0.0:
		var br: float = he.length() * 1.3 + 6.0
		ci.draw_set_transform(_o, -t.rotation, Vector2(s, s) * _k)
		ci.draw_circle(Vector2.ZERO, br, Color(0.75, 0.95, 1.0, 0.18), true, -1.0, true)
		ci.draw_arc(Vector2.ZERO, br, 0, TAU, 40, Color(0.85, 1.0, 1.0, 0.75), 2.0, true)
		ci.draw_arc(Vector2.ZERO, br * 0.8, -2.4, -1.5, 12, Color(1, 1, 1, 0.8), 3.0, true)
		ci.draw_arc(Vector2.ZERO, br * 0.92, 0.3 + sin(tm) * 0.2, 1.2, 12, Color(1.0, 0.7, 1.0, 0.45), 2.0, true)


static func _bolt(ci: CanvasItem, c: Vector2, sz: float, col: Color) -> void:
	var p := PackedVector2Array([c + Vector2(-0.2, -1) * sz, c + Vector2(0.45, -1) * sz, c + Vector2(0.05, -0.1) * sz,
		c + Vector2(0.4, -0.1) * sz, c + Vector2(-0.3, 1) * sz, c + Vector2(0.0, 0.15) * sz, c + Vector2(-0.4, 0.15) * sz])
	ci.draw_colored_polygon(p, col)


static func _star(ci: CanvasItem, c: Vector2, rad: float, col: Color, rot := -PI * 0.5) -> void:
	var p := PackedVector2Array()
	for i in 10:
		var a := rot + TAU * i / 10.0
		p.append(c + Vector2.from_angle(a) * (rad if i % 2 == 0 else rad * 0.45))
	ci.draw_colored_polygon(p, col)


static func _sparkle(ci: CanvasItem, c: Vector2, rad: float, tm: float) -> void:
	for i in 5:
		var a := tm * 9.0 + TAU * i / 5.0
		ci.draw_line(c, c + Vector2.from_angle(a) * rad * randf_range(0.6, 1.4), Color(2.5, 2.0, 0.8), 2.0, true)
	ci.draw_circle(c, rad * 0.4, Color(3.0, 2.6, 1.6), true, -1.0, true)


static func _bomb(ci: CanvasItem, t, col: Color, r: float, tm: float) -> void:
	ball(ci, Vector2.ZERO, r, col)
	match t.id:
		"paint_bomb":
			for i in 4:
				var a := -PI * 0.15 + i * 0.4
				ci.draw_circle(Vector2.from_angle(a) * r * 0.65, r * 0.18, Catalog.PAINT[i * 2], true, -1.0, true)
		"bubble_bomb":
			ci.draw_arc(Vector2.ZERO, r * 0.6, 0, TAU, 24, Color(1, 1, 1, 0.8), 2.0, true)
			ci.draw_circle(Vector2(r * 0.25, r * 0.15), r * 0.18, Color(1, 1, 1, 0.6), false, 1.5, true)
		"glue_bomb":
			for i in 3:
				var x := lerpf(-r * 0.5, r * 0.5, i / 2.0)
				ci.draw_colored_polygon(ellipse(Vector2(x, r * (0.55 + 0.15 * (i % 2))), r * 0.13, r * 0.28, 12), col.lightened(0.35))
		"freeze_bomb":
			for i in 3:
				var a := PI * i / 3.0
				ci.draw_line(Vector2.from_angle(a) * r * 0.55, -Vector2.from_angle(a) * r * 0.55, Color.WHITE, 2.5, true)
		"mega_boom":
			_star(ci, Vector2(0, r * 0.1), r * 0.5, Color("ff4757"))
	ci.draw_colored_polygon(rr(Rect2(-r * 0.22, -r * 1.12, r * 0.44, r * 0.24), 2.0), Color("636e72"))
	ci.draw_arc(Vector2(r * 0.25, -r * 1.12), r * 0.25, PI, PI * 1.8, 8, Color("c8814a"), 2.5, true)
	if t.fuse >= 0.0:
		_sparkle(ci, Vector2(r * 0.42, -r * 1.3), 7.0, tm)
	outline_circle(ci, Vector2.ZERO, r, col)
	shine(ci, Vector2.ZERO, r, 0.55)


# --------------------------------------------------------------- Wigglies
## Smooth closed curve through the outline points (Catmull-Rom).
static func smooth(pts: PackedVector2Array, sub := 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var p0 := pts[(i - 1 + n) % n]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n]
		var p3 := pts[(i + 2) % n]
		for k in sub:
			var tt := float(k) / sub
			var t2 := tt * tt
			var t3 := t2 * tt
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * tt + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	return out


static func draw_wiggly(ci: CanvasItem, w) -> void:
	if w.pts.size() < 3:
		return
	var base: Color = w.shown_color()
	var dark: Color = w.def.dark if w.paint.a == 0.0 else base.darkened(0.45)
	var R: float = w.radius()
	var c: Vector2 = w.com
	# a ring that's been pulled can collapse into a weird shape; outward-push the
	# smoothed curve a touch so the jelly reads as one blob
	var outline := smooth(w.pts, 4)
	var grown := PackedVector2Array()
	for p in outline:
		grown.append(c + (p - c) * 1.12)
	if Geometry2D.triangulate_polygon(grown).is_empty():
		# a hard squash can make the outline cross itself; fall back to its hull
		grown = Geometry2D.convex_hull(grown)
		if grown.size() > 1:
			grown.remove_at(grown.size() - 1)
		if grown.size() < 3:
			return
	# soft shadow
	var sh := PackedVector2Array()
	for p in grown:
		sh.append(p + Vector2(3, 6))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.14))
	# body with a top-lit gradient
	var cols := PackedColorArray()
	var light := base.lightened(0.35)
	for p in grown:
		var k := clampf(((p.y - c.y) / R + 1.0) * 0.5, 0.0, 1.0)
		cols.append(light.lerp(base.darkened(0.08), k))
	if w.kind == "puffy" or w.kind == "frosty" or w.kind == "gummy":
		for i in cols.size():
			cols[i].a = 0.94
	ci.draw_polygon(grown, cols)
	ci.draw_polyline(closed(grown), dark, maxf(2.0, 3.0 * w.size), true)
	# kind accents
	var up := Vector2.UP.rotated(w.angle * 0.35)
	var top := c + up * R * 1.05
	var tm: float = w.t
	match w.kind:
		"bloop":
			ci.draw_arc(top + up * 6.0, 7.0 * w.size, PI * 0.9, TAU * 0.95, 12, dark, 3.0 * w.size, true)
		"gummy":
			for i in 3:
				var dp := c + Vector2.DOWN.rotated(w.angle * 0.3) * R * 0.95 + Vector2((i - 1) * R * 0.4, 0)
				ci.draw_colored_polygon(ellipse(dp, 4.0 * w.size, (6.0 + 3.0 * sin(tm * 2.0 + i)) * w.size, 10), base.lightened(0.15))
		"zappy":
			_bolt(ci, top + up * 4.0, 10.0 * w.size, Color(2.0, 1.8, 0.6))
		"blaze":
			for i in 3:
				var fp: Vector2 = top + up * 2.0 + up.orthogonal() * (i - 1) * 7.0 * w.size
				var hgt: float = (12.0 + 5.0 * sin(tm * 12.0 + i * 2.0)) * w.size
				ci.draw_colored_polygon(PackedVector2Array([fp - up.orthogonal() * 5.0 * w.size, fp + up * hgt, fp + up.orthogonal() * 5.0 * w.size]), Color(2.2, 1.1, 0.3))
		"frosty":
			for i in 3:
				var a := -0.5 + i * 0.5
				var ip := c + up.rotated(a) * R * 1.0
				ci.draw_colored_polygon(PackedVector2Array([ip - up.orthogonal() * 4.0, ip + up.rotated(a) * 9.0 * w.size, ip + up.orthogonal() * 4.0]), Color(0.9, 1.0, 1.0))
		"puffy":
			for i in 3:
				ci.draw_circle(top + up.orthogonal() * (i - 1) * 10.0 * w.size, 7.0 * w.size, base.lightened(0.2), true, -1.0, true)
		"boulder":
			for i in 5:
				var sp := c + Vector2(cos(i * 2.4), sin(i * 1.7)).rotated(w.angle) * R * 0.55
				ci.draw_circle(sp, 3.0 * w.size, dark.lightened(0.15), true, -1.0, true)
		"twinkle":
			_star(ci, top + up * 6.0, 9.0 * w.size, Color(2.2, 2.0, 0.8), w.angle * 0.35 - PI * 0.5)
			for i in 3:
				var a := tm * 2.0 + TAU * i / 3.0
				_star(ci, c + Vector2.from_angle(a) * R * 1.35, 3.5 * w.size, Color(1.8, 1.6, 2.2))
	# glossy shine
	ci.draw_colored_polygon(ellipse(c + Vector2(-R * 0.38, -R * 0.45), R * 0.26, R * 0.15, 18, -0.6), Color(1, 1, 1, 0.55))
	ci.draw_circle(c + Vector2(-R * 0.12, -R * 0.62), R * 0.06, Color(1, 1, 1, 0.7), true, -1.0, true)
	_face(ci, w, c, R, tm)
	# states
	if w.frozen_t > 0.0:
		var ice := rr(Rect2(c - Vector2(R, R) * 1.25, Vector2(R, R) * 2.5), R * 0.4)
		ci.draw_colored_polygon(ice, Color(0.7, 0.93, 1.0, 0.5))
		ci.draw_polyline(closed(ice), Color(0.9, 0.98, 1.0, 0.95), 2.5, true)
	if w.bubble_t > 0.0:
		var br := R * 1.6
		ci.draw_circle(c, br, Color(0.75, 0.95, 1.0, 0.15), true, -1.0, true)
		ci.draw_arc(c, br, 0, TAU, 48, Color(0.85, 1.0, 1.0, 0.8), 2.0, true)
		ci.draw_arc(c, br * 0.82, -2.4, -1.4, 12, Color(1, 1, 1, 0.85), 3.0, true)
	if w.electric > 0.0:
		for i in 5:
			var a := randf() * TAU
			var p0 := c + Vector2.from_angle(a) * R
			ci.draw_line(p0, p0 + Vector2(randf_range(-14, 14), randf_range(-14, 14)), Color(1.5, 1.9, 2.4), 2.0, true)
	if w.kind == "gummy" and w.special_t > 0.0:
		ci.draw_arc(c, R * 1.25, 0, TAU, 40, Color(1.0, 1.6, 0.6, 0.6), 3.0, true)


static func _face(ci: CanvasItem, w, c: Vector2, R: float, tm: float) -> void:
	# squash the face with the body so it stretches with the jelly
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for p in w.pts:
		minp = minp.min(p)
		maxp = maxp.max(p)
	var sx := clampf((maxp.x - minp.x) / (R * 2.0), 0.6, 1.6)
	var sy := clampf((maxp.y - minp.y) / (R * 2.0), 0.6, 1.6)
	var rot: float = wrapf(w.angle, -PI, PI) * 0.3
	ci.draw_set_transform(c + Vector2(0, -R * 0.08), rot, Vector2(sx, sy))
	var mood: String = w.mood
	var ex := R * 0.34
	var ey := -R * 0.12
	var look: Vector2 = w.look
	if w.com_vel.length() > 60.0:
		look = w.com_vel.normalized()
	var blink: bool = w.blink_t < 0.0
	var ink := Color("1e1b2e")
	# cheeks
	ci.draw_circle(Vector2(-ex * 1.45, R * 0.18), R * 0.13, Color(1.0, 0.45, 0.6, 0.35), true, -1.0, true)
	ci.draw_circle(Vector2(ex * 1.45, R * 0.18), R * 0.13, Color(1.0, 0.45, 0.6, 0.35), true, -1.0, true)
	for side in [-1.0, 1.0]:
		var e := Vector2(side * ex, ey)
		match mood:
			"dizzy":
				var sp := PackedVector2Array()
				for i in 14:
					var a: float = float(i) * 0.75 + tm * 8.0 * side
					sp.append(e + Vector2.from_angle(a) * R * 0.012 * i)
				ci.draw_polyline(sp, ink, 2.0, true)
			"sleep":
				ci.draw_arc(e + Vector2(0, -R * 0.02), R * 0.12, 0.2, PI - 0.2, 10, ink, 2.5, true)
			"strain":
				ci.draw_line(e + Vector2(-R * 0.1, -R * 0.08), e + Vector2(R * 0.1 * side, 0), ink, 3.0, true)
				ci.draw_line(e + Vector2(-R * 0.1, R * 0.08), e + Vector2(R * 0.1 * side, 0), ink, 3.0, true)
			"party":
				ci.draw_arc(e + Vector2(0, R * 0.05), R * 0.12, PI + 0.3, TAU - 0.3, 10, ink, 3.0, true)
			_:
				if blink:
					ci.draw_line(e + Vector2(-R * 0.13, 0), e + Vector2(R * 0.13, 0), ink, 2.5, true)
				else:
					var big := 1.25 if mood == "scared" or mood == "wow" else 1.0
					ci.draw_colored_polygon(ellipse(e, R * 0.17 * big, R * 0.21 * big, 20), Color.WHITE)
					var pr := R * (0.07 if mood == "scared" else 0.1)
					var pp := e + look * R * 0.06
					ci.draw_circle(pp, pr, ink, true, -1.0, true)
					ci.draw_circle(pp + Vector2(-pr * 0.35, -pr * 0.4), pr * 0.4, Color.WHITE, true, -1.0, true)
		if mood == "scared":
			ci.draw_line(e + Vector2(-R * 0.14, -R * 0.32), e + Vector2(R * 0.12, -R * 0.36 + side * R * 0.04), ink, 2.0, true)
	# mouth
	var m := Vector2(0, R * 0.28)
	match mood:
		"wow", "scared":
			ci.draw_colored_polygon(ellipse(m, R * 0.1, R * 0.14 if mood == "wow" else R * 0.08, 16), ink)
		"dizzy":
			var wv := PackedVector2Array()
			for i in 9:
				wv.append(m + Vector2(lerpf(-R * 0.2, R * 0.2, i / 8.0), sin(i * 1.6 + tm * 6.0) * R * 0.04))
			ci.draw_polyline(wv, ink, 2.5, true)
		"sleep":
			ci.draw_circle(m, R * 0.05, ink, true, -1.0, true)
		"strain", "frozen":
			var zz := PackedVector2Array()
			for i in 7:
				zz.append(m + Vector2(lerpf(-R * 0.22, R * 0.22, i / 6.0), (R * 0.04 if i % 2 == 0 else -R * 0.04)))
			ci.draw_rect(Rect2(m - Vector2(R * 0.24, R * 0.08), Vector2(R * 0.48, R * 0.16)), Color.WHITE)
			ci.draw_polyline(zz, ink, 2.0, true)
		"party":
			ci.draw_colored_polygon(PackedVector2Array([m + Vector2(-R * 0.22, -R * 0.04), m + Vector2(R * 0.22, -R * 0.04), m + Vector2(0, R * 0.2)]), ink)
			ci.draw_colored_polygon(ellipse(m + Vector2(0, R * 0.1), R * 0.08, R * 0.05, 10), Color("ff6b81"))
		_:
			ci.draw_arc(m + Vector2(0, -R * 0.1), R * 0.2, 0.35, PI - 0.35, 14, ink, 3.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if mood == "sleep":
		var zp := c + Vector2(R * 0.7, -R * 1.1)
		for i in 3:
			var k := fmod(tm * 0.6 + i / 3.0, 1.0)
			text(ci, "z", zp + Vector2(k * 18.0, -k * 30.0), int(10 + k * 10), Color(1, 1, 1, 1.0 - k))
	elif mood == "dizzy":
		for i in 3:
			var a := tm * 4.0 + TAU * i / 3.0
			_star(ci, c + Vector2(cos(a) * R * 0.8, -R * 1.15 + sin(a) * R * 0.2), 5.0, Color(2.0, 1.8, 0.6))


## A little Wiggly picture for the toy box.
static func draw_wiggly_icon(ci: CanvasItem, kind: String, c: Vector2, R: float) -> void:
	var def: Dictionary = Catalog.WIGGLIES.get(kind, Catalog.WIGGLIES.bloop)
	var fake := WigglyIcon.new()
	fake.kind = kind
	fake.def = def
	fake.size = R / Wiggly.BASE_R
	fake.com = c
	fake.t = now()
	fake.pts = PackedVector2Array()
	for i in Wiggly.N:
		var a := TAU * i / Wiggly.N
		fake.pts.append(c + Vector2(cos(a) * R, sin(a) * R * 0.92 + R * 0.06))
	draw_wiggly(ci, fake)

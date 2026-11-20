class_name Backdrop
extends CanvasLayer
## The painted sky behind each world: gradient, sun or moon and stars,
## drifting clouds, and far-away scenery that moves slower than the camera.

var world: Node = null
var cam_pos := Vector2.ZERO
var cam_zoom := 1.0
var _painter: Control


func _ready() -> void:
	layer = -10
	_painter = Control.new()
	_painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painter.draw.connect(_paint)
	add_child(_painter)


func _process(_d: float) -> void:
	_painter.queue_redraw()


func _paint() -> void:
	var sz := _painter.size
	var id: String = world.world_id if world else "meadow"
	var sky: Dictionary = Worlds.sky(id)
	var night: bool = world.night if world else false
	var top: Color = Worlds.NIGHT_SKY.top if night and id != "toyroom" else sky.top
	var bottom: Color = Worlds.NIGHT_SKY.bottom if night and id != "toyroom" else sky.bottom
	if night and id == "toyroom":
		top = top.darkened(0.6)
		bottom = bottom.darkened(0.55)
	_painter.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(sz.x, 0), sz, Vector2(0, sz.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	var tm := Time.get_ticks_msec() / 1000.0
	var px := -cam_pos.x * 0.08
	var py := -cam_pos.y * 0.05
	if night or id == "moon":
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 140:
			var p := Vector2(fposmod(rng.randf() * sz.x * 1.5 + px * 0.5, sz.x), rng.randf() * sz.y * 0.75)
			var tw := 0.5 + 0.5 * sin(tm * rng.randf_range(1.0, 3.0) + i)
			_painter.draw_circle(p, rng.randf_range(0.8, 2.2), Color(1.3, 1.3, 1.5, 0.4 + 0.6 * tw))
		var moon := Vector2(sz.x * 0.78, sz.y * 0.18)
		_painter.draw_circle(moon, 70.0, Color(1, 1, 0.9, 0.08))
		_painter.draw_circle(moon, 42.0, Color(1.25, 1.22, 1.1))
		_painter.draw_circle(moon + Vector2(-12, -8), 8.0, Color(0.85, 0.85, 0.8))
		_painter.draw_circle(moon + Vector2(14, 12), 6.0, Color(0.85, 0.85, 0.8))
	elif sky.get("sun", false):
		var sun := Vector2(sz.x * 0.82, sz.y * 0.16)
		_painter.draw_circle(sun, 90.0, Color(1, 0.95, 0.6, 0.15))
		_painter.draw_circle(sun, 64.0, Color(1, 0.95, 0.6, 0.25))
		_painter.draw_circle(sun, 44.0, Color(1.4, 1.25, 0.7))
	# far scenery
	var far: Color = sky.far
	var far2: Color = sky.far2
	if night:
		far = far.darkened(0.55)
		far2 = far2.darkened(0.55)
	var horizon := sz.y * 0.62 + py * 3.0
	match String(sky.layer):
		"hills":
			_wave(sz, horizon - 40.0, 90.0, 0.004, px * 0.6, far.lightened(0.15))
			_wave(sz, horizon + 30.0, 70.0, 0.006, px, far2)
		"mountains":
			_peaks(sz, horizon - 30.0, 260.0, px * 0.5, far, true)
			_peaks(sz, horizon + 60.0, 170.0, px, far2, true)
		"candy":
			_wave(sz, horizon - 30.0, 80.0, 0.008, px * 0.6, far)
			_wave(sz, horizon + 40.0, 60.0, 0.012, px, far2)
		"sea":
			_painter.draw_rect(Rect2(0, horizon + 20.0, sz.x, sz.y), far2.lightened(0.1))
			_wave(sz, horizon + 10.0, 10.0, 0.03, px + tm * 30.0, far)
			_wave(sz, horizon - 60.0, 60.0, 0.005, px * 0.4, Color("7fd38b").darkened(0.1 if not night else 0.6))
		"craters":
			_wave(sz, horizon - 10.0, 50.0, 0.007, px * 0.6, far)
			_painter.draw_circle(Vector2(sz.x * 0.2 + px * 0.2, sz.y * 0.25), 60.0, Color(0.6, 0.45, 0.9, 0.5))
			_painter.draw_arc(Vector2(sz.x * 0.2 + px * 0.2, sz.y * 0.25), 86.0, -0.4, 0.9, 24, Color(0.8, 0.7, 1.0, 0.6), 4.0, true)
		"room":
			# a big window and wallpaper stripes
			var x := fposmod(px * 2.0, 90.0) - 90.0
			while x < sz.x:
				_painter.draw_rect(Rect2(x, 0, 30, sz.y), Color(1, 1, 1, 0.12))
				x += 90.0
			var win := Rect2(sz.x * 0.55 + px * 2.0, sz.y * 0.12, 300, 220)
			_painter.draw_rect(win.grow(14), Color("ffffff"))
			_painter.draw_rect(win, Color("8fd3ff") if not night else Color("1b2350"))
			_painter.draw_rect(Rect2(win.position.x + win.size.x * 0.5 - 6, win.position.y, 12, win.size.y), Color.WHITE)
			_painter.draw_rect(Rect2(win.position.x, win.position.y + win.size.y * 0.5 - 6, win.size.x, 12), Color.WHITE)
		"factory":
			var x := fposmod(px * 0.6, 260.0) - 260.0
			var i := 0
			while x < sz.x + 260.0:
				var hgt := 180.0 + 90.0 * absf(sin(i * 1.3))
				_painter.draw_rect(Rect2(x, horizon - hgt, 150, hgt + sz.y), far)
				_painter.draw_rect(Rect2(x + 100, horizon - hgt - 120, 26, 120), far2)
				for k in 3:
					var sy := horizon - hgt - 140 - k * 40 - fmod(tm * 20.0, 40.0)
					_painter.draw_circle(Vector2(x + 113, sy), 16 + k * 6, Color(0.8, 0.8, 0.8, 0.25 - k * 0.07))
				for wy in 3:
					_painter.draw_rect(Rect2(x + 20, horizon - hgt + 30 + wy * 45, 30, 20), Color(1.0, 0.85, 0.4, 0.5))
				x += 260.0
				i += 1
		"volcano":
			_peaks(sz, horizon + 20.0, 300.0, px * 0.5, far, false)
			var glow := Vector2(sz.x * 0.7 + px * 0.5, horizon - 280.0)
			_painter.draw_circle(glow, 60.0, Color(1.0, 0.45, 0.1, 0.35))
			for k in 4:
				var sy := glow.y - 40 - k * 50 - fmod(tm * 25.0, 50.0)
				_painter.draw_circle(Vector2(glow.x + sin(tm + k) * 10.0, sy), 30 + k * 10, Color(0.25, 0.2, 0.2, 0.35 - k * 0.07))
		"grid":
			var step := 64.0 * cam_zoom
			var gx := fposmod(-cam_pos.x * cam_zoom, step)
			while gx < sz.x:
				_painter.draw_line(Vector2(gx, 0), Vector2(gx, sz.y), Color(1, 1, 1, 0.22), 1.0)
				gx += step
			var gy := fposmod(-cam_pos.y * cam_zoom, step)
			while gy < sz.y:
				_painter.draw_line(Vector2(0, gy), Vector2(sz.x, gy), Color(1, 1, 1, 0.22), 1.0)
				gy += step
		"clouds":
			for i in 6:
				var cx := fposmod(i * 330.0 + px * (0.5 + i * 0.1) + tm * 6.0, sz.x + 400.0) - 200.0
				var cy := sz.y * (0.55 + 0.08 * (i % 3))
				_cloud(Vector2(cx, cy), 1.6 - (i % 3) * 0.3, Color(1, 1, 1, 0.85))
	# drifting clouds
	if id in ["meadow", "candy", "frosty", "lagoon", "clouds"] and not night:
		for i in 4:
			var cx := fposmod(i * 420.0 + tm * (12.0 + i * 3.0) + px * 0.3, sz.x + 400.0) - 200.0
			_cloud(Vector2(cx, sz.y * (0.12 + 0.07 * i)), 1.0 - i * 0.12, Color(1, 1, 1, 0.9))


func _wave(sz: Vector2, y: float, amp: float, freq: float, ox: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= sz.x + 20.0:
		pts.append(Vector2(x, y - amp * (0.5 + 0.5 * sin((x - ox) * freq)) - amp * 0.3 * sin((x - ox) * freq * 2.7)))
		x += 16.0
	pts.append(Vector2(sz.x, sz.y))
	pts.append(Vector2(0, sz.y))
	_painter.draw_colored_polygon(pts, col)


func _peaks(sz: Vector2, y: float, hgt: float, ox: float, col: Color, snow: bool) -> void:
	var w := 320.0
	var x := fposmod(ox, w) - w
	while x < sz.x + w:
		var i := int(floor((x - ox) / w))
		var h2 := hgt * (0.7 + 0.3 * absf(sin(i * 1.7)))
		var tri := PackedVector2Array([Vector2(x - w * 0.6, y), Vector2(x, y - h2), Vector2(x + w * 0.6, y)])
		_painter.draw_colored_polygon(tri, col)
		if snow:
			_painter.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.16, y - h2 * 0.72), Vector2(x, y - h2), Vector2(x + w * 0.16, y - h2 * 0.72)]), Color(1, 1, 1, 0.9))
		x += w
	_painter.draw_rect(Rect2(0, y, sz.x, sz.y - y), col)


func _cloud(c: Vector2, s: float, col: Color) -> void:
	for b in [[Vector2(-40, 6), 28.0], [Vector2(0, -6), 38.0], [Vector2(42, 6), 26.0], [Vector2(10, 12), 30.0]]:
		_painter.draw_circle(c + b[0] * s, b[1] * s, col, true, -1.0, true)

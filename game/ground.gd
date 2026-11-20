class_name Ground
extends StaticBody2D
## A solid piece of the world: a polygon with a themed fill, a top edge
## (grass, snow, candy…) and surface details.

var poly := PackedVector2Array()
var style := {}
var seed_i := 0


func setup(points: PackedVector2Array, st: Dictionary, s := 1) -> void:
	poly = points
	style = st
	seed_i = s
	collision_layer = Toy.LAYER_GROUND
	collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = float(st.get("fric", 0.9))
	pm.bounce = float(st.get("bounce", 0.05))
	physics_material_override = pm
	var cp := CollisionPolygon2D.new()
	cp.build_mode = CollisionPolygon2D.BUILD_SOLIDS
	cp.polygon = points
	add_child(cp)
	z_index = -2


func _draw() -> void:
	if poly.size() < 3:
		return
	var fill: Color = style.get("fill", Color("8b5a2b"))
	var fill2: Color = style.get("fill2", fill.darkened(0.25))
	# vertical gradient fill
	var top := INF
	var bottom := -INF
	for p in poly:
		top = minf(top, p.y)
		bottom = maxf(bottom, p.y)
	var cols := PackedColorArray()
	for p in poly:
		cols.append(fill.lerp(fill2, clampf((p.y - top) / maxf(1.0, bottom - top), 0.0, 1.0)))
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		draw_colored_polygon(poly, fill)
	else:
		for i in range(0, tris.size(), 3):
			var t3 := PackedVector2Array([poly[tris[i]], poly[tris[i + 1]], poly[tris[i + 2]]])
			if absf((t3[1] - t3[0]).cross(t3[2] - t3[0])) < 0.5:
				continue   # a flat sliver; drawing it makes Godot complain
			var c3 := PackedColorArray([cols[tris[i]], cols[tris[i + 1]], cols[tris[i + 2]]])
			draw_polygon(t3, c3)
	_pattern(top, bottom)
	# top edge band on upward-facing edges
	var band: Color = style.get("top", Color("6ad04f"))
	var bw := float(style.get("top_w", 14.0))
	var n := poly.size()
	var cw := _clockwise()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var e := b - a
		if e.length() < 0.5:
			continue
		var nrm := Vector2(e.y, -e.x).normalized() * (1.0 if cw else -1.0)
		if nrm.y < -0.45:
			draw_line(a + Vector2(0, bw * 0.35), b + Vector2(0, bw * 0.35), band, bw, true)
			draw_line(a - Vector2(0, bw * 0.1), b - Vector2(0, bw * 0.1), band.lightened(0.25), 3.0, true)
			_tufts(a, b, band)
	draw_polyline(poly + PackedVector2Array([poly[0]]), fill2.darkened(0.35), 2.0, true)


func _clockwise() -> bool:
	var s := 0.0
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		s += (b.x - a.x) * (b.y + a.y)
	return s < 0.0


func _tufts(a: Vector2, b: Vector2, band: Color) -> void:
	var kind := String(style.get("tuft", ""))
	if kind == "":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a.x * 13.0 + a.y * 7.0) + seed_i
	var len := a.distance_to(b)
	var steps := int(len / 26.0)
	for i in steps:
		var p := a.lerp(b, (float(i) + rng.randf()) / maxf(1.0, float(steps)))
		match kind:
			"grass":
				var c := band.lightened(rng.randf_range(0.0, 0.3))
				draw_line(p, p + Vector2(rng.randf_range(-4, 4), -rng.randf_range(6, 12)), c, 2.5, true)
				draw_line(p + Vector2(3, 0), p + Vector2(3 + rng.randf_range(-3, 5), -rng.randf_range(5, 10)), c, 2.0, true)
			"snow":
				draw_circle(p + Vector2(0, -2), rng.randf_range(3, 6), Color(1, 1, 1, 0.95))
			"candy":
				draw_circle(p + Vector2(0, -3), 3.0, Catalog.PAINT[rng.randi() % 8])
			"sand":
				if rng.randf() < 0.3:
					draw_circle(p + Vector2(0, -2), 2.0, Color("f7e1a8"))


func _pattern(top: float, bottom: float) -> void:
	var kind := String(style.get("pattern", "dots"))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 977 + 3
	var minx := INF
	var maxx := -INF
	for p in poly:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
	var area := (maxx - minx) * (bottom - top)
	var count := clampi(int(area / 2600.0), 0, 900)
	var col: Color = style.get("dot", Color(0, 0, 0, 0.1))
	match kind:
		"planks":
			var y := top + 30.0
			while y < bottom:
				draw_line(Vector2(minx, y), Vector2(maxx, y), col, 2.0)
				y += 34.0
			for i in count / 4:
				var p := Vector2(rng.randf_range(minx, maxx), rng.randf_range(top, bottom))
				if Geometry2D.is_point_in_polygon(p, poly):
					draw_line(p, p + Vector2(0, 30), col, 2.0)
		"grid":
			var x := floorf(minx / 80.0) * 80.0
			while x < maxx:
				draw_line(Vector2(x, top + 12), Vector2(x, bottom), col, 1.5)
				x += 80.0
			var y2 := top + 40.0
			while y2 < bottom:
				draw_line(Vector2(minx, y2), Vector2(maxx, y2), col, 1.5)
				y2 += 80.0
		"stripes":
			for i in count / 2:
				var p := Vector2(rng.randf_range(minx, maxx), rng.randf_range(top + 20, bottom))
				if Geometry2D.is_point_in_polygon(p, poly) and Geometry2D.is_point_in_polygon(p + Vector2(22, 22), poly):
					draw_line(p, p + Vector2(22, 22), col, 6.0, true)
		_:
			for i in count:
				var p := Vector2(rng.randf_range(minx, maxx), rng.randf_range(top + 18, bottom))
				if Geometry2D.is_point_in_polygon(p, poly):
					draw_circle(p, rng.randf_range(2.0, 5.5), col)

class_name Ground
extends StaticBody2D
## A solid piece of the world: a polygon with a themed fill, a top edge
## (grass, snow, candy…) and surface details.

var poly := PackedVector2Array()
var style := {}
var seed_i := 0
var cracks := 0              # 0-3: a platform you built, cracked by blasts (see World.damage_platforms)


## How badly blasts have damaged it (0 = like new, 1 = about to break): more
## cracks show as it gets worse.
func set_damage(k: float) -> void:
	var c := clampi(int(k * 4.0), 0, 3)
	if c != cracks:
		cracks = c
		queue_redraw()


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
	for piece in slices(points):
		# its outline, minus any points in a straight line (convex_hull, like
		# set_point_cloud, repeats the first point at the end: a side of zero
		# length, whose zero "normal" turns a shape cast, CCD, into NaN)
		var hull := Geometry2D.convex_hull(piece)
		if hull.size() > 3 and hull[0] == hull[hull.size() - 1]:
			hull.resize(hull.size() - 1)
		var cs := CollisionShape2D.new()
		var shape := ConvexPolygonShape2D.new()
		shape.points = hull
		cs.shape = shape
		add_child(cs)
	z_index = -2


## The polygon cut into solid convex pieces for collisions: an upright slice
## between each pair of neighbouring corners (left to right), with slices
## next to each other joined up again while the result stays convex.
##
## Godot's own split (CollisionPolygon2D's BUILD_SOLIDS) turns a long strip of
## ground into a fan of needle-thin triangles reaching from the two bottom
## corners up to the surface. Anything pushed a little way into one is
## shoved sideways by the next, out of the ground's top and into the needles
## below, where the squeeze flung whole heaps of ragdolls out of the world.
static func slices(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if points.size() < 3:
		return out
	var xs: Array[float] = []
	var top := INF
	var bottom := -INF
	for v in points:
		xs.append(v.x)
		top = minf(top, v.y)
		bottom = maxf(bottom, v.y)
	xs.sort()
	var cuts: Array[float] = [xs[0]]
	for x in xs:
		if x - cuts[cuts.size() - 1] > 0.5:
			cuts.append(x)
	var prev := PackedVector2Array()   # the last slice, while it might still join the next
	for i in cuts.size() - 1:
		var x0: float = cuts[i]
		var x1: float = cuts[i + 1]
		var slab := PackedVector2Array([Vector2(x0, top - 1.0), Vector2(x1, top - 1.0), Vector2(x1, bottom + 1.0), Vector2(x0, bottom + 1.0)])
		var pieces := Geometry2D.intersect_polygons(points, slab)
		var solid: Array[PackedVector2Array] = []
		for pc in pieces:
			if not Geometry2D.is_polygon_clockwise(pc) and pc.size() >= 3:
				solid.append(pc)
		if solid.size() == 1 and prev.size() > 0:
			var joined := Geometry2D.merge_polygons(prev, solid[0])
			if joined.size() == 1 and _convex(joined[0]):
				prev = joined[0]
				continue
		if prev.size() > 0:
			out.append(prev)
			prev = PackedVector2Array()
		if solid.size() == 1:
			prev = solid[0]
		else:
			for pc in solid:
				for c in Geometry2D.decompose_polygon_in_convex(pc):
					out.append(c)
	if prev.size() > 0:
		out.append(prev)
	return out


## True if every corner of `p` turns the same way (points in a straight line,
## or within a hair of it, don't count).
static func _convex(p: PackedVector2Array) -> bool:
	var turn := 0.0
	var n := p.size()
	for i in n:
		var e1 := p[(i + 1) % n] - p[i]
		var e2 := p[(i + 2) % n] - p[(i + 1) % n]
		var c := e1.cross(e2) / maxf(1e-6, e1.length() * e2.length())   # (the sine of the turn)
		if absf(c) < 1e-4:
			continue
		if turn == 0.0:
			turn = signf(c)
		elif signf(c) != turn:
			return false
	return true


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
	if cracks > 0:
		_cracks(fill2.darkened(0.55))


## Zigzag cracks across a damaged platform: more of them, and longer, the
## worse it is (the same ones each time it's drawn).
func _cracks(col: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 131 + 17
	var box := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		box = box.expand(v)
	for i in cracks * 3:
		var p := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var pts := PackedVector2Array([p])
		var a := rng.randf_range(0.0, TAU)
		var step := minf(box.size.x, box.size.y) * 0.3 + 8.0
		for k in 2 + cracks:
			a += rng.randf_range(-0.9, 0.9)
			var q := pts[pts.size() - 1] + Vector2.from_angle(a) * step
			if not Geometry2D.is_point_in_polygon(q, poly):
				break
			pts.append(q)
		if pts.size() > 1:
			draw_polyline(pts, Color(0.1, 0.08, 0.06, 0.75), 2.5 + cracks * 0.7, true)
			draw_polyline(pts, col, 1.2, true)


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

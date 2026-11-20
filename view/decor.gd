class_name Decor
extends Node2D
## Scenery that doesn't move things around: trees, flowers, candy, palms…

var kind := "tree"
var scale_f := 1.0
var extra := {}
var _t := 0.0


func _ready() -> void:
	z_index = -3 if kind in ["tree", "pine", "palm", "lollipop", "cane", "frame", "crystal", "snowman", "umbrella"] else (-1 if kind != "rug" else -1)
	_t = randf() * 10.0


func _process(d: float) -> void:
	if kind in ["flower", "glow_plant", "palm", "tree", "fern"]:
		_t += d
		queue_redraw()


func _draw() -> void:
	var s := scale_f
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var sway := sin(_t * 1.4) * 0.04
	match kind:
		"tree":
			draw_colored_polygon(PackedVector2Array([Vector2(-12, 0), Vector2(12, 0), Vector2(8, -110), Vector2(-8, -110)]), Color("8b5a2b"))
			for b in [[Vector2(0, -150), 70.0], [Vector2(-45, -120), 50.0], [Vector2(45, -118), 52.0], [Vector2(0, -195), 48.0]]:
				var p: Vector2 = b[0] + Vector2(sway * 60.0, 0)
				draw_circle(p + Vector2(4, 6), b[1], Color(0, 0, 0, 0.12), true, -1.0, true)
				draw_circle(p, b[1], Color("4cb848"), true, -1.0, true)
				draw_circle(p + Vector2(-b[1] * 0.25, -b[1] * 0.3), b[1] * 0.55, Color("6ad35f"), true, -1.0, true)
			for i in 4:
				draw_circle(Vector2(-40 + i * 26, -150 + (i % 2) * 30) + Vector2(sway * 60.0, 0), 6.0, Color("ff5a5a"), true, -1.0, true)
		"pine":
			draw_rect(Rect2(-8, -30, 16, 30), Color("6d4526"))
			for i in 3:
				var y := -30.0 - i * 50.0
				var wdt := 80.0 - i * 18.0
				draw_colored_polygon(PackedVector2Array([Vector2(-wdt, y), Vector2(wdt, y), Vector2(0, y - 85)]), Color("2f8f5b").lightened(i * 0.06))
				draw_colored_polygon(PackedVector2Array([Vector2(-wdt * 0.6, y - 18), Vector2(wdt * 0.6, y - 18), Vector2(0, y - 60)]), Color(1, 1, 1, 0.75))
		"flower":
			var c: Color = extra.get("c", Color("ff5a5a"))
			var top := Vector2(sway * 120.0, -26)
			draw_line(Vector2.ZERO, top, Color("3f9e3a"), 3.0, true)
			draw_colored_polygon(Art.ellipse(Vector2(-6, -10), 7, 3, 10, -0.5), Color("4cb848"))
			for i in 5:
				draw_circle(top + Vector2.from_angle(TAU * i / 5.0) * 6.0, 5.0, c, true, -1.0, true)
			draw_circle(top, 4.0, Color("ffd43b"), true, -1.0, true)
		"bush":
			for b in [[Vector2(-26, -18), 26.0], [Vector2(0, -28), 30.0], [Vector2(28, -18), 24.0]]:
				draw_circle(b[0], b[1], Color("3f9e3a"), true, -1.0, true)
				draw_circle(b[0] + Vector2(-6, -8), b[1] * 0.5, Color("5cc94a"), true, -1.0, true)
		"lollipop":
			var c2: Color = extra.get("c", Color("ff5a5a"))
			draw_line(Vector2.ZERO, Vector2(0, -150), Color.WHITE, 8.0, true)
			draw_circle(Vector2(0, -190), 52.0, c2, true, -1.0, true)
			var sp := PackedVector2Array()
			for i in 40:
				var a := i * 0.45
				sp.append(Vector2(0, -190) + Vector2.from_angle(a) * (2.0 + i * 1.2))
			draw_polyline(sp, Color(1, 1, 1, 0.85), 6.0, true)
		"cane":
			var path := PackedVector2Array()
			for i in 12:
				path.append(Vector2(0, -i * 12.0))
			for i in 10:
				var a := PI + PI * i / 9.0
				path.append(Vector2(20, -132) + Vector2(cos(a), sin(a)) * 20.0)
			draw_polyline(path, Color.WHITE, 14.0, true)
			for i in range(0, path.size() - 1, 2):
				draw_line(path[i], path[i + 1], Color("ff4757"), 14.0, true)
		"snowman":
			for b in [[Vector2(0, -32), 34.0], [Vector2(0, -88), 26.0], [Vector2(0, -132), 19.0]]:
				draw_circle(b[0], b[1], Color.WHITE, true, -1.0, true)
				draw_arc(b[0], b[1], 0, TAU, 32, Color("c7d6ea"), 2.0, true)
			draw_circle(Vector2(-6, -136), 2.5, Color("2d3436"))
			draw_circle(Vector2(6, -136), 2.5, Color("2d3436"))
			draw_colored_polygon(PackedVector2Array([Vector2(0, -131), Vector2(18, -128), Vector2(0, -126)]), Color("ff9f43"))
			draw_rect(Rect2(-18, -112, 36, 8), Color("e74c3c"))
		"palm":
			var trunk := PackedVector2Array()
			for i in 8:
				trunk.append(Vector2(sin(i * 0.4) * 10.0 + sway * i * 8.0, -i * 22.0))
			draw_polyline(trunk, Color("a0703c"), 14.0, true)
			var tip := trunk[trunk.size() - 1]
			for i in 5:
				var a := -PI * 0.5 + (i - 2) * 0.6 + sway * 4.0
				var leaf := PackedVector2Array([tip, tip + Vector2.from_angle(a - 0.15) * 60.0, tip + Vector2.from_angle(a) * 95.0 + Vector2(0, 20), tip + Vector2.from_angle(a + 0.15) * 60.0])
				draw_colored_polygon(leaf, Color("3fbf5a"))
			draw_circle(tip + Vector2(-6, 8), 7.0, Color("6d4526"), true, -1.0, true)
			draw_circle(tip + Vector2(6, 10), 7.0, Color("6d4526"), true, -1.0, true)
		"umbrella":
			var c3: Color = extra.get("c", Color("ff5a5a"))
			draw_line(Vector2.ZERO, Vector2(0, -110), Color("dfe6e9"), 4.0, true)
			var top_pts := PackedVector2Array()
			for i in 13:
				var a := PI + PI * i / 12.0
				top_pts.append(Vector2(0, -110) + Vector2(cos(a) * 80.0, sin(a) * 40.0))
			draw_colored_polygon(top_pts, c3)
			for i in 3:
				draw_colored_polygon(PackedVector2Array([Vector2(0, -150), Vector2(-60 + i * 50, -110), Vector2(-40 + i * 50, -110)]), Color.WHITE)
		"rug":
			draw_colored_polygon(Art.rr(Rect2(-260, -4, 520, 10), 4.0), Color("8c6cff"))
			for i in 9:
				draw_rect(Rect2(-250 + i * 56, -3, 26, 8), Color("ffd43b"))
		"frame":
			var fc: Color = extra.get("c", Color("ffd43b"))
			draw_colored_polygon(Art.rr(Rect2(-90, -70, 180, 140), 8.0), Color("8b5a2b"))
			draw_rect(Rect2(-76, -56, 152, 112), Color("bfe8ff"))
			draw_colored_polygon(PackedVector2Array([Vector2(-76, 56), Vector2(-20, -10), Vector2(30, 56)]), Color("5cc94a"))
			draw_colored_polygon(PackedVector2Array([Vector2(0, 56), Vector2(40, 0), Vector2(76, 56)]), Color("4cb848"))
			draw_circle(Vector2(40, -30), 14.0, fc, true, -1.0, true)
		"glow_plant":
			var gc: Color = extra.get("c", Color("6cf2ff"))
			for i in 3:
				var a := -PI * 0.5 + (i - 1) * 0.45 + sway * 3.0
				var tip := Vector2.from_angle(a) * (50.0 + i * 8.0)
				draw_line(Vector2.ZERO, tip, Color("3d3a7a"), 3.0, true)
				var pulse := 1.2 + 0.4 * sin(_t * 2.0 + i)
				draw_circle(tip, 7.0, Color(gc.r * pulse * 1.6, gc.g * pulse * 1.6, gc.b * pulse * 1.6), true, -1.0, true)
		"crystal":
			for i in 3:
				var x := (i - 1) * 22.0
				var hgt := 70.0 + (1 - absi(i - 1)) * 40.0
				draw_colored_polygon(PackedVector2Array([Vector2(x - 12, 0), Vector2(x + 12, 0), Vector2(x + 6, -hgt), Vector2(x, -hgt - 16), Vector2(x - 6, -hgt)]), Color(0.75, 0.55, 1.6))
		"fern":
			for i in 7:
				var a := -PI * 0.5 + (i - 3) * 0.32 + sway * 2.0
				var tip := Vector2.from_angle(a) * (46.0 - absf(i - 3) * 6.0)
				draw_line(Vector2.ZERO, tip, Color("229954"), 4.0, true)
				for k in 4:
					var q := tip * (0.3 + k * 0.18)
					draw_line(q, q + Vector2.from_angle(a - 0.9) * 9.0, Color("2ecc71"), 2.0, true)
					draw_line(q, q + Vector2.from_angle(a + 0.9) * 9.0, Color("2ecc71"), 2.0, true)
		"cloud_fluff":
			for i in 7:
				var x := (i - 3) * 85.0
				draw_circle(Vector2(x, 70 + absf(x) * 0.12), 60.0 - absf(x) * 0.08, Color(1, 1, 1, 0.95), true, -1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

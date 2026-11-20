class_name LinkView
extends Node2D
## Draws ropes, springs, wires (with power pulses), glue blobs and hinge pins.
## On a network client the host sends the end points instead (remote_links).

var world: Node = null
var remote_links: Array = []   # [{k, a: Vector2, b: Vector2, on: bool}]


func _ready() -> void:
	z_index = 5


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var tm := Time.get_ticks_msec() / 1000.0
	if world.puppet:
		for l in remote_links:
			_draw_one(String(l.k), l.a, l.b, bool(l.get("on", false)), tm)
		return
	for l in world.links:
		if l.broken or not l.valid():
			continue
		_draw_one(l.kind, l.world_a(), l.world_b(), l.signal_on, tm)


func _draw_one(kind: String, a: Vector2, b: Vector2, on: bool, tm: float) -> void:
	match kind:
		"rope":
			var mid := (a + b) * 0.5 + Vector2(0, 6)
			var pts := PackedVector2Array()
			for i in 13:
				var k := i / 12.0
				pts.append(a.lerp(mid, k).lerp(mid.lerp(b, k), k))
			draw_polyline(pts, Color("8b5a2b"), 4.0, true)
			draw_polyline(pts, Color("c8914f"), 2.0, true)
		"spring":
			var d := b - a
			var n := d.normalized().orthogonal()
			var pts := PackedVector2Array([a])
			var coils := 12
			for i in range(1, coils):
				pts.append(a + d * (float(i) / coils) + n * (7.0 if i % 2 == 0 else -7.0))
			pts.append(b)
			draw_polyline(pts, Color("74b9ff"), 3.0, true)
			draw_circle(a, 3.5, Color("dfe6e9"), true, -1.0, true)
			draw_circle(b, 3.5, Color("dfe6e9"), true, -1.0, true)
		"wire":
			var mid := (a + b) * 0.5 + Vector2(0, 14)
			var pts := PackedVector2Array()
			for i in 13:
				var k := i / 12.0
				pts.append(a.lerp(mid, k).lerp(mid.lerp(b, k), k))
			var col := Color(0.4, 2.0, 0.9) if on else Color(0.25, 0.45, 0.35)
			draw_polyline(pts, Color(0, 0, 0, 0.35), 4.5, true)
			draw_polyline(pts, col, 2.5, true)
			if on:
				for j in 2:
					var k := fmod(tm * 1.6 + j * 0.5, 1.0)
					var idx := clampi(int(k * 12.0), 0, 11)
					draw_circle(pts[idx].lerp(pts[idx + 1], k * 12.0 - idx), 3.5, Color(2.2, 2.6, 1.6), true, -1.0, true)
		"glue":
			draw_circle(a, 6.0, Color(1.0, 0.86, 0.35, 0.95), true, -1.0, true)
			draw_circle(a + Vector2(-1.5, -1.5), 2.2, Color(1, 1, 1, 0.8), true, -1.0, true)
		"hinge":
			draw_circle(a, 6.5, Color("636e72"), true, -1.0, true)
			draw_circle(a, 3.5, Color("dfe6e9"), true, -1.0, true)

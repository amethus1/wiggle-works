class_name WaterView
extends Node2D
## Draws water, lava and acid: see-through body, wavy surface with foam,
## and sparkles (water) or glowing bubbles (lava and acid).

var world: Node = null

const LOOK := {
	"water": {"top": Color(0.3, 0.68, 0.98, 0.45), "deep": Color(0.1, 0.32, 0.72, 0.72), "edge": Color(0.88, 0.98, 1.0, 0.95), "speed": 2.2, "wave": 1.0},
	"lava": {"top": Color(1.6, 0.62, 0.1, 0.97), "deep": Color(0.75, 0.12, 0.02, 1.0), "edge": Color(2.4, 1.5, 0.4, 1.0), "speed": 0.8, "wave": 0.6},
	"acid": {"top": Color(0.55, 1.35, 0.2, 0.8), "deep": Color(0.12, 0.5, 0.08, 0.92), "edge": Color(0.9, 2.0, 0.5, 1.0), "speed": 1.4, "wave": 0.8},
}


func _ready() -> void:
	z_index = 8


func _process(_d: float) -> void:
	if world and not world.water_shapes.is_empty():
		queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var tm := Time.get_ticks_msec() / 1000.0
	for ws in world.water_shapes:
		var kind := String(ws.get("kind", "water"))
		var look: Dictionary = LOOK.get(kind, LOOK.water)
		var poly: PackedVector2Array = ws.poly
		var top: float = ws.top
		var bottom := top
		for v in poly:
			bottom = maxf(bottom, v.y)
		var cols := PackedColorArray()
		var c_top: Color = look.top
		var c_deep: Color = look.deep
		for v in poly:
			var k := clampf((v.y - top) / maxf(1.0, bottom - top), 0.0, 1.0)
			cols.append(c_top.lerp(c_deep, k))
		draw_polygon(poly, cols)
		if ws.x1 <= ws.x0:
			continue
		var sp: float = look.speed
		var wv: float = look.wave
		var line := PackedVector2Array()
		var x: float = ws.x0
		while x <= ws.x1:
			line.append(Vector2(x, top + (sin(x * 0.02 + tm * sp) * 4.0 + sin(x * 0.047 - tm * sp * 0.6) * 2.5) * wv))
			x += 10.0
		line.append(Vector2(ws.x1, top))
		draw_polyline(line, look.edge, 3.0 if kind == "water" else 4.0, true)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(ws.x0)
		var wdt: float = ws.x1 - ws.x0
		if kind == "water":
			for i in int(wdt / 60.0):
				var sx: float = ws.x0 + fposmod(rng.randf() * wdt + tm * 15.0, wdt)
				var sy := top + rng.randf_range(14.0, minf(bottom - top - 10.0, 160.0))
				if Geometry2D.is_point_in_polygon(Vector2(sx, sy), poly):
					var tw := 0.5 + 0.5 * sin(tm * 3.0 + i)
					draw_line(Vector2(sx - 6, sy), Vector2(sx + 6, sy), Color(1, 1, 1, 0.25 * tw), 2.0, true)
		else:
			# bubbles rise and pop at the surface
			var deep := minf(bottom - top - 6.0, 140.0)
			var edge: Color = look.edge
			for i in maxi(2, int(wdt / 45.0)):
				var period := rng.randf_range(1.4, 2.8)
				var ph := fposmod(tm / period + rng.randf(), 1.0)
				var sx: float = ws.x0 + rng.randf() * wdt
				var sy := top + deep * (1.0 - ph)
				var r := rng.randf_range(3.0, 8.0) * (0.6 + ph * 0.6)
				if Geometry2D.is_point_in_polygon(Vector2(sx, sy + 2.0), poly):
					draw_circle(Vector2(sx, sy), r, Color(edge.r, edge.g, edge.b, 0.55))
					draw_arc(Vector2(sx, sy), r, 0.0, TAU, 12, Color(edge.r, edge.g, edge.b, 0.9), 1.5, true)
			if kind == "lava":
				# dark crust drifting on top
				for i in int(wdt / 90.0):
					var cx: float = ws.x0 + fposmod(rng.randf() * wdt + tm * 6.0, wdt)
					var cw := rng.randf_range(16.0, 34.0)
					draw_line(Vector2(cx - cw * 0.5, top + 6.0), Vector2(cx + cw * 0.5, top + 7.0), Color(0.35, 0.08, 0.02, 0.8), 5.0, true)

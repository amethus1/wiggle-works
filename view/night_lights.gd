class_name NightLights
extends Node2D
## At night, things that glow light up what's around them: lava pools, fires
## on the ground and fighters on fire, the glowing Wigglies (Zappy, Blaze,
## Twinkle) and laser swords. (Lamps, saucers and fireworks have their own
## lights: see ToyLogic.update_light.) A small pool of lights is moved onto
## whatever glows nearest the middle of the screen; by day they're all off.

const MOST := 20               # lights at once (each one costs some drawing)
const LAVA_GAP := 260.0        # px between lights along a lava pool
const GLOW_WIGGLIES := {"zappy": Color(1.0, 0.95, 0.45), "blaze": Color(1.0, 0.55, 0.2), "twinkle": Color(0.85, 0.7, 1.0)}

var world: Node = null
var _lights: Array[PointLight2D] = []
var _lava: Array = []          # [where, how big] along the lava pools (worked out when the pools change)
var _lava_v := -1
var _frame := 0


func _process(_d: float) -> void:
	if world == null:
		return
	if not world.night:
		if not _lights.is_empty() and _lights[0].visible:
			for l in _lights:
				l.visible = false
		return
	_frame += 1
	if _frame % 2 == 1:
		return   # (every other frame is plenty)
	var view := _view()
	var want: Array = []   # [where, color, energy, size]
	var tm := Time.get_ticks_msec() / 1000.0
	if int(world.water_version) != _lava_v:
		_lava_v = int(world.water_version)
		_lava.clear()
		for ws in world.water_shapes:
			if String(ws.get("kind", "")) != "lava" or float(ws.x1) <= float(ws.x0):
				continue
			var n := maxi(1, int((float(ws.x1) - float(ws.x0)) / LAVA_GAP))
			for i in n:
				_lava.append(Vector2(lerpf(float(ws.x0), float(ws.x1), (i + 0.5) / n), float(ws.top) + 8.0))
	for p in _lava:
		want.append([p, Color(1.0, 0.5, 0.15), 1.5 + 0.15 * sin(tm * 2.0 + p.x), 2.6])
	for z in world.fires:
		var r := float(z.r)
		want.append([z.p + Vector2(0, -20), Color(1.0, 0.55, 0.2), 1.6 + 0.4 * sin(tm * 17.0 + r), clampf(r / 70.0, 1.2, 4.0)])
	for f in world.fighters():
		if f.burning > 0.0:
			want.append([f.center(), Color(1.0, 0.55, 0.2), 1.1 + 0.3 * sin(tm * 20.0 + f.uid), 1.1])
	for w in world.wigglies():
		if GLOW_WIGGLIES.has(w.kind):
			var e := 1.0 + (0.6 if w.electric > 0.0 or w.special_t > 0.0 else 0.0)
			want.append([w.com, GLOW_WIGGLIES[w.kind], e, 1.3 * float(w.size)])
	for t in world.toys():
		if t.id == "laser_sword":
			var lc: Color = t.shown_color()
			want.append([t.global_position, lc.lightened(0.3), 1.1, 0.9])
	# the ones nearest the middle of the screen (and on it) get the lights
	var mid := view.get_center()
	var on_screen := view.grow(300.0)
	want = want.filter(func(e): return on_screen.has_point(e[0]))
	if want.size() > MOST:
		want.sort_custom(func(a, b): return (a[0] as Vector2).distance_squared_to(mid) < (b[0] as Vector2).distance_squared_to(mid))
		want.resize(MOST)
	while _lights.size() < want.size():
		var l := PointLight2D.new()
		l.texture = Art.light_texture()
		l.blend_mode = Light2D.BLEND_MODE_ADD
		add_child(l)
		_lights.append(l)
	for i in _lights.size():
		var l := _lights[i]
		if i < want.size():
			var e: Array = want[i]
			l.visible = true
			l.position = e[0]
			l.color = e[1]
			l.energy = e[2]
			l.texture_scale = e[3]
		else:
			l.visible = false


## What the camera shows, in world space.
func _view() -> Rect2:
	var vp := get_viewport()
	if vp == null:
		return Rect2(-2000, -2000, 4000, 4000)
	var xf := vp.get_canvas_transform().affine_inverse()
	var size := vp.get_visible_rect().size
	return Rect2(xf * Vector2.ZERO, Vector2.ZERO).expand(xf * size)

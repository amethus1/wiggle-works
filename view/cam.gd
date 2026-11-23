class_name Cam
extends Camera2D
## The game camera: zoom around the cursor, smooth panning, follows the
## Wiggly you're playing as, and shakes when big things happen.

var effects: Effects = null
var target_zoom := 1.0
var follow: Node = null   # a Wiggly or Fighter to follow
var _base := Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = false
	_base = position


func fit(r: Rect2, vp: Vector2) -> void:
	_base = r.get_center()
	var z := minf(vp.x / r.size.x, vp.y / r.size.y)
	target_zoom = clampf(z, 0.3, 2.0)
	zoom = Vector2(target_zoom, target_zoom)
	position = _base


func pan(by_screen: Vector2) -> void:
	_base -= by_screen / zoom.x
	follow = null


func move_world(by_world: Vector2) -> void:
	_base += by_world
	follow = null


func zoom_at(screen_p: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_p)
	target_zoom = clampf(target_zoom * factor, 0.22, 3.0)
	zoom = Vector2(target_zoom, target_zoom)
	var after := screen_to_world(screen_p)
	_base += before - after


func screen_to_world(p: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	return _base + (p - vp * 0.5) / zoom.x


func view_rect() -> Rect2:
	var vp := get_viewport_rect().size / zoom.x
	return Rect2(_base - vp * 0.5, vp)


func center() -> Vector2:
	return _base


func _process(dt: float) -> void:
	if follow != null and is_instance_valid(follow):
		var fp: Vector2 = follow.center() if follow is Fighter else follow.com
		_base = _base.lerp(fp + Vector2(0, -60), minf(1.0, dt * 5.0))
	var off := Vector2.ZERO
	if effects and effects.shake > 0.05:
		var t := Time.get_ticks_msec() / 1000.0
		off = Vector2(sin(t * 53.0), cos(t * 72.6)) * effects.shake * Settings.shake_2d      # (📳 ⚙️ Settings)
	if effects:
		off += effects.kick * Settings.shake_2d   # a jolt toward a blast or along a big blow
	position = _base + off
	Sfx.listener_pos = _base
	Sfx.listener_zoom = zoom.x

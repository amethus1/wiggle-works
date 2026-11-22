class_name FighterArt
## Draws people (chunky stick figures in team colors, with helmets, armor and
## shields) and beasts (animals and dinosaurs), standing or as ragdolls.

const INK := Color("1e1b2e")
const ICE := Color(0.72, 0.92, 1.0)

## For drawing a fighter somewhere other than itself (toy-box pictures and the
## placing ghost): where to draw, and an extra transform on top.
static var canvas: CanvasItem = null
static var outer := Transform2D.IDENTITY


static func _tf(ci: CanvasItem, p: Vector2, rot: float, sc: Vector2) -> void:
	ci.draw_set_transform_matrix(outer * Transform2D(rot, sc, 0.0, p))


static func draw(f) -> void:
	if f.beast:
		_beast(f)
	else:
		_person(f)
	_status(f)


# ------------------------------------------------------------------ people
static func _person(f) -> void:
	var ci: CanvasItem = canvas if canvas != null else f
	var s: float = f.size
	var shirt: Color = f.team_color()
	var pants: Color = shirt.darkened(0.55)
	var skin: Color = f.def.get("skin", Color("f6d7b0"))
	if f.state == "dead":
		shirt = shirt.lerp(Color(0.55, 0.55, 0.6), 0.45)
		skin = skin.lerp(Color(0.7, 0.7, 0.72), 0.35)
	if f.flash > 0.0:
		shirt = shirt.lerp(Color.WHITE, f.flash * 0.6)
		skin = skin.lerp(Color.WHITE, f.flash * 0.6)
	if f.shows("ice"):
		shirt = shirt.lerp(ICE, 0.45)
		skin = skin.lerp(ICE, 0.5)
	elif f.shows("zap") and int(f.t * 20.0) % 2 == 0:
		shirt = shirt.lerp(Color(1.0, 0.95, 0.5), 0.5)   # flickers yellow
		skin = skin.lerp(Color(1.0, 0.95, 0.5), 0.5)
	var limb := 7.0 * s
	var standing: bool = (f.puppet and String(f.net.get("st", "stand")) == "stand") or (not f.puppet and f.state == "stand")
	if standing:
		var c: Vector2 = f.center()
		var o: Dictionary = f.pose()
		var P := func(k: String) -> Vector2: return c + f.flipped(o[k])
		# shadow
		ci.draw_colored_polygon(Art.ellipse(c + Vector2(0, 46.0 * s), 16.0 * s, 3.5 * s, 16), Color(0, 0, 0, 0.18))
		# back limbs
		_line(ci, [P.call("hip"), P.call("knee_b"), P.call("foot_b")], pants.darkened(0.25), limb)
		_line(ci, [P.call("shoulder"), P.call("elbow_b"), P.call("hand_b")], shirt.darkened(0.3), limb * 0.85)
		# torso
		_line(ci, [P.call("shoulder"), P.call("hip")], shirt, 14.0 * s)
		if f.body_armor:
			_line(ci, [P.call("shoulder") + Vector2(0, 3 * s), P.call("hip") - Vector2(0, 5 * s)], Color("95a5a6"), 15.0 * s)
			ci.draw_line(P.call("shoulder") + Vector2(-4 * s * f.facing, 6 * s), P.call("hip") + Vector2(-4 * s * f.facing, -8 * s), Color(1, 1, 1, 0.3), 2.0, true)
		# front leg
		_line(ci, [P.call("hip"), P.call("knee_f"), P.call("foot_f")], pants, limb)
		ci.draw_circle(P.call("foot_f") + Vector2(2 * s * f.facing, 0), 4.0 * s, INK, true, -1.0, true)
		ci.draw_circle(P.call("foot_b") + Vector2(2 * s * f.facing, 0), 4.0 * s, INK.lightened(0.15), true, -1.0, true)
		# head
		_head(f, ci, P.call("head"), 0.0, s, skin)
		# front arm (in front of the body) and shield
		_line(ci, [P.call("shoulder"), P.call("elbow_f"), P.call("hand_f")], shirt.lightened(0.05), limb * 0.85)
		ci.draw_circle(P.call("hand_f"), 3.6 * s, skin, true, -1.0, true)
		if f.shield:
			var sp: Vector2 = P.call("shoulder") + Vector2(f.facing * 13.0 * s, 14.0 * s)
			_shield(ci, sp, s, f.team_color(), 0.0)
	else:
		var parts := _rag_parts(f)
		if parts.is_empty():
			return
		for k in ["thigh_b", "shin_b"]:
			_limb(ci, parts, k, pants.darkened(0.25), limb)
		for k in ["uarm_b", "larm_b"]:
			_limb(ci, parts, k, shirt.darkened(0.3), limb * 0.85)
		_limb(ci, parts, "torso", shirt, 14.0 * s, 1.0)
		if f.body_armor:
			_limb(ci, parts, "torso", Color("95a5a6"), 15.0 * s, 0.7)
		for k in ["thigh_f", "shin_f"]:
			_limb(ci, parts, k, pants, limb)
		if parts.has("head"):
			_head(f, ci, parts.head[0], parts.head[1], s, skin)
		for k in ["uarm_f", "larm_f"]:
			_limb(ci, parts, k, shirt.lightened(0.05), limb * 0.85)
		if f.shield and parts.has("larm_f"):
			_shield(ci, parts.larm_f[0], s, f.team_color(), parts.larm_f[1])


static func _line(ci: CanvasItem, pts: Array, col: Color, w: float) -> void:
	var p := PackedVector2Array(pts)
	ci.draw_polyline(p, col.darkened(0.45), w + 3.0, true)
	ci.draw_polyline(p, col, w, true)
	for q in p:
		ci.draw_circle(q, w * 0.5, col, true, -1.0, true)


## Ragdoll part transforms: name -> [position, rotation, half length].
static func _rag_parts(f) -> Dictionary:
	var out := {}
	if f.puppet:
		for k in f.net.get("parts", {}):
			var e: Array = f.net.parts[k]
			out[k] = [e[0], e[1], e[2]]
		return out
	for k in f.parts:
		var p = f.parts[k]
		if is_instance_valid(p):
			out[k] = [p.global_position, p.rotation, p.half.y]
	return out


static func _limb(ci: CanvasItem, parts: Dictionary, k: String, col: Color, w: float, shrink := 1.0) -> void:
	if not parts.has(k):
		return
	var e: Array = parts[k]
	var up := Vector2(0, -1).rotated(float(e[1])) * float(e[2]) * shrink
	_line(ci, [e[0] + up, e[0] - up], col, w)


static func _head(f, ci: CanvasItem, c: Vector2, rot: float, s: float, skin: Color) -> void:
	var r := 11.0 * s
	var fc: float = f.facing
	_tf(ci, c, rot, Vector2(fc, 1.0))
	ci.draw_circle(Vector2.ZERO, r + 1.5, INK, true, -1.0, true)
	ci.draw_circle(Vector2.ZERO, r, skin, true, -1.0, true)
	var helm := String(f.helmet)
	if helm == "" and f.type == "stick":
		ci.draw_arc(Vector2(-1, -2), r * 0.95, PI * 1.05, PI * 1.95, 12, f.hair, 4.0 * s, true)
	if f.def.has("beard"):
		var b: Color = f.def.beard
		ci.draw_colored_polygon(PackedVector2Array([Vector2(-r * 0.2, r * 0.25), Vector2(r * 0.95, r * 0.2), Vector2(r * 0.4, r * 1.25)]), b)
	# face
	var mood: String = f.face()
	var eye := Vector2(r * 0.42, -r * 0.12)
	if mood == "ko":
		for e in [eye, eye + Vector2(-r * 0.42, 0)]:
			ci.draw_line(e + Vector2(-2.5, -2.5) * s, e + Vector2(2.5, 2.5) * s, INK, 2.0, true)
			ci.draw_line(e + Vector2(-2.5, 2.5) * s, e + Vector2(2.5, -2.5) * s, INK, 2.0, true)
		ci.draw_line(Vector2(r * 0.05, r * 0.45), Vector2(r * 0.6, r * 0.45), INK, 2.0, true)
	else:
		ci.draw_circle(eye, 2.2 * s, INK, true, -1.0, true)
		ci.draw_circle(eye + Vector2(-r * 0.42, 0), 2.0 * s, INK, true, -1.0, true)
		match mood:
			"angry":
				ci.draw_line(eye + Vector2(-r * 0.62, -r * 0.32), eye + Vector2(r * 0.12, -r * 0.14), INK, 2.2, true)
				ci.draw_line(Vector2(r * 0.1, r * 0.42), Vector2(r * 0.65, r * 0.38), INK, 2.0, true)
			"scared":
				ci.draw_circle(Vector2(r * 0.38, r * 0.45), 3.0 * s, INK, true, -1.0, true)
			"frozen":
				# brrr: a wobbly frozen mouth
				ci.draw_polyline(PackedVector2Array([Vector2(r * 0.05, r * 0.45), Vector2(r * 0.2, r * 0.38), Vector2(r * 0.35, r * 0.45), Vector2(r * 0.5, r * 0.38), Vector2(r * 0.65, r * 0.45)]), INK, 1.6, true)
			"zapped":
				# hair-raising zigzag grin
				ci.draw_polyline(PackedVector2Array([Vector2(r * 0.0, r * 0.4), Vector2(r * 0.15, r * 0.55), Vector2(r * 0.3, r * 0.4), Vector2(r * 0.45, r * 0.55), Vector2(r * 0.6, r * 0.4)]), INK, 1.8, true)
				ci.draw_arc(eye, 3.6 * s, 0, TAU, 10, INK, 1.2, true)
			_:
				ci.draw_arc(Vector2(r * 0.35, r * 0.18), r * 0.32, 0.4, PI - 0.6, 8, INK, 2.0, true)
	# helmets
	match helm:
		"army":
			ci.draw_colored_polygon(_dome(r * 1.12, 0.0), Color("556b2f"))
			ci.draw_line(Vector2(-r * 1.15, -r * 0.05), Vector2(r * 1.25, -r * 0.05), Color("3e4f22"), 3.0 * s, true)
		"knight":
			ci.draw_circle(Vector2.ZERO, r * 1.08, Color("bdc3c7"), true, -1.0, true)
			ci.draw_rect(Rect2(Vector2(0, -r * 0.25), Vector2(r * 1.05, r * 0.2)), INK)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-r * 0.2, -r * 1.05), Vector2(r * 0.2, -r * 1.05), Vector2(-r * 0.6, -r * 1.7)]), f.team_color())
			ci.draw_arc(Vector2.ZERO, r * 1.08, 0, TAU, 20, Color("7f8c8d"), 2.0, true)
		"viking":
			ci.draw_colored_polygon(_dome(r * 1.1, 0.0), Color("95a5a6"))
			for sx in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([Vector2(sx * r * 0.8, -r * 0.4), Vector2(sx * r * 1.0, -r * 0.6), Vector2(sx * r * 1.4, -r * 1.5)]), Color("f5f5dc"))
		"hood":
			ci.draw_colored_polygon(_dome(r * 1.15, 0.25), Color("2e7d32"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-r * 1.1, -r * 0.3), Vector2(-r * 1.9, r * 0.1), Vector2(-r * 1.0, r * 0.4)]), Color("2e7d32"))
		"beret":
			ci.draw_colored_polygon(Art.ellipse(Vector2(-r * 0.1, -r * 0.8), r * 1.0, r * 0.4, 16, -0.15), f.team_color().darkened(0.2))
		"medic":
			ci.draw_colored_polygon(_dome(r * 1.08, 0.0), Color.WHITE)
			ci.draw_rect(Rect2(Vector2(-r * 0.12, -r * 0.95), Vector2(r * 0.24, r * 0.6)), Color("e74c3c"))
			ci.draw_rect(Rect2(Vector2(-r * 0.3, -r * 0.77), Vector2(r * 0.6, r * 0.24)), Color("e74c3c"))
		"ninja":
			ci.draw_circle(Vector2.ZERO, r * 1.02, Color("2d3436"), true, -1.0, true)
			ci.draw_rect(Rect2(Vector2(-r * 0.1, -r * 0.32), Vector2(r * 1.05, r * 0.38)), skin)
			ci.draw_circle(eye, 2.2 * s, INK, true, -1.0, true)
			ci.draw_line(Vector2(-r * 1.0, -r * 0.55), Vector2(r * 1.0, -r * 0.55), f.team_color(), 3.0 * s, true)
			ci.draw_line(Vector2(-r * 1.0, -r * 0.55), Vector2(-r * 1.8, -r * 0.2), f.team_color(), 3.0 * s, true)
	_tf(ci, Vector2.ZERO, 0.0, Vector2.ONE)


static func _dome(r: float, low: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		p.append(Vector2(cos(a) * r, sin(a) * r * 0.95 + r * low))
	return p


static func _shield(ci: CanvasItem, c: Vector2, s: float, col: Color, rot: float) -> void:
	_tf(ci, c, rot, Vector2.ONE)
	var p := Art.rr(Rect2(Vector2(-6, -24) * s, Vector2(12, 46) * s), 6.0 * s)
	ci.draw_colored_polygon(p, col.darkened(0.15))
	ci.draw_polyline(Art.closed(p), Color("7f8c8d"), 2.5, true)
	ci.draw_circle(Vector2.ZERO, 4.0 * s, Color("f1c40f"), true, -1.0, true)
	_tf(ci, Vector2.ZERO, 0.0, Vector2.ONE)


# ----------------------------------------------------------------- beasts
static func _beast(f) -> void:
	var ci: CanvasItem = canvas if canvas != null else f
	var d: Dictionary = f.def
	var s: float = f.size
	var col: Color = d.get("color", Color("8e6e53"))
	if f.paint.a > 0.0:
		col = f.paint
	if f.state == "dead":
		col = col.lerp(Color(0.6, 0.6, 0.62), 0.45)
	if f.flash > 0.0:
		col = col.lerp(Color.WHITE, f.flash * 0.55)
	if f.shows("ice"):
		col = col.lerp(ICE, 0.45)
	elif f.shows("zap") and int(f.t * 20.0) % 2 == 0:
		col = col.lerp(Color(1.0, 0.95, 0.5), 0.45)
	var standing: bool = (f.puppet and String(f.net.get("st", "stand")) == "stand") or (not f.puppet and f.state == "stand")
	var b: Vector2 = d.body * s
	var legs: float = float(d.legs) * s
	var fc: float = f.facing
	if standing:
		var c: Vector2 = f.center()
		var bc := c + Vector2(0, -legs * 0.5)
		ci.draw_colored_polygon(Art.ellipse(c + Vector2(0, (b.y + legs) * 0.5), b.x * 0.45, 4.0 * s + b.y * 0.04, 18), Color(0, 0, 0, 0.18))
		_tf(ci, bc, 0.0, Vector2(fc, 1.0))
		_beast_body(f, ci, d, b, legs, col, true)
		_tf(ci, Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var parts := _rag_parts(f)
		if parts.has("tail"):
			var tp: Array = parts.tail
			_tf(ci, tp[0], tp[1], Vector2(fc, 1.0))
			_tail(ci, d, float(d.tail) * s, b, col, true)
			_tf(ci, Vector2.ZERO, 0.0, Vector2.ONE)
		if parts.has("torso"):
			var tor: Array = parts.torso
			_tf(ci, tor[0], tor[1], Vector2(fc, 1.0))
			# a long tail is its own ragdoll piece (drawn above), so don't draw a second one
			_beast_body(f, ci, d, b, legs, col, false, not parts.has("tail"))
			_tf(ci, Vector2.ZERO, 0.0, Vector2.ONE)
		if parts.has("head"):
			var hp: Array = parts.head
			if parts.has("torso"):
				ci.draw_line(parts.torso[0], hp[0], col.darkened(0.15), maxf(6.0, float(d.head) * s * 0.5), true)
			_tf(ci, hp[0], hp[1], Vector2(fc, 1.0))
			_beast_head(f, ci, d, float(d.head) * s, col, 0.0)
			_tf(ci, Vector2.ZERO, 0.0, Vector2.ONE)


## Body, legs, neck, head and tail around the body centre (facing right).
static func _beast_body(f, ci: CanvasItem, d: Dictionary, b: Vector2, legs: float, col: Color, standing: bool, with_tail := true) -> void:
	var s: float = f.size
	var moving := clampf(absf(f.move), 0.0, 1.0) if standing else 0.0
	var dark := col.darkened(0.3)
	var lw := maxf(4.0, b.y * 0.22)
	var biped: bool = d.get("biped", false)
	var leg_x: Array = [-b.x * 0.05, b.x * 0.05] if biped else [-b.x * 0.32, b.x * 0.3, -b.x * 0.26, b.x * 0.36]
	var attach_y := b.y * 0.3
	# far legs first
	for i in leg_x.size():
		var far := i % 2 == 1 if biped else i >= 2
		var ph: float = f.walk + float(i) * (PI if biped else PI * 0.5)
		var sw := sin(ph) * 0.5 * moving
		var hip := Vector2(leg_x[i], attach_y)
		var foot := hip + Vector2(sin(sw) * legs * 0.6, legs * 1.05 - maxf(0.0, cos(ph)) * legs * 0.18 * moving)
		if not standing:
			foot = hip + Vector2(sin(0.4 * (1 if i % 2 == 0 else -1)) * legs * 0.5, legs * 0.9)
		var knee := (hip + foot) * 0.5 + Vector2((-1.0 if biped else 1.0) * legs * 0.12, 0)
		var lc := dark.darkened(0.15) if far else dark
		_line(ci, [hip, knee, foot], lc, lw)
	if d.get("wings", false):
		var flap := sin(f.t * 10.0) * 0.6
		for sgn in [1.0, -1.0]:
			var tip := Vector2(-b.x * 0.2, -b.y * 0.2) + Vector2(cos(-PI * 0.5 + flap * sgn), sin(-PI * 0.5 + flap * sgn)) * b.x * 1.4
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-b.x * 0.3, 0), Vector2(b.x * 0.3, -b.y * 0.1), tip]), col.darkened(0.15 if sgn > 0 else 0.3))
	if with_tail:
		_tail(ci, d, float(d.tail) * s, b, col, false, f.t, moving)
	# body
	var bp := Art.ellipse(Vector2.ZERO, b.x * 0.5, b.y * 0.5, 28)
	ci.draw_colored_polygon(bp, col)
	ci.draw_colored_polygon(Art.ellipse(Vector2(-b.x * 0.05, b.y * 0.18), b.x * 0.4, b.y * 0.22, 20), col.lightened(0.12))
	ci.draw_polyline(Art.closed(bp), col.darkened(0.45), 2.0, true)
	if d.get("plates", false):
		for i in 6:
			var x := lerpf(-b.x * 0.35, b.x * 0.3, i / 5.0)
			var y := -b.y * 0.45 + absf(x) * 0.05
			var hgt := b.y * (0.35 + 0.2 * sin(i / 5.0 * PI))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x - 9 * s, y + 4), Vector2(x, y - hgt), Vector2(x + 9 * s, y + 4)]), Color("e67e22"))
	if f.team != "wild":
		ci.draw_line(Vector2(b.x * 0.25, -b.y * 0.42), Vector2(b.x * 0.25, b.y * 0.42), f.team_color(), maxf(4.0, b.x * 0.06), true)
	# neck and head
	var neck_len := float(d.neck) * s
	var hr := float(d.head) * s
	var long_neck: bool = d.get("long_neck", false)
	var sh := Vector2(b.x * 0.4, -b.y * 0.2)
	var bob := sin(f.walk * 2.0) * 2.0 * s * moving
	var hpos := sh + Vector2(neck_len * (0.35 if long_neck else 0.7) + hr * 0.5, -neck_len * (0.95 if long_neck else 0.6) + bob)
	if not standing:
		return
	if neck_len > 2.0:
		_line(ci, [sh, (sh + hpos) * 0.5 + Vector2(0, -neck_len * 0.08), hpos], col, maxf(5.0, hr * (0.55 if long_neck else 0.8)))
	if d.get("tiny_arms", false):
		_line(ci, [Vector2(b.x * 0.42, b.y * 0.05), Vector2(b.x * 0.52, b.y * 0.18), Vector2(b.x * 0.58, b.y * 0.12)], dark, 4.0 * s)
	var bite := 0.0
	if f.swing > 0.0:
		bite = sin((1.0 - f.swing / maxf(0.01, f._swing_time())) * PI) * 0.7
	_beast_head_at(f, ci, d, hpos, hr, col, bite)


static func _beast_head_at(f, ci: CanvasItem, d: Dictionary, at: Vector2, hr: float, col: Color, bite: float) -> void:
	# draws relative to the current (body) transform
	_beast_head_shape(f, ci, d, at, hr, col, bite)


static func _beast_head(f, ci: CanvasItem, d: Dictionary, hr: float, col: Color, bite: float) -> void:
	_beast_head_shape(f, ci, d, Vector2.ZERO, hr, col, bite)


static func _beast_head_shape(f, ci: CanvasItem, d: Dictionary, at: Vector2, hr: float, col: Color, bite: float) -> void:
	var s: float = f.size
	var mood: String = f.face()
	var dark := col.darkened(0.3)
	if d.get("frill", false):
		ci.draw_colored_polygon(Art.ellipse(at + Vector2(-hr * 0.5, -hr * 0.2), hr * 0.75, hr * 1.0, 20), col.darkened(0.12))
		for i in 5:
			var a := -PI * 0.9 + i * 0.32
			ci.draw_circle(at + Vector2(-hr * 0.5, -hr * 0.2) + Vector2.from_angle(a) * hr * 0.9, hr * 0.12, Color("f5f5dc"), true, -1.0, true)
	if d.get("trunk", false):
		_line(ci, [at + Vector2(hr * 0.6, hr * 0.1), at + Vector2(hr * 0.95, hr * 0.7), at + Vector2(hr * 0.85, hr * 1.3)], col, hr * 0.28)
	# jaw (opens when biting)
	var jaw := PackedVector2Array([at + Vector2(-hr * 0.2, hr * 0.15), at + Vector2(hr * 1.2, hr * 0.15).rotated(0.0), at + Vector2(-hr * 0.1, hr * 0.5)])
	if bite > 0.01:
		var pivot := at + Vector2(-hr * 0.2, hr * 0.15)
		for i in jaw.size():
			jaw[i] = pivot + (jaw[i] - pivot).rotated(bite)
	ci.draw_colored_polygon(jaw, dark)
	var head := Art.ellipse(at + Vector2(hr * 0.3, -hr * 0.1), hr * 0.95, hr * 0.62, 22)
	ci.draw_colored_polygon(head, col)
	ci.draw_polyline(Art.closed(head), col.darkened(0.45), 2.0, true)
	if bite > 0.15 and String(d.get("attack", "")) == "bite":
		for i in 4:
			var x := lerpf(hr * 0.1, hr * 1.1, i / 3.0)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(x - 3 * s, hr * 0.3), at + Vector2(x + 3 * s, hr * 0.3), at + Vector2(x, hr * 0.45)]), Color.WHITE)
	# eye
	var eye := at + Vector2(hr * 0.35, -hr * 0.3)
	if mood == "ko":
		ci.draw_line(eye + Vector2(-3, -3) * s, eye + Vector2(3, 3) * s, INK, 2.0, true)
		ci.draw_line(eye + Vector2(-3, 3) * s, eye + Vector2(3, -3) * s, INK, 2.0, true)
	else:
		ci.draw_circle(eye, maxf(2.5, hr * 0.16), Color.WHITE, true, -1.0, true)
		ci.draw_circle(eye + Vector2(hr * 0.04, 0), maxf(1.6, hr * 0.09), INK, true, -1.0, true)
		if mood == "angry":
			ci.draw_line(eye + Vector2(-hr * 0.2, -hr * 0.22), eye + Vector2(hr * 0.2, -hr * 0.1), INK, 2.0, true)
		elif mood == "zapped" or mood == "scared" or mood == "frozen":
			ci.draw_arc(eye, maxf(3.5, hr * 0.22), 0, TAU, 12, INK, 1.4, true)
	# extras
	if d.get("horns", false):
		for sx in [0.0, 0.3]:
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(hr * sx - 3, -hr * 0.6), at + Vector2(hr * sx + 3, -hr * 0.6), at + Vector2(hr * (sx + 0.4), -hr * 1.3)]), Color("f5f5dc"))
	if d.get("frill", false):
		ci.draw_colored_polygon(PackedVector2Array([at + Vector2(hr * 0.9, -hr * 0.2), at + Vector2(hr * 1.05, -hr * 0.05), at + Vector2(hr * 1.5, -hr * 0.35)]), Color("f5f5dc"))
		for sx in [0.1, 0.45]:
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(hr * sx - 3, -hr * 0.6), at + Vector2(hr * sx + 3, -hr * 0.6), at + Vector2(hr * (sx + 0.7), -hr * 1.35)]), Color("f5f5dc"))
	if d.get("comb", false):
		for i in 3:
			ci.draw_circle(at + Vector2(hr * (0.1 + i * 0.25), -hr * 0.75), hr * 0.22, Color("e74c3c"), true, -1.0, true)
		ci.draw_colored_polygon(PackedVector2Array([at + Vector2(hr * 1.1, -hr * 0.2), at + Vector2(hr * 1.7, 0), at + Vector2(hr * 1.1, hr * 0.15)]), Color("f1c40f"))
	match String(d.get("ears", "")):
		"flop":
			ci.draw_colored_polygon(Art.ellipse(at + Vector2(-hr * 0.2, -hr * 0.3), hr * 0.25, hr * 0.5, 12, 0.3), dark)
		"point":
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-hr * 0.3, -hr * 0.5), at + Vector2(hr * 0.1, -hr * 0.55), at + Vector2(-hr * 0.15, -hr * 1.1)]), dark)
		"round":
			ci.draw_circle(at + Vector2(-hr * 0.2, -hr * 0.7), hr * 0.25, dark, true, -1.0, true)
	if d.get("trunk", false):
		ci.draw_colored_polygon(Art.ellipse(at + Vector2(-hr * 0.4, 0), hr * 0.55, hr * 0.75, 18), dark)


static func _tail(ci: CanvasItem, d: Dictionary, tl: float, b: Vector2, col: Color, as_part: bool, tm := 0.0, moving := 0.0) -> void:
	if tl < 2.0:
		return
	var base := Vector2(-b.x * 0.45, -b.y * 0.05) if not as_part else Vector2(tl * 0.45, 0)
	var sway := sin(tm * 6.0) * 0.12 * (0.3 + moving)
	var dir := Vector2(-1, -0.12).normalized().rotated(sway)
	var tip := base + dir * tl
	var nrm := dir.orthogonal() * maxf(3.0, b.y * 0.22)
	ci.draw_colored_polygon(PackedVector2Array([base + nrm, tip, base - nrm]), col.darkened(0.08))
	if d.get("plates", false):
		for k in [0.75, 0.9]:
			var sp := base.lerp(tip, k)
			ci.draw_line(sp, sp + Vector2(-4, -14), Color("f5f5dc"), 3.0, true)


# ------------------------------------------------------------------ status
static func _status(f) -> void:
	var ci: CanvasItem = canvas if canvas != null else f
	var c: Vector2 = f.center()
	var top := c + Vector2(0, -f.half_size().y - 14.0)
	var st: String = f.net.get("st", "stand") if f.puppet else f.state
	var hp_ratio: float = float(f.net.get("hp", 1.0)) if f.puppet else f.hp / maxf(1.0, f.max_hp)
	var tm: float = f.t
	if canvas == null:
		_overlays(f, ci, c, st, tm)
	if st == "dead":
		for i in 3:
			var a := tm * 3.0 + TAU * i / 3.0
			Art._star(ci, top + Vector2(cos(a) * 14.0, sin(a) * 4.0), 5.0, Color(2.0, 1.8, 0.6))
		return
	if hp_ratio < 0.999:
		var w := 34.0
		ci.draw_rect(Rect2(top + Vector2(-w * 0.5, 0), Vector2(w, 5)), Color(0, 0, 0, 0.5))
		var hc := Color("5ad66a") if hp_ratio > 0.5 else (Color("ffd43b") if hp_ratio > 0.25 else Color("ff6b6b"))
		ci.draw_rect(Rect2(top + Vector2(-w * 0.5, 0), Vector2(w * hp_ratio, 5)), hc)
	if f.team != "wild" and not f.beast:
		ci.draw_circle(top + Vector2(0, -8), 4.0, f.team_color(), true, -1.0, true)
	if f.burning > 0.0:
		for i in 3:
			var fp: Vector2 = c + Vector2(randf_range(-10, 10), randf_range(-20, 20)) * f.size
			ci.draw_colored_polygon(PackedVector2Array([fp + Vector2(-5, 4), fp + Vector2(0, -12), fp + Vector2(5, 4)]), Color(2.2, 1.0, 0.25))
	if f.player_id >= 0:
		Art._star(ci, top + Vector2(0, -22), 6.0, Color(2.0, 1.8, 0.5))


## What toys and Wiggly powers are doing to a fighter: an ice block, a bubble,
## sparks, gooey feet, drips. Drawn from the mood flags, so a friend's copy
## over Wi-Fi shows them too.
static func _overlays(f, ci: CanvasItem, c: Vector2, st: String, tm: float) -> void:
	var hs: Vector2 = f.half_size()
	var s: float = f.size
	if st != "stand":
		var r: float = f.radius() * 0.8
		hs = Vector2(r, r)
	if f.shows("goo"):
		# green gummy blobs stuck round the feet
		var feet := c + Vector2(0, hs.y - 4.0 * s)
		for i in 5:
			var x := (float(i) / 4.0 - 0.5) * maxf(hs.x * 1.6, 24.0 * s)
			var blob := 4.5 * s + 2.0 * s * sin(tm * 3.0 + i)
			ci.draw_circle(feet + Vector2(x, 0), blob, Color(0.35, 0.84, 0.42, 0.85), true, -1.0, true)
		ci.draw_line(feet + Vector2(-hs.x * 0.6, 4.0 * s), feet + Vector2(-hs.x * 0.6, 4.0 * s + 6.0 * s + 3.0 * s * sin(tm * 2.0)), Color(0.35, 0.84, 0.42, 0.85), 3.0 * s, true)
	if f.shows("wet") and not f.shows("ice"):
		for i in 3:
			var ph := fposmod(tm * 1.3 + i * 0.37, 1.0)
			var dp := c + Vector2((float(i) - 1.0) * hs.x * 0.7, -hs.y * 0.4 + ph * hs.y * 1.3)
			var dc := Color(0.45, 0.75, 1.0, 0.8 * (1.0 - ph))
			ci.draw_circle(dp, 2.6 * s, dc, true, -1.0, true)
			ci.draw_colored_polygon(PackedVector2Array([dp + Vector2(-2.4, 0) * s, dp + Vector2(0, -5.5) * s, dp + Vector2(2.4, 0) * s]), dc)
	if f.shows("zap"):
		for i in 6:
			var a := randf() * TAU
			var p0 := c + Vector2(cos(a) * hs.x * 1.3, sin(a) * hs.y * 0.9)
			var p1 := p0 + Vector2(randf_range(-14, 14), randf_range(-14, 14)) * s
			var p2 := p1 + Vector2(randf_range(-10, 10), randf_range(-10, 10)) * s
			ci.draw_polyline(PackedVector2Array([p0, p1, p2]), Color(1.6, 1.9, 2.4), 2.0, true)
	if f.shows("ice"):
		# a see-through ice block with shiny edges, big enough for heads and tails
		var box := _ice_box(f, c, hs, st)
		var poly := Art.rr(box, 10.0 * s)
		ci.draw_colored_polygon(poly, Color(0.7, 0.93, 1.0, 0.42))
		ci.draw_polyline(Art.closed(poly), Color(0.88, 0.98, 1.0, 0.95), 2.5, true)
		ci.draw_line(box.position + Vector2(8, 10) * s, box.position + Vector2(box.size.x * 0.45, 6.0 * s), Color(1, 1, 1, 0.85), 3.0, true)
		ci.draw_line(box.position + Vector2(8, 22) * s, box.position + Vector2(8.0 * s, box.size.y * 0.35), Color(1, 1, 1, 0.6), 2.0, true)
		ci.draw_line(box.end - Vector2(10, 14) * s, box.end - Vector2(box.size.x * 0.35, 9.0 * s), Color(1, 1, 1, 0.5), 2.0, true)
	if f.shows("bubble"):
		var br: float = maxf(hs.x, hs.y) * 1.25 + 8.0
		ci.draw_circle(c, br, Color(0.7, 0.93, 1.0, 0.22), true, -1.0, true)
		ci.draw_arc(c, br, 0, TAU, 48, Color(0.35, 0.7, 0.95, 0.55), 4.0, true)
		ci.draw_arc(c, br - 2.0, 0, TAU, 48, Color(0.9, 1.0, 1.0, 0.9), 2.0, true)
		ci.draw_arc(c, br * 0.8, -2.4, -1.4, 12, Color(1, 1, 1, 0.95), 4.0, true)
		ci.draw_arc(c, br * 0.9, 0.3 + sin(tm) * 0.2, 1.2, 12, Color(1.0, 0.6, 1.0, 0.55), 2.5, true)


## The ice block round a frozen fighter: a beast's head, neck and tail go in too.
static func _ice_box(f, c: Vector2, hs: Vector2, st: String) -> Rect2:
	var s: float = f.size
	if st != "stand":
		var r: float = f.radius() * 1.05 + 8.0 * s
		return Rect2(c - Vector2(r, r * 0.8), Vector2(r, r * 0.8) * 2.0)
	if not f.beast:
		var half := Vector2(maxf(hs.x + 10.0 * s, 24.0 * s), hs.y + 10.0 * s)
		return Rect2(c - half, half * 2.0)
	var d: Dictionary = f.def
	var front := hs.x + (float(d.neck) * 0.7 + float(d.head) * 1.3) * s
	var back := hs.x + float(d.tail) * 0.6 * s
	var up := hs.y + (float(d.neck) * (0.95 if d.get("long_neck", false) else 0.5) + float(d.head) * 0.5) * s
	var fc: float = f.facing
	var x0 := c.x - (back if fc > 0.0 else front) - 6.0 * s
	var x1 := c.x + (front if fc > 0.0 else back) + 6.0 * s
	return Rect2(x0, c.y - up - 6.0 * s, x1 - x0, up + hs.y + 12.0 * s)

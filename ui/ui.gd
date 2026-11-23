class_name UI
## Builders for the game's look: rounded panels, chunky friendly buttons.
## Buttons can take keyboard and gamepad focus (a white ring shows which one);
## in-game bars turn that off for their whole tree with no_focus(), because
## Space and Enter are game keys there, and pop-ups turn it back on (focus_on).

const BG := Color("1d1b3a")
const PANEL := Color(0.13, 0.12, 0.27, 0.94)
const PANEL2 := Color("2c2a55")
const LINE := Color("4a4790")
const TEXT := Color("fdfcff")
const MUTED := Color("b9b6e3")
const ACCENT := Color("ffcf4a")
const GOOD := Color("5ad66a")
const BAD := Color("ff6b6b")
# Dark text on the yellow "lit" buttons and cards. The 2D canvas blends in
# linear light (viewport/hdr_2d), which makes thin dark letters on a light
# background look washed out, so they get a thin outline of the same ink to
# thicken them (ink()).
const INK := Color("15132e")
const INK_OUTLINE := 3


static func box(col: Color, radius := 16, border := 0, border_col := LINE, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	s.anti_aliasing = true
	return s


static func panel(radius := 18) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(PANEL, radius, 2, LINE, 12)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	p.add_theme_stylebox_override("panel", s)
	return p


static func button(txt: String, col := PANEL2, font_size := 18, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", INK)
	# (thickens the dark letters when pressed/lit; behind light letters on a
	# dark button it doesn't show)
	b.add_theme_constant_override("outline_size", INK_OUTLINE)
	b.add_theme_color_override("font_outline_color", INK)
	var n := box(col, 14, 2, col.lightened(0.18), 12)
	var h := box(col.lightened(0.12), 14, 2, col.lightened(0.35), 12)
	var p := box(ACCENT, 14, 2, ACCENT.lightened(0.3), 12)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	b.add_theme_stylebox_override("disabled", box(col.darkened(0.3), 14, 0, col, 12))
	b.add_theme_stylebox_override("focus", focus_ring())
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	return b


static func set_on(b: Button, on: bool, col := PANEL2) -> void:
	var c := ACCENT if on else col
	b.add_theme_stylebox_override("normal", box(c, 14, 2, c.lightened(0.25), 12))
	b.add_theme_stylebox_override("hover", box(c.lightened(0.1), 14, 2, c.lightened(0.35), 12))
	ink(b, on)


## A screenshot of an HDR viewport (viewport/hdr_2d: linear half-floats) as an
## ordinary sRGB picture for save_png. Image.linear_to_srgb() only works on
## 8-bit images, and squeezing linear colours into 8 bits first bands smooth
## gradients (fog, sky), so this converts at full precision through a table.
## Slow-ish (a second or two for a big window): for screenshot tools, not play.
static func srgb_image(img: Image) -> Image:
	if not ProjectSettings.get_setting("rendering/viewport/hdr_2d", false):
		return img
	img.convert(Image.FORMAT_RGBAF)
	var f := img.get_data().to_float32_array()
	var lut := PackedByteArray()
	lut.resize(4097)
	for i in 4097:
		lut[i] = clampi(roundi(Color(i / 4096.0, 0, 0).linear_to_srgb().r * 255.0), 0, 255)
	var out := PackedByteArray()
	out.resize(f.size())
	for i in f.size():
		if i % 4 == 3:
			out[i] = clampi(roundi(f[i] * 255.0), 0, 255)
		else:
			out[i] = lut[clampi(int(f[i] * 4096.0 + 0.5), 0, 4096)]
	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, out)


## Dark, thickened text for something lit up yellow (`on`), light text otherwise.
static func ink(c: Control, on: bool) -> void:
	var col := INK if on else TEXT
	c.add_theme_color_override("font_color", col)
	if c is Button:
		c.add_theme_color_override("font_hover_color", col)
	c.add_theme_constant_override("outline_size", INK_OUTLINE if on else 0)
	c.add_theme_color_override("font_outline_color", INK)


static func label(txt: String, size := 16, col := TEXT) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


static func title(txt: String, size := 22) -> Label:
	var l := label(txt, size, ACCENT)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	return l


## The ring round whatever the keyboard or gamepad is on (only shown when you
## got there with keys, not with the mouse).
static func focus_ring(radius := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.set_corner_radius_all(radius + 3)
	s.set_border_width_all(3)
	s.border_color = Color.WHITE
	s.set_expand_margin_all(4)
	s.anti_aliasing = true
	return s


## In-game bars: nothing under `c` takes focus, so Space and Enter stay game
## keys (Fight!, pause, next wave) instead of pressing the last button clicked.
static func no_focus(c: Control) -> void:
	c.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED


## Pop-ups and menus: arrows, Tab and a gamepad move between the buttons
## under `c`, and Enter (or the pad's A) presses one.
static func focus_on(c: Control) -> void:
	c.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED


## The first button, slider or text box under `n` that can take focus (or
## null). A pop-up's ✕ (meta "no_first") only if there's nothing else.
static func first_focus(n: Node) -> Control:
	var f := _scan_focus(n, false)
	return f if f else _scan_focus(n, true)


static func _scan_focus(n: Node, any: bool) -> Control:
	if (n is BaseButton or n is Slider or n is LineEdit) and (n as Control).is_visible_in_tree() \
			and (n as Control).get_focus_mode_with_override() == Control.FOCUS_ALL \
			and not (n is BaseButton and (n as BaseButton).disabled) and (any or not n.has_meta("no_first")):
		return n as Control
	for c in n.get_children():
		var f := _scan_focus(c, any)
		if f:
			return f
	return null


## A key or gamepad press that moves between buttons, while nothing has focus
## yet: puts the focus on the first button under `n` (true if it did). Menus
## and pop-ups call this from _input, so the ring only shows once you use keys.
static func wake_focus(e: InputEvent, n: Node) -> bool:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return false
	var vp := n.get_viewport()
	if vp.gui_get_focus_owner() != null:
		return false
	var nav := false
	for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
		if e.is_action_pressed(a):
			nav = true
	if not nav:
		return false
	var f := first_focus(n)
	if f == null:
		return false
	f.grab_focus()
	vp.set_input_as_handled()
	return true


## Team swatches show a letter too (🐾 for wild), so they're easy to tell
## apart without seeing colours well.
const TEAM_MARK := {"red": "R", "blue": "B", "green": "G", "yellow": "Y", "wild": "🐾"}


static func team_mark(tid: String) -> String:
	return String(TEAM_MARK.get(tid, ""))


## A team swatch button's letter: white with a dark edge, readable on every colour.
static func mark_swatch(b: Button, tid: String, font_size := 18) -> void:
	b.text = team_mark(tid)
	b.add_theme_font_size_override("font_size", font_size)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))

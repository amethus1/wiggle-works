class_name UI
## Builders for the game's look: rounded panels, chunky friendly buttons.

const BG := Color("1d1b3a")
const PANEL := Color(0.13, 0.12, 0.27, 0.94)
const PANEL2 := Color("2c2a55")
const LINE := Color("4a4790")
const TEXT := Color("fdfcff")
const MUTED := Color("b9b6e3")
const ACCENT := Color("ffcf4a")
const GOOD := Color("5ad66a")
const BAD := Color("ff6b6b")


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
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", Color("1d1b3a"))
	var n := box(col, 14, 2, col.lightened(0.18), 12)
	var h := box(col.lightened(0.12), 14, 2, col.lightened(0.35), 12)
	var p := box(ACCENT, 14, 2, ACCENT.lightened(0.3), 12)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("hover_pressed", p)
	b.add_theme_stylebox_override("disabled", box(col.darkened(0.3), 14, 0, col, 12))
	if min_w > 0.0:
		b.custom_minimum_size.x = min_w
	return b


static func set_on(b: Button, on: bool, col := PANEL2) -> void:
	var c := ACCENT if on else col
	b.add_theme_stylebox_override("normal", box(c, 14, 2, c.lightened(0.25), 12))
	b.add_theme_stylebox_override("hover", box(c.lightened(0.1), 14, 2, c.lightened(0.35), 12))
	b.add_theme_color_override("font_color", Color("1d1b3a") if on else TEXT)
	b.add_theme_color_override("font_hover_color", Color("1d1b3a") if on else TEXT)


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

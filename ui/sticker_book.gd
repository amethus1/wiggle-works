class_name StickerBook
## 📒 The Sticker Book pop-up's insides, the same on the title screen and in
## the 2D playground: every sticker, the ones you have in color, and on the
## ones you're still working on that count something, how far you've got
## ("3 / 10" and a little bar).

## Stickers whose progress is counted: id -> [name in Settings.counters, goal].
## A counter that's a Dictionary (worlds visited, specials used) counts its
## members. Goals of 0 are worked out in goal().
const COUNTED := {
	"boom": ["booms", 10],
	"painter": ["paints", 10],
	"builder": ["platforms", 10],
	"armory": ["gifts", 5],
	"player": ["jumps", 10],
	"explorer": ["worlds", 0],
	"special": ["specials", 0],
	"ace": ["b3_air_kos", 3],
	"hero": ["b3_hero_kos", 5],
	"historybuff": ["b3_history", 3],
	"puzzles": ["", 0],
}


static func title() -> String:
	return "📒 Sticker Book  (%d / %d)" % [got_count(), Catalog.STICKERS.size()]


static func got_count() -> int:
	var n := 0
	for s in Catalog.STICKERS:
		if Settings.stickers.has(s.id):
			n += 1
	return n


static func goal(id: String) -> int:
	match id:
		"explorer":
			return Catalog.WORLDS.size()
		"special":
			return Catalog.WIGGLY_ORDER.size()
		"puzzles":
			return B3Puzzles.STAGES.size()
	return int(COUNTED[id][1]) if COUNTED.has(id) else 0


## How far along a sticker you don't have yet is: [done, goal], or [] if it
## isn't counted (or you've got it).
static func progress(id: String) -> Array:
	if not COUNTED.has(id) or Settings.stickers.has(id):
		return []
	var g := goal(id)
	var have := 0
	if id == "puzzles":
		have = Settings.b3_puzzles.size()
	else:
		var v: Variant = Settings.counters.get(String(COUNTED[id][0]), 0)
		have = (v as Dictionary).size() if v is Dictionary else int(v)
	return [clampi(have, 0, g), g]


## Fills `v` (the pop-up's column) with the book: a grid of stickers that
## scrolls, as tall as `view_h` (the screen's height) allows.
static func build(v: VBoxContainer, view_h: float) -> void:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = clampf(view_h - 220.0, 240.0, 640.0)
	v.add_child(sc)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	sc.add_child(g)
	for s in Catalog.STICKERS:
		g.add_child(cell(s))


## One sticker: its picture (❔ until you have it), name and goal.
static func cell(s: Dictionary) -> Control:
	var got: bool = Settings.stickers.has(s.id)
	var p := PanelContainer.new()
	p.name = "Sticker_" + String(s.id)
	p.add_theme_stylebox_override("panel", UI.box(UI.PANEL2 if got else UI.PANEL2.darkened(0.35), 16, 3, UI.ACCENT if got else UI.LINE, 10))
	p.custom_minimum_size = Vector2(170, 136)
	var c := VBoxContainer.new()
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_theme_constant_override("separation", 2)
	p.add_child(c)
	var e := UI.label(String(s.emoji) if got else "❔", 40)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(e)
	var n := UI.label(String(s.name), 15, UI.TEXT if got else UI.MUTED)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(n)
	var d := UI.label(String(s.desc), 12, UI.MUTED)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD
	d.custom_minimum_size.x = 150
	c.add_child(d)
	var pr := progress(String(s.id))
	if not pr.is_empty():
		# working on it: "3 / 10" over a little bar
		var row := HBoxContainer.new()
		row.name = "Progress"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		c.add_child(row)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(80, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = float(pr[1])
		bar.value = float(pr[0])
		bar.add_theme_stylebox_override("background", UI.box(UI.LINE, 5, 0, UI.LINE, 0))
		bar.add_theme_stylebox_override("fill", UI.box(UI.ACCENT, 5, 0, UI.LINE, 0))
		row.add_child(bar)
		row.add_child(UI.label("%d / %d" % [int(pr[0]), int(pr[1])], 13, UI.ACCENT))
	return p

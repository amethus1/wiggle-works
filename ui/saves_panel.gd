class_name SavesPanel
extends VBoxContainer
## 💾 The six playground save slots (Saves), each with its picture, name and
## when it was saved. In the playground each has 💾 Save here (a slot that's
## already used asks "Sure?" first, so nothing gets saved over by accident)
## and 📂 Load; on the title screen just 📂 Load. ✏️ renames one.

var can_save := true
var on_save := Callable()     # (slot): save the playground there, then call refresh()
var on_load := Callable()     # (slot)
var grid: GridContainer


func build() -> void:
	add_theme_constant_override("separation", 8)
	Saves.migrate()
	grid = GridContainer.new()
	grid.name = "Slots"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)
	var tip := UI.label("💾 Save here keeps everything you've made. 📂 Load brings it back." if can_save
		else "📂 Load one to carry on where you left off.", 14, UI.MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	tip.custom_minimum_size.x = 600
	add_child(tip)
	refresh()


func refresh() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for i in Saves.SLOTS:
		grid.add_child(_slot(i + 1))
	UI.focus_on(self)


func _slot(slot: int) -> Control:
	var d := Saves.read(slot)
	var used := not d.is_empty()
	var card := PanelContainer.new()
	card.name = "Slot%d" % slot
	card.add_theme_stylebox_override("panel", UI.box(UI.PANEL2 if used else UI.PANEL2.darkened(0.3), 16, 2, UI.LINE, 8))
	card.custom_minimum_size.x = 220
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	# the picture (or the world's emoji, or a big ➕ for an empty slot)
	var pic := PanelContainer.new()
	pic.custom_minimum_size = Vector2(204, 115)
	pic.add_theme_stylebox_override("panel", UI.box(Color("1d1b3a"), 10, 0, UI.LINE, 0))
	pic.clip_contents = true
	v.add_child(pic)
	var tex := Saves.thumb(slot) if used else null
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = Vector2(204, 115)
		pic.add_child(tr)
	else:
		var wd: Dictionary = Catalog.world_def(String(d.get("world", "meadow")))
		var em := UI.label(String(wd.emoji) if used else "📭", 52, Color.WHITE if used else UI.MUTED)
		em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		em.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pic.add_child(em)
	# the name (✏️ renames it)
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 4)
	v.add_child(nr)
	var nm := UI.label(String(d.get("name", "")) if used else "Empty slot %d" % slot, 17, UI.TEXT if used else UI.MUTED)
	nm.name = "Name"
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.custom_minimum_size.x = 120
	nr.add_child(nm)
	if used:
		var ren := UI.button("✏️", UI.PANEL2, 14, 34)
		ren.tooltip_text = "Give it a name"
		ren.pressed.connect(func(): _rename(slot, nr, nm, ren))
		nr.add_child(ren)
	var when := UI.label(("💾 " + Saves.when_text(d)) if used else " ", 13, UI.MUTED)
	v.add_child(when)
	# the buttons
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 6)
	v.add_child(br)
	if can_save:
		var sv := UI.button("💾 Save here", Color("2f9e4f"), 15)
		sv.name = "Save"
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.pressed.connect(func():
			if used and not sv.has_meta("sure"):
				# a slot with something in it: press again to save over it
				sv.set_meta("sure", true)
				sv.text = "✅ Sure? Again!"
				UI.set_on(sv, true)
				get_tree().create_timer(3.0).timeout.connect(func():
					if is_instance_valid(sv) and sv.has_meta("sure"):
						sv.remove_meta("sure")
						sv.text = "💾 Save here"
						UI.set_on(sv, false, Color("2f9e4f")))
				return
			if on_save.is_valid():
				on_save.call(slot))
		br.add_child(sv)
	var ld := UI.button("📂 Load", UI.PANEL2 if can_save else Color("2f9e4f"), 15)
	ld.name = "Load"
	ld.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ld.disabled = not used
	ld.visible = used or can_save      # (on the title screen an empty slot has nothing to load)
	ld.pressed.connect(func():
		if on_load.is_valid():
			on_load.call(slot))
	br.add_child(ld)
	return card


## ✏️ The name turns into a box to type in; Enter (or clicking away) keeps it.
func _rename(slot: int, row: HBoxContainer, nm: Label, ren: Button) -> void:
	var ed := LineEdit.new()
	ed.text = nm.text
	ed.max_length = 24
	ed.select_all_on_focus = true
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed.add_theme_font_size_override("font_size", 16)
	nm.visible = false
	ren.visible = false
	row.add_child(ed)
	row.move_child(ed, 0)
	ed.grab_focus()
	var done := func():
		if not is_instance_valid(ed) or ed.has_meta("done"):
			return
		ed.set_meta("done", true)
		Saves.rename(slot, ed.text)
		refresh.call_deferred()
	ed.text_submitted.connect(func(_t: String): done.call())
	ed.focus_exited.connect(done)

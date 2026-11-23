class_name B3UIInspector
extends RefCounted
## The 3D Battle HUD's Inspector (for B3UI, its `inspector`): the card at the
## bottom right for the fighters you've selected, with their health, team
## colours, moods, 🚀 Launch, 💚 Heal, 🗑️, 🎮 Play as me! and 🎥 Follow. B3UI
## passes show_inspect on to it; its widgets (inspect, insp_title, insp_acts...)
## stay on B3UI, where the rest of the HUD and the tests look at them.

var ui = null                     # the HUD (b3_ui.gd)
var battle:
	get:
		return ui.battle


func _init(hud) -> void:
	ui = hud


func build() -> void:
	var inspect := UI.panel(20)
	ui.inspect = inspect
	inspect.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	inspect.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	inspect.grow_vertical = Control.GROW_DIRECTION_BEGIN
	inspect.offset_right = -10
	inspect.offset_bottom = -96
	inspect.custom_minimum_size = Vector2(300, 0)
	inspect.visible = false
	ui.root.add_child(inspect)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	inspect.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var insp_title := UI.title("", 22)
	ui.insp_title = insp_title
	insp_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(insp_title)
	var x := UI.button("✖", UI.PANEL2, 14, 36)
	x.pressed.connect(func(): battle.tools.select(null))
	h.add_child(x)
	var insp_hp := ProgressBar.new()
	ui.insp_hp = insp_hp
	insp_hp.custom_minimum_size = Vector2(270, 20)
	insp_hp.show_percentage = false
	insp_hp.add_theme_stylebox_override("background", UI.box(Color("1d1b3a"), 10, 0, UI.LINE, 0))
	insp_hp.add_theme_stylebox_override("fill", UI.box(UI.GOOD, 10, 0, UI.LINE, 0))
	v.add_child(insp_hp)
	var insp_info := UI.label("", 15, UI.MUTED)
	ui.insp_info = insp_info
	v.add_child(insp_info)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 4)
	v.add_child(tr)
	var insp_team: Dictionary = ui.insp_team
	for t in B3Defs.TEAM_ORDER:
		var tid := String(t)
		var col := B3Defs.team_col(tid)
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 34)
		b.focus_mode = Control.FOCUS_NONE
		UI.mark_swatch(b, tid, 16)      # a letter on each colour (🐾 for wild)
		b.tooltip_text = "Join the %s team" % B3Defs.TEAM[tid].name
		b.add_theme_stylebox_override("normal", UI.box(col, 16, 2, col.darkened(0.35), 0))
		b.add_theme_stylebox_override("hover", UI.box(col.lightened(0.15), 16, 3, Color.WHITE, 0))
		b.add_theme_stylebox_override("pressed", UI.box(col, 16, 3, Color.WHITE, 0))
		b.pressed.connect(func():
			var undo: Array = []
			var join := func(u: B3Unit):
				if u.team != tid:
					undo.append([u, u.team])
				if not _for_host(u, {"c": "team", "t": tid}):
					u.set_team(tid)
			if _each("team", join) > 0:
				battle.snd("tick", null, 0.5)
				ui.counts_dirty = true
				battle.tools.undo.did("team", undo, tid)
			reinspect())
		tr.add_child(b)
		insp_team[tid] = b
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 3)
	v.add_child(pr)
	var insp_pers: Dictionary = ui.insp_pers
	for pid in B3Defs.PERS_ORDER:
		var ps := String(pid)
		var d: Dictionary = B3Defs.PERS[ps]
		var b := UI.button(String(d.icon), UI.PANEL2, 16, 36)
		b.tooltip_text = "%s: %s" % [d.name, d.tip]
		b.pressed.connect(func():
			var undo: Array = []
			var feel := func(u: B3Unit):
				if u.pers_choice != ps:
					undo.append([u, u.pers_choice])
				if not _for_host(u, {"c": "mood", "p": ps}):
					u.set_personality(ps)
			if _each("mood", feel) > 0:
				battle.snd("tick", null, 0.5)
				battle.tools.undo.did("mood", undo, ps)
			reinspect())
		pr.add_child(b)
		insp_pers[ps] = b
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 6)
	v.add_child(ar)
	var insp_acts: Dictionary = ui.insp_acts
	var launch := UI.button("🚀 Launch!", Color("c0392b").darkened(0.1), 16)
	launch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fly := func(u: B3Unit):
		battle.snd("whoosh", u.position, 1.0)
		if not _for_host(u, {"c": "launch"}):
			u.knock_down(Vector3(randf_range(-4, 4), 18.0, randf_range(-4, 4)))
	launch.pressed.connect(func(): _each("launch", fly, true))
	ar.add_child(launch)
	insp_acts["launch"] = launch
	var heal := UI.button("💚 Heal", Color("2f9e4f"), 16)
	var mend := func(u: B3Unit):
		if _for_host(u, {"c": "heal"}):
			return
		u.hp = u.max_hp
		battle.fx.heal(u.center() + Vector3(0, 0.6, 0))
		battle.snd("heal", u.position, 0.8)
	heal.pressed.connect(func(): _each("heal", mend, true))
	ar.add_child(heal)
	insp_acts["heal"] = heal
	var rm := UI.button("🗑️", UI.PANEL2, 16, 44)
	rm.tooltip_text = "Remove [Delete]"
	rm.pressed.connect(func():
		var gone: Array[B3Unit] = []
		var pick := func(u: B3Unit): gone.append(u)
		_each("erase", pick)
		battle.tools.erase_units(gone)
		battle.tools.select(null))
	ar.add_child(rm)
	insp_acts["erase"] = rm
	var pl := HBoxContainer.new()
	pl.add_theme_constant_override("separation", 6)
	v.add_child(pl)
	var play := UI.button("🎮 Play as me!", Color("8e44ad"), 17)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.tooltip_text = "Control this fighter yourself [P]"
	play.pressed.connect(func():
		if targets().size() > 1:
			ui.toast("🎮 Pick just one fighter to play as!", false)
			battle.snd("nope", null, 0.5)
			return
		var u: B3Unit = battle.tools.selected
		if u and is_instance_valid(u) and not u.dead:
			battle.tools.play_as(u))      # (it says so if you can't: B3Battle.hands_off)
	pl.add_child(play)
	insp_acts["play"] = play
	var fol := UI.button("🎥 Follow", UI.PANEL2, 17)
	fol.tooltip_text = "Keep the camera on this fighter [F]"
	fol.pressed.connect(func():
		var u: B3Unit = battle.tools.selected
		if u and is_instance_valid(u) and not u.dead:
			battle.tools.follow(u))
	pl.add_child(fol)


## 🧩 / 🌊 True (with a message and a "nope") if the Inspector can't do
## `what` to `u` (B3Battle.hands_off: the puzzle's army, Wave Defense's
## attackers, and fair play with your own army in a puzzle).
func hands_off(u: B3Unit, what: String) -> bool:
	var why: String = battle.hands_off(u, what)
	if why == "":
		return false
	ui.toast(why, false)
	battle.snd("nope", u.position, 0.6)
	return true


## The fighters the Inspector's buttons act on: everyone you've selected
## (🔍 Select: drag a box round them), or just the one.
func targets() -> Array[B3Unit]:
	var out: Array[B3Unit] = []
	var tl = battle.tools
	for u: B3Unit in tl.group:
		if is_instance_valid(u) and not u.dead:
			out.append(u)
	if out.is_empty() and tl.selected and is_instance_valid(tl.selected) and not tl.selected.dead:
		out.append(tl.selected)
	return out


## Does `fn` to each selected fighter that `what` may be done to (see
## B3Battle.hands_off: puzzle and wave armies are hands off). If none of
## them may, says why (with a "nope"). Returns how many it did. `alive`:
## only fighters that aren't knocked out.
func _each(what: String, fn: Callable, alive := false) -> int:
	var n := 0
	var why := ""
	var at := Vector3.ZERO
	for u in targets():
		if alive and u.dead:
			continue
		var w: String = battle.hands_off(u, what)
		if w != "":
			why = w
			at = u.position
			continue
		fn.call(u)
		n += 1
	if n == 0 and why != "":
		ui.toast(why, false)
		battle.snd("nope", at, 0.6)
	return n


## The Inspector again, for what's selected now.
func reinspect() -> void:
	show_for(battle.tools.selected)


## In a friend's battle, buttons that change a fighter ask the host to do it.
func _for_host(u: Node, c: Dictionary) -> bool:
	if not battle.puppet or battle.net == null:
		return false
	c["nid"] = int(u.get_meta("nid", 0))
	battle.net.send_cmd(c)
	return true


func show_for(u: B3Unit) -> void:
	var inspect: PanelContainer = ui.inspect
	if u == null or not is_instance_valid(u):
		inspect.visible = false
		return
	inspect.visible = true
	var us := targets()
	if us.is_empty():
		us = [u]
	var many := us.size() > 1
	var d := u.def
	ui.insp_title.text = "👥 %d fighters" % us.size() if many else "%s %s" % [d.icon, d.name]
	update_info(u)
	# a colour or mood lights up when everyone selected has it
	var insp_team: Dictionary = ui.insp_team
	var insp_pers: Dictionary = ui.insp_pers
	var insp_acts: Dictionary = ui.insp_acts
	for t in insp_team:
		var col := B3Defs.team_col(t)
		var on := true
		for o in us:
			on = on and o.team == t
		insp_team[t].add_theme_stylebox_override("normal", UI.box(col, 16, 4 if on else 2, Color.WHITE if on else col.darkened(0.35), 0))
	for p in insp_pers:
		var on := true
		for o in us:
			on = on and o.pers_choice == p
		UI.set_on(insp_pers[p], on)
	# what you can't do to them shows dimmed (clicking says why)
	var off := {}
	for what in ["team", "mood", "launch", "heal", "erase", "play"]:
		var all_off := true
		for o in us:
			all_off = all_off and battle.hands_off(o, what) != ""
		off[what] = all_off
	for t in insp_team:
		(insp_team[t] as Control).modulate.a = 0.4 if off.team else 1.0
	for p in insp_pers:
		(insp_pers[p] as Control).modulate.a = 0.4 if off.mood else 1.0
	for k in insp_acts:
		(insp_acts[k] as Control).modulate.a = 0.4 if off[String(k)] or (many and k == "play") else 1.0
	var play: Button = insp_acts.get("play")
	if play:
		play.tooltip_text = "Pick just one fighter to play as" if many else "Control this fighter yourself [P]"


func update_info(u: B3Unit) -> void:
	var insp_hp: ProgressBar = ui.insp_hp
	var insp_info: Label = ui.insp_info
	var us := targets()
	if us.size() > 1:
		# 👥 lots selected: their health together, and how many are standing
		var hp := 0.0
		var mx := 0.0
		var up := 0
		for o in us:
			hp += maxf(0.0, o.hp)
			mx += o.max_hp
			up += 0 if o.down else 1
		insp_hp.max_value = maxf(1.0, mx)
		insp_hp.value = hp
		insp_info.text = "❤️ %d%% together   •   🧍 %d standing\nThe buttons change all of them." % [roundi(100.0 * hp / maxf(1.0, mx)), up]
		return
	insp_hp.max_value = u.max_hp
	insp_hp.value = maxf(0.0, u.hp)
	var pd: Dictionary = B3Defs.PERS[u.pers]
	var state := "😵 Knocked down!" if u.down else ("🏃 Running away!" if u.fleeing else ("🎉 Cheering!" if u.cheer else ""))
	var w := u.wpn
	var wtxt := "melee" if String(w.type) == "melee" else "range %d" % int(float(w.range))
	insp_info.text = "❤️ %d / %d   •   %s %s\n⚔️ %s   •   KOs: %d   %s" % [int(maxf(0.0, u.hp)), int(u.max_hp), pd.icon, pd.name, wtxt, u.kills, state]

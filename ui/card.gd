class_name Card
extends Control
## A toy-box card: a drawn picture of the thing and its name. Click it to
## start placing, or drag it straight out into the world.

var id := ""
var hud = null
var _down := false
var _from := Vector2.ZERO
var _dragging := false
var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_down = true
			_dragging = false
			_from = e.global_position
			Sfx.play("click", null, 0.4, 1.3)
		elif _down:
			_down = false
			var out := _dragging and not _over_drawer(e.global_position)
			if _dragging and hud.game.placing == id:
				hud.game.placing = ""
			hud.card_released(id, out)
			_dragging = false
		accept_event()
	elif e is InputEventMouseMotion and _down:
		if not _dragging and e.global_position.distance_to(_from) > 12.0:
			_dragging = true
			hud.game.placing = id    # shows the ghost under the mouse
		accept_event()


func _over_drawer(p: Vector2) -> bool:
	var d: Control = hud.drawers.toybox
	return d.get_global_rect().has_point(p)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := UI.PANEL2.lightened(0.12) if _hover else UI.PANEL2
	draw_style_box(UI.box(bg, 14, 2, UI.ACCENT if _hover else UI.LINE, 0), r)
	Preview.draw_thumb(self, id, Rect2(Vector2(6, 4), Vector2(size.x - 12, size.y - 34)))
	var name := Catalog.spawn_name(id)
	var fs := 13
	var w := Art.font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w > size.x - 8:
		fs = 11
		w = Art.font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(Art.font, Vector2((size.x - w) * 0.5, size.y - 10), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.TEXT)

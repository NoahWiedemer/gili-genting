class_name TitleScreen
extends CanvasLayer
## Title screen with the key art, drifting embers and the main menu.

signal done(choice: String)

var _btns: Array = []
var _menu: PanelContainer
var _press: Label
var _started := false

func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme
	add_child(root)
	var bg := TextureRect.new()
	bg.texture = Data.ui_tex("title_bg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(bg)
	var tw := bg.create_tween().set_loops()
	tw.tween_property(bg, "modulate", Color(1.05, 0.95, 0.95), 3.0)
	tw.tween_property(bg, "modulate", Color(0.92, 0.9, 1.0), 3.0)
	bg.pivot_offset = Vector2(170, 230)  # zoom towards the chicken with the cleaver
	bg.scale = Vector2(1.12, 1.12)
	var zt := bg.create_tween().set_loops()
	zt.tween_property(bg, "scale", Vector2(1.0, 1.0), 14.0).set_trans(Tween.TRANS_SINE)
	zt.tween_property(bg, "scale", Vector2(1.12, 1.12), 14.0).set_trans(Tween.TRANS_SINE)
	# cinematic letterbox bars
	for top in [true, false]:
		var lb := ColorRect.new()
		lb.color = Color(0, 0, 0, 0.85)
		lb.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		lb.offset_top = 0 if top else -14
		lb.offset_bottom = 14 if top else 0
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child.call_deferred(lb)
	var vign := ColorRect.new()
	vign.set_anchors_preset(Control.PRESET_FULL_RECT)
	vign.color = Color(0, 0, 0, 0.25)
	vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vign)
	var emb := CPUParticles2D.new()
	emb.amount = 40
	emb.lifetime = 6.0
	emb.preprocess = 6.0
	emb.position = Vector2(320, 380)
	emb.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emb.emission_rect_extents = Vector2(340, 4)
	emb.direction = Vector2(0.2, -1)
	emb.spread = 20
	emb.initial_velocity_min = 12
	emb.initial_velocity_max = 30
	emb.gravity = Vector2(4, -2)
	emb.scale_amount_min = 1.0
	emb.scale_amount_max = 2.0
	emb.color = Color(1.0, 0.5, 0.25, 0.8)
	root.add_child(emb)
	var logo_box := VBoxContainer.new()
	logo_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo_box.offset_left = -300
	logo_box.offset_right = 300
	logo_box.offset_top = 26
	root.add_child(logo_box)
	var logo := UI.label("GILI GENTING", UI.CREAM, 42, true)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_constant_override("outline_size", 8)
	logo.add_theme_color_override("font_outline_color", Color(0.25, 0.02, 0.02))
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	logo.add_theme_constant_override("shadow_offset_x", 3)
	logo.add_theme_constant_override("shadow_offset_y", 3)
	logo_box.add_child(logo)
	var sub := UI.label("The Island of Chicken", Color(1, 0.6, 0.45), 10)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_box.add_child(sub)
	var lt := logo.create_tween().set_loops()
	lt.tween_property(logo, "position:y", 3.0, 1.6).set_trans(Tween.TRANS_SINE)
	lt.tween_property(logo, "position:y", 0.0, 1.6).set_trans(Tween.TRANS_SINE)
	var menu := UI.make_panel("panel_dark")
	_menu = menu
	menu.modulate.a = 0.0
	menu.visible = false
	menu.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	menu.offset_left = -70
	menu.offset_right = 70
	menu.offset_top = -100
	menu.offset_bottom = -30
	root.add_child(menu)
	var v := VBoxContainer.new()
	menu.add_child(v)
	_add(v, "Neues Spiel", "new")
	var cont := _add(v, "Fortsetzen", "continue")
	cont.disabled = not Game.has_save()
	_add(v, "Beenden", "quit")
	var foot := UI.label("Ein Hühnchen. Eine Insel. Eine Schlachtzeit.", Color(1, 1, 1, 0.55))
	foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	foot.offset_left = -200
	foot.offset_right = 200
	foot.offset_top = -30
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(foot)
	_press = UI.label("▶  Drücke Enter  ◀", UI.GOLD, 14, true)
	_press.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_press.offset_left = -150
	_press.offset_right = 150
	_press.offset_top = -78
	_press.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_press.add_theme_constant_override("outline_size", 6)
	_press.add_theme_color_override("font_outline_color", Color(0.15, 0.02, 0.02))
	root.add_child(_press)
	var pt := _press.create_tween().set_loops()
	pt.tween_property(_press, "modulate:a", 0.25, 0.8).set_trans(Tween.TRANS_SINE)
	pt.tween_property(_press, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	Audio.music("title", 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if _started:
		return
	if event.is_action_pressed("accept") or event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		_started = true
		Audio.sfx("cluck_angry")
		UI.flash(Color(1, 0.3, 0.2), 0.4, 0.5)
		_press.queue_free()
		_menu.visible = true
		create_tween().tween_property(_menu, "modulate:a", 1.0, 0.35)
		await get_tree().process_frame
		(_btns[1] if not _btns[1].disabled else _btns[0]).grab_focus()

func _add(v: VBoxContainer, text: String, id: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_entered.connect(func(): Audio.sfx("ui_move", 1.0, 0.6))
	b.pressed.connect(func():
		Audio.sfx("ui_select")
		if id == "quit":
			get_tree().quit()
		else:
			done.emit(id))
	v.add_child(b)
	_btns.append(b)
	return b

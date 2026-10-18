class_name CharacterCreator
extends CanvasLayer
## Character creator: name + class (with sprite preview, stats and skill tree overview).

signal done(result: Dictionary)

const ORDER := ["krieger", "magier", "heiler", "tank", "assassine"]
var idx := 0
var name_edit: LineEdit
var preview: TextureRect
var cls_name: Label
var desc: Label
var stats_lbl: Label
var tree_lbl: Label
var _t := 0.0
var _icons: Array = []

func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme
	add_child(root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.05, 0.08)
	root.add_child(bg)
	var t := TextureRect.new()
	t.texture = Data.ui_tex("title_bg")
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.modulate = Color(0.25, 0.25, 0.32)
	root.add_child(t)
	var title := UI.label("Wer bist du, Huhn?", UI.GOLD, 28, true)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -250
	title.offset_right = 250
	title.offset_top = 14
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var main := HBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_CENTER)
	main.offset_left = -290
	main.offset_right = 290
	main.offset_top = -120
	main.offset_bottom = 130
	main.add_theme_constant_override("separation", 10)
	root.add_child(main)
	# left: preview
	var lp := UI.make_panel("panel")
	lp.custom_minimum_size = Vector2(190, 0)
	main.add_child(lp)
	var lv := VBoxContainer.new()
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lp.add_child(lv)
	cls_name = UI.label("", UI.GOLD, 14, true)
	cls_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(cls_name)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(160, 120)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lv.add_child(preview)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	lv.add_child(row)
	for i in ORDER.size():
		var ic := TextureRect.new()
		ic.texture = Data.sprite_tex(Data.CLASSES[ORDER[i]]["sprite"])
		ic.custom_minimum_size = Vector2(30, 30)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(ic)
		_icons.append(ic)
	var arrows := UI.label("◀  A / D  ▶", UI.DIM)
	arrows.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(arrows)
	# right: info
	var rp := UI.make_panel("panel")
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(rp)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	rp.add_child(rv)
	rv.add_child(UI.label("Name", UI.GOLD))
	name_edit = LineEdit.new()
	name_edit.text = "Ania"
	name_edit.max_length = 12
	name_edit.theme = UI.theme
	rv.add_child(name_edit)
	desc = UI.label("")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(300, 30)
	rv.add_child(desc)
	stats_lbl = UI.label("", UI.TEAL)
	rv.add_child(stats_lbl)
	tree_lbl = UI.label("", UI.CREAM)
	tree_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tree_lbl.custom_minimum_size = Vector2(300, 0)
	rv.add_child(tree_lbl)
	var go := Button.new()
	go.text = "▶ Aufwachen"
	go.alignment = HORIZONTAL_ALIGNMENT_LEFT
	go.pressed.connect(_confirm)
	rv.add_child(go)
	var hint := UI.label("Die Klasse verändert dein Aussehen und deinen Skilltree.", UI.DIM)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -250
	hint.offset_right = 250
	hint.offset_top = -22
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)
	_show()
	go.grab_focus()
	name_edit.text_submitted.connect(func(_t): go.grab_focus())

func _show() -> void:
	var c: Dictionary = Data.CLASSES[ORDER[idx]]
	for i in _icons.size():
		_icons[i].modulate = Color(1, 1, 1) if i == idx else Color(0.35, 0.35, 0.42)
	cls_name.text = c["name"]
	preview.texture = Data.sprite_tex(c["sprite"])
	desc.text = c["desc"]
	var b: Dictionary = c["base"]
	stats_lbl.text = "♥ %d   ✦ %d   Angr %d   Vert %d   Magie %d   Tempo %d" % [b["hp"], b["mp"], b["atk"], b["def"], b["mag"], b["spd"]]
	var parts := []
	for br in c["branches"]:
		parts.append(br["name"])
	tree_lbl.text = "Start-Skill: %s\nSkilltree: %s" % [Data.skill(c["start"])["name"], "  ·  ".join(parts)]

func _process(delta: float) -> void:
	_t += delta
	if preview:
		preview.position.y = abs(sin(_t * 3.0)) * -4.0

func _unhandled_input(event: InputEvent) -> void:
	if name_edit.has_focus():
		return
	if event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		idx = (idx - 1 + ORDER.size()) % ORDER.size()
		Audio.sfx("cluck1", randf_range(0.9, 1.2))
		_show()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		idx = (idx + 1) % ORDER.size()
		Audio.sfx("cluck2", randf_range(0.9, 1.2))
		_show()
		get_viewport().set_input_as_handled()

func _confirm() -> void:
	Audio.sfx("cluck_angry")
	done.emit({"name": name_edit.text.strip_edges(), "class": ORDER[idx]})

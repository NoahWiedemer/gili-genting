extends CanvasLayer
## Global UI: theme, fades, dialog with choices, narration, memory flashes, toasts, HUD.

signal _advance

const CREAM := Color(0.97, 0.92, 0.8)
const GOLD := Color(1.0, 0.8, 0.38)
const RED := Color(0.92, 0.3, 0.28)
const TEAL := Color(0.45, 0.9, 0.85)
const DIM := Color(0.6, 0.62, 0.68)

var theme: Theme
var font: Font
var title_font: Font
var busy_count := 0

var _fade: ColorRect
var _flash: ColorRect
var _dialog: PanelContainer
var _dlg_name: Label
var _dlg_text: RichTextLabel
var _dlg_portrait: TextureRect
var _dlg_portrait_frame: PanelContainer
var _dlg_arrow: Label
var _choices: VBoxContainer
var _choice_panel: PanelContainer
var _toast_box: VBoxContainer
var _hud: Control
var _hud_map: Label
var _hud_days: Label
var _hud_quest: Label
var _hud_party: HBoxContainer
var _narr: Label
var _narr_bg: ColorRect
var _narr_hint: Label
var _typing := false
var _skip := false
var _waiting := false
var _choice_index := -1

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_theme()
	_build_hud()
	_build_dialog()
	_build_narration()
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toast_box.offset_left = -220
	_toast_box.offset_right = -8
	_toast_box.offset_top = 34
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	# the fade covers world + HUD, but dialogs, narration, choices and toasts stay readable on top of it
	move_child(_fade, _hud.get_index() + 1)
	Game.toast.connect(toast)
	Game.party_changed.connect(_refresh_hud)
	Game.quests_changed.connect(_refresh_hud)
	Game.inventory_changed.connect(_refresh_hud)

# ------------------------------------------------------------------ theme
func _load_font(path: String) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var f: FontFile = load(path)
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.generate_mipmaps = false
	f.multichannel_signed_distance_field = false
	return f

func _build_theme() -> void:
	theme = Theme.new()
	font = _load_font("res://assets/fonts/GiliPixel.ttf")
	title_font = _load_font("res://assets/fonts/GiliTitle.ttf")
	if font == null:
		font = ThemeDB.fallback_font
	if title_font == null:
		title_font = font
	theme.default_font = font
	theme.default_font_size = 10
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_color("default_color", "RichTextLabel", CREAM)
	theme.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.6))
	theme.set_constant("shadow_offset_x", "RichTextLabel", 1)
	theme.set_constant("shadow_offset_y", "RichTextLabel", 1)
	theme.set_constant("line_separation", "RichTextLabel", 3)
	theme.set_stylebox("panel", "PanelContainer", panel_style("panel"))
	theme.set_stylebox("panel", "Panel", panel_style("panel"))
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 10
	empty.content_margin_right = 4
	empty.content_margin_top = 1
	empty.content_margin_bottom = 1
	var focus := _focus_style()
	for st in ["normal", "pressed", "disabled"]:
		theme.set_stylebox(st, "Button", empty)
	theme.set_stylebox("hover", "Button", focus)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("hover_pressed", "Button", focus)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_focus_color", "Button", GOLD)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_hover_pressed_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.55))
	theme.set_constant("h_separation", "Button", 4)
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.05, 0.08, 0.12, 0.9)
	le.border_color = GOLD
	le.set_border_width_all(1)
	le.content_margin_left = 4
	le.content_margin_right = 4
	theme.set_stylebox("normal", "LineEdit", le)
	theme.set_stylebox("focus", "LineEdit", le)
	theme.set_color("font_color", "LineEdit", CREAM)
	theme.set_color("caret_color", "LineEdit", GOLD)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.04, 0.05, 0.08, 0.95)
	bar_bg.border_color = Color(0.0, 0.0, 0.0, 1)
	bar_bg.set_border_width_all(1)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.4, 0.9, 0.4)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	theme.set_constant("separation", "VBoxContainer", 2)
	theme.set_constant("separation", "HBoxContainer", 4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.9, 0.75, 0.4, 0.6)
	theme.set_stylebox("grabber", "VScrollBar", sb)
	theme.set_stylebox("grabber_highlight", "VScrollBar", sb)
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(0, 0, 0, 0.3)
	theme.set_stylebox("scroll", "VScrollBar", sbg)

func panel_style(kind := "panel") -> StyleBox:
	var t := Data.ui_tex(kind)
	if t:
		var s := StyleBoxTexture.new()
		s.texture = t
		s.texture_margin_left = 8
		s.texture_margin_right = 8
		s.texture_margin_top = 8
		s.texture_margin_bottom = 8
		s.content_margin_left = 8
		s.content_margin_right = 8
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		return s
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.06, 0.11, 0.16, 0.94) if kind != "panel_light" else Color(0.85, 0.78, 0.6, 0.97)
	f.border_color = Color(0.82, 0.62, 0.3)
	f.set_border_width_all(2)
	f.set_corner_radius_all(2)
	f.content_margin_left = 8
	f.content_margin_right = 8
	f.content_margin_top = 6
	f.content_margin_bottom = 6
	return f

func _focus_style() -> StyleBox:
	var t := Data.ui_tex("button_focus")
	if t:
		var s := StyleBoxTexture.new()
		s.texture = t
		s.texture_margin_left = 6
		s.texture_margin_right = 6
		s.texture_margin_top = 6
		s.texture_margin_bottom = 6
		s.content_margin_left = 10
		s.content_margin_right = 4
		s.content_margin_top = 1
		s.content_margin_bottom = 1
		return s
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.9, 0.7, 0.3, 0.25)
	f.content_margin_left = 10
	f.content_margin_right = 4
	return f

func make_panel(kind := "panel") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = theme
	p.add_theme_stylebox_override("panel", panel_style(kind))
	return p

func label(text: String, color := CREAM, size := 10, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = theme
	l.add_theme_color_override("font_color", color)
	if title:
		l.add_theme_font_override("font", title_font)
		l.add_theme_font_size_override("font_size", 14 if size == 10 else size)
	elif size != 10:
		l.add_theme_font_size_override("font_size", size)
	return l

func is_busy() -> bool:
	return busy_count > 0

# ------------------------------------------------------------------ fades
func fade_out(t := 0.5, color := Color.BLACK) -> void:
	_fade.color = Color(color.r, color.g, color.b, _fade.color.a)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, t)
	await tw.finished

func fade_in(t := 0.5) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, t)
	await tw.finished

func flash(color := Color.WHITE, t := 0.35, strength := 0.9) -> void:
	_flash.color = Color(color.r, color.g, color.b, strength)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, t)

# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = theme
	_hud.visible = false
	add_child(_hud)
	var tl := make_panel("panel_dark")
	tl.position = Vector2(6, 6)
	_hud.add_child(tl)
	var v := VBoxContainer.new()
	tl.add_child(v)
	_hud_map = label("", GOLD)
	v.add_child(_hud_map)
	_hud_quest = label("", CREAM)
	_hud_quest.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_quest.custom_minimum_size = Vector2(190, 0)
	v.add_child(_hud_quest)
	var tr := make_panel("panel_dark")
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.offset_left = -6
	tr.offset_right = -6
	tr.offset_top = 6
	_hud.add_child(tr)
	_hud_days = label("", RED)
	tr.add_child(_hud_days)
	_hud_party = HBoxContainer.new()
	_hud_party.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hud_party.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud_party.offset_left = 6
	_hud_party.offset_top = -6
	_hud_party.offset_bottom = -6
	_hud.add_child(_hud_party)
	var hint := label("TAB Menü  ·  E Interagieren  ·  SHIFT Rennen", Color(1, 1, 1, 0.45))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = -8
	hint.offset_right = -8
	hint.offset_top = -4
	hint.offset_bottom = -4
	_hud.add_child(hint)

func show_hud(on: bool) -> void:
	_hud.visible = on
	_refresh_hud()

func set_map_name(n: String) -> void:
	_hud_map.text = n

func clear_banners() -> void:
	for n in get_tree().get_nodes_in_group("area_banner"):
		n.queue_free()

func area_banner(n: String) -> void:
	if n == "":
		return
	var l := label(n, CREAM, 28, true)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.offset_left = -300
	l.offset_right = 300
	l.offset_top = 52
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02))
	l.modulate.a = 0.0
	l.add_to_group("area_banner")
	add_child(l)
	move_child(l, _hud.get_index() + 1)
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.8)
	tw.tween_interval(1.8)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func _refresh_hud() -> void:
	if not _hud or not _hud.visible or Game.chars.is_empty():
		return
	if Game.flag("revolution"):
		_hud_days.text = "⚔ Der Zeiger schlägt auf Revolution"
	elif Game.days_left <= 0:
		_hud_days.text = "☠ Heute ist deine Schlachtzeit"
	else:
		_hud_days.text = "☠ Noch %d %s bis zur Schlachtung" % [Game.days_left, "Tag" if Game.days_left == 1 else "Tage"]
	if Game.quests.has("main"):
		_hud_quest.text = "◆ " + Game.quest_text("main")
	else:
		_hud_quest.text = ""
	for c in _hud_party.get_children():
		c.queue_free()
	for id in Game.active_party():
		var p := make_panel("panel_dark")
		var h := HBoxContainer.new()
		p.add_child(h)
		var tex := TextureRect.new()
		tex.texture = Data.sprite_tex(("p_cls_" + Game.char_class(id)) if id == "ania" else ("p_" + id))
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.custom_minimum_size = Vector2(22, 22)
		h.add_child(tex)
		var vv := VBoxContainer.new()
		vv.add_theme_constant_override("separation", 0)
		h.add_child(vv)
		var st := Game.stats(id)
		vv.add_child(label("%s  Lv%d" % [Game.char_name(id), Game.level_of(id)], CREAM))
		vv.add_child(label("♥%d/%d  ✦%d" % [Game.chars[id]["hp"], st["hp"], Game.chars[id]["mp"]],
			RED if Game.chars[id]["hp"] < st["hp"] * 0.3 else Color(0.75, 0.95, 0.75)))
		_hud_party.add_child(p)

# ------------------------------------------------------------------ toasts
func toast(text: String) -> void:
	var p := make_panel("panel_dark")
	var l := label(text, CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(196, 0)
	p.add_child(l)
	p.modulate.a = 0
	_toast_box.add_child(p)
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)

# ------------------------------------------------------------------ dialog
func _build_dialog() -> void:
	_dialog = make_panel("panel")
	_dialog.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_dialog.offset_left = -250
	_dialog.offset_right = 250
	_dialog.offset_top = -92
	_dialog.offset_bottom = -8
	_dialog.visible = false
	add_child(_dialog)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_dialog.add_child(h)
	_dlg_portrait_frame = make_panel("panel_dark")
	_dlg_portrait_frame.custom_minimum_size = Vector2(66, 66)
	h.add_child(_dlg_portrait_frame)
	_dlg_portrait = TextureRect.new()
	_dlg_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dlg_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dlg_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dlg_portrait.custom_minimum_size = Vector2(52, 52)
	_dlg_portrait_frame.add_child(_dlg_portrait)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_dlg_name = label("", GOLD, 14, true)
	v.add_child(_dlg_name)
	_dlg_text = RichTextLabel.new()
	_dlg_text.theme = theme
	_dlg_text.bbcode_enabled = true
	_dlg_text.fit_content = true
	_dlg_text.scroll_active = false
	_dlg_text.custom_minimum_size = Vector2(400, 36)
	_dlg_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_dlg_text)
	_dlg_arrow = label("▼", GOLD)
	_dlg_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_dlg_arrow)
	_choice_panel = make_panel("panel")
	_choice_panel.visible = false
	add_child(_choice_panel)
	_choices = VBoxContainer.new()
	_choice_panel.add_child(_choices)

func _input(event: InputEvent) -> void:
	if not (_dialog.visible or _narr.visible):
		return
	if event.is_action_pressed("accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		if _choice_panel.visible:
			return
		get_viewport().set_input_as_handled()
		if _typing:
			_skip = true
		elif _waiting:
			_advance.emit()

const PORTRAITS := {"Jimmy": "p_jimmy", "Vian": "p_vian", "Nugget": "p_nugget", "Madame Paprika": "p_paprika",
	"Toter Hai": "p_shark", "Heuschrecke": "p_grasshopper", "Alte Dame": "p_witch", "Der Schlachter": "p_butcher",
	"Bauer Made": "p_bauer", "Opa Kura": "turtle", "Berta": "cow", "Herr Morchel": "mushroom", "Lieselotte": "ladybug",
	"Toké": "gecko", "Kevin": "backpacker", "Ibu Wayan": "warung_woman", "Der Wanderer": "wanderer", "Der Wolf": "wolf",
	"Buchmacher Benny": "bookie", "Klößchen": "calf", "Hannah": "p_witch"}

func _portrait_for(who: String) -> String:
	match who:
		"", "Erzähler": return ""
	if who == Game.player_name:
		return "p_ania"
	return PORTRAITS.get(who, "")

func say(who: String, text: String, portrait := "?") -> void:
	await _show_line(who, text, portrait)
	_waiting = true
	_dlg_arrow.modulate.a = 1.0
	if Game.auto:
		await get_tree().create_timer(0.02).timeout
		_waiting = false
		return
	await _advance
	_waiting = false
	Audio.sfx("ui_select", 1.0, 0.5)

func choose(who: String, text: String, options: Array, portrait := "?") -> int:
	await _show_line(who, text, portrait)
	for c in _choices.get_children():
		c.queue_free()
	_choice_index = -1
	var first: Button = null
	for i in options.size():
		var b := Button.new()
		b.theme = theme
		b.text = options[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _choice_index = i; _advance.emit())
		b.focus_entered.connect(func(): Audio.sfx("ui_move", 1.0, 0.5))
		_choices.add_child(b)
		if first == null:
			first = b
	_choice_panel.visible = true
	await get_tree().process_frame
	_choice_panel.reset_size()
	_choice_panel.position = Vector2(_dialog.position.x + _dialog.size.x - _choice_panel.size.x, _dialog.position.y - _choice_panel.size.y - 4)
	first.grab_focus()
	if Game.auto:
		_choice_index = Game.auto_queue.pop_front() if not Game.auto_queue.is_empty() else 0
		print("  [auto] %s -> %s" % [text.left(40), options[_choice_index]])
		_choice_panel.visible = false
		return _choice_index
	await _advance
	_choice_panel.visible = false
	Audio.sfx("ui_select")
	return _choice_index

func _show_line(who: String, text: String, portrait: String) -> void:
	if not _dialog.visible:
		busy_count += 1
		_dialog.visible = true
		_dialog.modulate.a = 0
		create_tween().tween_property(_dialog, "modulate:a", 1.0, 0.12)
	_dlg_arrow.modulate.a = 0.0
	if portrait == "?":
		portrait = _portrait_for(who)
	_dlg_portrait_frame.visible = portrait != ""
	if portrait != "":
		_dlg_portrait.texture = Data.sprite_tex(portrait)
	_dlg_name.text = who
	_dlg_name.visible = who != ""
	text = text.replace("{name}", Game.player_name)
	_dlg_text.text = text
	_dlg_text.visible_characters = 0
	_typing = true
	_skip = false
	var total := _dlg_text.get_total_character_count()
	var i := 0
	while i < total and not _skip and not Game.auto:
		i += 1
		_dlg_text.visible_characters = i
		if i % 3 == 0:
			Audio.sfx("text_blip", randf_range(0.95, 1.1) * (0.8 if who == "" else 1.0), 0.35)
		await get_tree().create_timer(0.022).timeout
	_dlg_text.visible_characters = -1
	_typing = false

func close_dialog() -> void:
	if _dialog.visible:
		_dialog.visible = false
		busy_count = max(0, busy_count - 1)

## Convenience: plays a list of [who, text] lines and closes the box.
func talk(lines: Array) -> void:
	for l in lines:
		await say(l[0], l[1], l[2] if l.size() > 2 else "?")
	close_dialog()

func ask(who: String, text: String, options: Array, portrait := "?") -> int:
	var r := await choose(who, text, options, portrait)
	close_dialog()
	return r

# ------------------------------------------------------------------ narration / memory
func _build_narration() -> void:
	_narr_bg = ColorRect.new()
	_narr_bg.color = Color(0, 0, 0, 0)
	_narr_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_narr_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_narr_bg)
	_narr = Label.new()
	_narr.theme = theme
	_narr.set_anchors_preset(Control.PRESET_FULL_RECT)
	_narr.offset_left = 70
	_narr.offset_right = -70
	_narr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_narr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_narr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narr.add_theme_color_override("font_color", CREAM)
	_narr.visible = false
	add_child(_narr)
	_narr_hint = label("[E] weiter  ▼", GOLD)
	_narr_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_narr_hint.offset_left = -110
	_narr_hint.offset_right = -14
	_narr_hint.offset_top = -24
	_narr_hint.offset_bottom = -8
	_narr_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_narr_hint.visible = false
	add_child(_narr_hint)
	var ht := _narr_hint.create_tween().set_loops()
	ht.tween_property(_narr_hint, "modulate:a", 0.3, 0.6)
	ht.tween_property(_narr_hint, "modulate:a", 1.0, 0.6)

## Shows text lines centered over a (semi-)dark background, one by one. style: "book" | "memory" | "void"
func narrate(lines: Array, style := "book", bg_alpha := 0.88) -> void:
	busy_count += 1
	var col := CREAM
	var bgc := Color(0.02, 0.02, 0.04)
	match style:
		"memory":
			col = Color(0.7, 0.95, 1.0)
			bgc = Color(0.0, 0.05, 0.08)
		"void":
			col = Color(0.15, 0.12, 0.12)
			bgc = Color(0.97, 0.96, 0.94)
		"blood":
			col = Color(1, 0.75, 0.7)
			bgc = Color(0.12, 0.0, 0.0)
	_narr_bg.color = Color(bgc.r, bgc.g, bgc.b, _narr_bg.color.a)
	_narr.add_theme_color_override("font_color", col)
	_narr.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0) if style == "void" else Color(0, 0, 0, 0.7))
	var tw := create_tween()
	tw.tween_property(_narr_bg, "color:a", bg_alpha, 0.6)
	await tw.finished
	_narr.visible = true
	for line in lines:
		_narr.text = String(line).replace("{name}", Game.player_name)
		_narr.modulate.a = 0
		var t2 := create_tween()
		t2.tween_property(_narr, "modulate:a", 1.0, 0.7)
		_waiting = false
		_typing = true
		_skip = false
		await t2.finished
		_typing = false
		_waiting = true
		_narr_hint.visible = true
		if not Game.auto:
			await _advance
		_narr_hint.visible = false
		_waiting = false
		var t3 := create_tween()
		t3.tween_property(_narr, "modulate:a", 0.0, 0.35)
		await t3.finished
	_narr.visible = false
	var t4 := create_tween()
	t4.tween_property(_narr_bg, "color:a", 0.0, 0.6)
	await t4.finished
	busy_count = max(0, busy_count - 1)

## Full-screen pixel illustration with captions at the bottom.
func illustration(img: String, lines: Array, music := "") -> void:
	busy_count += 1
	var prev := Audio.current_music()
	if music != "":
		Audio.music(music, 1.0)
	var tr := TextureRect.new()
	tr.texture = Data.ui_tex(img)
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.modulate.a = 0.0
	add_child(tr)
	move_child(tr, _narr_bg.get_index())
	var tw := create_tween()
	tw.tween_property(tr, "modulate:a", 1.0, 1.0)
	# slow ken-burns drift
	tr.pivot_offset = Vector2(320, 180)
	var kb := create_tween()
	kb.tween_property(tr, "scale", Vector2(1.06, 1.06), 14.0)
	await tw.finished
	var cap := make_panel("panel_dark")
	cap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cap.offset_left = -270
	cap.offset_right = 270
	cap.offset_top = -64
	cap.offset_bottom = -10
	add_child(cap)
	var l := label("", CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(520, 40)
	cap.add_child(l)
	for line in lines:
		l.text = String(line).replace("{name}", Game.player_name)
		l.visible_ratio = 0.0
		var t2 := create_tween()
		_typing = true
		_skip = false
		t2.tween_property(l, "visible_ratio", 1.0, clamp(l.text.length() * 0.025, 0.4, 2.5))
		while t2.is_running() and not _skip and not Game.auto:
			await get_tree().process_frame
		t2.kill()
		l.visible_ratio = 1.0
		_typing = false
		_waiting = true
		_narr.visible = true  # enables input routing
		_narr.text = ""
		if Game.auto:
			await get_tree().create_timer(0.02).timeout
			continue
		_narr_hint.visible = true
		await _advance
		_narr_hint.visible = false
		_waiting = false
	_narr.visible = false
	cap.queue_free()
	var t3 := create_tween()
	t3.tween_property(tr, "modulate:a", 0.0, 0.8)
	await t3.finished
	tr.queue_free()
	if music != "" and prev != "":
		Audio.music(prev, 1.0)
	busy_count = max(0, busy_count - 1)

func memory(lines: Array) -> void:
	var prev := Audio.current_music()
	Audio.sfx("memory_flash")
	flash(Color(0.6, 1, 1), 0.8, 1.0)
	Audio.music("memory", 1.0)
	await narrate(lines, "memory", 0.94)
	flash(Color(0.6, 1, 1), 0.6, 0.8)
	Audio.music(prev, 1.0)

func chapter(num: String, title: String) -> void:
	busy_count += 1
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	bg.add_child(v)
	var a := label(num, GOLD, 10)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	var b := label(title, CREAM, 28, true)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	v.modulate.a = 0
	var tw := create_tween()
	tw.tween_property(bg, "color:a", 0.75, 0.5)
	tw.tween_property(v, "modulate:a", 1.0, 0.8)
	tw.tween_interval(2.0)
	tw.tween_property(v, "modulate:a", 0.0, 0.6)
	tw.tween_property(bg, "color:a", 0.0, 0.5)
	await tw.finished
	bg.queue_free()
	busy_count = max(0, busy_count - 1)

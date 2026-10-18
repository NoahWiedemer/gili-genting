class_name BattleUI
extends CanvasLayer
## Battle HUD: party status, enemy list, command menus, targeting, banners, speech and results.

signal _picked(value)

var battle: Battle
var root: Control
const CMDS := ["ANGRIFF", "SKILLS", "ITEMS", "ABWEHR", "FLUCHT"]
var party_box: HBoxContainer
var foe_box: VBoxContainer
var foe_panel: PanelContainer
var cmd_btns: Array = []
var active: Battler
var cmd_panel: PanelContainer
var cmd_list: VBoxContainer
var info_panel: PanelContainer
var info_label: Label
var banner_panel: PanelContainer
var banner_label: Label
var skill_lbl: Label
var _mode := ""             # "", "menu", "target", "wait"
var _targets: Array = []
var _tidx := 0
var _all := false
var _arrows: Array = []
var _rows := {}

func _ready() -> void:
	layer = 20
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# ---- bottom bar: commands + party cards (FF-pixel-remaster style)
	var bar := UI.make_panel("panel")
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 6
	bar.offset_right = -6
	bar.offset_top = -104
	bar.offset_bottom = -4
	root.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	bar.add_child(hb)
	var cp := UI.make_panel("panel_dark")
	cp.custom_minimum_size = Vector2(112, 0)
	hb.add_child(cp)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 0)
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	cp.add_child(cv)
	for i in CMDS.size():
		var b := Button.new()
		b.text = "  " + CMDS[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", UI.title_font)
		b.add_theme_font_size_override("font_size", 14)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = true
		var idx := i
		b.pressed.connect(func(): if _mode == "main": _picked.emit(idx))
		b.focus_entered.connect(func():
			for k in cmd_btns.size():
				cmd_btns[k].text = ("▶ " if k == idx else "  ") + CMDS[k]
			Audio.sfx("ui_move", 1.0, 0.5))
		cv.add_child(b)
		cmd_btns.append(b)
	party_box = HBoxContainer.new()
	party_box.add_theme_constant_override("separation", 4)
	party_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(party_box)
	# foes (top left)
	var fp := UI.make_panel("panel_dark")
	fp.position = Vector2(6, 6)
	fp.custom_minimum_size = Vector2(0, 0)
	root.add_child(fp)
	foe_box = VBoxContainer.new()
	foe_box.add_theme_constant_override("separation", 0)
	fp.add_child(foe_box)
	foe_panel = fp
	# command menu
	cmd_panel = UI.make_panel("panel")
	cmd_panel.visible = false
	root.add_child(cmd_panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 0)
	cmd_panel.add_child(sc)
	cmd_list = VBoxContainer.new()
	cmd_list.add_theme_constant_override("separation", 1)
	sc.add_child(cmd_list)
	cmd_panel.set_meta("scroll", sc)
	# info line (top)
	info_panel = UI.make_panel("panel_dark")
	info_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	info_panel.offset_left = -150
	info_panel.offset_right = 150
	info_panel.offset_top = 6
	info_panel.visible = false
	root.add_child(info_panel)
	info_label = UI.label("")
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_panel.add_child(info_label)
	banner_panel = UI.make_panel("panel")
	banner_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_panel.offset_left = -170
	banner_panel.offset_right = 170
	banner_panel.offset_top = 8
	banner_panel.visible = false
	root.add_child(banner_panel)
	banner_label = UI.label("", UI.CREAM)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_panel.add_child(banner_label)
	skill_lbl = UI.label("", UI.GOLD, 28, true)
	skill_lbl.set_anchors_preset(Control.PRESET_CENTER)
	skill_lbl.offset_left = -300
	skill_lbl.offset_right = 300
	skill_lbl.offset_top = -100
	skill_lbl.offset_bottom = -70
	skill_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skill_lbl.add_theme_constant_override("outline_size", 6)
	skill_lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.02))
	skill_lbl.modulate.a = 0
	root.add_child(skill_lbl)

# ------------------------------------------------------------------ status panels
func portrait_tex(b: Battler) -> Texture2D:
	var n := "p_" + b.cid
	if b.cid == "ania":
		n = "p_cls_" + Game.char_class("ania")
		if Data.tex("res://assets/sprites/%s.png" % n) == null:
			n = "p_ania"
	return Data.sprite_tex(n)

func refresh() -> void:
	for c in party_box.get_children():
		c.queue_free()
	for b in battle.party:
		var on := b == active
		var card := UI.make_panel("panel" if on else "panel_dark")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not b.alive:
			card.modulate = Color(0.75, 0.6, 0.6)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 5)
		card.add_child(h)
		# portrait with weapon badge
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(54, 54)
		h.add_child(holder)
		var frame := Panel.new()
		var fs := StyleBoxFlat.new()
		fs.bg_color = Color(0.1, 0.14, 0.22) if on else Color(0.05, 0.07, 0.11)
		fs.border_color = Color(1.0, 0.82, 0.4) if on else Color(0.62, 0.5, 0.3)
		fs.set_border_width_all(2)
		fs.set_corner_radius_all(2)
		frame.add_theme_stylebox_override("panel", fs)
		frame.position = Vector2(0, 2)
		frame.size = Vector2(54, 54)
		holder.add_child(frame)
		var pt := TextureRect.new()
		pt.texture = portrait_tex(b)
		pt.position = Vector2(3, 5)
		pt.size = Vector2(48, 48)
		pt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pt.clip_contents = true
		if not b.alive:
			pt.modulate = Color(0.5, 0.4, 0.4)
		holder.add_child(pt)
		var wpn: String = Game.chars[b.cid]["equip"]["weapon"]
		if wpn != "":
			var badge := PanelContainer.new()
			var bs := StyleBoxFlat.new()
			bs.bg_color = Color(0.05, 0.08, 0.13)
			bs.border_color = Color(0.85, 0.68, 0.35)
			bs.set_border_width_all(1)
			bs.set_corner_radius_all(2)
			badge.add_theme_stylebox_override("panel", bs)
			badge.position = Vector2(-3, 38)
			badge.size = Vector2(20, 20)
			holder.add_child(badge)
			var wi := TextureRect.new()
			wi.texture = Data.item_icon(wpn)
			wi.custom_minimum_size = Vector2(18, 18)
			wi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			wi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			badge.add_child(wi)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var nh := HBoxContainer.new()
		v.add_child(nh)
		var nm := UI.label(b.display_name, UI.CREAM if b.alive else UI.RED, 14, true)
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nh.add_child(nm)
		var st := ""
		for sname in b.statuses:
			if Data.STATUS.has(sname):
				st += Data.STATUS[sname]["icon"]
		if not b.alive:
			st = "K.O."
		nh.add_child(UI.label(st, UI.GOLD))
		var hp_col := Color(0.32, 0.86, 0.45) if float(b.hp) / b.base["hp"] > 0.3 else Color(0.95, 0.35, 0.25)
		v.add_child(_stat_row("HP", "%d/%d" % [b.hp, b.base["hp"]]))
		v.add_child(_bar(b.hp, b.base["hp"], hp_col, 0))
		v.add_child(_stat_row("MP", str(b.mp)))
		v.add_child(_bar(b.mp, max(1, b.base["mp"]), Color(0.3, 0.55, 1.0), 0))
		party_box.add_child(card)
	for k in range(battle.party.size(), 3):
		var empty := UI.make_panel("panel_dark")
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.modulate = Color(1, 1, 1, 0.45)
		var el := UI.label("Slot %d\nfrei" % (k + 1), UI.DIM, 14, true)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		el.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_child(el)
		party_box.add_child(empty)
	for c in foe_box.get_children():
		c.queue_free()
	var any := false
	for f in battle.foes:
		if not f.alive:
			continue
		any = true
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		row.custom_minimum_size = Vector2(128, 0)
		var top := HBoxContainer.new()
		var fn := UI.label(f.display_name, Color(1, 0.78, 0.72))
		fn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(fn)
		top.add_child(UI.label("%d/%d" % [f.hp, f.base["hp"]], UI.CREAM))
		row.add_child(top)
		var r: float = float(f.hp) / f.base["hp"]
		row.add_child(_bar(f.hp, f.base["hp"], Color(0.9, 0.25, 0.2) if r > 0.3 else Color(1.0, 0.55, 0.15), 0))
		foe_box.add_child(row)
	foe_panel.visible = any
	foe_panel.reset_size()

func _stat_row(k: String, val: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	var a := UI.label(k, UI.CREAM)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(a)
	var b := UI.label(val, UI.CREAM)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(b)
	return r

func _bar(v: int, mx: int, col: Color, w: int) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.theme = UI.theme
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(w, 7)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.max_value = mx
	pb.value = v
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.05, 0.09)
	bg.border_color = Color(0.5, 0.56, 0.68)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)
	var f := StyleBoxFlat.new()
	f.bg_color = col
	f.set_corner_radius_all(2)
	f.border_color = Color(0.03, 0.05, 0.09)
	f.set_border_width_all(1)
	f.shadow_color = col.lightened(0.4)
	pb.add_theme_stylebox_override("fill", f)
	return pb

# ------------------------------------------------------------------ banners / speech
func banner(text: String, t := 0.8) -> void:
	banner_panel.visible = true
	banner_label.text = text
	await get_tree().create_timer(t).timeout
	banner_panel.visible = false

func skill_banner(text: String, friendly: bool) -> void:
	skill_lbl.text = text
	skill_lbl.add_theme_color_override("font_color", UI.GOLD if friendly else Color(1, 0.45, 0.4))
	skill_lbl.modulate.a = 0
	skill_lbl.offset_left = -340
	skill_lbl.offset_right = 260
	var tw := create_tween()
	tw.tween_property(skill_lbl, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(skill_lbl, "offset_left", -300, 0.18)
	tw.parallel().tween_property(skill_lbl, "offset_right", 300, 0.18)
	tw.tween_interval(0.75)
	tw.tween_property(skill_lbl, "modulate:a", 0.0, 0.25)

func speech(b: Battler, text: String) -> void:
	var p := UI.make_panel("panel_light")
	var l := UI.label(text, Color(0.15, 0.08, 0.05))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(150, 0)
	p.add_child(l)
	root.add_child(p)
	await get_tree().process_frame
	p.reset_size()
	var sp: Vector2 = battle.camera.unproject_position(b.top() + Vector3(0, 0.25, 0))
	var vs := root.get_viewport_rect().size
	var scale := vs / Vector2(get_viewport().get_visible_rect().size)
	sp *= scale
	p.position = Vector2(clamp(sp.x - p.size.x * 0.5, 4, vs.x - p.size.x - 4), clamp(sp.y - p.size.y, 4, vs.y - 90))
	Audio.sfx("text_blip", 0.8)
	await get_tree().create_timer(1.3 + text.length() * 0.025).timeout
	p.queue_free()

# ------------------------------------------------------------------ commands
func command(b: Battler) -> Dictionary:
	if Game.auto:
		return _auto_command(b)
	while true:
		var choice: int = await _main_menu(b)
		match choice:
			-1:
				return {"back": true}
			0:
				var t = await _select_target(b, "enemy", "attack")
				if t != null:
					return {"type": "attack", "target": t}
			1:
				var r: Dictionary = await _skill_menu(b)
				if not r.is_empty():
					return r
			2:
				var r2: Dictionary = await _item_menu(b)
				if not r2.is_empty():
					return r2
			3:
				return {"type": "defend"}
			4:
				return {"type": "flee"}
	return {}

func _main_menu(b: Battler) -> int:
	active = b
	refresh()
	_info("Was tut %s?" % b.display_name)
	for i in cmd_btns.size():
		cmd_btns[i].disabled = (i == 2 and _food_items().is_empty())
		cmd_btns[i].focus_mode = Control.FOCUS_ALL
	await get_tree().process_frame
	cmd_btns[0].grab_focus()
	_mode = "main"
	if OS.get_cmdline_user_args().has("--inputtest"):
		print("[it] menu open: main")
	var r = await _picked
	_mode = ""
	for btn in cmd_btns:
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = "  " + btn.text.substr(2)
		btn.release_focus()
	info_panel.visible = false
	Audio.sfx("ui_select" if r >= 0 else "ui_cancel")
	return r

func end_turn_highlight() -> void:
	active = null
	refresh()

func _auto_command(b: Battler) -> Dictionary:
	var opts := []
	for sid in Game.known_skills(b.cid):
		var s: Dictionary = Data.skill(sid)
		if s.get("kind", "") != "passive" and b.mp_cost(sid) <= b.mp and not b.once_used.get(sid, false):
			opts.append(sid)
	var foes := battle.foes.filter(func(x): return x.alive)
	if foes.is_empty():
		return {"type": "defend"}
	if not opts.is_empty() and randf() < 0.6:
		var sid: String = opts[randi() % opts.size()]
		var tk: String = Data.skill(sid).get("target", "enemy")
		var t = foes[0]
		if tk in ["ally", "allies", "self"]:
			t = b
		elif tk == "ko_ally":
			var ko := battle.party.filter(func(x): return not x.alive)
			if ko.is_empty():
				return {"type": "attack", "target": foes[randi() % foes.size()]}
			t = ko[0]
		return {"type": "skill", "id": sid, "target": t}
	var food := _food_items()
	var hurt := battle.party.filter(func(x): return x.alive and float(x.hp) / x.base["hp"] < 0.35)
	var dead := battle.party.filter(func(x): return not x.alive)
	if not dead.is_empty() and Game.count("f_shake") > 0:
		return {"type": "item", "id": "f_shake", "target": dead[0]}
	for heal_sid in ["glucken_segen", "wurmsuppe", "kraeuterpicken", "sanfter_riese"]:
		if heal_sid in opts and not hurt.is_empty():
			return {"type": "skill", "id": heal_sid, "target": hurt[0] if Data.skill(heal_sid)["target"] == "ally" else b}
	if not hurt.is_empty():
		for it in ["f_nasigoreng", "f_mango", "f_wurm", "f_koerner"]:
			if Game.count(it) > 0:
				return {"type": "item", "id": it, "target": hurt[0]}
	if not food.is_empty() and randf() < 0.1:
		var it: String = food[0]
		var mode := "ko_ally" if Data.ITEMS[it]["effect"].has("revive") else "ally"
		var tgt = b
		if mode == "ko_ally":
			var ko2 := battle.party.filter(func(x): return not x.alive)
			if ko2.is_empty():
				return {"type": "attack", "target": foes[0]}
			tgt = ko2[0]
		return {"type": "item", "id": it, "target": tgt}
	return {"type": "attack", "target": foes[randi() % foes.size()]}

func _food_items() -> Array:
	var out := []
	for k in Game.inventory:
		if Data.ITEMS[k]["type"] == "food":
			out.append(k)
	out.sort()
	return out

func _skill_menu(b: Battler) -> Dictionary:
	var skills: Array = []
	for sid in Game.known_skills(b.cid):
		if Data.skill(sid).get("kind", "") != "passive":
			skills.append(sid)
	var opts := []
	for sid in skills:
		var s: Dictionary = Data.skill(sid)
		var cost := b.mp_cost(sid)
		var dis: bool = cost > b.mp or b.once_used.get(sid, false)
		opts.append({"text": "%s  %d MP" % [s["name"], cost], "disabled": dis, "desc": s.get("desc", "")})
	var c: int = await _menu(opts, b, "Skill wählen")
	if c < 0:
		return {}
	var sid: String = skills[c]
	var t = await _select_target(b, Data.skill(sid).get("target", "enemy"), sid)
	if t == null:
		return await _skill_menu(b)
	return {"type": "skill", "id": sid, "target": t}

func _item_menu(b: Battler) -> Dictionary:
	var items := _food_items()
	var opts := []
	for it in items:
		opts.append({"text": "%s  ×%d" % [Data.ITEMS[it]["name"], Game.count(it)], "desc": Data.ITEMS[it]["desc"]})
	var c: int = await _menu(opts, b, "Item wählen")
	if c < 0:
		return {}
	var it: String = items[c]
	var mode := "ko_ally" if Data.ITEMS[it]["effect"].has("revive") else "ally"
	var t = await _select_target(b, mode)
	if t == null:
		return await _item_menu(b)
	return {"type": "item", "id": it, "target": t}

func _menu(opts: Array, b: Battler, info: String) -> int:
	for c in cmd_list.get_children():
		c.queue_free()
	var first: Button = null
	for i in opts.size():
		var o: Dictionary = opts[i]
		var btn := Button.new()
		btn.text = o["text"]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = o.get("disabled", false)
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(func(): _picked.emit(i))
		var desc: String = o.get("desc", "")
		btn.focus_entered.connect(func():
			Audio.sfx("ui_move", 1.0, 0.5)
			_info(desc if desc != "" else info))
		cmd_list.add_child(btn)
		if first == null and not btn.disabled:
			first = btn
	cmd_panel.visible = true
	await get_tree().process_frame
	var sc: ScrollContainer = cmd_panel.get_meta("scroll")
	var h: float = min(cmd_list.get_combined_minimum_size().y, 140.0)
	sc.custom_minimum_size = Vector2(cmd_list.get_combined_minimum_size().x + 6, h)
	cmd_panel.reset_size()
	var vs := root.get_viewport_rect().size
	cmd_panel.position = Vector2(8, vs.y - 94 - cmd_panel.size.y)
	_info(info)
	_mode = "menu"
	if OS.get_cmdline_user_args().has("--inputtest"):
		print("[it] menu open: ", opts.size(), " focus=", first)
	if first:
		first.grab_focus()
	var r = await _picked
	_mode = ""
	cmd_panel.visible = false
	info_panel.visible = false
	if r >= 0:
		Audio.sfx("ui_select")
	else:
		Audio.sfx("ui_cancel")
	return r

func _info(t: String) -> void:
	info_panel.visible = t != ""
	info_label.text = t

var _pv_actor: Battler
var _pv_sid := ""

func _select_target(b: Battler, mode: String, sid := ""):
	_pv_actor = b
	_pv_sid = sid
	var pool: Array = []
	_all = false
	match mode:
		"enemy":
			pool = battle.foes.filter(func(x): return x.alive)
		"enemies", "random_enemies":
			pool = battle.foes.filter(func(x): return x.alive)
			_all = true
		"ally":
			pool = battle.party.filter(func(x): return x.alive)
		"allies":
			pool = battle.party.filter(func(x): return x.alive)
			_all = true
		"self":
			return b
		"ko_ally":
			pool = battle.party.filter(func(x): return not x.alive)
			if pool.is_empty():
				await banner("Niemand ist K.O.", 0.6)
				return null
	if pool.is_empty():
		return null
	pool.sort_custom(func(a, c): return a.position.z < c.position.z)
	_targets = pool
	_tidx = 0
	if mode == "ally":
		_tidx = maxi(0, pool.find(b))
	_mode = "target"
	_update_arrows()
	var r = await _picked
	_mode = ""
	for a in _arrows:
		a.queue_free()
	_arrows.clear()
	info_panel.visible = false
	if r == null or (r is int and r < 0):
		Audio.sfx("ui_cancel")
		return null
	Audio.sfx("ui_select")
	return r

func _update_arrows() -> void:
	for a in _arrows:
		a.queue_free()
	_arrows.clear()
	var list: Array = _targets if _all else [_targets[_tidx]]
	for t in list:
		var l := Label3D.new()
		l.text = "▼"
		l.font = UI.font
		l.font_size = 30
		l.pixel_size = 0.012
		l.modulate = Color(1.4, 1.1, 0.4)
		l.outline_size = 8
		l.outline_modulate = Color.BLACK
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 9
		l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		battle.add_child(l)
		l.global_position = t.top() + Vector3(0, 0.15, 0.3)
		var tw := l.create_tween().set_loops()
		tw.tween_property(l, "position:y", l.position.y + 0.1, 0.25)
		tw.tween_property(l, "position:y", l.position.y, 0.25)
		_arrows.append(l)
	var est := ""
	if _pv_sid != "" and _pv_actor:
		est = battle.estimate(_pv_actor, _targets[_tidx], _pv_sid)
	if _all:
		_info("Ziel: alle" + (("   ·   " + est + " je Ziel") if est != "" else ""))
	else:
		var t: Battler = _targets[_tidx]
		var st := ""
		for s in t.statuses:
			if Data.STATUS.has(s):
				st += "  " + Data.STATUS[s]["name"]
		_info("%s   ♥ %d/%d%s%s" % [t.display_name, t.hp, t.base["hp"], st, ("   ·   " + est) if est != "" else ""])

func _unhandled_input(event: InputEvent) -> void:
	if _mode == "menu" or _mode == "main":
		if event.is_action_pressed("cancel"):
			get_viewport().set_input_as_handled()
			_picked.emit(-1)
	elif _mode == "target":
		if event.is_action_pressed("cancel"):
			get_viewport().set_input_as_handled()
			_picked.emit(null)
		elif event.is_action_pressed("accept"):
			get_viewport().set_input_as_handled()
			_picked.emit("ALL" if _all else _targets[_tidx])
		elif not _all and (event.is_action_pressed("move_up") or event.is_action_pressed("move_left")):
			get_viewport().set_input_as_handled()
			_tidx = (_tidx - 1 + _targets.size()) % _targets.size()
			Audio.sfx("ui_move")
			_update_arrows()
		elif not _all and (event.is_action_pressed("move_down") or event.is_action_pressed("move_right")):
			get_viewport().set_input_as_handled()
			_tidx = (_tidx + 1) % _targets.size()
			Audio.sfx("ui_move")
			_update_arrows()
	elif _mode == "wait":
		if event.is_action_pressed("accept"):
			get_viewport().set_input_as_handled()
			_picked.emit(0)

# ------------------------------------------------------------------ results
func results(xp: int, grains: int, drops: Array, lvls: Array) -> void:
	var p := UI.make_panel("panel")
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -150
	p.offset_right = 150
	p.offset_top = -70
	p.offset_bottom = 40
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UI.label("SIEG", UI.GOLD, 14, true))
	var share := xp
	var n := Game.active_party().filter(func(id): return Game.chars[id]["hp"] > 0).size()
	if n > 0:
		share = int(ceil(float(xp) / n))
	v.add_child(UI.label("Erfahrung: %d  (je %d pro Slot)" % [xp, share]))
	v.add_child(UI.label("Körner: +%d" % grains))
	for d in drops:
		v.add_child(UI.label("Beute: " + Data.ITEMS[d]["name"], UI.TEAL))
	for l in lvls:
		v.add_child(UI.label("▲ " + l, UI.GOLD))
	if not lvls.is_empty():
		Audio.sfx("level_up")
	v.add_child(UI.label("[E] weiter", UI.DIM))
	_mode = "wait"
	if Game.auto:
		print("  [auto] results xp=%d grains=%d lv=%s" % [xp, grains, str(lvls)])
		await get_tree().create_timer(0.1).timeout
	else:
		await _picked
	_mode = ""
	p.queue_free()

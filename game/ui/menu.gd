class_name PauseMenu
extends CanvasLayer
## Main menu: Status, Ausrüstung, Skilltree, Inventar, Team, Quests, Speichern.

signal closed

var main
var root: Control
var tabs: VBoxContainer
var content: VBoxContainer
var footer: Label
var header: Label
var _back: Array[Callable] = []
var _tab_btns: Array = []
var _cur_tab := 0

const TABS := ["Status", "Ausrüstung", "Skilltree", "Inventar", "Team", "Quests", "Speichern", "Optionen", "Schließen"]

func _ready() -> void:
	layer = 30
	UI.busy_count += 1
	UI.show_hud(false)
	UI.clear_banners()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.05, 0.6)
	root.add_child(dim)
	var tp := UI.make_panel("panel")
	tp.position = Vector2(10, 10)
	tp.custom_minimum_size = Vector2(110, 0)
	root.add_child(tp)
	tabs = VBoxContainer.new()
	tp.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_entered.connect(func(): Audio.sfx("ui_move", 1.0, 0.5); _show_tab(i, false))
		b.pressed.connect(func(): _enter_tab(i))
		tabs.add_child(b)
		_tab_btns.append(b)
	var info := UI.make_panel("panel_dark")
	info.position = Vector2(10, 0)
	info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info.offset_left = 10
	info.offset_right = 120
	info.offset_top = -64
	info.offset_bottom = -10
	root.add_child(info)
	var iv := VBoxContainer.new()
	info.add_child(iv)
	iv.add_child(UI.label("◆ %d Körner" % Game.grains, UI.GOLD))
	var pt := int(Game.playtime)
	iv.add_child(UI.label("⌚ %d:%02d" % [pt / 3600, (pt / 60) % 60], UI.DIM))
	iv.add_child(UI.label("☠ %d Menschen" % Game.kills, UI.RED))
	var cp := UI.make_panel("panel")
	cp.set_anchors_preset(Control.PRESET_FULL_RECT)
	cp.offset_left = 126
	cp.offset_top = 10
	cp.offset_right = -10
	cp.offset_bottom = -10
	root.add_child(cp)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	cp.add_child(cv)
	header = UI.label("", UI.GOLD, 14, true)
	cv.add_child(header)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	cv.add_child(sc)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	sc.add_child(content)
	footer = UI.label("", UI.CREAM)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.custom_minimum_size = Vector2(0, 22)
	cv.add_child(footer)
	Audio.sfx_any(["menu_open", "ui_select"])
	await get_tree().process_frame
	_tab_btns[0].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		Audio.sfx("ui_cancel")
		if _back.is_empty() or event.is_action_pressed("menu"):
			_close()
		else:
			var cb: Callable = _back.pop_back()
			cb.call()

func _close() -> void:
	Audio.sfx_any(["menu_close"])
	UI.busy_count = max(0, UI.busy_count - 1)
	UI.show_hud(true)
	closed.emit()

func _clear() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	footer.text = ""

func _btn(parent: Control, text: String, cb: Callable, desc := "", disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = disabled
	b.pressed.connect(func(): Audio.sfx("ui_select"); cb.call())
	b.focus_entered.connect(func(): Audio.sfx("ui_move", 1.0, 0.4); footer.text = desc)
	parent.add_child(b)
	return b

func _focus_first() -> void:
	await get_tree().process_frame
	for b in _find_buttons(content):
		if not b.disabled:
			b.grab_focus()
			return

func _find_buttons(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out += _find_buttons(c)
	return out

func _to_tabs() -> void:
	_back.clear()
	_show_tab(_cur_tab, false)
	_tab_btns[_cur_tab].grab_focus()

func _show_tab(i: int, interactive: bool) -> void:
	_cur_tab = i
	header.text = TABS[i]
	_clear()
	match i:
		0: _status()
		1: _equip_members(interactive)
		2: _skill_members(interactive)
		3: _inventory(interactive)
		4: _team(interactive)
		5: _quests()
		6: _save_tab(interactive)
		7: _options(interactive)
		8: footer.text = "Zurück auf die Insel."

func _enter_tab(i: int) -> void:
	if i == 8:
		_close()
		return
	if i in [0, 5]:
		return
	_back = [_to_tabs]
	_show_tab(i, true)
	_focus_first()

# ------------------------------------------------------------------ status
func _status() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	content.add_child(h)
	for id in Game.active_party():
		var p := UI.make_panel("panel_dark")
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(p)
		var v := VBoxContainer.new()
		p.add_child(v)
		var tex := TextureRect.new()
		var pn: String = ("p_cls_" + Game.char_class(id)) if id == "ania" else ("p_" + id)
		tex.texture = Data.sprite_tex(pn)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.custom_minimum_size = Vector2(0, 64)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(tex)
		var st := Game.stats(id)
		var cls: String = Data.CLASSES[Game.char_class(id)]["name"]
		v.add_child(UI.label(Game.char_name(id), UI.GOLD, 14, true))
		var slot := Game.slot_of(id)
		v.add_child(UI.label("%s · Lv %d" % [cls, Game.level_of(id)]))
		v.add_child(UI.label("XP %d / %d" % [Game.slot_xp[slot], Data.xp_to_next(Game.slot_level[slot])], UI.DIM))
		v.add_child(UI.label("♥ %d/%d   ✦ %d/%d" % [Game.chars[id]["hp"], st["hp"], Game.chars[id]["mp"], st["mp"]], Color(0.7, 1, 0.7)))
		v.add_child(UI.label("Angriff %d   Vert. %d" % [st["atk"], st["def"]]))
		v.add_child(UI.label("Magie %d   Res. %d" % [st["mag"], st["res"]]))
		v.add_child(UI.label("Tempo %d   Krit %d%%" % [st["spd"], st["crit"]]))
		v.add_child(UI.label("Skillpunkte frei: %d" % Game.points_free(id), UI.GOLD))
		var bio: String = "Eine Henne ohne Erinnerung. Ihr Zeiger tickt." if id == "ania" else Data.COMPANIONS[id]["bio"]
		var bl := UI.label(bio, UI.DIM)
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size = Vector2(140, 0)
		v.add_child(bl)
	var buffs := []
	for fb in Game.food_buffs:
		buffs.append("%s (%d Kämpfe)" % [Data.STATUS[fb["id"]]["name"], int(fb["battles"])])
	if not buffs.is_empty():
		content.add_child(UI.label("Essens-Buffs: " + ", ".join(buffs), UI.TEAL))

# ------------------------------------------------------------------ member picker
func _member_buttons(cb: Callable, interactive: bool) -> void:
	var h := HBoxContainer.new()
	content.add_child(h)
	for id in Game.active_party():
		var b := _btn(h, Game.char_name(id), func(): cb.call(id), "", not interactive)
		b.icon = Data.sprite_tex(Game.char_sprite(id))
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 22)

# ------------------------------------------------------------------ equipment
func _equip_members(interactive: bool) -> void:
	_member_buttons(func(id): _equip_view(id), interactive)
	footer.text = "Wähle ein Huhn."

func _equip_view(id: String) -> void:
	_clear()
	_back = [_to_tabs]
	header.text = "Ausrüstung – " + Game.char_name(id)
	var st := Game.stats(id)
	content.add_child(UI.label("Angriff %d · Vert. %d · Magie %d · Res. %d · Tempo %d · Krit %d%%" % [st["atk"], st["def"], st["mag"], st["res"], st["spd"], st["crit"]], UI.TEAL))
	var names := {"weapon": "Waffe", "armor": "Rüstung", "charm": "Talisman"}
	for slot in ["weapon", "armor", "charm"]:
		var it: String = Game.chars[id]["equip"][slot]
		var txt := "%s:  %s" % [names[slot], Data.ITEMS[it]["name"] if it != "" else "—"]
		var b := _btn(content, txt, func(): _equip_pick(id, slot), Data.ITEMS[it]["desc"] if it != "" else "Leer.")
		if it != "":
			b.icon = Data.item_icon(it)
	_focus_first()

func _equip_pick(id: String, slot: String) -> void:
	_clear()
	_back.append(func(): _equip_view(id))
	var any := false
	for it in Game.inventory:
		if Data.ITEMS[it]["type"] == slot:
			any = true
			var stxt := []
			for k in Data.ITEMS[it].get("stats", {}):
				stxt.append("%s+%d" % [k, Data.ITEMS[it]["stats"][k]])
			var b := _btn(content, "%s ×%d   %s" % [Data.ITEMS[it]["name"], Game.count(it), " ".join(stxt)],
				func(): Game.equip(id, it); Audio.sfx_any(["equip", "chest_open"]); _back.pop_back(); _equip_view(id), Data.ITEMS[it]["desc"])
			b.icon = Data.item_icon(it)
	if Game.chars[id]["equip"][slot] != "":
		_btn(content, "— ablegen —", func(): Game.unequip(id, slot); _back.pop_back(); _equip_view(id))
	if not any and Game.chars[id]["equip"][slot] == "":
		content.add_child(UI.label("Nichts Passendes im Gefieder.", UI.DIM))
	_focus_first()

# ------------------------------------------------------------------ skill tree
func _skill_members(interactive: bool) -> void:
	_member_buttons(func(id): _tree_view(id), interactive)
	footer.text = "Jede Klasse hat ihren eigenen Skilltree. Punkte hängen am Level des Team-Slots."

func _node_style(owned: bool, can: bool, focus: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.28, 0.2, 0.06, 0.95) if owned else (Color(0.08, 0.13, 0.2, 0.95) if can else Color(0.04, 0.05, 0.08, 0.9))
	st.border_color = Color(1.0, 0.82, 0.35) if owned else (Color(0.75, 0.85, 1.0) if can else Color(0.3, 0.32, 0.38))
	if focus:
		st.border_color = Color(1, 1, 1)
		st.bg_color = st.bg_color.lightened(0.15)
	st.set_border_width_all(2 if (owned or focus) else 1)
	st.set_corner_radius_all(3)
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	if owned:
		st.shadow_color = Color(1, 0.75, 0.2, 0.35)
		st.shadow_size = 3
	return st

func _tree_view(id: String, focus_sid := "") -> void:
	_clear()
	_back = [_to_tabs]
	var cls := Game.char_class(id)
	var c: Dictionary = Data.CLASSES[cls]
	header.text = "Skilltree – %s (%s)" % [Game.char_name(id), c["name"]]
	var top := HBoxContainer.new()
	content.add_child(top)
	top.add_child(UI.label("◆ Freie Punkte: %d" % Game.points_free(id), UI.GOLD, 14, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UI.label("Slot-Level %d" % Game.level_of(id), UI.DIM))
	# root node (start skill)
	var rootbox := CenterContainer.new()
	content.add_child(rootbox)
	var rs := PanelContainer.new()
	rs.add_theme_stylebox_override("panel", _node_style(true, true, false))
	rs.add_child(UI.label("★ " + Data.skill(c["start"])["name"] + "  (Start)", UI.GOLD))
	rootbox.add_child(rs)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	content.add_child(cols)
	var focus_btn: Button = null
	for br in c["branches"]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		cols.add_child(col)
		var bl := UI.label(br["name"].to_upper(), UI.GOLD, 14, true)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(bl)
		for row in 3:
			var sid: String = br["skills"][row]
			var sk: Dictionary = Data.skill(sid)
			var owned: bool = sid in Game.chars[id]["skills"]
			var can := Game.can_unlock(id, sid)
			# connector line from the node above
			var conn := CenterContainer.new()
			var line := ColorRect.new()
			line.custom_minimum_size = Vector2(2, 8)
			line.color = Color(1, 0.8, 0.35) if owned else Color(0.35, 0.38, 0.45)
			conn.add_child(line)
			col.add_child(conn)
			var b := Button.new()
			var kind := "Passiv" if sk.get("kind", "") == "passive" else ("%d MP" % sk.get("mp", 0))
			b.text = ("★ " if owned else ("◆ " if can else "· ")) + sk["name"] + "\n   %s · %d Pkt" % [kind, row + 1]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_stylebox_override("normal", _node_style(owned, can, false))
			b.add_theme_stylebox_override("disabled", _node_style(owned, can, false))
			b.add_theme_stylebox_override("pressed", _node_style(owned, can, true))
			b.add_theme_stylebox_override("hover", _node_style(owned, can, true))
			b.add_theme_stylebox_override("focus", _node_style(owned, can, true))
			b.add_theme_color_override("font_color", UI.GOLD if owned else (UI.CREAM if can else Color(0.5, 0.52, 0.58)))
			b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
			b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
			b.add_theme_constant_override("line_spacing", 0)
			var desc: String = sk["desc"] + ("" if owned else ("" if can else "  [gesperrt]"))
			b.pressed.connect(func():
				if Game.unlock(id, sid):
					Audio.sfx_any(["skill_unlock", "level_up"])
					UI.flash(Color(1, 0.85, 0.4), 0.3, 0.25)
					_tree_view(id, sid)
				else:
					Audio.sfx("ui_error"))
			b.focus_entered.connect(func(): Audio.sfx("ui_move", 1.0, 0.4); footer.text = desc)
			col.add_child(b)
			if sid == focus_sid:
				focus_btn = b
	if Game.flag("revolution") and id == "ania":
		content.add_child(UI.label("✦ Revolution: \"Der Zeiger schlägt\" freigeschaltet (+%d Bonuspunkte)" % Game.bonus_points, Color(1, 0.4, 0.35)))
	_btn(content, "Skilltree zurücksetzen", func(): Game.reset_tree(id); _tree_view(id), "Alle Punkte zurückerhalten. Kostet nichts außer Würde.")
	if focus_btn:
		await get_tree().process_frame
		focus_btn.grab_focus()
	else:
		_focus_first()

# ------------------------------------------------------------------ inventory
func _inventory(interactive: bool) -> void:
	var keys: Array = Game.inventory.keys()
	keys.sort_custom(func(a, b): return Data.ITEMS[a]["type"] + a < Data.ITEMS[b]["type"] + b)
	if keys.is_empty():
		content.add_child(UI.label("Dein Gefieder ist leer.", UI.DIM))
	var types := {"weapon": "Waffe", "armor": "Rüstung", "charm": "Talisman", "food": "Essen", "key": "Wichtig", "loot": "Wertsache"}
	for it in keys:
		var d: Dictionary = Data.ITEMS[it]
		var b := _btn(content, "%s ×%d   [%s]" % [d["name"], Game.count(it), types[d["type"]]],
			func(): if d["type"] == "food": _use_food(it), d["desc"], not interactive)
		b.icon = Data.item_icon(it)

func _use_food(it: String) -> void:
	_clear()
	header.text = "%s – an wen?" % Data.ITEMS[it]["name"]
	_back.append(func(): _show_tab(3, true); _focus_first())
	for id in Game.active_party():
		var st := Game.stats(id)
		_btn(content, "%s   ♥ %d/%d  ✦ %d/%d" % [Game.char_name(id), Game.chars[id]["hp"], st["hp"], Game.chars[id]["mp"], st["mp"]], func():
			var msg := Game.use_food(it, id)
			UI.toast(msg)
			Audio.sfx("magic_heal")
			_back.pop_back()
			_show_tab(3, true)
			_focus_first())
	_focus_first()

# ------------------------------------------------------------------ team
func _team(interactive: bool) -> void:
	content.add_child(UI.label("Max. 3 Hühner. Erfahrung wird auf alle Slots im Team aufgeteilt –", UI.DIM))
	content.add_child(UI.label("allein levelst du schneller. Wer in einen Slot kommt, übernimmt dessen Level.", UI.DIM))
	for s in 3:
		var id: String = Game.party[s]
		var txt := "Slot %d  (Lv %d):  %s" % [s + 1, Game.slot_level[s], Game.char_name(id) if id != "" else "— frei —"]
		if s == 0:
			content.add_child(UI.label(txt + "  (du)", UI.GOLD))
		else:
			_btn(content, txt, func(): _team_pick(s), "Wähle, wer diesen Slot besetzt.", not interactive)
	var bench := Game.recruited.filter(func(x): return not (x in Game.party))
	if not bench.is_empty():
		content.add_child(UI.label("Wartet am Lagerfeuer: " + ", ".join(bench.map(func(x): return Game.char_name(x))), UI.TEAL))
	if Game.recruited.is_empty():
		content.add_child(UI.label("Noch hat sich dir niemand angeschlossen. Einsamkeit ist kein angenehmer Begleiter.", UI.DIM))

func _team_pick(slot: int) -> void:
	_clear()
	_back.append(func(): _show_tab(4, true); _focus_first())
	header.text = "Slot %d besetzen" % (slot + 1)
	for id in Game.recruited:
		if Game.party[slot] == id:
			continue
		var cls: String = Data.CLASSES[Data.COMPANIONS[id]["class"]]["name"]
		var b := _btn(content, "%s (%s)%s" % [Game.char_name(id), cls, "  – im Team" if id in Game.party else ""], func():
			var msg: String = Game.set_slot(slot, id)
			if msg != "":
				UI.toast(msg)
			Audio.sfx("cluck1")
			_back.pop_back()
			_show_tab(4, true)
			_focus_first(), Data.COMPANIONS[id]["bio"])
		b.icon = Data.sprite_tex(Data.COMPANIONS[id]["sprite"])
		b.add_theme_constant_override("icon_max_width", 22)
	if Game.party[slot] != "":
		_btn(content, "%s gehen lassen" % Game.char_name(Game.party[slot]), func():
			Game.dismiss(Game.party[slot])
			Audio.sfx("cluck2", 0.8)
			_back.pop_back()
			_show_tab(4, true)
			_focus_first(), "Sie wartet am Lagerfeuer. Hühner sind nachtragend, aber geduldig.")
	_focus_first()

# ------------------------------------------------------------------ quests
func _quests() -> void:
	var ids: Array = Game.quests.keys()
	ids.sort_custom(func(a, b): return (0 if a == "main" else 1) < (0 if b == "main" else 1))
	for q in ids:
		var done: bool = Game.quest_state(q) == "done"
		var qd: Dictionary = Game.QUESTS[q]
		content.add_child(UI.label(("✔ " if done else ("★ " if qd.get("main", false) else "◆ ")) + qd["name"], UI.DIM if done else UI.GOLD))
		var l := UI.label("    " + ("Erledigt." if done else Game.quest_text(q)), UI.DIM if done else UI.CREAM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(l)

# ------------------------------------------------------------------ options
func _options(interactive: bool) -> void:
	var st: Dictionary = Game.settings
	var pct := func(v): return "%d%%" % int(round(v * 100))
	_btn(content, "Musik: %s   ◀ ▶" % pct.call(st["music"]), func(): _cycle("music"), "Enter: Lautstärke ändern", not interactive)
	_btn(content, "Effekte: %s   ◀ ▶" % pct.call(st["sfx"]), func(): _cycle("sfx"), "Enter: Lautstärke ändern", not interactive)
	_btn(content, "Tiefenschärfe: %s" % ("an" if st["dof"] else "aus"), func():
		st["dof"] = not st["dof"]
		_apply_opts(), "Der Tilt-Shift-Effekt. Wirkt ab dem nächsten Gebiet.", not interactive)
	_btn(content, "Vollbild: %s   (F11)" % ("an" if st["fullscreen"] else "aus"), func():
		st["fullscreen"] = not st["fullscreen"]
		_apply_opts(), "", not interactive)

func _cycle(k: String) -> void:
	var v: float = Game.settings[k] + 0.2
	if v > 1.01:
		v = 0.0
	Game.settings[k] = snappedf(v, 0.1)
	_apply_opts()

func _apply_opts() -> void:
	Game.apply_settings()
	Game.save_settings()
	if main and main.map and main.map.camera:
		main.map.camera.attributes = Dof.make(main.map.cam_offset.length(), 3.2, 2.4) if Game.settings["dof"] else CameraAttributesPractical.new()
	var idx := 0
	for b in _find_buttons(content):
		if b.has_focus():
			break
		idx += 1
	_show_tab(7, true)
	await get_tree().process_frame
	var bs := _find_buttons(content)
	if idx < bs.size():
		bs[idx].grab_focus()

# ------------------------------------------------------------------ save
func _save_tab(interactive: bool) -> void:
	content.add_child(UI.label("Speichert deinen Fortschritt. (Beim Betreten jedes Gebiets wird automatisch gespeichert.)", UI.DIM))
	_btn(content, "Jetzt speichern", func():
		if main and main.map and main.map.player:
			Game.map_pos = main.map.player.global_position
			Game.has_map_pos = true
		Game.save_game()
		Audio.sfx("save")
		UI.toast("Gespeichert. Der Zeiger tickt weiter."), "", not interactive)
	_btn(content, "Zum Titelbildschirm", func():
		_close()
		main.show_title.call_deferred(), "Ungespeicherter Fortschritt geht verloren.", not interactive)

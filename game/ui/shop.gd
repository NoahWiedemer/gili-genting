class_name ShopScreen
extends CanvasLayer
## Toké the gecko's black market: buy (stock grows with the story) and sell (half price).

signal closed

var list: VBoxContainer
var desc: Label
var money: Label
var tab_buy: Label
var tab_sell: Label
var selling := false

func _ready() -> void:
	layer = 30
	UI.busy_count += 1
	UI.show_hud(false)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.theme
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0.02, 0.05, 0.55)
	root.add_child(dim)
	var p := UI.make_panel("panel")
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.offset_left = -210
	p.offset_right = 210
	p.offset_top = -150
	p.offset_bottom = 140
	root.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := TextureRect.new()
	t.texture = Data.sprite_tex("gecko")
	t.custom_minimum_size = Vector2(40, 40)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(t)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(hv)
	hv.add_child(UI.label("Tokés Schwarzmarkt", UI.GOLD, 14, true))
	money = UI.label("", UI.CREAM)
	hv.add_child(money)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 14)
	v.add_child(tabs)
	tab_buy = UI.label("KAUFEN", UI.GOLD, 14, true)
	tab_sell = UI.label("VERKAUFEN", UI.DIM, 14, true)
	tabs.add_child(UI.label("◀", UI.DIM))
	tabs.add_child(tab_buy)
	tabs.add_child(tab_sell)
	tabs.add_child(UI.label("▶", UI.DIM))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 160)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	v.add_child(sc)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	desc = UI.label("", UI.DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(0, 24)
	v.add_child(desc)
	v.add_child(UI.label("[E] bestätigen   [A/D] Kaufen/Verkaufen   [Q] gehen", UI.DIM))
	_build()

func _build(focus_idx := 0) -> void:
	for c in list.get_children():
		c.queue_free()
	money.text = "Du hast %d Körner" % Game.grains
	tab_buy.add_theme_color_override("font_color", UI.DIM if selling else UI.GOLD)
	tab_sell.add_theme_color_override("font_color", UI.GOLD if selling else UI.DIM)
	var btns := []
	var items: Array = Data.shop_stock() if not selling else Game.inventory.keys()
	if selling:
		items = items.filter(func(x): return Data.sell_price(x) > 0)
		items.sort()
	for it in items:
		var d: Dictionary = Data.ITEMS[it]
		var b := Button.new()
		var owned := Game.count(it)
		if selling:
			b.text = "%s ×%d   → %d K" % [d["name"], owned, Data.sell_price(it)]
		else:
			b.text = "%s   %d K   %s" % [d["name"], d["price"], ("(hast %d)" % owned) if owned > 0 else "NEU"]
		b.icon = Data.item_icon(it)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx := btns.size()
		b.focus_entered.connect(func(): desc.text = d["desc"]; Audio.sfx("ui_move", 1.0, 0.4))
		b.pressed.connect(func(): _trade(it, idx))
		list.add_child(b)
		btns.append(b)
	if btns.is_empty():
		var l := UI.label("Nichts, was Toké haben will. \"Geh Touristen ausnehmen, dann reden wir.\"" if selling else "Ausverkauft.", UI.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(l)
		desc.text = ""
		return
	await get_tree().process_frame
	btns[clampi(focus_idx, 0, btns.size() - 1)].grab_focus()

func _trade(it: String, idx: int) -> void:
	var d: Dictionary = Data.ITEMS[it]
	if selling:
		if Game.remove_item(it):
			Game.grains += Data.sell_price(it)
			Audio.sfx_any(["sell", "coin"])
			desc.text = "Toké: \"Gebraucht, leicht blutig. Ich nehm's.\""
			_build(idx)
	elif Game.grains >= d["price"]:
		Game.grains -= d["price"]
		Game.add_item(it, 1, false)
		Audio.sfx("coin")
		_build(idx)
	else:
		Audio.sfx("ui_error")
		desc.text = "Toké: \"Keine Körner, keine Ware. So funktioniert eure Welt doch, oder?\""

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		UI.busy_count = max(0, UI.busy_count - 1)
		UI.show_hud(true)
		closed.emit()
	elif event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		get_viewport().set_input_as_handled()
		selling = not selling
		Audio.sfx("ui_move")
		_build()

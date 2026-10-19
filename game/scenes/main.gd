extends Node
## Root controller: title → creator → maps ↔ battles, menus and game over.

var map: Map
var _in_battle := false

func _ready() -> void:
	Story.main = self
	var a := OS.get_cmdline_user_args()
	if a.has("--capture"):
		_capture_after(float(a[a.find("--capture") + 1]))
	await get_tree().process_frame
	if a.has("--cs"):
		Game.new_game("Ania", "krieger")
		cutscene(a[a.find("--cs") + 1], false)
		return
	if a.has("--creator"):
		var c := CharacterCreator.new()
		add_child(c)
		UI.fade_in(0.1)
		return
	if OS.get_cmdline_user_args().has("--shot"):
		_debug_shot()
		return
	if OS.get_cmdline_user_args().has("--story"):
		_debug_story()
		return
	if OS.get_cmdline_user_args().has("--inputtest"):
		_input_test()
		return
	show_title()

func show_title() -> void:
	Audio.ambient("")
	if map:
		map.queue_free()
		map = null
	UI.show_hud(false)
	var t := TitleScreen.new()
	add_child(t)
	await UI.fade_in(0.8)
	var choice: String = await t.done
	await UI.fade_out(0.6)
	t.queue_free()
	if choice == "continue" and Game.load_game():
		goto_map(Game.map_id, "@pos" if Game.has_map_pos else Game.spawn)
	else:
		var c := CharacterCreator.new()
		add_child(c)
		await UI.fade_in(0.5)
		var res: Dictionary = await c.done
		await UI.fade_out(0.6)
		c.queue_free()
		Game.new_game(res["name"], res["class"])
		await Story.intro()
		goto_map("strand", "start")

func goto_map(id: String, spawn: String, fade := true) -> void:
	if fade:
		await UI.fade_out(0.4)
	if map:
		map.queue_free()
		await get_tree().process_frame
	Game.map_id = id
	if spawn != "@pos":
		Game.spawn = spawn
		Game.has_map_pos = false
	var def: Dictionary = Maps.get_def(id)
	map = Map.new()
	map.main = self
	add_child(map)
	map.build(id, def, spawn)
	if spawn != "@pos":
		Game.save_game()
	await get_tree().process_frame
	await UI.fade_in(0.5)
	map.start()

func battle(group: Array, opts := {}) -> String:
	_in_battle = true
	map.active = false
	UI.clear_banners()
	Audio.sfx("battle_start")
	UI.flash(Color(1, 1, 1), 0.3, 0.9)
	# swirl: quick zoom into the player
	var cam := map.camera
	var tw := create_tween()
	tw.tween_property(cam, "fov", 14.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	await UI.fade_out(0.15, Color(1, 1, 1))
	cam.fov = map.def.get("fov", 34.0)
	map.visible = false
	map.process_mode = Node.PROCESS_MODE_DISABLED
	var env_backup: Environment = map.atmos.world_env.environment
	map.atmos.world_env.environment = null
	UI.show_hud(false)
	var b := Battle.new()
	add_child(b)
	b.setup(group, opts, map.def)
	await get_tree().process_frame
	UI.fade_in(0.25)
	var r: String = await b.run()
	await UI.fade_out(0.5)
	b.queue_free()
	await get_tree().process_frame
	_in_battle = false
	if r == "lose":
		map.atmos.world_env.environment = env_backup
		await game_over()
		return "lose"
	map.atmos.world_env.environment = env_backup
	map.visible = true
	map.process_mode = Node.PROCESS_MODE_INHERIT
	map.camera.current = true
	UI.show_hud(true)
	var mus = map.def.get("music", "")
	if map.id == "hof" and Game.flag("power_off"):
		mus = ["farm_2", "farm"]
	if mus is Array:
		Audio.music_pick(mus, "map_" + map.id, 0.5)
	else:
		Audio.music(mus, 0.5)
	await UI.fade_in(0.4)
	return r

## Plays an in-engine cinematic (see story/cutscenes.gd). Leaves the screen faded out
## unless fade_back is true (then it returns to the current map).
func cutscene(scene: String, fade_back := true) -> void:
	var prev_music := Audio.current_music()
	await UI.fade_out(0.6)
	var had_map := map != null and is_instance_valid(map)
	var env_backup: Environment = null
	if had_map:
		map.active = false
		map.visible = false
		map.process_mode = Node.PROCESS_MODE_DISABLED
		env_backup = map.atmos.world_env.environment
		map.atmos.world_env.environment = null
	UI.show_hud(false)
	UI.clear_banners()
	var cs := Cutscene.new()
	add_child(cs)
	var cz := Cutscenes.new()
	await cz.call(scene, cs)
	var end_col: Color = cs.get_meta("end_color", Color.BLACK)
	await UI.fade_out(0.9, end_col)
	await UI.letterbox(false, 0.01)
	cs.queue_free()
	await get_tree().process_frame
	if had_map and is_instance_valid(map):
		map.atmos.world_env.environment = env_backup
		map.visible = true
		map.process_mode = Node.PROCESS_MODE_INHERIT
		map.camera.current = true
		if fade_back:
			Audio.music(prev_music, 1.0)
			UI.show_hud(true)
			await UI.fade_in(0.7)
			map.active = true

func game_over() -> void:
	UI.show_hud(false)
	var g := GameOverScreen.new()
	add_child(g)
	await UI.fade_in(0.8)
	var choice: String = await g.done
	await UI.fade_out(0.6)
	g.queue_free()
	if choice == "retry" and Game.load_game():
		Game.full_heal()
		goto_map(Game.map_id, "@pos" if Game.has_map_pos else Game.spawn, false)
	else:
		show_title()

func open_menu() -> void:
	var m := PauseMenu.new()
	m.main = self
	add_child(m)
	await m.closed
	m.queue_free()

func open_shop() -> void:
	var s := ShopScreen.new()
	add_child(s)
	await s.closed
	s.queue_free()

func _capture_after(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shot.png")
	print("SHOT_SAVED")
	get_tree().quit()

func _debug_shot() -> void:
	## Dev helper: godot -- --shot <map> [battle] renders a screenshot to user://shot.png
	var args := OS.get_cmdline_user_args()
	var mid: String = args[args.find("--shot") + 1] if args.size() > args.find("--shot") + 1 else "strand"
	Game.new_game("Ania", "krieger")
	if args.has("--party"):
		Game.recruit("jimmy")
		Game.recruit("vian")
	var sp := "start"
	if args.has("--spawn"):
		sp = args[args.find("--spawn") + 1]
	for f in ["mem1", "strand_intro", "dorf_intro", "steppe_intro", "klippe_intro", "hof_intro", "epilog_intro", "arena_done"]:
		Game.set_flag(f)
	if args.has("--flags"):
		for f in String(args[args.find("--flags") + 1]).split(","):
			Game.set_flag(f)
	await goto_map(mid, sp, false)
	for i in 60:
		await get_tree().process_frame
	if args.has("--menu"):
		var m := PauseMenu.new()
		m.main = self
		add_child(m)
		await get_tree().process_frame
		var tab := int(args[args.find("--menu") + 1])
		if tab == 2:
			for id in Game.active_party():
				Game.slot_level[Game.slot_of(id)] = 5
			Game.unlock("ania", "hackbeil_wirbel")
			Game.unlock("ania", "huehnerwut")
			m._tree_view("ania")
		elif tab == 1:
			Game.add_item("w_korkenzieher")
			Game.add_item("c_haizahn")
			m._equip_view("ania")
		else:
			m._show_tab(tab, true)
		for i in 20:
			await get_tree().process_frame
	if args.has("--event"):
		Story.run(args[args.find("--event") + 1], null)
		for i in 200:
			await get_tree().process_frame
	if args.has("--battle"):
		var grp: Array = ["tourist_m", "tourist_f", "crab"]
		if args.has("--boss"):
			grp = ["butcher"]
		battle(grp, {})
		for i in 320:
			await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shot.png")
	print("SHOT_SAVED ", OS.get_user_data_dir() + "/shot.png")
	get_tree().quit()

# ------------------------------------------------------------------ automated playtest (dev only)
func _wait_map(mid: String) -> void:
	var t := 0
	while not (map and is_instance_valid(map) and map.id == mid and map.active):
		await get_tree().process_frame
		t += 1
		if t > 20000:
			push_error("TIMEOUT waiting for map " + mid)
			get_tree().quit(1)
			return
	print("[story] map ready: ", mid)

func _ev(name: String, actor_id := "") -> void:
	print("[story] event ", name)
	var a = map.actor_by_id(actor_id) if actor_id != "" else null
	map.active = false
	await Story.run(name, a)
	if map and is_instance_valid(map):
		map.active = true

func _fight_enemy(eid: String) -> void:
	for e in map.enemies:
		if e.ent.get("id", "") == eid:
			print("[story] encounter ", eid)
			map.active = true
			await map.encounter(e)
			return
	push_warning("enemy not found " + eid)

func _fight_all() -> void:
	## Simulates a thorough player: fights every enemy, rests, equips gear and spends skill points.
	var n := 0
	for e in map.enemies.duplicate():
		n += 1
		var low := false
		for pid in Game.active_party():
			if Game.chars[pid]["hp"] < Game.stats(pid)["hp"] * 0.5:
				low = true
		if n % 3 == 0 or low:
			Game.full_heal()
		if is_instance_valid(e) and e.visible:
			print("[story] encounter ", e.ent.get("id", "?"), " ", e.ent["group"])
			map.active = true
			await map.encounter(e)
			_auto_manage()
	for a in map.actors.duplicate():
		if is_instance_valid(a) and a.ent.get("type", "") == "chest":
			map.active = false
			await a.interact()
	_auto_manage()
	map.active = true
	Game.full_heal()

func _auto_manage() -> void:
	for id in Game.active_party():
		for slot in ["weapon", "armor", "charm"]:
			var best := ""
			var bv := -1
			for it in Game.inventory:
				if Data.ITEMS[it]["type"] == slot:
					var v := 0
					for k in Data.ITEMS[it].get("stats", {}):
						v += Data.ITEMS[it]["stats"][k]
					if v > bv:
						bv = v
						best = it
			var cur: String = Game.chars[id]["equip"][slot]
			var cv := -1
			if cur != "":
				cv = 0
				for k in Data.ITEMS[cur].get("stats", {}):
					cv += Data.ITEMS[cur]["stats"][k]
			if best != "" and bv > cv:
				Game.equip(id, best)
		var cls := Game.char_class(id)
		for row in 3:
			for br in Data.CLASSES[cls]["branches"]:
				Game.unlock(id, br["skills"][row])
	# buy healing if rich
	while Game.grains > 150 and Game.count("f_nasigoreng") < 4:
		Game.grains -= 55
		Game.add_item("f_nasigoreng", 1, false)
	while Game.grains > 100 and Game.count("f_shake") < 3:
		Game.grains -= 60
		Game.add_item("f_shake", 1, false)

func _menu_test() -> void:
	print("[story] menu test")
	var m := PauseMenu.new()
	m.main = self
	add_child(m)
	await get_tree().process_frame
	for i in 7:
		m._show_tab(i, true)
		await get_tree().process_frame
	for id in Game.active_party():
		m._equip_view(id)
		m._equip_pick(id, "weapon")
		m._equip_pick(id, "charm")
		m._tree_view(id)
		await get_tree().process_frame
		var cls := Game.char_class(id)
		for br in Data.CLASSES[cls]["branches"]:
			Game.unlock(id, br["skills"][0])
		m._tree_view(id)
	m._team(true)
	m._team_pick(1)
	m._use_food("f_mango")
	m._inventory(true)
	m._quests()
	await get_tree().process_frame
	m._close()
	m.queue_free()
	var sh := ShopScreen.new()
	add_child(sh)
	await get_tree().process_frame
	await get_tree().process_frame
	sh.queue_free()
	UI.busy_count = 0

func _debug_story() -> void:
	var args := OS.get_cmdline_user_args()
	Engine.time_scale = 4.0
	var cls := "krieger"
	if args.has("--class"):
		cls = args[args.find("--class") + 1]
	Game.new_game("Testhuhn", cls)
	goto_map("strand", "start", false)
	await _wait_map("strand")
	await _ev("mem_pakt")
	await _ev("kura")
	for i in 5:
		Game.add_item("k_plastik", 1, false)
		await _ev("plastik")
	await _ev("kura")
	Game.auto_queue = [1]
	await _ev("kevin")
	Game.auto_queue = [0]
	await _ev("barwoman")
	await _fight_all()
	await _menu_test()
	goto_map("dorf", "from_strand")
	await _wait_map("dorf")
	await _ev("mem_sturm")
	await _fight_all()
	Game.auto_queue = [0, 1]
	await _ev("arena")
	await _ev("jimmy_wait")
	await _ev("berta")
	await _ev("morchel")
	for i in 3:
		Game.add_item("k_pilz", 1, false)
		await _ev("pilz")
	await _ev("morchel")
	await _ev("lieselotte")
	for i in 3:
		Game.add_item("k_punkt", 1, false)
		await _ev("punkt")
	await _ev("lieselotte")
	await _fight_all()
	goto_map("shakebar", "door")
	await _wait_map("shakebar")
	await _ev("nugget")
	await _fight_all()
	goto_map("steppe", "from_dorf")
	await _wait_map("steppe")
	await _ev("wanderer")
	await _ev("vian")
	await _ev("paprika")
	await _ev("brunnen")
	await _ev("kalb")
	await _ev("berta")
	await _fight_all()
	await _menu_test()
	await _ev("wolf")
	_ev("steppe_east")
	await _wait_map("void")
	_ev("heuschrecke")
	await _wait_map("klippe")
	await _fight_all()
	Game.auto_queue = [0, 1]
	_ev("klippe_edge")
	await _wait_map("hof")
	await _fight_all()
	goto_map("scheune", "door")
	await _wait_map("scheune")
	await _fight_all()
	goto_map("hof", "from_scheune")
	await _wait_map("hof")
	await _ev("strom")
	goto_map("schlachthaus", "door")
	await _wait_map("schlachthaus")
	_ev("finale")
	await _wait_map("hexenhaus")
	await _ev("witch", "witch")
	await _ev("buch")
	_ev("spiegel")
	var t := 0
	while get_children().filter(func(c): return c is TitleScreen).is_empty():
		await get_tree().process_frame
		t += 1
		if t > 30000:
			push_error("TIMEOUT waiting for ending")
			break
	print("[story] REACHED TITLE AFTER ENDING. kills=%d levels=%s party=%s recruited=%s" % [Game.kills, str(Game.slot_level), str(Game.party), str(Game.recruited)])
	get_tree().quit()

# ------------------------------------------------------------------ simulated-input test (dev only)
func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var ev2 := InputEventAction.new()
	ev2.action = action
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await get_tree().create_timer(0.08).timeout

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://it_%s.png" % name)
	print("[it] snap ", name)

func _input_test() -> void:
	Game.new_game("Ania", "assassine")
	Game.set_flag("strand_intro")
	goto_map("strand", "start", false)
	await _wait_map("strand")
	var p0 := map.player.global_position
	Input.action_press("move_right")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("move_right")
	print("[it] moved: ", p0, " -> ", map.player.global_position)
	await _snap("walk")
	# dialog with Opa Kura
	var kura = map.actor_by_id("kura")
	map.player.teleport(kura.global_position + Vector3(-0.9, 0, 0))
	map.player.facing = Vector3(1, 0, 0)
	await get_tree().create_timer(0.3).timeout
	await _press("accept")
	await get_tree().create_timer(1.2).timeout
	await _snap("dialog")
	for i in 12:
		await _press("accept")
		await get_tree().create_timer(0.4).timeout
	await _snap("choice")
	await _press("ui_accept")
	for i in 6:
		await _press("accept")
		await get_tree().create_timer(0.4).timeout
	print("[it] kura quest: ", Game.quest_state("kura"), " busy=", UI.busy_count)
	# battle via touching an enemy
	var crab = null
	for e in map.enemies:
		if e.ent.get("id") == "tour2":
			crab = e
	map.player.teleport(crab.global_position + Vector3(-0.5, 0, 0))
	var bt: Battle = null
	for i in 400:
		await get_tree().process_frame
		for c in get_children():
			if c is Battle:
				bt = c
		if bt:
			break
	print("[it] battle started: ", bt != null)
	var snapped := false
	var guard := 0
	while bt and is_instance_valid(bt) and guard < 3000:
		guard += 1
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(bt):
			break
		var m: String = bt.ui._mode
		if m == "menu" or m == "main":
			if not snapped:
				await get_tree().create_timer(0.3).timeout
				await _snap("battle_menu")
				snapped = true
			await _press("ui_accept")
		elif m == "target":
			await _press("accept")
		elif m == "wait":
			await _snap("battle_result")
			await _press("accept")
	for i in 60:
		await get_tree().process_frame
	print("[it] after battle map active: ", map.active, " lvl=", Game.slot_level)
	await get_tree().create_timer(2.5).timeout
	await _press("menu")
	await get_tree().create_timer(0.5).timeout
	await _snap("menu")
	await _press("ui_down")
	await _press("ui_down")
	await _press("ui_accept")
	await get_tree().create_timer(0.3).timeout
	await _press("ui_accept")
	await get_tree().create_timer(0.3).timeout
	await _snap("skilltree")
	await _press("cancel")
	await _press("cancel")
	await _press("cancel")
	await get_tree().create_timer(0.5).timeout
	print("[it] menu closed busy=", UI.busy_count, " active=", map.active)
	get_tree().quit()

extends Node
## Persistent game state: party, slots, inventory, quests, flags, save/load.

signal party_changed
signal inventory_changed
signal quests_changed
signal toast(text: String)

const SAVE_PATH := "user://gili_save.json"
const STATS := ["hp", "mp", "atk", "def", "mag", "res", "spd"]

var player_name := "Ania"
var player_class := "krieger"
var chars := {}            # id -> {class, hp, mp, equip:{weapon,armor,charm}, skills:[...]}
var recruited := []        # companion ids that have joined (can be swapped)
var party := ["ania", "", ""]
var slot_level := [1, 1, 1]
var slot_xp := [0, 0, 0]
var bonus_points := 0
var inventory := {}
var grains := 0
var flags := {}
var quests := {}           # id -> {"state": "active"/"done", "progress": int}
var days_left := 7
var map_id := "strand"
var spawn := "start"
var map_pos := Vector3.ZERO
var has_map_pos := false
var food_buffs := []       # [{id, battles, team}]
var killed := {}           # map_id -> [entity ids]
var playtime := 0.0
var kills := 0
var auto := false          # automated playtest mode (dev)
var god := false
var auto_queue: Array = [] # scripted dialog choices for auto mode
var settings := {"music": 0.8, "sfx": 0.9, "dof": true, "fullscreen": true}
const SETTINGS_PATH := "user://gili_settings.json"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	var args := OS.get_cmdline_user_args()
	auto = args.has("--auto")
	god = args.has("--god")
	load_settings()

func _process(delta: float) -> void:
	playtime += delta

# ------------------------------------------------------------------ input
func _setup_input() -> void:
	var map := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"accept": [KEY_ENTER, KEY_SPACE, KEY_E, KEY_KP_ENTER], "cancel": [KEY_ESCAPE, KEY_BACKSPACE, KEY_Q],
		"menu": [KEY_TAB, KEY_M, KEY_C], "run": [KEY_SHIFT], "fullscreen": [KEY_F11],
	}
	var pads := {"accept": JOY_BUTTON_A, "cancel": JOY_BUTTON_B, "menu": JOY_BUTTON_Y, "run": JOY_BUTTON_X,
		"move_up": JOY_BUTTON_DPAD_UP, "move_down": JOY_BUTTON_DPAD_DOWN, "move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.3)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		if pads.has(action):
			var jb := InputEventJoypadButton.new()
			jb.button_index = pads[action]
			InputMap.action_add_event(action, jb)
	var ui_extra := {"ui_accept": [KEY_E], "ui_up": [KEY_W], "ui_down": [KEY_S], "ui_left": [KEY_A], "ui_right": [KEY_D], "ui_cancel": [KEY_Q, KEY_BACKSPACE]}
	for action in ui_extra:
		for k in ui_extra[action]:
			var ev2 := InputEventKey.new()
			ev2.physical_keycode = k
			InputMap.action_add_event(action, ev2)
	var axes := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0]}
	for action in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axes[action][0]
		jm.axis_value = axes[action][1]
		InputMap.action_add_event(action, jm)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

# ------------------------------------------------------------------ new game
func new_game(pname: String, pclass: String) -> void:
	player_name = pname if pname.strip_edges() != "" else "Ania"
	player_class = pclass
	chars.clear()
	recruited.clear()
	party = ["ania", "", ""]
	slot_level = [1, 1, 1]
	slot_xp = [0, 0, 0]
	bonus_points = 0
	inventory = {"f_mango": 2}
	grains = 20
	flags = {}
	quests = {}
	days_left = 7
	map_id = "strand"
	spawn = "start"
	has_map_pos = false
	food_buffs = []
	killed = {}
	playtime = 0.0
	kills = 0
	_make_char("ania", pclass)
	chars["ania"]["equip"]["weapon"] = "w_zahnstocher"
	full_heal()

func _make_char(id: String, cls: String) -> void:
	chars[id] = {"class": cls, "hp": 1, "mp": 0, "equip": {"weapon": "", "armor": "", "charm": ""}, "skills": []}

# ------------------------------------------------------------------ characters
func char_name(id: String) -> String:
	if id == "ania":
		return player_name
	return Data.COMPANIONS[id]["name"]

func char_class(id: String) -> String:
	return chars[id]["class"]

func char_sprite(id: String) -> String:
	if id == "ania":
		return Data.CLASSES[player_class]["sprite"]
	return Data.COMPANIONS[id]["sprite"]

func slot_of(id: String) -> int:
	return party.find(id)

func level_of(id: String) -> int:
	var s := slot_of(id)
	return slot_level[s] if s >= 0 else slot_level[1]

func active_party() -> Array:
	var out: Array = []
	for id in party:
		if id != "":
			out.append(id)
	return out

func known_skills(id: String) -> Array:
	var cls := char_class(id)
	var out: Array = [Data.CLASSES[cls]["start"]]
	out += chars[id]["skills"]
	if id == "ania" and flags.get("revolution", false):
		out.append("revolution")
	return out

func passive(id: String, key: String) -> float:
	var v := 0.0
	for sid in known_skills(id):
		var s: Dictionary = Data.skill(sid)
		if s.get("kind", "") == "passive":
			v += float(s["passive"].get(key, 0.0))
	return v

func stats(id: String) -> Dictionary:
	var cls: Dictionary = Data.CLASSES[char_class(id)]
	var lv := level_of(id)
	var st := {}
	for k in STATS:
		st[k] = float(cls["base"][k]) + float(cls["grow"][k]) * (lv - 1)
	st["crit"] = 5.0
	for slot in chars[id]["equip"]:
		var it: String = chars[id]["equip"][slot]
		if it != "":
			for k in Data.ITEMS[it].get("stats", {}):
				st[k] = st.get(k, 0.0) + Data.ITEMS[it]["stats"][k]
	for k in ["hp", "mp", "atk", "def", "mag", "spd"]:
		st[k] *= 1.0 + passive(id, k)
	st["crit"] += passive(id, "crit") * 100.0
	for k in st:
		st[k] = int(round(st[k]))
	return st

func skill_points(id: String) -> int:
	return max(0, level_of(id) - 1 + bonus_points)

func points_spent(id: String) -> int:
	var cls := char_class(id)
	var n := 0
	for sid in chars[id]["skills"]:
		n += Data.skill_cost(cls, sid)
	return n

func points_free(id: String) -> int:
	return skill_points(id) - points_spent(id)

func can_unlock(id: String, sid: String) -> bool:
	if sid in chars[id]["skills"]:
		return false
	var cls := char_class(id)
	var req := Data.skill_req(cls, sid)
	if req != "" and not (req in chars[id]["skills"]):
		return false
	return points_free(id) >= Data.skill_cost(cls, sid)

func unlock(id: String, sid: String) -> bool:
	if not can_unlock(id, sid):
		return false
	chars[id]["skills"].append(sid)
	clamp_hp(id)
	party_changed.emit()
	return true

func reset_tree(id: String) -> void:
	chars[id]["skills"] = []
	clamp_hp(id)
	party_changed.emit()

func clamp_hp(id: String) -> void:
	var st := stats(id)
	chars[id]["hp"] = clampi(chars[id]["hp"], 0, st["hp"])
	chars[id]["mp"] = clampi(chars[id]["mp"], 0, st["mp"])

func full_heal() -> void:
	for id in chars:
		var st := stats(id) if (slot_of(id) >= 0 or id in recruited) else {}
		if st.is_empty():
			continue
		chars[id]["hp"] = st["hp"]
		chars[id]["mp"] = st["mp"]
	party_changed.emit()

# ------------------------------------------------------------------ party
func recruit(id: String) -> void:
	if id in recruited:
		return
	recruited.append(id)
	_make_char(id, Data.COMPANIONS[id]["class"])
	var free := party.find("")
	if free >= 0:
		set_slot(free, id)
	var st := stats(id)
	chars[id]["hp"] = st["hp"]
	chars[id]["mp"] = st["mp"]
	party_changed.emit()

func set_slot(slot: int, id: String) -> String:
	## Puts a companion into slot 1 or 2. Returns a message if the tree had to be reset.
	var msg := ""
	var old := party.find(id)
	if old >= 0:
		party[old] = ""
	party[slot] = id
	# a slot that is filled for the first time catches up (max. 2 levels below the leader)
	if id != "" and not flags.get("slot_used_%d" % slot, false):
		flags["slot_used_%d" % slot] = true
		var target := maxi(1, slot_level[0] - 2)
		if slot_level[slot] < target:
			slot_level[slot] = target
			slot_xp[slot] = 0
			toast.emit("Slot %d holt auf: Level %d" % [slot + 1, target])
	if id != "" and points_spent(id) > skill_points(id):
		reset_tree(id)
		msg = "%s hat zu viele Skillpunkte für diesen Slot – Skilltree zurückgesetzt." % char_name(id)
	if id != "":
		clamp_hp(id)
	party_changed.emit()
	return msg

func dismiss(id: String) -> void:
	var s := party.find(id)
	if s > 0:
		party[s] = ""
		party_changed.emit()

func add_xp(total: int) -> Array:
	## Splits XP between active (alive) party slots. Returns level-up messages.
	var members := []
	for i in 3:
		if party[i] != "" and chars[party[i]]["hp"] > 0:
			members.append(i)
	if members.is_empty():
		return []
	var share := int(ceil(float(total) / members.size()))
	var msgs := []
	for i in members:
		slot_xp[i] += share
		while slot_xp[i] >= Data.xp_to_next(slot_level[i]):
			slot_xp[i] -= Data.xp_to_next(slot_level[i])
			var before := stats(party[i])
			slot_level[i] += 1
			var after := stats(party[i])
			chars[party[i]]["hp"] += after["hp"] - before["hp"]
			chars[party[i]]["mp"] += after["mp"] - before["mp"]
			msgs.append("%s erreicht Level %d! (+1 Skillpunkt)" % [char_name(party[i]), slot_level[i]])
	party_changed.emit()
	return msgs

# ------------------------------------------------------------------ inventory
func add_item(id: String, n := 1, announce := true) -> void:
	inventory[id] = inventory.get(id, 0) + n
	inventory_changed.emit()
	if announce:
		toast.emit("Erhalten: %s%s" % [Data.ITEMS[id]["name"], (" ×%d" % n) if n > 1 else ""])

func remove_item(id: String, n := 1) -> bool:
	if inventory.get(id, 0) < n:
		return false
	inventory[id] -= n
	if inventory[id] <= 0:
		inventory.erase(id)
	inventory_changed.emit()
	return true

func count(id: String) -> int:
	return inventory.get(id, 0)

func add_grains(n: int, announce := true) -> void:
	grains = max(0, grains + n)
	inventory_changed.emit()
	if announce and n > 0:
		toast.emit("+%d Körner" % n)

func equip(id: String, item: String) -> void:
	var slot: String = Data.ITEMS[item]["type"]
	var cur: String = chars[id]["equip"][slot]
	if not remove_item(item, 1):
		return
	if cur != "":
		add_item(cur, 1, false)
	chars[id]["equip"][slot] = item
	clamp_hp(id)
	party_changed.emit()

func unequip(id: String, slot: String) -> void:
	var cur: String = chars[id]["equip"][slot]
	if cur == "":
		return
	chars[id]["equip"][slot] = ""
	add_item(cur, 1, false)
	clamp_hp(id)
	party_changed.emit()

func use_food(item: String, target: String) -> String:
	## Uses a food item outside of battle. Returns a message.
	var e: Dictionary = Data.ITEMS[item]["effect"]
	var c: Dictionary = chars[target]
	var st := stats(target)
	if e.has("revive"):
		if c["hp"] > 0:
			return "%s ist nicht K.O." % char_name(target)
		c["hp"] = int(st["hp"] * e["revive"])
	elif c["hp"] <= 0:
		return "%s ist K.O. – dafür braucht es einen Shake." % char_name(target)
	if e.has("hp"):
		c["hp"] = min(st["hp"], c["hp"] + e["hp"])
	if e.has("mp"):
		c["mp"] = min(st["mp"], c["mp"] + e["mp"])
	if e.has("buff"):
		food_buffs.append({"id": e["buff"], "battles": e["battles"], "team": e.get("team", false), "who": target})
	remove_item(item)
	party_changed.emit()
	return "%s: %s benutzt." % [char_name(target), Data.ITEMS[item]["name"]]

# ------------------------------------------------------------------ quests
const QUESTS := {
	"main": {"name": "Die Schlachtzeit", "main": true, "steps": [
		"Finde heraus, wer du bist.",
		"Folge dem Pfad ins Dorf im Inselinneren.",
		"Finde einen Weg durch das Dorf der Verbannten.",
		"Durchquere die verlassene Steppe nach Osten.",
		"Erreiche die Klippe der Aussichtslosen.",
		"Der Zeiger schlägt auf Revolution. Zum Hof von Bauer Made.",
		"Kappe den Strom. Dann: der Schlachter.",
		"Es ist vorbei. Oder?"]},
	"kura": {"name": "Opa Kuras Strand", "steps": ["Sammle 5× Plastikmüll am Strand für Opa Kura.", "Bring den Müll zu Opa Kura."]},
	"kalb": {"name": "Muttermilch", "steps": ["Finde Klößchen, das Kalb von Kuh Berta.", "Bring Klößchens Glocke zu Berta."]},
	"pilz": {"name": "Pilzfreunde", "steps": ["Finde die 3 Freunde von Herrn Morchel im Dorf.", "Kehre zu Herrn Morchel zurück."]},
	"punkte": {"name": "Lieselottes Punkte", "steps": ["Finde die 3 verlorenen Punkte von Marienkäfer Lieselotte.", "Bring Lieselotte ihre Punkte."]},
	"hai": {"name": "Ein toter Hai", "steps": ["Irgendwo in der Steppe soll es einen Brunnen geben ...", "Erledigt."]},
}

func quest_state(id: String) -> String:
	return quests.get(id, {}).get("state", "")

func quest_step(id: String) -> int:
	return quests.get(id, {}).get("progress", 0)

func start_quest(id: String) -> void:
	if quests.has(id):
		return
	quests[id] = {"state": "active", "progress": 0}
	quests_changed.emit()
	if not QUESTS[id].get("main", false):
		toast.emit("Neue Nebenquest: %s" % QUESTS[id]["name"])
		Audio.sfx("quest")

func set_step(id: String, step: int) -> void:
	if not quests.has(id):
		quests[id] = {"state": "active", "progress": 0}
	quests[id]["progress"] = step
	quests_changed.emit()

func complete_quest(id: String) -> void:
	if not quests.has(id):
		quests[id] = {"state": "active", "progress": 0}
	quests[id]["state"] = "done"
	quests[id]["progress"] = QUESTS[id]["steps"].size() - 1
	quests_changed.emit()
	toast.emit("Quest abgeschlossen: %s" % QUESTS[id]["name"])
	Audio.sfx("item_get")

func quest_text(id: String) -> String:
	var steps: Array = QUESTS[id]["steps"]
	return steps[clampi(quest_step(id), 0, steps.size() - 1)]

func flag(k: String) -> bool:
	return flags.get(k, false)

func set_flag(k: String, v = true) -> void:
	flags[k] = v

func mark_killed(map: String, eid: String) -> void:
	if not killed.has(map):
		killed[map] = []
	if not (eid in killed[map]):
		killed[map].append(eid)

func is_killed(map: String, eid: String) -> bool:
	return eid in killed.get(map, [])

# ------------------------------------------------------------------ settings
func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				settings[k] = d[k]
	apply_settings()

func save_settings() -> void:
	FileAccess.open(SETTINGS_PATH, FileAccess.WRITE).store_string(JSON.stringify(settings))

func apply_settings() -> void:
	Audio.music_volume = settings["music"]
	Audio.sfx_volume = settings["sfx"]
	Audio.refresh_volume()
	if not auto and OS.get_cmdline_user_args().is_empty():
		get_window().mode = Window.MODE_FULLSCREEN if settings["fullscreen"] else Window.MODE_WINDOWED

# ------------------------------------------------------------------ save/load
func save_game() -> void:
	var d := {
		"player_name": player_name, "player_class": player_class, "chars": chars, "recruited": recruited,
		"party": party, "slot_level": slot_level, "slot_xp": slot_xp, "bonus_points": bonus_points,
		"inventory": inventory, "grains": grains, "flags": flags, "quests": quests, "days_left": days_left,
		"map_id": map_id, "spawn": spawn, "map_pos": [map_pos.x, map_pos.y, map_pos.z], "has_map_pos": has_map_pos,
		"food_buffs": food_buffs, "killed": killed, "playtime": playtime, "kills": kills,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func load_game() -> bool:
	if not has_save():
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	player_name = d["player_name"]
	player_class = d["player_class"]
	chars = d["chars"]
	for id in chars:
		chars[id]["hp"] = int(chars[id]["hp"])
		chars[id]["mp"] = int(chars[id]["mp"])
	recruited = d["recruited"]
	party = d["party"]
	slot_level = d["slot_level"].map(func(x): return int(x))
	slot_xp = d["slot_xp"].map(func(x): return int(x))
	bonus_points = int(d["bonus_points"])
	inventory = {}
	for k in d["inventory"]:
		inventory[k] = int(d["inventory"][k])
	grains = int(d["grains"])
	flags = d["flags"]
	quests = d["quests"]
	for q in quests:
		quests[q]["progress"] = int(quests[q]["progress"])
	days_left = int(d["days_left"])
	map_id = d["map_id"]
	spawn = d["spawn"]
	var mp: Array = d["map_pos"]
	map_pos = Vector3(mp[0], mp[1], mp[2])
	has_map_pos = d["has_map_pos"]
	food_buffs = d["food_buffs"]
	killed = d["killed"]
	playtime = d["playtime"]
	kills = int(d.get("kills", 0))
	return true

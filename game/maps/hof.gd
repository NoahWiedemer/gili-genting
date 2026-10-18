extends RefCounted
## Kapitel 5: Vollmond über dem Hof von Bauer Made.

static func def() -> Dictionary:
	var p := Painter.new(60, 44, "\"", 55)
	p.forest_edge("T", 2.5)
	p.scatter(3, 3, 54, 38, "g", 0.08, "\"")
	p.scatter(3, 3, 54, 38, "b", 0.02, "\"", 2)
	# fields
	p.rect(5, 26, 16, 11, "%")
	p.rect(38, 26, 16, 11, "%")
	p.scatter(5, 26, 16, 11, "S", 0.02, "%", 4)
	p.scatter(38, 26, 16, 11, "S", 0.02, "%", 4)
	# yard
	p.rect(14, 6, 32, 16, ":")
	p.path([Vector2(30, 44), Vector2(30, 21)], ":", 3)
	p.path([Vector2(14, 14), Vector2(8, 14)], ":", 2)
	# fences around the yard
	for x in range(13, 47):
		if x < 28 or x > 32:
			p.setc(x, 22, "F")
	# lamp posts
	for q in [Vector2i(27, 23), Vector2i(33, 23), Vector2i(20, 14), Vector2i(40, 14), Vector2i(30, 9), Vector2i(36, 18), Vector2i(24, 18)]:
		p.setc(q.x, q.y, "l")
	p.setc(44, 8, "x")
	p.setc(45, 8, "k")
	p.setc(16, 19, "k")
	for q in [Vector2i(30, 41), Vector2i(38, 17), Vector2i(30, 19)]:
		p.rect(q.x - 1, q.y - 1, 3, 3, ":")
	return {
		"name": "Hof von Bauer Made",
		"music": "farm", "ambient": "night_loop", "env": "moon", "night": true, "power_lights": true,
		"weather": ["fireflies", "wind"],
		"rows": p.rows(),
		"on_enter": "hof_enter",
		"battle": {"ground": "dirt_path", "props": ["scarecrow", "fence", "jungle_tree", "haybale"], "backdrop": "bd_farm", "horizon": 0.85,
			"detail": ["haybale", "milkcans", "cages", "wheelbarrow", "feed_sacks", "chopping_block", "trough"], "decals": ["g_straw", "g_pebbles", "g_stain"]},
		"backdrop": "bd_farm",
		"decor": [
			{"sprites": ["haybale", "feed_sacks", "milkcans", "wheelbarrow", "trough"], "on": ":", "density": 0.018, "rect": [14, 6, 32, 15]},
			{"sprites": ["hibiscus", "bougainvillea", "fern", "bird_paradise", "monstera", "yellow_shrub", "orchids", "banana_small"], "on": "\"", "density": 0.03, "sway": 0.05},
		],
		"decals": [{"sprites": ["g_straw", "g_pebbles", "g_stain", "g_stones"], "on": ":", "density": 0.1}, {"sprites": ["g_flowers_w", "g_flowers_r", "g_clover", "g_leaves", "g_frangi"], "on": "\"", "density": 0.13}],
		"spawns": {"start": [30, 41, 0, -1], "from_scheune": [19, 13, 0, 1], "from_schlacht": [37, 17, 0, 1]},
		"entities": [
			{"type": "house", "x": 16, "z": 9, "w": 6, "d": 4, "style": "barn", "to": "scheune", "spawn": "door", "door": 18, "lit": false},
			{"type": "house", "x": 34, "z": 12, "w": 7, "d": 4, "style": "slaughter", "to": "schlachthaus", "spawn": "door", "door": 37, "sign": "SCHLACHTHAUS",
				"locked": "power_off", "locked_text": "Abgeschlossen. Durch das Fenster: Haken. Ketten. Licht. Erst der Strom."},
			{"type": "house", "x": 24, "z": 6, "w": 6, "d": 3, "style": "plaster", "door": 26},
			{"type": "prop", "id": "powerbox", "sprite": "powerbox", "x": 42, "z": 17, "event": "strom", "block": true, "marker": "!"},
			{"type": "light", "x": 37, "z": 16, "y": 2.2, "color": "ff3030", "energy": 3.0, "range": 6.0, "power": true},
			{"type": "light", "x": 42, "z": 18, "y": 1.2, "color": "80c0ff", "energy": 1.5, "range": 3.0, "power": true},
			{"type": "fire", "x": 33, "z": 33},
			{"type": "npc", "id": "liese", "sprite": "ladybug", "x": 9, "z": 22, "event": "lieselotte", "quest": "punkte"},
			{"type": "pickup", "id": "punkt1", "x": 7, "z": 33, "item": "k_punkt", "event": "punkt"},
			{"type": "pickup", "id": "punkt2", "x": 49, "z": 29, "item": "k_punkt", "event": "punkt"},
			{"type": "pickup", "id": "punkt3", "x": 26, "z": 4, "item": "k_punkt", "event": "punkt"},
			{"type": "prop", "sprite": "farm_sign", "x": 28, "z": 38, "lines": [["Schild", "HOF MADE – Frische Eier · Frisches Fleisch · Frisch geschlachtet. Seit 1987."]]},
			{"type": "prop", "sprite": "tractor", "x": 44, "z": 16, "block": true, "block_size": 1.5},
			{"type": "prop", "sprite": "cages", "x": 33, "z": 17, "block": true, "lines": [["Hühner in Käfigen", "Lass uns raus ... bitte ... Nicht mal einen halben Quadratmeter ..."]]},
			{"type": "prop", "sprite": "cages", "x": 32, "z": 17, "flip": true, "block": true},
			{"type": "prop", "sprite": "chopping_block", "x": 41, "z": 19},
			{"type": "prop", "sprite": "knife_rack", "x": 35, "z": 17},
			{"type": "prop", "sprite": "red_lamp", "x": 39, "z": 17, "power": true},
			{"type": "prop", "sprite": "haybale", "x": 15, "z": 14, "block": true},
			{"type": "prop", "sprite": "weathervane", "x": 22, "z": 9},
			{"type": "prop", "sprite": "firewood", "x": 30, "z": 7},
			{"type": "prop", "sprite": "bird_cage", "x": 34, "z": 19, "lines": [["Küken im Käfig", "Piep. (Es hat Angst. Noch.)"]]},
			{"type": "prop", "sprite": "slaughter_table", "x": 39, "z": 19, "block": true},
			# the revolution arrives once the lights are out
			{"type": "npc", "id": "army1", "sprite": "cls_base", "x": 28, "z": 25, "event": "army", "if": "power_off"},
			{"type": "npc", "id": "army2", "sprite": "chick", "x": 31, "z": 26, "event": "army", "if": "power_off"},
			{"type": "npc", "id": "army3", "sprite": "cls_assassine", "x": 33, "z": 21, "event": "army", "if": "power_off", "flip": true},
			{"type": "npc", "id": "army4", "sprite": "cls_krieger", "x": 25, "z": 20, "event": "army", "if": "power_off"},
			{"type": "npc", "id": "army5", "sprite": "cls_tank", "x": 21, "z": 20, "event": "army", "if": "power_off"},
			{"type": "npc", "id": "army6", "sprite": "chick", "x": 35, "z": 20, "event": "army", "if": "power_off", "flip": true},
			{"type": "npc", "id": "army7", "sprite": "cls_magier", "x": 40, "z": 20, "event": "army", "if": "power_off", "flip": true},
			# enemies
			{"type": "enemy", "id": "h_hand1", "x": 22, "z": 16, "group": ["farmhand", "nightdog"], "radius": 2.5},
			{"type": "enemy", "id": "h_hand2", "x": 38, "z": 9, "group": ["farmhand", "farmhand"], "radius": 2.5},
			{"type": "enemy", "id": "h_dog1", "x": 30, "z": 30, "group": ["nightdog", "nightdog"], "radius": 3.0, "chase": 4.0},
			{"type": "enemy", "id": "h_dog2", "x": 12, "z": 31, "group": ["nightdog", "farmhand"], "radius": 3.0},
			{"type": "chest", "id": "h1", "x": 8, "z": 14, "items": {"f_sambal": 1}},
			{"type": "chest", "id": "h2", "x": 52, "z": 38, "items": {}, "grains": 60},
		],
	}

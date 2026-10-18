extends RefCounted
## Kapitel 2: Das Dorf der Verbannten – in der Abenddämmerung.

static func def() -> Dictionary:
	var p := Painter.new(62, 46, "\"", 21)
	p.forest_edge("T", 2.8)
	p.scatter(3, 3, 56, 40, "T", 0.018, "\"", 3)
	p.scatter(3, 3, 56, 40, "b", 0.03, "\"", 1)
	p.scatter(3, 3, 56, 40, "f", 0.02, "\"", 2)
	p.scatter(3, 3, 56, 40, "g", 0.08, "\"")
	# plaza + paths
	p.circle(30, 23, 5.5, "o", 0.6)
	p.path([Vector2(30, 46), Vector2(30, 27)], ":", 3)
	p.path([Vector2(30, 18), Vector2(30, 13)], ":", 3)
	p.path([Vector2(25, 23), Vector2(4, 22)], ":", 2)
	p.path([Vector2(35, 23), Vector2(62, 22)], ":", 3)
	p.path([Vector2(10, 22), Vector2(10, 18)], ":", 2)
	p.path([Vector2(40, 23), Vector2(41, 33)], ":", 2)
	p.path([Vector2(46, 22), Vector2(48, 13)], ":", 2)
	p.path([Vector2(16, 22), Vector2(16, 33)], ":", 2)
	p.path([Vector2(22, 22), Vector2(22, 11)], ":", 2)
	# arena (north)
	p.rect(25, 5, 11, 8, ":")
	for x in range(25, 36):
		p.setc(x, 5, "F")
		if x < 29 or x > 31:
			p.setc(x, 12, "F")
	for z in range(5, 13):
		p.setc(25, z, "F")
		p.setc(35, z, "F")
	# cow paddock (south-east)
	p.rect(45, 34, 10, 7, "\"")
	for x in range(45, 55):
		p.setc(x, 34, "F")
		p.setc(x, 40, "F")
	for z in range(34, 41):
		p.setc(45, z, "F")
		if z != 37:
			p.setc(54, z, "F")
	p.rect(46, 35, 8, 5, "%")
	# market (west of plaza)
	p.rect(18, 24, 5, 4, "o")
	p.setc(18, 24, "x")
	p.setc(19, 24, "k")
	p.setc(22, 24, "x")
	# lanterns
	for q in [Vector2i(27, 17), Vector2i(33, 17), Vector2i(26, 29), Vector2i(34, 29), Vector2i(28, 36), Vector2i(32, 40),
			Vector2i(12, 21), Vector2i(42, 21), Vector2i(52, 21), Vector2i(24, 13), Vector2i(36, 13), Vector2i(43, 30), Vector2i(18, 31)]:
		p.setc(q.x, q.y, "l")
	# keep spots clear
	for q in [Vector2i(30, 43), Vector2i(60, 22), Vector2i(4, 39), Vector2i(55, 16), Vector2i(44, 14), Vector2i(20, 26), Vector2i(57, 40), Vector2i(6, 32), Vector2i(12, 24), Vector2i(33, 38), Vector2i(49, 20)]:
		p.rect(q.x - 1, q.y - 1, 3, 3, "\"" if p.getc(q.x, q.y) != ":" else ":")
	return {
		"name": "Dorf der Verbannten",
		"music": ["village", "village_2"], "ambient": "night_loop", "env": "dusk", "night": true,
		"weather": ["fireflies", "petals"],
		"rows": p.rows(),
		"on_enter": "dorf_enter",
		"battle": {"ground": "dirt_path", "props": ["jungle_tree", "banana_tree", "lantern", "palm", "stall"], "lights": [[-4, 1.5, -2, "ffa050", 2.5], [5, 1.5, -2, "ffa050", 2.5]],
			"backdrop": "bd_village", "horizon": 0.85, "detail": ["pots", "banana_small", "bench", "canang", "hibiscus", "coop", "rice_sacks"], "decals": ["g_pebbles", "g_frangi", "g_leaves"]},
		"decor": [
			{"sprites": ["hibiscus", "bougainvillea", "fern", "bird_paradise", "monstera", "yellow_shrub", "orchids", "banana_small"], "on": "\"", "density": 0.045, "sway": 0.06},
			{"sprites": ["canang", "pots"], "on": "o", "density": 0.04},
		],
		"decals": [{"sprites": ["g_flowers_w", "g_flowers_r", "g_clover", "g_leaves", "g_frangi"], "on": "\"", "density": 0.13}, {"sprites": ["g_pebbles", "g_stones", "g_frangi", "g_leaves"], "on": ":o", "density": 0.09}],
		"spawns": {"start": [30, 43, 0, -1], "from_strand": [30, 43, 0, -1], "from_steppe": [59, 22, -1, 0],
			"from_fischer": [10, 18, 0, 1], "from_shake": [41, 34, 0, 1], "from_hexe": [48, 12, 0, 1], "from_keller": [38, 23, 0, 1]},
		"entities": [
			# houses
			{"type": "house", "x": 8, "z": 14, "w": 5, "d": 3, "style": "wood", "to": "fischerhaus", "spawn": "door", "door": 10},
			{"type": "house", "x": 38, "z": 30, "w": 6, "d": 3, "style": "bamboo", "to": "shakebar", "spawn": "door", "door": 41, "sign": "MAGIC SHAKES"},
			{"type": "house", "x": 46, "z": 8, "w": 5, "d": 3, "style": "plaster", "to": "hexenhaus", "spawn": "start", "door": 48, "locked": "epilog_open", "locked_text": "Die Tür ist verschlossen. Es riecht nach Räucherstäbchen und ... Zukunft?"},
			{"type": "house", "x": 13, "z": 30, "w": 5, "d": 3, "style": "bamboo", "door": 15},
			{"type": "house", "x": 19, "z": 7, "w": 4, "d": 3, "style": "wood", "door": 21},
			{"type": "house", "x": 38, "z": 9, "w": 4, "d": 3, "style": "bamboo", "door": 39},
			{"type": "house", "x": 50, "z": 25, "w": 5, "d": 3, "style": "wood", "door": 52},
			{"type": "house", "x": 4, "z": 26, "w": 4, "d": 3, "style": "bamboo", "door": 5},
			{"type": "house", "x": 23, "z": 35, "w": 4, "d": 3, "style": "plaster", "door": 24},
			# plaza & village life
			{"type": "fire", "x": 30, "z": 23},
			{"type": "prop", "sprite": "shrine", "x": 33, "z": 19, "block": true, "event": "shrine"},
			# puzzle: three lanterns -> the witch's cellar under the old well
			{"type": "switch", "id": "lt_markt", "x": 23, "z": 21, "key": "markt", "symbol": "◆", "puzzle": "laternen", "order": ["markt", "ruhe", "schrein"], "event": "switch", "sprite": "lantern", "color": "ffb050", "fail_text": "Alle Laternen verlöschen wieder. Irgendwo kichert ein Gecko.", "open_text": "Aus Richtung des alten Brunnens klirrt Metall."},
			{"type": "switch", "id": "lt_ruhe", "x": 28, "z": 26, "key": "ruhe", "symbol": "✚", "puzzle": "laternen", "order": ["markt", "ruhe", "schrein"], "event": "switch", "sprite": "lantern", "color": "ffb050", "fail_text": "Alle Laternen verlöschen wieder. Irgendwo kichert ein Gecko.", "open_text": "Aus Richtung des alten Brunnens klirrt Metall."},
			{"type": "switch", "id": "lt_schrein", "x": 35, "z": 19, "key": "schrein", "symbol": "✦", "puzzle": "laternen", "order": ["markt", "ruhe", "schrein"], "event": "switch", "sprite": "lantern", "color": "ffb050", "fail_text": "Alle Laternen verlöschen wieder. Irgendwo kichert ein Gecko.", "open_text": "Aus Richtung des alten Brunnens klirrt Metall."},
			{"type": "prop", "sprite": "wall_piece", "x": 31, "z": 18, "event": "schrein_tafel", "block": true},
			{"type": "prop", "sprite": "well", "x": 38, "z": 21, "event": "dorfbrunnen", "block": true, "block_size": 1.0},
			{"type": "prop", "sprite": "stall", "x": 21, "z": 23, "block": true, "block_size": 1.2},
			{"type": "prop", "sprite": "stall", "x": 18, "z": 27, "flip": true, "block": true, "block_size": 1.2},
			{"type": "prop", "sprite": "rice_sacks", "x": 23, "z": 26},
			{"type": "prop", "sprite": "cidomo", "x": 36, "z": 24, "block": true, "block_size": 1.4, "lines": [["", "Ein Cidomo. Auf Gili gibt es keine Autos. Nur Pferde, die genauso müde aussehen wie Berta."]]},
			{"type": "prop", "sprite": "laundry", "x": 9, "z": 18},
			{"type": "prop", "sprite": "coop", "x": 14, "z": 34, "block": true, "lines": [["Hühner im Stall", "Bwok? ... Bwok. (Sie starren dich an, als wüssten sie etwas, das du noch nicht weißt.)"]]},
			{"type": "prop", "sprite": "banana_tree", "x": 6, "z": 13, "sway": 0.1},
			{"type": "prop", "sprite": "banana_tree", "x": 44, "z": 29, "sway": 0.1},
			{"type": "prop", "sprite": "banana_tree", "x": 26, "z": 33, "sway": 0.1},
			{"type": "prop", "sprite": "bicycle", "x": 22, "z": 38},
			{"type": "prop", "sprite": "pots", "x": 37, "z": 33},
			{"type": "prop", "sprite": "lantern_string", "x": 27, "z": 27},
			{"type": "light", "x": 27, "z": 27, "y": 1.8, "color": "ffb060", "energy": 1.6, "range": 4.0, "flicker": true},
			{"type": "prop", "sprite": "lantern_string", "x": 34, "z": 28, "flip": true},
			{"type": "light", "x": 34, "z": 28, "y": 1.8, "color": "ff8060", "energy": 1.6, "range": 4.0, "flicker": true},
			{"type": "prop", "sprite": "bench", "x": 27, "z": 21},
			{"type": "prop", "sprite": "notice_board", "x": 25, "z": 19, "block": true, "lines": [["Aushang", "GESUCHT: Huhn, weiß, ca. 2 kg. Antwortet auf den Namen „Ania“. Belohnung: 1 Grillabend. – Bauer Made"], ["", "Darunter, in krakeliger Kinderschrift: „Hühner haben auch Gefühle“. Jemand hat es durchgestrichen."]]},
			{"type": "prop", "sprite": "scooter", "x": 44, "z": 24, "lines": [["", "Ein kaputter Roller. Auf Gili sind Motorfahrzeuge verboten. Jemand hat das auf die harte Tour gelernt."]]},
			{"type": "prop", "sprite": "trash_bags", "x": 12, "z": 28},
			{"type": "prop", "sprite": "firewood", "x": 7, "z": 18},
			{"type": "prop", "sprite": "water_jar", "x": 21, "z": 11},
			{"type": "prop", "sprite": "canang", "x": 32, "z": 20},
			{"type": "npc", "id": "jimmy_camp", "sprite": "jimmy", "x": 32, "z": 24, "event": "jimmy_wait", "if": "jimmy_waiting", "flip": true},
			{"type": "stone", "id": "mem2", "x": 44, "z": 14, "event": "mem_sturm"},
			{"type": "npc", "id": "toke", "sprite": "gecko", "x": 20, "z": 26, "event": "toke", "marker": "◆"},
			{"type": "npc", "id": "wayan2", "sprite": "warung_woman", "x": 34, "z": 26, "event": "villager", "flip": true},
			# arena
			{"type": "npc", "id": "jimmy_cage", "sprite": "jimmy", "x": 30, "z": 7, "unless": "arena_done", "lines": [["Jimmy", "..."]]},
			{"type": "npc", "id": "benny", "sprite": "bookie", "x": 27, "z": 9, "unless": "arena_done", "event": "arena", "flip": false, "story_flag": "arena_done"},
			{"type": "npc", "id": "arena_guard", "sprite": "guard", "x": 33, "z": 9, "unless": "arena_done", "event": "arena", "flip": true},
			{"type": "trigger", "id": "arena_t", "x": 28, "z": 11, "w": 5, "d": 3, "event": "arena", "unless": "arena_done", "once": false},
			# side quests
			{"type": "npc", "id": "berta", "sprite": "cow", "x": 48, "z": 37, "event": "berta", "quest": "kalb"},
			{"type": "npc", "id": "kloesschen", "sprite": "calf", "x": 51, "z": 38, "if": "kalb_home", "lines": [["Klößchen", "Mama sagt, du bist doch kein dummes Huhn. Nur ein bisschen."]]},
			{"type": "npc", "id": "morchel", "sprite": "mushroom", "x": 4, "z": 39, "event": "morchel", "quest": "pilz"},
			{"type": "pickup", "id": "pilz_markt", "x": 21, "z": 27, "item": "k_pilz", "event": "pilz"},
			{"type": "chest", "id": "dorf1", "x": 6, "z": 32, "items": {"f_mango": 2}, "grains": 20},
			{"type": "chest", "id": "dorf2", "x": 57, "z": 40, "items": {"a_sarong": 1}},
			# enemies
			{"type": "enemy", "id": "d_farm1", "x": 15, "z": 21, "group": ["farmer"], "radius": 2.5},
			{"type": "enemy", "id": "d_dog1", "x": 44, "z": 27, "group": ["dog"], "radius": 3.0, "chase": 3.6},
			{"type": "enemy", "id": "d_tour1", "x": 37, "z": 38, "group": ["tourist_f", "tourist_f"], "radius": 2.0},
			{"type": "enemy", "id": "d_guard1", "x": 53, "z": 13, "group": ["guard", "fisher"], "radius": 2.0},
			{"type": "enemy", "id": "d_gate", "x": 56, "z": 22, "group": ["guard", "dog"], "radius": 1.0, "aggro": 2.5, "if": "arena_done"},
			# exits
			{"type": "warp", "x": 27, "z": 45, "w": 7, "d": 1, "to": "strand", "spawn": "from_dorf"},
			{"type": "trigger", "id": "east_block", "x": 58, "z": 19, "w": 2, "d": 7, "event": "dorf_east", "unless": "arena_done", "once": false},
			{"type": "warp", "x": 61, "z": 19, "w": 1, "d": 7, "to": "steppe", "spawn": "from_dorf", "if": "arena_done"},
		],
	}

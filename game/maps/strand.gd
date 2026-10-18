extends RefCounted
## Kapitel 1: Der Strand von Gili Genting – nach dem Sturm.

static func def() -> Dictionary:
	var p := Painter.new(62, 34, "\"", 7)
	p.coast_south(12.5, 1.4, [[".", 1]])
	p.coast_south(23.0, 1.5, [[",", 1], ["-", 2], ["~", 1]])
	p.forest_edge("T", 3.2, "\"")
	p.scatter(0, 4, 62, 8, "T", 0.05, "\"", 2)
	p.scatter(0, 4, 62, 9, "b", 0.05, "\"", 1)
	p.scatter(0, 4, 62, 9, "f", 0.035, "\"", 2)
	p.scatter(0, 4, 62, 10, "g", 0.10, "\"")
	# rocks framing the beach
	p.circle(1.5, 20, 3.2, "R", 0.8)
	p.circle(2.5, 26, 2.5, "#", 0.5)
	p.rect(51, 11, 3, 13, "R")
	p.circle(52, 15, 2.2, "R", 0.6)
	p.circle(52, 25, 1.6, "#", 0.3)
	p.circle(47, 28, 1.4, "#", 0.4)
	p.circle(20, 29, 1.2, "#", 0.4)
	# hidden cove east (reachable by wading through the shallows south of the rocks)
	p.rect(54, 13, 7, 9, ".")
	p.forest_edge("T", 1.2, ".")
	p.rect(51, 24, 3, 2, "-")
	# memory stone nook
	p.circle(12, 10.5, 1.6, "\"", 0.0)
	for q in [Vector2i(10, 9), Vector2i(14, 9), Vector2i(11, 8), Vector2i(13, 8)]:
		p.setc(q.x, q.y, "r")
	# path to the village (north-east)
	p.path([Vector2(39, 17), Vector2(41, 12), Vector2(44, 7), Vector2(45, 0)], ":", 2)
	# beach bar clearing
	p.rect(25, 9, 9, 5, ".")
	# palms along the beach
	p.scatter(4, 12, 46, 7, "Y", 0.07, ".", 2)
	for q in [Vector2i(8, 15), Vector2i(19, 13), Vector2i(35, 14), Vector2i(47, 13), Vector2i(57, 16)]:
		p.setc(q.x, q.y, "Y")
	# storm debris at start
	for q in [Vector2i(4, 17), Vector2i(9, 20)]:
		p.setc(q.x, q.y, "x")
	p.setc(7, 21, "k")
	for q in [Vector2i(22, 17), Vector2i(26, 18), Vector2i(33, 18), Vector2i(37, 17)]:
		p.setc(q.x, q.y, "u")
	# keep important spots clear
	for q in [Vector2i(6, 19), Vector2i(12, 11), Vector2i(18, 20), Vector2i(29, 14), Vector2i(57, 18), Vector2i(44, 5), Vector2i(23, 14),
			Vector2i(8, 13), Vector2i(11, 14), Vector2i(14, 15), Vector2i(16, 12), Vector2i(5, 21)]:
		p.rect(q.x - 1, q.y - 1, 3, 3, p.getc(q.x, q.y) if p.getc(q.x, q.y) in ".\",:" else ".")
	return {
		"name": "Strand von Gili Genting",
		"music": ["beach", "beach_2"], "ambient": "waves_loop", "env": "day", "water": true,
		"weather": ["petals", "wind", "butterflies"],
		"rows": p.rows(),
		"on_enter": "strand_enter",
		"battle": {"ground": "sand", "props": ["palm", "bush", "palm", "umbrella", "hibiscus"], "water": true, "backdrop": "bd_beach", "horizon": 0.72,
			"detail": ["shells", "coconuts", "driftwood", "seaweed_rock", "surfboard", "towel", "sandcastle"], "decals": ["g_shells", "g_footprints", "g_pebbles"]},
		"decor": [
			{"sprites": ["shells", "coconuts", "driftwood", "seaweed_rock", "trash"], "on": ".,", "density": 0.03},
			{"sprites": ["hibiscus", "bougainvillea", "fern", "bird_paradise", "monstera", "yellow_shrub", "orchids", "banana_small"], "on": "\"", "density": 0.05, "sway": 0.06},
			{"sprites": ["mushrooms_small", "fern"], "on": "\"", "density": 0.02},
		],
		"decals": [{"sprites": ["g_shells", "g_footprints", "g_pebbles"], "on": ".", "density": 0.05}, {"sprites": ["g_flowers_w", "g_flowers_r", "g_clover", "g_leaves", "g_frangi"], "on": "\"", "density": 0.13}],
		"spawns": {"start": [6, 19, 1, 0], "from_dorf": [44, 3, 0, 1], "from_bar": [29, 14, 0, 1], "from_grotte": [6, 20, 1, 0]},
		"entities": [
			{"type": "stone", "id": "mem1", "x": 12, "z": 11, "event": "mem_pakt"},
			{"type": "fire", "x": 23, "z": 14},
			# puzzle: tide stones -> hidden grotto
			{"type": "switch", "id": "gz_stern", "x": 8, "z": 13, "key": "stern", "symbol": "★", "color": "ffd060", "puzzle": "gezeiten", "order": ["sing", "herz", "stern"], "event": "switch", "sprite": "seaweed_rock", "fail_text": "Die Symbole erlöschen. Das Meer kichert.", "open_text": "Ein dumpfes Grollen am Felsen im Westen. Etwas hat sich verschoben."},
			{"type": "switch", "id": "gz_sing", "x": 11, "z": 14, "key": "sing", "symbol": "♪", "color": "70ffb0", "puzzle": "gezeiten", "order": ["sing", "herz", "stern"], "event": "switch", "sprite": "seaweed_rock", "fail_text": "Die Symbole erlöschen. Das Meer kichert.", "open_text": "Ein dumpfes Grollen am Felsen im Westen. Etwas hat sich verschoben."},
			{"type": "switch", "id": "gz_herz", "x": 14, "z": 15, "key": "herz", "symbol": "♥", "color": "ff6070", "puzzle": "gezeiten", "order": ["sing", "herz", "stern"], "event": "switch", "sprite": "seaweed_rock", "fail_text": "Die Symbole erlöschen. Das Meer kichert.", "open_text": "Ein dumpfes Grollen am Felsen im Westen. Etwas hat sich verschoben."},
			{"type": "prop", "sprite": "wall_piece", "x": 16, "z": 12, "event": "gezeiten_tafel", "block": true},
			{"type": "prop", "id": "grotte_rock", "sprite": "boulder", "x": 5, "z": 21, "event": "grotte_spalt", "block": true, "unless": "gezeiten_open"},
			{"type": "warp", "x": 5, "z": 21, "w": 1, "d": 1, "to": "grotte", "spawn": "start", "if": "gezeiten_open"},
			{"type": "prop", "sprite": "jukung", "x": 30, "z": 24, "block": true, "block_size": 1.6},
			{"type": "prop", "sprite": "jukung", "x": 12, "z": 25, "flip": true, "block": true, "block_size": 1.6},
			{"type": "prop", "sprite": "tiki", "x": 25, "z": 13},
			{"type": "light", "x": 25, "z": 13, "y": 1.5, "color": "ffa040", "energy": 1.4, "range": 3.5, "flicker": true},
			{"type": "prop", "sprite": "tiki", "x": 33, "z": 13},
			{"type": "light", "x": 33, "z": 13, "y": 1.5, "color": "ffa040", "energy": 1.4, "range": 3.5, "flicker": true},
			{"type": "prop", "sprite": "towel", "x": 24, "z": 18},
			{"type": "prop", "sprite": "towel", "x": 34, "z": 19, "flip": true},
			{"type": "prop", "sprite": "surfboard", "x": 38, "z": 19},
			{"type": "prop", "sprite": "sandcastle", "x": 28, "z": 20, "event": "sandcastle"},
			{"type": "prop", "sprite": "hammock", "x": 45, "z": 14, "block": true},
			{"type": "prop", "sprite": "trash", "x": 41, "z": 21},
			{"type": "prop", "sprite": "pier", "x": 21, "z": 22},
			{"type": "prop", "sprite": "dock_post", "x": 22, "z": 22},
			{"type": "prop", "sprite": "dead_fish", "x": 14, "z": 21},
			{"type": "prop", "sprite": "suitcase", "x": 36, "z": 15, "lines": [["", "Ein verlorener Koffer. Aufkleber: Bali, Bangkok, Ballermann. Drin: Sonnencreme LSF 50 und eine Packung Chicken Nuggets."]]},
			{"type": "prop", "sprite": "trash_bags", "x": 47, "z": 18},
			{"type": "prop", "sprite": "coconut_barrow", "x": 34, "z": 12},
			{"type": "npc", "id": "kura", "sprite": "turtle", "x": 18, "z": 21, "event": "kura", "flip": true, "quest": "kura"},
			{"type": "house", "x": 26, "z": 9, "w": 6, "d": 3, "style": "bamboo", "to": "strandbar", "spawn": "door", "door": 28, "sign": "STRANDBAR"},
			{"type": "pickup", "id": "pl1", "x": 9, "z": 22, "item": "k_plastik", "event": "plastik"},
			{"type": "pickup", "id": "pl2", "x": 15, "z": 17, "item": "k_plastik", "event": "plastik"},
			{"type": "pickup", "id": "pl3", "x": 24, "z": 21, "item": "k_plastik", "event": "plastik"},
			{"type": "pickup", "id": "pl4", "x": 36, "z": 20, "item": "k_plastik", "event": "plastik"},
			{"type": "pickup", "id": "pl5", "x": 56, "z": 15, "item": "k_plastik", "event": "plastik"},
			{"type": "chest", "id": "cove", "x": 58, "z": 18, "items": {"w_fischgraete": 1}, "grains": 20},
			{"type": "chest", "id": "debris", "x": 5, "z": 16, "items": {"f_mango": 1}},
			{"type": "npc", "id": "sign_beach", "sprite": "fence", "x": 41, "z": 14, "lines": [["Schild", "\"GILI GENTING – Paradise for everyone!*\"\n*Hühner ausgenommen."]]},
			{"type": "enemy", "id": "crab1", "x": 10, "z": 21, "group": ["crab"], "radius": 2.0, "chase": 2.2},
			{"type": "enemy", "id": "crab2", "x": 16, "z": 23, "group": ["crab", "crab"], "radius": 2.0, "chase": 2.2},
			{"type": "enemy", "id": "crab3", "x": 35, "z": 18, "group": ["crab", "macaque"], "radius": 2.0},
			{"type": "enemy", "id": "monkey1", "x": 20, "z": 6, "group": ["macaque", "macaque"], "radius": 3.0, "chase": 3.4},
			{"type": "enemy", "id": "gate", "x": 44, "z": 4, "group": ["guard", "tourist_m"], "radius": 1.0, "aggro": 3.0, "if": "mem1"},
			{"type": "trigger", "id": "gate_block", "x": 41, "z": 0, "w": 8, "d": 3, "event": "strand_noexit", "once": false, "unless": "mem1"},
			{"type": "warp", "x": 42, "z": 0, "w": 6, "d": 1, "to": "dorf", "spawn": "from_strand", "if": "mem1"},
		],
	}

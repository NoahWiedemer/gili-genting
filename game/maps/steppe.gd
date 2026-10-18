extends RefCounted
## Kapitel 3: Die verlassene Steppe – Hitze, Ruinen, Füchse und ein Brunnen.

static func def() -> Dictionary:
	var p := Painter.new(66, 42, "=", 33)
	# dry grass patches and old fields
	for c in [Vector3(14, 30, 5), Vector3(40, 18, 6), Vector3(26, 8, 4), Vector3(52, 34, 4), Vector3(8, 16, 3)]:
		p.circle(c.x, c.y, c.z, "_", 1.0)
	p.rect(30, 30, 12, 6, "%")
	p.forest_edge("#", 1.6)
	p.forest_edge("R", 0.8)
	p.scatter(2, 2, 62, 38, "d", 0.016, "=_", 3)
	p.scatter(2, 2, 62, 38, "s", 0.09, "=_")
	p.scatter(2, 2, 62, 38, "r", 0.012, "=_", 3)
	p.scatter(2, 2, 62, 38, "#", 0.006, "=", 4)
	# jungle remnant (south-east) with macaques
	p.circle(58, 36, 5.5, ";", 1.0)
	p.scatter(52, 30, 13, 11, "T", 0.18, ";", 1)
	# hidden oasis with the well (north-west), only reachable through a gap in the rocks
	p.rect(2, 2, 12, 9, "R")
	p.rect(4, 3, 7, 6, "q")
	p.setc(7, 4, "q")
	p.setc(4, 3, "b")
	p.setc(10, 3, "b")
	p.setc(4, 8, "f")
	p.path([Vector2(7, 8), Vector2(7, 13)], "q", 1)
	p.rect(6, 11, 3, 3, "_")
	p.setc(6, 12, "d")
	p.setc(8, 12, "s")
	# main path west -> east
	p.path([Vector2(0, 21), Vector2(16, 20), Vector2(28, 24), Vector2(44, 22), Vector2(66, 20)], ":", 2)
	# calf pen
	p.rect(46, 26, 9, 7, "_")
	for x in range(46, 55):
		p.setc(x, 26, "F")
		p.setc(x, 32, "F")
	for z in range(26, 33):
		p.setc(46, z, "F")
		if z != 29:
			p.setc(54, z, "F")
	# wolf's construction site
	for q in [Vector2i(59, 17), Vector2i(59, 24), Vector2i(61, 17), Vector2i(61, 24)]:
		p.setc(q.x, q.y, "F")
	for q in [Vector2i(1, 21), Vector2i(14, 12), Vector2i(30, 25), Vector2i(41, 10), Vector2i(20, 31), Vector2i(7, 6), Vector2i(57, 20), Vector2i(50, 29), Vector2i(64, 20)]:
		p.rect(q.x - 1, q.y - 1, 3, 3, p.getc(q.x, q.y) if p.getc(q.x, q.y) in "=_:q" else "=")
	return {
		"name": "Verlassene Steppe",
		"music": ["steppe", "steppe_2"], "ambient": "wind_loop", "env": "noon",
		"weather": ["dust", "wind"],
		"rows": p.rows(),
		"on_enter": "steppe_enter",
		"battle": {"ground": "cracked_earth", "props": ["dead_tree", "dry_shrub", "boulder", "thorn_bush"], "backdrop": "bd_steppe", "horizon": 0.8,
			"detail": ["skull", "bones", "thorn_bush", "rock_pile", "termite", "wheel", "rusty_barrel"], "decals": ["g_cracks", "g_pebbles", "g_stones", "g_straw"]},
		"decor": [
			{"sprites": ["skull", "bones", "rock_pile", "thorn_bush", "wheel", "rusty_barrel", "bucket", "thorn_bush"], "on": "=_", "density": 0.035},
			{"sprites": ["termite"], "on": "=_", "density": 0.006, "block": true},
			{"sprites": ["fern", "monstera", "orchids"], "on": "q;", "density": 0.12, "sway": 0.06},
		],
		"decals": [{"sprites": ["g_cracks", "g_pebbles", "g_stones", "g_straw"], "on": "=_:", "density": 0.16}, {"sprites": ["g_moss", "g_mush", "g_flowers_w"], "on": "q", "density": 0.3}],
		"spawns": {"start": [1, 21, 1, 0], "from_dorf": [1, 21, 1, 0]},
		"entities": [
			# ruins of the banished commune
			{"type": "house", "x": 11, "z": 9, "w": 5, "d": 3, "style": "ruin"},
			{"type": "house", "x": 38, "z": 6, "w": 6, "d": 3, "style": "ruin"},
			{"type": "house", "x": 22, "z": 33, "w": 4, "d": 3, "style": "ruin"},
			{"type": "house", "x": 33, "z": 13, "w": 4, "d": 3, "style": "ruin"},
			{"type": "fire", "x": 20, "z": 30},
			{"type": "prop", "sprite": "signpost", "x": 3, "z": 19, "lines": [["Wegweiser", "← Dorf   → Hof Made   ↑ (unleserlich, jemand hat \"BRUNNEN?\" draufgekritzelt)"]]},
			{"type": "prop", "sprite": "plow", "x": 33, "z": 29},
			{"type": "prop", "sprite": "wall_piece", "x": 16, "z": 10},
			{"type": "prop", "sprite": "wall_piece", "x": 37, "z": 8, "flip": true},
			{"type": "prop", "sprite": "stakes", "x": 58, "z": 18},
			{"type": "prop", "sprite": "stakes", "x": 58, "z": 23, "flip": true},
			{"type": "prop", "sprite": "stakes", "x": 62, "z": 16},
			{"type": "prop", "sprite": "skull", "x": 29, "z": 27},
			{"type": "npc", "id": "schatz", "sprite": "", "x": 29, "z": 30, "event": "schatz", "unless": "schatz"},
			# characters
			{"type": "npc", "id": "wanderer", "sprite": "wanderer", "x": 14, "z": 13, "event": "wanderer", "unless": "wanderer_met", "story_flag": "wanderer_met"},
			{"type": "npc", "id": "vian", "sprite": "vian", "x": 30, "z": 26, "event": "vian", "unless": "vian_recruited", "story_flag": "vian_met"},
			{"type": "prop", "sprite": "dead_tree", "x": 31, "z": 25, "ox": 0.3},
			{"type": "npc", "id": "nugget", "sprite": "nugget", "x": 50, "z": 14, "event": "nugget", "unless": "nugget_recruited", "story_flag": "nugget_met", "flip": true},
			{"type": "prop", "sprite": "cages", "x": 52, "z": 13, "block": true, "lines": [["", "Ein umgekippter Transportkäfig. Darauf gestempelt: 'Legehennen – Festland – Halle 7'. Leer. Bis auf eine Feder."]]},
			{"type": "prop", "sprite": "trash_bags", "x": 53, "z": 15},
			# easter egg: the dead shark in the well
			{"type": "prop", "id": "well", "sprite": "well", "x": 7, "z": 4, "event": "brunnen", "block": true, "block_size": 1.0},
			{"type": "light", "x": 7, "z": 5, "y": 0.5, "color": "60ffd0", "energy": 1.2, "range": 3.0},
			# calf quest
			{"type": "npc", "id": "kalb", "sprite": "calf", "x": 50, "z": 29, "event": "kalb", "unless": "kalb_free"},
			{"type": "enemy", "id": "pen_guard", "x": 56, "z": 29, "group": ["farmer", "dog"], "radius": 1.0, "aggro": 3.0},
			# the wolf
			{"type": "npc", "id": "wolf", "sprite": "wolf", "x": 60, "z": 20, "event": "wolf", "unless": "wolf_dead", "flip": true},
			{"type": "npc", "id": "wolf_guard", "sprite": "guard", "x": 60, "z": 22, "unless": "wolf_dead", "flip": true, "event": "wolf"},
			{"type": "trigger", "id": "wolf_t", "x": 56, "z": 17, "w": 2, "d": 8, "event": "wolf", "unless": "wolf_dead", "once": false},
			{"type": "trigger", "id": "east_exit", "x": 64, "z": 17, "w": 2, "d": 8, "event": "steppe_east", "once": false},
			{"type": "warp", "x": 0, "z": 18, "w": 1, "d": 6, "to": "dorf", "spawn": "from_steppe"},
			{"type": "chest", "id": "st1", "x": 45, "z": 9, "items": {"f_kokos": 2}, "grains": 60},
			{"type": "chest", "id": "st2", "x": 23, "z": 37, "items": {"f_nasigoreng": 1}},
			{"type": "chest", "id": "st3", "x": 61, "z": 37, "items": {"f_mango": 2}, "grains": 80},
			# enemies
			{"type": "enemy", "id": "s_fox1", "x": 20, "z": 16, "group": ["fox", "fox"], "radius": 3.0, "chase": 3.8},
			{"type": "enemy", "id": "s_fox2", "x": 36, "z": 30, "group": ["fox", "farmer"], "radius": 3.0, "chase": 3.6},
			{"type": "enemy", "id": "s_farm", "x": 44, "z": 16, "group": ["farmer", "farmer"], "radius": 2.5},
			{"type": "enemy", "id": "s_monk", "x": 56, "z": 34, "group": ["macaque", "macaque", "macaque"], "radius": 2.5, "chase": 3.8},
			{"type": "enemy", "id": "s_dog", "x": 10, "z": 34, "group": ["dog", "dog"], "radius": 3.0, "chase": 3.8},
		],
	}

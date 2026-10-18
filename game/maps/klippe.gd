extends RefCounted
## Kapitel 4: Die Klippe der Aussichtslosen – Sturm, Nacht, Entscheidung.

static func def() -> Dictionary:
	var p := Painter.new(36, 44, "~", 44)
	p.path([Vector2(18, 44), Vector2(17, 36), Vector2(12, 29), Vector2(14, 22), Vector2(21, 17), Vector2(19, 10), Vector2(17, 5)], "K", 6)
	p.circle(17, 5, 3.6, "K", 0.6)
	p.circle(12, 29, 3.5, "K", 0.8)
	p.circle(21, 17, 3.2, "K", 0.8)
	for z in 44:
		for x in 36:
			if p.getc(x, z) == "K":
				var n := sin(x * 0.9 + z * 0.4) + sin(z * 0.7 - x * 0.3)
				p.setc(x, z, "K" if n > 1.1 else "G")
	p.scatter(0, 6, 36, 38, "d", 0.025, "KG", 3)
	p.scatter(0, 6, 36, 38, "s", 0.08, "KG")
	p.scatter(0, 6, 36, 38, "r", 0.03, "KG", 2)
	# jagged rocks in the surf
	for c in [Vector2(8, 12), Vector2(27, 8), Vector2(26, 30), Vector2(6, 38), Vector2(29, 40), Vector2(10, 4), Vector2(25, 22)]:
		p.circle(c.x, c.y, 1.3, "U", 0.6)
	for q in [Vector2i(18, 41), Vector2i(17, 5), Vector2i(17, 7), Vector2i(12, 28), Vector2i(20, 17)]:
		p.rect(q.x - 1, q.y - 1, 3, 3, "K")
	return {
		"name": "Klippe der Aussichtslosen",
		"music": "cliff", "ambient": "rain_loop", "env": "storm", "water": true,
		"weather": ["storm"],
		"rows": p.rows(),
		"on_enter": "klippe_enter",
		"battle": {"ground": "grass_dry", "props": ["dead_tree", "boulder", "thorn_bush"], "backdrop": "bd_cliff", "horizon": 0.62,
			"detail": ["rock_pile", "thorn_bush", "bones", "skull"], "decals": ["g_cracks", "g_stones", "g_moss"]},
		"backdrop": "bd_cliff",
		"decor": [{"sprites": ["rock_pile", "thorn_bush", "bones"], "on": "KG", "density": 0.03}],
		"decals": [{"sprites": ["g_cracks", "g_stones", "g_moss", "g_puddle"], "on": "KG", "density": 0.12}],
		"spawns": {"start": [18, 41, 0, -1]},
		"entities": [
			{"type": "prop", "id": "dead_wanderer", "sprite": "dead_chicken", "x": 16, "z": 5},
			{"type": "trigger", "id": "edge", "x": 13, "z": 3, "w": 9, "d": 5, "event": "klippe_edge", "unless": "revolution", "once": false},
			{"type": "enemy", "id": "k_fish", "x": 12, "z": 30, "group": ["fisher", "fisher"], "radius": 2.0},
			{"type": "enemy", "id": "k_fox", "x": 21, "z": 18, "group": ["fox", "fox", "fox"], "radius": 2.0, "chase": 3.6},
			{"type": "npc", "id": "paprika", "sprite": "paprika", "x": 14, "z": 24, "event": "paprika", "unless": "paprika_recruited", "story_flag": "paprika_met"},
			{"type": "chest", "id": "k1", "x": 9, "z": 28, "items": {"f_shake": 1}},
			{"type": "light", "x": 17, "z": 6, "y": 1.0, "color": "8090ff", "energy": 1.5, "range": 5.0},
		],
	}

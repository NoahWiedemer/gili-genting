extends RefCounted
## Die Scheune – Heu, Werkzeug und ein schlafender Hund.

static func def() -> Dictionary:
	return {
		"name": "Scheune", "music": "farm", "env": "interior", "cam_dist": 10.0, "cam_pitch": 42.0, "cam_margin": 3.0,
		"rows": [
			"WWWWWWWWWWWWWW",
			"WxxhhhhhhhhkkW",
			"WhhhhhhhhhhhhW",
			"WhhhhhhhhhhhhW",
			"WkhhhhhhhhhhxW",
			"WhhhhhhhhhhhhW",
			"WhhhhhhhhhhhhW",
			"WWWWWWhhWWWWWW",
		],
		"battle": {"detail": ["haybale", "feed_sacks", "milkcans", "wheelbarrow"], "decals": ["g_straw"], "ground": "straw_floor", "props": ["crates", "barrel"], "lights": [[0, 2.5, 1, "ffa050", 1.8]]},
		"spawns": {"door": [6, 6, 0, -1]},
		"entities": [
			{"type": "light", "x": 7, "z": 3, "y": 1.8, "color": "ffb060", "energy": 2.0, "range": 6.0, "flicker": true, "shadow": true},
			{"type": "enemy", "id": "sch_dog", "x": 9, "z": 3, "group": ["nightdog", "nightdog"], "sleeping": true, "radius": 0.5},
			{"type": "chest", "id": "sch1", "x": 3, "z": 2, "items": {"w_hackbeil": 1}},
			{"type": "chest", "id": "sch2", "x": 11, "z": 5, "items": {"f_nasigoreng": 1}},
			{"type": "prop", "sprite": "firewood", "x": 12, "z": 2},
			{"type": "prop", "sprite": "water_jar", "x": 1, "z": 5},
			{"type": "prop", "sprite": "bird_cage", "x": 8, "z": 1, "block": true, "lines": [["Huhn im Käfig", "Bitte ... sag dem Bauern nicht, dass ich gesprochen hab. Er mag keine Hühner, die sprechen."]]},
			{"type": "prop", "sprite": "haybale", "x": 2, "z": 3, "block": true},
			{"type": "prop", "sprite": "feed_sacks", "x": 10, "z": 1},
			{"type": "npc", "id": "hen_sleep", "sprite": "hen_sleep", "x": 5, "z": 4, "lines": [["Schlafendes Huhn", "Zzz ... ist es schon Vollmond? ... Zzz ... Revolution ... Zzz ..."]]},
			{"type": "warp", "x": 6, "z": 7, "w": 2, "d": 1, "to": "hof", "spawn": "from_scheune"},
		],
	}

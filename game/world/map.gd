class_name Map
extends Node3D
## A playable area built from a map definition (ASCII terrain + entities).

const WATER_SHADER := preload("res://shaders/water.gdshader")

var id := ""
var def := {}
var terrain: Terrain
var atmos: Atmosphere
var player: Player
var camera: Camera3D
var cam_target := Vector3.ZERO
var cam_offset := Vector3(0, 8.2, 11.5)
var actors: Array = []       # interactables
var enemies: Array = []
var triggers: Array = []     # {rect: Rect2, ent, fired}
var dyn_lights: Array = []   # lights that can be switched off (power cut)
var active := false
var bounds := Rect2()
var occluders: Array = []   # [{node, rect: Rect2 (x,z of area hidden behind it), a: current alpha, house: bool}]
var _tex_cache := {}
var main

func tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var t := Data.tex("res://assets/textures/%s.png" % name)
	if t == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.from_hsv(float(abs(name.hash()) % 360) / 360.0, 0.35, 0.75))
		t = ImageTexture.create_from_image(img)
	_tex_cache[name] = t
	return t

func build(map_id: String, d: Dictionary, spawn_name: String) -> void:
	id = map_id
	def = d
	name = "Map_" + map_id
	terrain = Terrain.new(d["rows"])
	add_child(terrain.build(tex))
	bounds = Rect2(0, 0, terrain.w, terrain.d)
	var night: bool = d.get("night", false)
	# atmosphere
	var holder := Node3D.new()
	add_child(holder)
	atmos = Atmosphere.new()
	add_child(atmos)
	cam_target = Vector3(terrain.w * 0.5, 0, terrain.d * 0.5)
	# camera
	camera = Camera3D.new()
	camera.fov = d.get("fov", 34.0)
	camera.near = 0.3
	camera.far = 120.0
	var dist: float = d.get("cam_dist", 11.5)
	var pitch: float = deg_to_rad(d.get("cam_pitch", 36.0))
	cam_offset = Vector3(0, sin(pitch) * dist, cos(pitch) * dist)
	if d.get("dof", true):
		# focus exactly on the chicken's plane; interiors get a slightly narrower band
		camera.attributes = Dof.make(dist, 2.6 if d.has("cam_dist") else 3.2, 1.8 if d.has("cam_dist") else 2.4)
	add_child(camera)
	camera.current = true
	# player
	player = Player.new()
	player.map = self
	add_child(player)
	atmos.setup(d.get("env", "day"), player)
	if d.get("env", "day") in ["storm", "moon", "dark", "dusk", "interior", "slaughter", "eclipse"]:
		var pl := OmniLight3D.new()
		pl.light_color = Color(1.0, 0.85, 0.65) if d.get("env", "") != "storm" else Color(0.7, 0.8, 1.0)
		pl.light_energy = 0.9
		pl.omni_range = 3.2
		pl.position = Vector3(0, 1.2, 0.8)
		player.add_child(pl)
	for w in d.get("weather", []):
		atmos.add_weather(w)
	if d.get("env", "") in ["day", "noon"]:
		atmos.add_cloud_shadows(Vector3(terrain.w * 0.5, 0, terrain.d * 0.5), max(terrain.w, terrain.d) + 30)
	if d.has("backdrop"):
		var bt := Data.tex("res://assets/backdrops/%s.png" % d["backdrop"])
		if bt:
			var bq := MeshInstance3D.new()
			var qm := QuadMesh.new()
			var bw: float = terrain.w + 50.0
			qm.size = Vector2(bw, bw * bt.get_height() / bt.get_width())
			bq.mesh = qm
			var bm := StandardMaterial3D.new()
			bm.albedo_texture = bt
			bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bq.material_override = bm
			bq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bq.position = Vector3(terrain.w * 0.5, qm.size.y * 0.25, -14.0)
			add_child(bq)
	# sea
	if d.get("water", false):
		_add_water(night)
	_spawn_terrain_props(night)
	_spawn_decor(d.get("decor", []), d.get("decals", []))
	# entities
	for e in d.get("entities", []):
		_spawn_entity(e, night)
	# killed enemies leave blood
	for eid in Game.killed.get(id, []):
		for e in d.get("entities", []):
			if e.get("id", "") == eid and e["type"] == "enemy":
				add_blood(Vector3(e["x"] + 0.5, 0, e["z"] + 0.5))
	# spawn player
	var sp: Vector3
	if spawn_name == "@pos" and Game.has_map_pos:
		sp = Game.map_pos
	else:
		var s: Array = d["spawns"].get(spawn_name, d["spawns"].values()[0])
		sp = Vector3(s[0] + 0.5, 0, s[1] + 0.5)
		if s.size() > 2:
			player.facing = Vector3(s[2], 0, s[3]).normalized()
	player.global_position = Vector3(sp.x, ground_height(sp), sp.z)
	Game.quests_changed.connect(refresh_markers)
	Game.inventory_changed.connect(refresh_markers)
	player.sprite.set_flip(player.facing.x < 0)
	cam_target = player.global_position
	_update_camera(1.0)
	refresh()

func _add_occluder(sp: PixelSprite, pos: Vector3, w: float, h: float) -> void:
	if h < 1.15:
		return
	var depth := h * 1.25
	occluders.append({"node": sp, "rect": Rect2(pos.x - w * 0.42, pos.z - depth, w * 0.84, depth - 0.05), "a": 1.0, "house": false})

func _update_occluders(delta: float) -> void:
	var pp := Vector2(player.global_position.x, player.global_position.z)
	for o in occluders:
		var target := 0.32 if o["rect"].has_point(pp) else 1.0
		if is_equal_approx(o["a"], target):
			continue
		o["a"] = move_toward(o["a"], target, delta * 3.0)
		if not is_instance_valid(o["node"]):
			continue
		if o["house"]:
			_set_house_alpha(o["node"], o["a"])
		else:
			o["node"].set_alpha(o["a"])

func _set_house_alpha(n: Node, a: float) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = c.material_override
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH if a < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
			m.albedo_color.a = a
		elif c is Label3D:
			c.modulate.a = a

## Scatters extra detail sprites and flat ground decals (deterministic per map).
func _spawn_decor(rules: Array, decals: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id + "decor")
	var reserved := {}
	for e in def.get("entities", []):
		if e.has("x") and e.has("z"):
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					reserved[Vector2i(int(e["x"]) + dx, int(e["z"]) + dz)] = true
	for sp in def.get("spawns", {}).values():
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				reserved[Vector2i(int(sp[0]) + dx, int(sp[1]) + dz)] = true
	for r in rules:
		var on: String = r.get("on", "\"")
		var rect: Array = r.get("rect", [0, 0, terrain.w, terrain.d])
		var sprites: Array = r["sprites"]
		var block: bool = r.get("block", false)
		for z in range(rect[1], rect[1] + rect[3]):
			for x in range(rect[0], rect[0] + rect[2]):
				var c := terrain.char_at(x, z)
				if not (c in on) or not terrain.is_walkable(x, z) or reserved.has(Vector2i(x, z)):
					continue
				if rng.randf() >= r.get("density", 0.05):
					continue
				var tx := Data.sprite_tex(sprites[rng.randi() % sprites.size()])
				var spr := PixelSprite.make(tx, r.get("sway", 0.0))
				add_child(spr)
				spr.position = Vector3(x + 0.5 + rng.randf_range(-0.25, 0.25), terrain.height_at(x, z), z + 0.5 + rng.randf_range(-0.2, 0.2))
				if rng.randf() < 0.5:
					spr.set_flip(true)
				if block:
					terrain.walk[Vector2i(x, z)] = false
					_block(spr.position, 0.7)
				reserved[Vector2i(x, z)] = true
				_add_occluder(spr, spr.position, spr.width, spr.height)
	# flat ground decals
	var dmats := {}
	for r in decals:
		var on2: String = r.get("on", "\"")
		for z in terrain.d:
			for x in terrain.w:
				if not (terrain.char_at(x, z) in on2) or rng.randf() >= r.get("density", 0.06):
					continue
				var nm: String = r["sprites"][rng.randi() % r["sprites"].size()]
				var t := Data.sprite_tex(nm)
				if not dmats.has(nm):
					var m := StandardMaterial3D.new()
					m.albedo_texture = t
					m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					m.roughness = 1.0
					dmats[nm] = m
				var mi := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.orientation = PlaneMesh.FACE_Y
				q.size = Vector2(t.get_width(), t.get_height()) / 32.0
				mi.mesh = q
				mi.material_override = dmats[nm]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				mi.position = Vector3(x + rng.randf_range(0.3, 0.7), terrain.height_at(x, z) + 0.01, z + rng.randf_range(0.3, 0.7))
				mi.rotation.y = PI * 0.5 * (rng.randi() % 4)

func _spawn_terrain_props(night: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var power: bool = def.get("power_lights", false)
	for z in terrain.d:
		for x in terrain.w:
			var c := terrain.char_at(x, z)
			if not Terrain.PROPS.has(c):
				continue
			var info: Array = Terrain.PROPS[c]
			var sp := PixelSprite.make(Data.sprite_tex(info[0]), info[2], info[3] * rng.randf_range(0.9, 1.12))
			add_child(sp)
			var j: float = info[4]
			var h := terrain.height_at(x, z)
			sp.position = Vector3(x + 0.5 + rng.randf_range(-j, j), h, z + 0.5 + rng.randf_range(-j, j) * 0.6)
			if rng.randf() < 0.5 and not (c in ["F", "l", "u"]):
				sp.set_flip(true)
			_add_occluder(sp, sp.position, sp.width, sp.height)
			if c == "l":
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.62, 0.3)
				l.light_energy = 2.2 if night else 0.6
				l.omni_range = 5.0
				l.omni_attenuation = 1.3
				l.position = sp.position + Vector3(0, 0.75, 0.15)
				add_child(l)
				var fl := Flicker.new()
				fl.light = l
				l.add_child(fl)
				sp.set_emission(0.15 if night else 0.0)
				if power:
					dyn_lights.append(l)

func _add_water(night: bool) -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(terrain.w + 80, terrain.d + 80)
	pm.subdivide_width = 60
	pm.subdivide_depth = 60
	w.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("glow", atmos.water_glow())
	if def.get("env", "") in ["storm", "moon", "dark"]:
		m.set_shader_parameter("shallow", Color(0.12, 0.42, 0.5))
		m.set_shader_parameter("mid", Color(0.04, 0.22, 0.32))
		m.set_shader_parameter("deep", Color(0.01, 0.06, 0.12))
		m.set_shader_parameter("foam_col", Color(0.6, 0.7, 0.8))
		m.set_shader_parameter("wave_speed", 1.8)
		m.set_shader_parameter("min_alpha", 0.93)
		m.set_shader_parameter("foam_width", 0.14)
	elif def.get("env", "") == "dusk":
		m.set_shader_parameter("shallow", Color(0.45, 0.6, 0.65))
		m.set_shader_parameter("mid", Color(0.15, 0.35, 0.5))
		m.set_shader_parameter("deep", Color(0.06, 0.12, 0.28))
	w.material_override = m
	w.position = Vector3(terrain.w * 0.5, -0.12, terrain.d * 0.5)
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w)

func _cond_ok(e: Dictionary) -> bool:
	if e.has("if"):
		for f in String(e["if"]).split(","):
			if not Game.flag(f.strip_edges()):
				return false
	if e.has("unless"):
		for f in String(e["unless"]).split(","):
			if Game.flag(f.strip_edges()):
				return false
	if e.has("id") and e["type"] == "enemy" and Game.is_killed(id, e["id"]):
		return false
	if e.has("id") and e["type"] in ["chest_gone", "pickup"] and Game.flag("got_%s_%s" % [id, e["id"]]):
		return false
	return true

func _pos(e: Dictionary) -> Vector3:
	var x: float = e.get("x", 0) + 0.5
	var z: float = e.get("z", 0) + 0.5
	return Vector3(x, ground_height(Vector3(x, 0, z)), z)

func _spawn_entity(e: Dictionary, night: bool) -> Node3D:
	var n: Node3D = null
	if e["type"] in ["npc", "enemy", "chest", "pickup", "stone"] and not terrain.is_walkable(int(e["x"]), int(e["z"])):
		push_warning("[%s] entity %s on blocked tile %d,%d ('%s')" % [id, e.get("id", e["type"]), e["x"], e["z"], terrain.char_at(int(e["x"]), int(e["z"]))])
	match e["type"]:
		"house":
			n = House.build(e, tex, night)
			add_child(n)
			var hw: float = e.get("w", 4)
			var hd: float = e.get("d", 3)
			occluders.append({"node": n, "rect": Rect2(e["x"] - 0.3, e["z"] - 3.2, hw + 0.6, hd + 3.0), "a": 1.0, "house": true})
			if e.has("to"):
				var door := Actor.new()
				door.ent = {"type": "door", "to": e["to"], "spawn": e.get("spawn", "door"), "locked": e.get("locked", ""),
					"if": e.get("door_if", ""), "id": "door_" + e["to"]}
				door.map = self
				add_child(door)
				var dx: float = e.get("door", e["x"] + floor(e.get("w", 4) / 2.0))
				door.global_position = Vector3(dx + 0.5, 0, e["z"] + e.get("d", 3) + 0.3)
				door.interact_radius = 1.1
				actors.append(door)
		"prop":
			var a := Actor.new()
			a.ent = e
			a.map = self
			a.interactable = e.has("event") or e.has("lines")
			add_child(a)
			a.global_position = _pos(e) + Vector3(e.get("ox", 0.0), e.get("oy", 0.0), e.get("oz", 0.0))
			a.setup_sprite(e["sprite"], e.get("sway", 0.0), e.get("flip", false))
			a.idle_anim = false
			_add_occluder(a.sprite, a.global_position, a.sprite.width, a.sprite.height)
			if e.has("glow"):
				a.sprite.set_emission(e["glow"])
			if e.get("block", false):
				a.set_meta("body", _block(a.global_position, e.get("block_size", 0.8)))
			if a.interactable:
				actors.append(a)
			n = a
		"npc", "stone", "chest", "pickup", "sign":
			n = _spawn_interactable(e)
		"switch":
			var sa := Actor.new()
			sa.ent = e
			sa.map = self
			add_child(sa)
			sa.global_position = _pos(e)
			sa.setup_sprite(e.get("sprite", "boulder"))
			sa.idle_anim = false
			sa.set_meta("body", _block(sa.global_position, 0.6))
			var gl := OmniLight3D.new()
			gl.name = "Glow"
			gl.light_color = Color(e.get("color", "60e0ff"))
			gl.light_energy = 0.0
			gl.omni_range = 3.0
			gl.position = Vector3(0, 0.9, 0.4)
			sa.add_child(gl)
			var sym := Label3D.new()
			sym.name = "Sym"
			sym.text = e.get("symbol", "★")
			sym.font = UI.font
			sym.font_size = 30
			sym.pixel_size = 0.014
			sym.outline_size = 6
			sym.outline_modulate = Color(0, 0, 0, 0.8)
			sym.modulate = Color(0.55, 0.55, 0.6)
			sym.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sym.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sym.position = Vector3(0, sa.sprite.height + 0.25, 0.1)
			sa.add_child(sym)
			actors.append(sa)
			n = sa
			Story.switch_visual.call_deferred(sa)
		"enemy":
			var en := EnemyActor.new()
			en.ent = e
			en.map = self
			add_child(en)
			en.global_position = _pos(e)
			var grp: Array = e["group"]
			en.setup_sprite(e.get("sprite", Data.ENEMIES[grp[0]]["sprite"]), 0.0, e.get("flip", false))
			en.init_enemy()
			enemies.append(en)
			n = en
		"light":
			var l := OmniLight3D.new()
			l.light_color = Color(e.get("color", "ffb060"))
			l.light_energy = e.get("energy", 2.0)
			l.omni_range = e.get("range", 4.5)
			l.shadow_enabled = e.get("shadow", false)
			l.omni_attenuation = 1.2
			add_child(l)
			l.global_position = _pos(e) + Vector3(0, e.get("y", 1.4), 0)
			if e.get("flicker", false):
				var fl := Flicker.new()
				fl.light = l
				l.add_child(fl)
			if e.get("power", false):
				dyn_lights.append(l)
			n = l
		"fire":
			n = _campfire(e)
		"mirror":
			var mi := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(0.8, 1.5)
			q.center_offset = Vector3(0, 0.85, 0)
			mi.mesh = q
			var mm := StandardMaterial3D.new()
			mm.albedo_color = Color(0.55, 0.62, 0.7)
			mm.metallic = 0.9
			mm.roughness = 0.08
			mm.emission_enabled = true
			mm.emission = Color(0.25, 0.1, 0.1)
			mi.material_override = mm
			add_child(mi)
			mi.global_position = _pos(e)
			var a := Actor.new()
			a.ent = e
			a.map = self
			add_child(a)
			a.global_position = _pos(e) + Vector3(0, 0, 0.3)
			actors.append(a)
			n = mi
		"warp", "trigger":
			var r := Rect2(e["x"], e["z"], e.get("w", 1), e.get("d", 1))
			triggers.append({"rect": r, "ent": e, "fired": false})
		"blood":
			add_blood(_pos(e))
	if n and e.has("id"):
		n.set_meta("eid", e["id"])
		n.set_meta("ent", e)
	return n

func _spawn_interactable(e: Dictionary) -> Actor:
	var a := Actor.new()
	a.ent = e
	a.map = self
	add_child(a)
	a.global_position = _pos(e)
	var spr: String = e.get("sprite", "")
	match e["type"]:
		"stone":
			spr = "crystal"
			var l := OmniLight3D.new()
			l.light_color = Color(0.35, 0.95, 1.0)
			l.light_energy = 2.2
			l.omni_range = 4.0
			l.position = Vector3(0, 0.8, 0.3)
			a.add_child(l)
			var fl := Flicker.new()
			fl.light = l
			fl.pulse = true
			l.add_child(fl)
		"chest":
			spr = "chest_open" if Game.flag("got_%s_%s" % [id, e["id"]]) else "chest"
		"pickup":
			spr = e.get("sprite", "")
		"sign":
			spr = e.get("sprite", "")
	if spr != "":
		a.setup_sprite(spr, e.get("sway", 0.0), e.get("flip", false))
		if e["type"] == "stone":
			a.sprite.set_emission(0.6)
			a.idle_anim = false
		if e["type"] == "chest":
			a.idle_anim = false
			_block(a.global_position, 0.6)
		if e.get("block", e["type"] == "npc"):
			_block(a.global_position, e.get("block_size", 0.55))
	else:
		# invisible interactable (sign / sparkle)
		var sp := Sparkle.new()
		a.add_child(sp)
	if e["type"] == "pickup":
		var sp2 := Sparkle.new()
		a.add_child(sp2)
	if e.has("marker"):
		a.set_marker(e["marker"])
	if e.get("ants", false) and a.sprite:
		a.idle_anim = false
		a.sprite.scale = Vector3(1, -1, 1)
		a.sprite.position.y = a.sprite.height
		var ants := AntTrail.new()
		a.add_child(ants)
	actors.append(a)
	return a

func _campfire(e: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.global_position = _pos(e)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 3.0
	l.omni_range = 6.0
	l.shadow_enabled = true
	l.position = Vector3(0, 0.6, 0)
	root.add_child(l)
	var fl := Flicker.new()
	fl.light = l
	l.add_child(fl)
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var grad := Gradient.new()
	grad.set_color(0, Color(4.0, 2.2, 0.6, 1))
	grad.set_color(1, Color(1.2, 0.2, 0.05, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Data.tex("res://assets/fx/spark.png")
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	p.draw_pass_1 = q
	p.position = Vector3(0, 0.1, 0)
	root.add_child(p)
	# logs & stones
	var logs := PixelSprite.make(Data.sprite_tex("campfire"))
	logs.set_emission(0.35)
	root.add_child(logs)
	_block(root.global_position, 0.6)
	var a := Actor.new()
	a.ent = {"type": "npc", "event": e.get("event", "rest")}
	a.map = self
	a.interact_radius = 1.5
	add_child(a)
	a.global_position = root.global_position
	actors.append(a)
	return root

func _block(p: Vector3, size: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, 2, size * 0.7)
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.global_position = p + Vector3(0, 1, 0)
	return body

func add_blood(p: Vector3) -> void:
	var t := Data.tex("res://assets/fx/blood_puddle.png")
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(1.2, 0.6) if t == null else Vector2(t.get_width() / 32.0, t.get_height() / 32.0)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if t:
		m.albedo_texture = t
	else:
		m.albedo_color = Color(0.45, 0.02, 0.03)
	m.roughness = 0.25
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(p.x, ground_height(p) + 0.015, p.z)
	mi.rotation.y = randf_range(-0.3, 0.3)

# ------------------------------------------------------------------ queries
func ground_height(p: Vector3) -> float:
	var x := int(floor(p.x))
	var z := int(floor(p.z))
	if terrain.is_walkable(x, z):
		return terrain.height_at(x, z)
	return 0.0

func is_walkable_pos(p: Vector3) -> bool:
	return terrain.is_walkable(int(floor(p.x)), int(floor(p.z)))

func find_interactable(p: Vector3, facing: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := 99.0
	for a in actors:
		if not is_instance_valid(a) or not a.visible or not a.interactable:
			continue
		var v: Vector3 = a.global_position - p
		v.y = 0
		var dist := v.length()
		if dist > a.interact_radius:
			continue
		var score := dist - (v.normalized().dot(facing) * 0.5 if dist > 0.01 else 0.0)
		if score < bd:
			bd = score
			best = a
	return best

func actor_by_id(eid: String) -> Node3D:
	for c in get_children():
		if c.has_meta("eid") and c.get_meta("eid") == eid:
			return c
	return null

# ------------------------------------------------------------------ runtime
func start() -> void:
	active = true
	Audio.listener = player
	var mus = def.get("music", "")
	if id == "hof" and Game.flag("power_off"):
		mus = ["farm_2", "farm"]
	if mus is Array:
		Audio.music_pick(mus, "map_" + id)
	else:
		Audio.music(mus)
	Audio.ambient(def.get("ambient", ""))
	UI.set_map_name(def.get("name", ""))
	UI.show_hud(true)
	if not def.has("cam_dist"):
		UI.area_banner(def.get("name", ""))
	if def.has("on_enter"):
		active = false
		await Story.run(def["on_enter"], null)
		active = true

func _process(delta: float) -> void:
	if player == null:
		return
	cam_target = cam_target.lerp(player.global_position, clamp(delta * 4.0, 0.0, 1.0))
	_update_camera(delta)
	_update_occluders(delta)
	if active:
		_check_triggers()

func _update_camera(_d: float) -> void:
	var t := cam_target
	if def.has("cam_dist"):
		# rooms: keep the whole room framed, follow the chicken only a little
		var c := Vector3(bounds.size.x * 0.5, 0, bounds.size.y * 0.5 - 0.6)
		t = c + Vector3((cam_target.x - c.x) * 0.25, cam_target.y, (cam_target.z - c.z) * 0.15)
		camera.global_position = t + cam_offset + Vector3(0, 0.4, 0)
		camera.look_at(t + Vector3(0, 0.4, 0), Vector3.UP)
		return
	var mx: float = def.get("cam_margin", 6.0)
	t.x = clamp(t.x, min(mx, bounds.size.x * 0.5), max(bounds.size.x - mx, bounds.size.x * 0.5))
	t.z = clamp(t.z, min(3.0, bounds.size.y * 0.5), max(bounds.size.y - 1.0, bounds.size.y * 0.5))
	camera.global_position = t + cam_offset + Vector3(0, 0.4, 0)
	camera.look_at(t + Vector3(0, 0.4, 0), Vector3.UP)

func _check_triggers() -> void:
	var p := Vector2(player.global_position.x, player.global_position.z)
	for t in triggers:
		var e: Dictionary = t["ent"]
		if not _cond_ok(e):
			continue
		var inside: bool = t["rect"].has_point(p)
		if inside and not t["fired"]:
			t["fired"] = true
			if e["type"] == "warp":
				active = false
				main.goto_map(e["to"], e.get("spawn", "start"))
				return
			else:
				if e.get("once", true) and Game.flag("trig_%s_%s" % [id, e.get("id", "")]):
					continue
				if e.get("once", true):
					Game.set_flag("trig_%s_%s" % [id, e.get("id", "")])
				active = false
				await Story.run(e["event"], null)
				if is_instance_valid(self):
					active = true
		elif not inside:
			t["fired"] = false

func refresh_markers() -> void:
	for a in actors:
		if is_instance_valid(a) and a is Actor and (a.ent.has("quest") or a.ent.has("story_flag")):
			var m: String = Story.marker_for(a.ent)
			a.set_marker(m, Color(1, 0.85, 0.3) if m == "!" else Color(0.5, 1, 0.6))

func refresh() -> void:
	## Re-evaluates conditional entities (shows/hides them).
	refresh_markers()
	for c in get_children():
		if c.has_meta("ent"):
			var e: Dictionary = c.get_meta("ent")
			if e.has("if") or e.has("unless") or e["type"] in ["enemy", "pickup"]:
				var ok := _cond_ok(e)
				c.visible = ok
				if c is EnemyActor:
					c.set_process(ok)
				if c is Actor and not ok and c.get("ent").get("type", "") == "pickup":
					c.queue_free()
				if not ok and c.has_meta("body") and is_instance_valid(c.get_meta("body")):
					c.get_meta("body").queue_free()
					c.remove_meta("body")
					if c is Actor:
						c.interactable = false

func encounter(en: EnemyActor) -> void:
	if not active:
		return
	active = false
	var e: Dictionary = en.ent
	var o := {"boss": e.get("boss", false), "first_strike": en.sleeping}
	if e.has("intro"):
		o["intro_line"] = e["intro"]
	var res: String = await main.battle(e["group"], o)
	if res == "win":
		Game.mark_killed(id, e.get("id", ""))
		add_blood(en.global_position)
		enemies.erase(en)
		en.queue_free()
		if e.has("after"):
			await Story.run(e["after"], null)
	elif res == "flee":
		en.cooldown = 3.0
		en.global_position = en.home
	for other in enemies:
		if is_instance_valid(other):
			other.cooldown = max(other.cooldown, 1.5)
	active = true

func open_menu() -> void:
	active = false
	await main.open_menu()
	active = true

func power_off() -> void:
	for l in dyn_lights:
		var tw := create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.25)
		if l.get_child_count() > 0:
			l.get_child(0).queue_free()
	for c in get_children():
		if c.has_meta("ent") and c.get_meta("ent").get("power", false) and c is Actor:
			c.sprite.set_emission(0.0)

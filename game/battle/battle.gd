class_name Battle
extends Node3D
## Classic Final-Fantasy-style turn-based battle: choose commands for every party member,
## then everyone acts in speed order. Rendered as an HD-2D diorama.

signal finished(result: String)

var party: Array[Battler] = []
var foes: Array[Battler] = []
var camera: Camera3D
var atmos: Atmosphere
var ui: BattleUI
var opts := {}
var map_def := {}
var _cam_base := Vector3.ZERO
var _cam_look := Vector3(0, 1.0, 0)
var _shake := 0.0
var _fx_meta := {}
var result := ""
var round_no := 0
var total_xp := 0
var total_grains := 0
var drops: Array = []

const PARTY_POS := [Vector3(2.5, 0, -0.1), Vector3(3.7, 0, -1.3), Vector3(3.9, 0, 1.1)]
const FOE_POS := [Vector3(-2.3, 0, 0.0), Vector3(-3.8, 0, -1.4), Vector3(-4.0, 0, 1.2), Vector3(-1.5, 0, -2.2), Vector3(-1.2, 0, 1.6)]

func setup(group: Array, o: Dictionary, mdef: Dictionary) -> void:
	opts = o
	map_def = mdef
	if FileAccess.file_exists("res://assets/fx/fx_meta.json"):
		_fx_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fx/fx_meta.json"))
		if typeof(_fx_meta) != TYPE_DICTIONARY:
			_fx_meta = {}
	_build_arena()
	var i := 0
	for id in Game.party:
		if id == "":
			continue
		var b := Battler.new()
		b.battle = self
		add_child(b)
		b.setup_party(id)
		b.position = PARTY_POS[i]
		b.home = b.position
		party.append(b)
		i += 1
	i = 0
	for eid in group:
		_add_foe(eid, i)
		i += 1
	# food buffs
	for fb in Game.food_buffs:
		for b in party:
			if fb.get("team", false) or fb.get("who", "") == b.cid:
				b.add_status(fb["id"], 99)
	ui = BattleUI.new()
	ui.battle = self
	add_child(ui)

func _add_foe(eid: String, i: int) -> Battler:
	var b := Battler.new()
	b.battle = self
	add_child(b)
	b.setup_enemy(eid)
	var p: Vector3 = FOE_POS[i % FOE_POS.size()]
	if b.is_boss and i == 0:
		p = Vector3(-2.9, 0, 0.0)
	b.position = p
	b.home = p
	b.update_bar()
	foes.append(b)
	return b

func _build_arena() -> void:
	var bd: Dictionary = map_def.get("battle", {})
	var ground: String = bd.get("ground", "grass")
	var tex: Texture2D = Data.tex("res://assets/textures/%s.png" % ground)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 26)
	g.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(40, 26, 1)
	m.roughness = 0.95
	g.material_override = m
	add_child(g)
	# a second ground band for variety
	if bd.has("ground2"):
		var g2 := MeshInstance3D.new()
		var pm2 := PlaneMesh.new()
		pm2.size = Vector2(40, 3)
		g2.mesh = pm2
		var m2 := m.duplicate()
		m2.albedo_texture = Data.tex("res://assets/textures/%s.png" % bd["ground2"])
		m2.uv1_scale = Vector3(40, 3, 1)
		g2.material_override = m2
		g2.position = Vector3(0, 0.005, bd.get("ground2_z", 4.2))
		add_child(g2)
	if bd.get("water", false):
		var w := MeshInstance3D.new()
		var wp := PlaneMesh.new()
		wp.size = Vector2(60, 30)
		wp.subdivide_width = 40
		wp.subdivide_depth = 20
		w.mesh = wp
		var wm := ShaderMaterial.new()
		wm.shader = load("res://shaders/water.gdshader")
		w.material_override = wm
		w.position = Vector3(0, -0.12, -14.5)
		add_child(w)
		pm.size = Vector2(40, 20)
		g.position.z = 3.0
	# painted panorama backdrop far behind the arena (blurred by the DOF)
	var bdt: Texture2D = Data.tex("res://assets/backdrops/%s.png" % bd.get("backdrop", "")) if bd.has("backdrop") else null
	if bdt:
		var bq := MeshInstance3D.new()
		var qm := QuadMesh.new()
		var bw := 46.0
		var bh := bw * bdt.get_height() / bdt.get_width()
		qm.size = Vector2(bw, bh)
		bq.mesh = qm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_texture = bdt
		bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.disable_receive_shadows = true
		bmat.disable_fog = false
		bq.material_override = bmat
		bq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bq.position = Vector3(0, bh * 0.5 - bh * bd.get("horizon", 0.66) + 0.6, -13.0)
		add_child(bq)
		if not bd.get("water", false):
			g.position.z = -1.0
	# backdrop props
	var props: Array = bd.get("props", ["bush"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var x := -9.0
	while x < 9.0:
		var s: String = props[rng.randi() % props.size()]
		var sp := PixelSprite.make(Data.sprite_tex(s), 0.08)
		add_child(sp)
		sp.position = Vector3(x + rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-6.0, -3.6))
		x += rng.randf_range(1.0, 2.6)
	for k in 6:
		var s2: String = props[rng.randi() % props.size()]
		var sp2 := PixelSprite.make(Data.sprite_tex(s2), 0.08)
		add_child(sp2)
		sp2.position = Vector3([-8.5, -7.0, 7.0, 8.5, -6.0, 6.2][k], 0, rng.randf_range(-2.0, 2.5))
	var small: Array = bd.get("detail", [])
	for k in 14:
		if small.is_empty():
			break
		var ds := PixelSprite.make(Data.sprite_tex(small[rng.randi() % small.size()]), 0.06)
		add_child(ds)
		var side := -1.0 if k % 2 == 0 else 1.0
		ds.position = Vector3(rng.randf_range(-9.5, 9.5), 0, rng.randf_range(-3.2, -1.6)) if k < 8 else Vector3(side * rng.randf_range(5.6, 9.0), 0, rng.randf_range(-1.0, 3.0))
		if rng.randf() < 0.5:
			ds.set_flip(true)
	var gdec: Array = bd.get("decals", [])
	for k in 26:
		if gdec.is_empty():
			break
		var t2 := Data.sprite_tex(gdec[rng.randi() % gdec.size()])
		var mi := MeshInstance3D.new()
		var q2 := QuadMesh.new()
		q2.orientation = PlaneMesh.FACE_Y
		q2.size = Vector2(t2.get_width(), t2.get_height()) / 32.0
		mi.mesh = q2
		var dm := StandardMaterial3D.new()
		dm.albedo_texture = t2
		dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mi.material_override = dm
		add_child(mi)
		mi.position = Vector3(rng.randf_range(-9, 9), 0.012, rng.randf_range(-4, 4))
		mi.rotation.y = PI * 0.5 * (rng.randi() % 4)
	for l in bd.get("lights", []):
		var ol := OmniLight3D.new()
		ol.light_color = Color(l[3])
		ol.light_energy = l[4]
		ol.omni_range = 7.0
		ol.position = Vector3(l[0], l[1], l[2])
		add_child(ol)
		var fl := Flicker.new()
		fl.light = ol
		ol.add_child(fl)
	camera = Camera3D.new()
	camera.fov = 38.0
	_cam_base = Vector3(0.3, 3.1, 9.2)
	camera.position = _cam_base
	add_child(camera)
	camera.look_at(_cam_look, Vector3.UP)
	camera.attributes = Dof.make(9.4, 2.8, 2.6, 0.1)
	atmos = Atmosphere.new()
	add_child(atmos)
	var focus := Node3D.new()
	add_child(focus)
	atmos.setup(map_def.get("battle_env", map_def.get("env", "day")), focus)
	for wthr in map_def.get("weather", []):
		if wthr != "storm":
			atmos.add_weather(wthr)
		else:
			atmos.add_weather("rain")
	if map_def.get("env", "") in ["moon", "storm", "dark", "slaughter", "interior"]:
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.7, 0.5) if map_def.get("env", "") != "storm" else Color(0.6, 0.7, 1.0)
		fill.light_energy = 1.4
		fill.omni_range = 9.0
		fill.position = Vector3(0, 3.0, 3.0)
		add_child(fill)

const CAM_HOME := Vector3(0.3, 3.1, 9.2)
const LOOK_HOME := Vector3(0, 1.0, 0)

func _process(delta: float) -> void:
	if _shake > 0:
		_shake = max(0.0, _shake - delta * 2.5)
		camera.position = _cam_base + Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.15
	else:
		camera.position = camera.position.lerp(_cam_base, 0.2)
	if camera:
		camera.look_at(_cam_look, Vector3.UP)

func cam_focus(p: Vector3, amount := 1.0) -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_cam_base", CAM_HOME.lerp(Vector3(p.x * 0.45, 2.6, 7.4), amount), 0.35)
	tw.tween_property(self, "_cam_look", LOOK_HOME.lerp(Vector3(p.x * 0.55, 1.0, p.z * 0.3), amount), 0.35)

func cam_reset() -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "_cam_base", CAM_HOME, 0.45)
	tw.tween_property(self, "_cam_look", LOOK_HOME, 0.45)

func shake(amount := 0.6) -> void:
	_shake = max(_shake, amount)

# ------------------------------------------------------------------ main loop
func run() -> String:
	camera.current = true
	var boss_track := {"bookie": ["boss_dnb_1", "boss"], "wolf": ["boss_dnb_2", "boss"], "bauer": ["boss_dnb_3", "boss"], "butcher": ["boss_dnb_3", "boss"]}
	if opts.get("boss", false):
		Audio.music_pick(boss_track.get(foes[0].cid, ["boss_dnb_1", "boss_dnb_2", "boss"]), "boss", 0.3)
	elif foes.size() >= 3:
		Audio.music_pick(["battle_4", "battle_1", "boss_dnb_1"], "battle", 0.3)
	else:
		Audio.music_pick(["battle_1", "battle_2", "battle_3", "battle_4", "battle_5", "battle"], "battle", 0.3)
	for f in foes:
		Audio.voice(f.cid, null, 0.7)
		break
	ui.refresh()
	# intro: camera swoop
	var start := _cam_base + Vector3(0, 2.0, 4.0)
	camera.position = start
	var tw := create_tween()
	tw.tween_property(camera, "position", _cam_base, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for f in foes:
		f.sprite.set_alpha(0.0)
		var t2 := create_tween()
		t2.tween_method(func(v): f.sprite.set_alpha(v), 0.0, 1.0, 0.6)
	await tw.finished
	var names := {}
	for f in foes:
		names[f.display_name] = names.get(f.display_name, 0) + 1
	var parts := []
	for n in names:
		parts.append(("%d× %s" % [names[n], n]) if names[n] > 1 else n)
	await ui.banner(", ".join(parts) + (" greift an!" if parts.size() == 1 else " greifen an!"), 1.0)
	if opts.has("intro_line"):
		await ui.speech(foes[0], opts["intro_line"])
	elif randf() < 0.6:
		var q: Array = Data.ENEMIES[foes[0].cid].get("quips", [])
		if q.size() > 0:
			await ui.speech(foes[0], q[randi() % q.size()])
	if opts.get("first_strike", false):
		await ui.banner("Überraschungsangriff! Sie schlafen.", 1.0)
		for f in foes:
			f.add_status("betaeubt", 1)
	while result == "":
		round_no += 1
		if OS.get_cmdline_user_args().has("--inputtest") or Game.auto:
			print("    round ", round_no, " hp=", party.map(func(x): return x.hp), " foes=", foes.map(func(x): return x.hp))
		var cmds := {}
		var members: Array[Battler] = []
		for b in party:
			if b.alive and not b.has_status("betaeubt"):
				members.append(b)
		var i := 0
		while i < members.size():
			var b := members[i]
			b.step_forward(true)
			var c: Dictionary = await ui.command(b)
			b.step_forward(false)
			if c.get("back", false):
				i = max(0, i - 1)
				if i < members.size():
					cmds.erase(members[i])
				continue
			cmds[b] = c
			if c["type"] == "flee":
				break
			i += 1
		ui.end_turn_highlight()
		# flee resolves immediately
		for b in cmds:
			if cmds[b]["type"] == "flee":
				if await _try_flee():
					result = "flee"
				else:
					cmds.erase(b)
				break
		if result != "":
			break
		for f in foes:
			if f.alive:
				cmds[f] = _enemy_ai(f)
		var order: Array = cmds.keys()
		var prio := {}
		for b in order:
			var p: float = b.stat("spd") * randf_range(0.85, 1.15)
			if cmds[b]["type"] == "defend":
				p += 1000.0
			prio[b] = p
		order.sort_custom(func(a, b): return prio[a] > prio[b])
		for b in order:
			if result != "":
				break
			if not b.alive:
				continue
			if b.has_status("betaeubt"):
				await ui.banner("%s ist betäubt!" % b.display_name, 0.6)
				continue
			await _execute(b, cmds[b])
			ui.refresh()
			_check_end()
		# stunned-but-skipped party members lose their stun this round too
		if result == "":
			await _end_of_round()
			_check_end()
		ui.refresh()
	return await _finish()

func _check_end() -> void:
	if result != "":
		return
	if foes.all(func(f): return not f.alive):
		result = "win"
	elif party.all(func(p): return not p.alive):
		result = "lose"

func _try_flee() -> bool:
	if opts.get("boss", false) or opts.get("no_flee", false):
		await ui.banner("Vor dieser Schlachtung gibt es kein Entkommen!", 1.0)
		return false
	var ps := 0.0
	var fs := 0.0
	for b in party:
		if b.alive:
			ps += b.stat("spd")
	for f in foes:
		if f.alive:
			fs += f.stat("spd")
	var chance: float = clamp(0.5 + (ps / max(1, party.size()) - fs / max(1, foes.size())) * 0.04, 0.25, 0.92)
	Audio.sfx("flee")
	if randf() < chance:
		await ui.banner("Ihr gackert davon!", 0.8)
		return true
	await ui.banner("Flucht gescheitert! Die Beine sind zu kurz.", 0.9)
	return false

# ------------------------------------------------------------------ AI
func _enemy_ai(f: Battler) -> Dictionary:
	var e: Dictionary = Data.ENEMIES[f.cid]
	var skills: Array = e["skills"]
	var targets := party.filter(func(p): return p.alive)
	if targets.is_empty():
		return {"type": "defend"}
	var taunt := targets.filter(func(p): return p.has_status("spott"))
	var tgt: Battler = taunt[0] if not taunt.is_empty() else targets[randi() % targets.size()]
	# prefer weakened chickens sometimes (they are cruel)
	if taunt.is_empty() and randf() < 0.3:
		targets.sort_custom(func(a, b): return float(a.hp) / a.base["hp"] < float(b.hp) / b.base["hp"])
		tgt = targets[0]
	# boss scripts
	if f.cid == "butcher":
		if f.has_status("geladen"):
			f.statuses.erase("geladen")
			return {"type": "skill", "id": "e_schlachtzeit", "target": tgt}
		if float(f.hp) / f.base["hp"] < 0.75 and randf() < 0.42:
			return {"type": "skill", "id": "e_schlachtzeit_laden", "target": f}
		skills = ["e_haken", "e_hackbeil", "e_rupfen"]
	if f.cid == "wolf":
		var alive_foes := foes.filter(func(x): return x.alive).size()
		if alive_foes < 3 and randf() < 0.25:
			return {"type": "skill", "id": "e_bauantrag", "target": f}
		skills = ["e_wolfsbiss", "e_knirschen", "e_abriss"]
	if randf() < (0.2 if f.is_boss else 0.35) or skills.is_empty():
		return {"type": "attack", "target": tgt}
	var sid: String = skills[randi() % skills.size()]
	var s: Dictionary = Data.skill(sid)
	if s.get("target", "") in ["ally", "allies", "self"]:
		return {"type": "skill", "id": sid, "target": f}
	return {"type": "skill", "id": sid, "target": tgt}

# ------------------------------------------------------------------ execution
func _opponents(b: Battler) -> Array:
	return (foes if b.is_party else party).filter(func(x): return x.alive)

func _allies(b: Battler) -> Array:
	return (party if b.is_party else foes).filter(func(x): return x.alive)

func _resolve_targets(b: Battler, kind: String, t) -> Array:
	match kind:
		"enemies":
			return _opponents(b)
		"allies":
			return _allies(b)
		"self":
			return [b]
		"ko_ally":
			if t is Battler and not t.alive:
				return [t]
			var ko := (party if b.is_party else foes).filter(func(x): return not x.alive)
			return [ko[0]] if not ko.is_empty() else []
		"random_enemies":
			return _opponents(b)
		_:
			if t is Battler and t.alive:
				# respect the side
				return [t]
			var pool: Array = _opponents(b) if kind == "enemy" else _allies(b)
			return [pool[randi() % pool.size()]] if not pool.is_empty() else []

func _execute(b: Battler, c: Dictionary) -> void:
	if not b.is_party and randf() < 0.6:
		Audio.voice(b.cid, null, 0.75)
	elif b.is_party and randf() < 0.25:
		Audio.voice("jimmy" if b.cid == "jimmy" else "chicken", null, 0.5)
	match c["type"]:
		"defend":
			b.add_status("verteidigt", 1)
			await ui.banner("%s plustert sich auf." % b.display_name, 0.5)
		"attack":
			var tg := _resolve_targets(b, "enemy", c.get("target"))
			if tg.is_empty():
				return
			await _melee(b, tg[0], 1.0, "fx_slash" if b.is_party else "fx_claw", "peck" if b.is_party else "hit", {})
		"item":
			await _use_item(b, c["id"], c.get("target"))
		"skill":
			await _skill(b, c["id"], c.get("target"))

func _skill(b: Battler, sid: String, t) -> void:
	var s: Dictionary = Data.skill(sid)
	var cost := b.mp_cost(sid)
	if b.is_party:
		if b.mp < cost:
			await ui.banner("Nicht genug MP!", 0.6)
			return
		b.mp -= cost
	if s.get("once", false):
		b.once_used[sid] = true
	var targets := _resolve_targets(b, s.get("target", "enemy"), t)
	if targets.is_empty():
		return
	ui.skill_banner(s["name"], b.is_party)
	var focus_p: Vector3 = targets[0].global_position if targets.size() == 1 else (Vector3(-3, 0, 0) if not targets[0].is_party else Vector3(3, 0, 0))
	cam_focus(focus_p, 0.8 if s.get("kind", "") in ["phys", "mag"] else 0.4)
	if sid == "revolution" or sid == "e_schlachtzeit" or sid == "schlachtfest" or sid == "inferno":
		UI.flash(Color(1, 0.15, 0.1), 0.6, 0.55)
		Audio.sfx("thunder", 0.8)
		Engine.time_scale = 0.45
		await get_tree().create_timer(0.35, true, false, true).timeout
		Engine.time_scale = 1.0
	var kind: String = s.get("kind", "phys")
	match kind:
		"phys":
			var hits: int = s.get("hits", 1)
			if s.get("target", "") == "random_enemies":
				for h in hits:
					var pool := _opponents(b)
					if pool.is_empty():
						break
					await _melee(b, pool[randi() % pool.size()], s.get("power", 1.0), s.get("fx", "fx_slash"), s.get("sfx", "slash"), s, h < hits - 1)
			elif targets.size() > 1:
				await b.cast_anim()
				for tg in targets:
					if tg.alive:
						await _hit(b, tg, s.get("power", 1.0), s, false)
						play_fx(s.get("fx", "fx_slash"), tg.center())
						Audio.sfx_var(s.get("sfx", "slash"))
						await get_tree().create_timer(0.12).timeout
			else:
				for h in hits:
					if targets[0].alive:
						await _melee(b, targets[0], s.get("power", 1.0), s.get("fx", "fx_slash"), s.get("sfx", "slash"), s, h < hits - 1)
		"mag":
			await b.cast_anim()
			for tg in targets:
				if not tg.alive:
					continue
				play_fx(s.get("fx", "fx_fire"), tg.center(), 1.4)
				_burst(tg.center(), s.get("elem", "magic"))
				Audio.sfx_var(s.get("sfx", "magic_fire"))
				await get_tree().create_timer(0.18).timeout
				await _hit(b, tg, s.get("power", 1.0), s, true)
		"heal":
			await b.cast_anim()
			for tg in targets:
				if not tg.alive:
					continue
				var amt := 0
				if s.has("pct"):
					amt = int(tg.base["hp"] * s["pct"])
				else:
					amt = int(b.stat("mag") * s.get("power", 1.0) * 1.7 + 10)
				play_fx(s.get("fx", "fx_heal"), tg.center(), 1.2)
				_burst(tg.center(), "heal")
				Audio.sfx(s.get("sfx", "magic_heal"))
				_heal(tg, amt)
				if s.has("buff"):
					tg.add_status(s["buff"]["id"], s["buff"]["turns"])
				await get_tree().create_timer(0.15).timeout
		"revive":
			await b.cast_anim()
			for tg in targets:
				tg.alive = true
				tg.hp = int(tg.base["hp"] * s.get("power", 0.5))
				play_fx("fx_heal", tg.center(), 1.4)
				Audio.sfx("level_up")
				await tg.revive_anim()
				popup(tg.top(), "Wiederbelebt!", Color(0.6, 1, 0.6))
		"buff", "debuff":
			await b.cast_anim()
			for tg in targets:
				if not tg.alive:
					continue
				var bf: Dictionary = s["buff"]
				tg.add_status(bf["id"], bf["turns"])
				if bf["id"] == "beschuetzt":
					tg.protector = b
				play_fx(s.get("fx", "fx_buff"), tg.center())
				Audio.sfx(s.get("sfx", "buff"))
				popup(tg.top(), Data.STATUS[bf["id"]]["name"], Data.STATUS[bf["id"]]["color"])
				await get_tree().create_timer(0.12).timeout
		"status":
			await b.cast_anim()
			for tg in targets:
				if not tg.alive:
					continue
				play_fx(s.get("fx", "fx_poison"), tg.center())
				Audio.sfx(s.get("sfx", "poison"))
				_try_status(tg, s["status"])
				await get_tree().create_timer(0.12).timeout
		"special":
			await _special(b, s, targets)
	cam_reset()
	ui.refresh()

func _special(b: Battler, s: Dictionary, targets: Array) -> void:
	match s.get("effect", ""):
		"mana_ei":
			await b.cast_anim()
			var tg: Battler = targets[0]
			var cost := int(b.base["hp"] * 0.1)
			b.hp = max(1, b.hp - cost)
			var gain := int(tg.base["mp"] * 0.35)
			tg.mp = min(tg.base["mp"], tg.mp + gain)
			play_fx("fx_egg", tg.center())
			Audio.sfx("magic_heal")
			popup(tg.top(), "+%d MP" % gain, Color(0.5, 0.75, 1.0))
		"cleanse":
			await b.cast_anim()
			for tg in targets:
				tg.clear_bad()
				play_fx("fx_heal", tg.center())
			Audio.sfx("magic_heal")
		"steal":
			var tg: Battler = targets[0]
			await _melee(b, tg, s.get("power", 0.7), s.get("fx", "fx_claw"), "hit", {})
			var n := mini(Game.grains, randi_range(6, 18))
			if n > 0:
				Game.grains -= n
				Audio.sfx("coin")
				await ui.speech(b, "Danke für die %d Körner!" % n)
		"summon":
			await b.cast_anim()
			var alive_n := foes.filter(func(x): return x.alive).size()
			if alive_n < 4:
				var nb := _add_foe(s.get("summon", "guard"), foes.size())
				nb.sprite.set_alpha(0.0)
				var tw := create_tween()
				tw.tween_method(func(v): nb.sprite.set_alpha(v), 0.0, 1.0, 0.5)
				await ui.speech(b, "Security! Hier ist ein Huhn ohne Armband!")
		"charge":
			b.add_status("geladen", 2)
			await b.cast_anim()
			Audio.sfx("buff")
			await ui.speech(b, "Hühnchen ... deine Schlachtzeit ist JETZT.")

func _melee(b: Battler, tg: Battler, power: float, fx: String, snd: String, s: Dictionary, quick := false) -> void:
	# protector intercepts
	if tg.has_status("beschuetzt") and tg.protector and tg.protector.alive and tg.protector != b:
		popup(tg.top(), "Geschützt!", Color(0.7, 0.85, 1))
		tg = tg.protector
	await b.lunge_to(tg)
	b.strike_anim()
	play_fx(fx, tg.center(), 1.2)
	Audio.sfx_var(snd)
	await _hit(b, tg, power, s, false)
	if not quick:
		await get_tree().create_timer(0.08).timeout
		await b.return_home()
	else:
		await get_tree().create_timer(0.05).timeout
	# counter
	if tg.alive and tg.has_status("konter") and b.alive and not s.get("_counter", false):
		await ui.banner("%s kontert!" % tg.display_name, 0.4)
		await _melee(tg, b, 0.8, "fx_slash", "slash", {"_counter": true})
	if quick:
		return

func _hit(b: Battler, tg: Battler, power: float, s: Dictionary, magic: bool) -> void:
	if not tg.alive:
		return
	# miss
	if not magic and b.has_status("blind") and randf() < 0.5:
		popup(tg.top(), "Daneben!", Color(0.8, 0.8, 0.8))
		Audio.sfx("whoosh")
		return
	if not magic and randf() < clamp((tg.stat("spd") - b.stat("spd")) * 0.008, 0.0, 0.12):
		popup(tg.top(), "Ausgewichen!", Color(0.8, 0.8, 0.8))
		Audio.sfx("whoosh")
		return
	var atk: float = b.stat("mag") if magic else (b.stat("def") * 1.1 if s.get("use_def", false) else b.stat("atk"))
	var dfn: float = tg.stat("res") if magic else tg.stat("def")
	var dmg := power * atk * 2.2 * 100.0 / (100.0 + dfn * 3.2) * randf_range(0.9, 1.1)
	if tg.is_party:
		dmg *= 0.55
	if s.has("execute") and float(tg.hp) / tg.base["hp"] < s["execute"]:
		dmg *= 2.6
	var crit := false
	var cc: float = b.base.get("crit", 5) / 100.0 + s.get("crit_bonus", 0.0)
	if b.has_status("sicherer_krit") and not magic:
		cc = 1.0
		b.statuses.erase("sicherer_krit")
	if randf() < cc:
		crit = true
		dmg *= 1.75
	if tg.has_status("verteidigt"):
		dmg *= 0.5
	var n := maxi(1, int(dmg))
	await damage(tg, n, crit, b)
	if b.is_party and b.alive and b.passive("lifesteal") > 0:
		_heal(b, int(n * b.passive("lifesteal")), true)
	if not magic and tg.is_party and tg.alive and tg.passive("thorns") > 0 and b.alive:
		await damage(b, int(n * tg.passive("thorns")), false, null)
	if s.has("status") and tg.alive:
		_try_status(tg, s["status"])

func damage(tg: Battler, n: int, crit: bool, src: Battler) -> void:
	if Game.god and tg.is_party:
		n = 0
	if tg.is_party and tg.hp - n <= 0 and tg.passive("endure") > 0 and not tg.endure_used:
		tg.endure_used = true
		n = tg.hp - 1
		popup(tg.top() + Vector3(0, 0.3, 0), "Letztes Gegacker!", Color(1, 0.8, 0.3))
	tg.hp = max(0, tg.hp - n)
	tg.hurt_anim(crit)
	popup(tg.top(), str(n) + ("!" if crit else ""), Color(1, 0.95, 0.4) if crit else Color(1, 1, 1), crit)
	if crit:
		shake(0.9)
		UI.flash(Color(1, 0.9, 0.8), 0.15, 0.25)
		Audio.sfx("hit_crit")
		Engine.time_scale = 0.35
		await get_tree().create_timer(0.12, true, false, true).timeout
		Engine.time_scale = 1.0
	else:
		shake(0.35)
	_burst(tg.center(), "feathers" if tg.chicken else "blood")
	tg.update_bar()
	if tg.hp <= 0:
		await _kill(tg)

func _kill(tg: Battler) -> void:
	tg.alive = false
	tg.statuses.clear()
	if tg.is_party:
		Audio.sfx("chicken_ko")
		popup(tg.top() + Vector3(0, 0.25, 0), "K.O.", Color(1, 0.4, 0.4))
		tg.die_anim()
	else:
		var e: Dictionary = Data.ENEMIES[tg.cid]
		total_xp += int(e["xp"] * 1.3)
		total_grains += e["grains"]
		for dr in e.get("drops", []):
			if randf() < dr[1]:
				drops.append(dr[0])
		Game.kills += 1
		Audio.sfx("enemy_die", randf_range(0.85, 1.1))
		Audio.sfx("blood_splat")
		play_fx("fx_blood", tg.center(), 1.6)
		_burst(tg.center(), "blood_big")
		_blood_decal(tg.global_position)
		if e.has("death") and randf() < (1.0 if tg.is_boss else 0.55):
			ui.speech(tg, e["death"])
		await tg.die_anim()

## Expected outcome of an action on a target, shown while targeting.
func estimate(b: Battler, tg: Battler, sid: String) -> String:
	var s: Dictionary = {"kind": "phys", "power": 1.0} if sid == "attack" else Data.skill(sid)
	var kind: String = s.get("kind", "phys")
	if kind in ["phys", "mag"]:
		var magic := kind == "mag"
		var atk: float = b.stat("mag") if magic else (b.stat("def") * 1.1 if s.get("use_def", false) else b.stat("atk"))
		var dfn: float = tg.stat("res") if magic else tg.stat("def")
		var d: float = s.get("power", 1.0) * atk * 2.2 * 100.0 / (100.0 + dfn * 3.2)
		if tg.is_party:
			d *= 0.55
		var hits: int = s.get("hits", 1)
		var lo := int(d * 0.9) * hits
		var hi := int(d * 1.1) * hits
		return "≈ %d–%d Schaden" % [lo, hi]
	if kind == "heal":
		var amt := int(tg.base["hp"] * s["pct"]) if s.has("pct") else int(b.stat("mag") * s.get("power", 1.0) * 1.7 + 10)
		return "heilt ≈ %d" % amt
	if kind == "revive":
		return "belebt mit %d%% HP" % int(s.get("power", 0.5) * 100)
	if s.has("status"):
		return "%s (%d%%)" % [Data.STATUS[s["status"]["id"]]["name"], int(s["status"].get("chance", 1.0) * 100)]
	return ""

func _blood_decal(p: Vector3) -> void:
	var t := Data.tex("res://assets/fx/blood_puddle.png")
	if t == null:
		return
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(t.get_width(), t.get_height()) / 26.0
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.roughness = 0.2
	mi.material_override = m
	add_child(mi)
	mi.global_position = p + Vector3(-0.3, 0.015, 0)
	mi.scale = Vector3(0.2, 1, 0.2)
	create_tween().tween_property(mi, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _heal(tg: Battler, amt: int, quiet := false) -> void:
	if amt <= 0:
		return
	tg.hp = min(tg.base["hp"], tg.hp + amt)
	popup(tg.top() + (Vector3(0.3, 0.2, 0) if quiet else Vector3.ZERO), "+%d" % amt, Color(0.5, 1, 0.55))

func _try_status(tg: Battler, st: Dictionary) -> void:
	var ch: float = st.get("chance", 1.0)
	if tg.is_boss and st["id"] == "betaeubt":
		ch *= 0.35
	if randf() < ch:
		tg.add_status(st["id"], st.get("turns", 2))
		popup(tg.top() + Vector3(0, 0.25, 0), Data.STATUS[st["id"]]["name"], Data.STATUS[st["id"]]["color"])
	else:
		popup(tg.top() + Vector3(0, 0.25, 0), "Wirkungslos", Color(0.7, 0.7, 0.7))

func _use_item(b: Battler, item: String, t) -> void:
	var it: Dictionary = Data.ITEMS[item]
	var e: Dictionary = it["effect"]
	var tg: Battler = t if t is Battler else b
	if not Game.remove_item(item):
		return
	ui.skill_banner(it["name"], true)
	await b.cast_anim()
	if e.has("revive"):
		if not tg.alive:
			tg.alive = true
			tg.hp = int(tg.base["hp"] * e["revive"])
			await tg.revive_anim()
			popup(tg.top(), "Wiederbelebt! Farben!", Color(0.9, 0.6, 1.0))
			play_fx("fx_heal", tg.center(), 1.3)
		return
	if not tg.alive:
		return
	if e.has("hp"):
		_heal(tg, e["hp"])
		play_fx("fx_heal", tg.center())
	if e.has("mp"):
		tg.mp = min(tg.base["mp"], tg.mp + e["mp"])
		popup(tg.top() + Vector3(0, 0.25, 0), "+%d MP" % e["mp"], Color(0.5, 0.75, 1.0))
	if e.has("buff"):
		var tgs: Array = party.filter(func(x): return x.alive) if e.get("team", false) else [tg]
		for x in tgs:
			x.add_status(e["buff"], 4)
			popup(x.top() + Vector3(0, 0.45, 0), Data.STATUS[e["buff"]]["name"], Data.STATUS[e["buff"]]["color"])
	Audio.sfx("magic_heal")

func _end_of_round() -> void:
	var poison_mult := 1.0
	for p in party:
		if p.passive("poison_mult") > 0:
			poison_mult = 2.0
	for b in party + foes:
		if not b.alive:
			continue
		if b.has_status("gift"):
			var n := int(b.base["hp"] * 0.07 * (poison_mult if not b.is_party else 1.0)) + 2
			if b.is_boss:
				n = int(n * 0.5)
			popup(b.top(), str(n), Color(0.8, 0.45, 1.0))
			play_fx("fx_poison", b.center(), 0.8)
			await damage(b, n, false, null)
		if b.alive and b.has_status("blutung"):
			var n2 := int(b.base["hp"] * 0.06) + 3
			if b.is_boss:
				n2 = int(n2 * 0.5)
			await damage(b, n2, false, null)
		if b.alive and (b.has_status("regen") or b.has_status("unverwuestlich")):
			_heal(b, int(b.base["hp"] * 0.08))
		for s in b.statuses.keys():
			if b.statuses[s] < 90:
				b.statuses[s] -= 1
			if b.statuses[s] <= 0:
				b.statuses.erase(s)
	await get_tree().create_timer(0.2).timeout

func _finish() -> String:
	for b in party:
		b.sync_to_game()
	if result == "win":
		if opts.get("boss", false):
			Audio.music_pick(["boss_victory", "victory"], "victory", 0.2)
		else:
			Audio.music_pick(["victory", "victory_2", "victory_3"], "victory", 0.2)
		for b in party:
			if b.alive:
				b.hp = min(b.base["hp"], b.hp + int(b.base["hp"] * 0.15))
				b.sync_to_game()
		for b in party:
			if b.alive:
				b.hop()
		await get_tree().create_timer(0.3).timeout
		for b in party:
			if b.alive:
				b.hop()
		var lv := Game.add_xp(total_xp)
		Game.add_grains(total_grains, false)
		for d in drops:
			Game.add_item(d, 1, false)
		# food buffs run out
		for fb in Game.food_buffs:
			fb["battles"] = int(fb["battles"]) - 1
		Game.food_buffs = Game.food_buffs.filter(func(x): return int(x["battles"]) > 0)
		await ui.results(total_xp, total_grains, drops, lv)
	elif result == "lose":
		Audio.music("gameover", 0.3)
		await ui.banner("Alle Hühner sind K.O.", 1.2)
	return result

# ------------------------------------------------------------------ fx
func play_fx(fx: String, pos: Vector3, scl := 1.0) -> void:
	var t := Data.tex("res://assets/fx/%s.png" % fx)
	if t == null:
		return
	var meta: Dictionary = _fx_meta.get(fx, {})
	var frames: int = meta.get("frames", max(1, t.get_width() / max(1, t.get_height())))
	var s := Sprite3D.new()
	s.texture = t
	s.hframes = frames
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true
	s.render_priority = 3
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.pixel_size = 0.025 * scl
	s.modulate = Color(1.6, 1.6, 1.6)
	add_child(s)
	s.global_position = pos + Vector3(0, 0, 0.4)
	var tw := create_tween()
	tw.tween_method(func(v): s.frame = mini(int(v), frames - 1), 0.0, float(frames) - 0.01, frames * 0.055)
	tw.tween_callback(s.queue_free)

func _burst(pos: Vector3, kind: String) -> void:
	## Smooth 3D particle bursts that intentionally break the pixel look.
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0.3)
	pm.spread = 70.0
	pm.gravity = Vector3(0, -6, 0)
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.0
	pm.angular_velocity_min = -300
	pm.angular_velocity_max = 300
	pm.angle_min = -180
	pm.angle_max = 180
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	match kind:
		"feathers":
			p.amount = 10
			p.lifetime = 1.6
			pm.gravity = Vector3(0, -1.2, 0)
			pm.initial_velocity_min = 1.0
			pm.initial_velocity_max = 2.6
			pm.damping_min = 2.0
			pm.damping_max = 3.0
			q.size = Vector2(0.12, 0.24)
			m.albedo_texture = Data.tex("res://assets/fx/feather.png")
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		"blood", "blood_big":
			p.amount = 14 if kind == "blood" else 40
			q.size = Vector2(0.07, 0.07)
			m.albedo_color = Color(0.7, 0.02, 0.04)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_texture = Data.tex("res://assets/fx/spark.png")
			pm.initial_velocity_max = 5.0 if kind == "blood_big" else 3.5
		"heal":
			p.amount = 24
			pm.gravity = Vector3(0, 1.5, 0)
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 1.2
			pm.spread = 180.0
			q.size = Vector2(0.08, 0.08)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(0.6, 2.0, 0.8)
			m.albedo_texture = Data.tex("res://assets/fx/spark.png")
		_:
			p.amount = 30
			pm.gravity = Vector3(0, 0.5, 0)
			pm.spread = 180.0
			q.size = Vector2(0.09, 0.09)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			var col := {"feuer": Color(3.0, 1.2, 0.3), "eis": Color(0.8, 1.6, 3.0), "blitz": Color(2.5, 2.5, 1.0)}
			m.albedo_color = col.get(kind, Color(1.8, 1.0, 2.6))
			m.albedo_texture = Data.tex("res://assets/fx/spark.png")
	q.material = m
	p.draw_pass_1 = q
	p.process_material = pm
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)
	if kind in ["feuer", "blitz"]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.2) if kind == "feuer" else Color(0.8, 0.85, 1.0)
		l.light_energy = 5.0
		l.omni_range = 5.0
		add_child(l)
		l.global_position = pos + Vector3(0, 0.3, 0.6)
		var tw := create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.6)
		tw.tween_callback(l.queue_free)

func popup(pos: Vector3, text: String, col: Color, big := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = UI.font
	l.font_size = 40 if big else 30
	l.pixel_size = 0.0125
	l.modulate = col
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0, 0.5)
	var tw := create_tween()
	tw.tween_property(l, "global_position:y", l.global_position.y + 0.55, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)

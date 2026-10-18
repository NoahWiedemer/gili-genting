class_name Battler
extends Node3D
## One combatant in a battle (party chicken or enemy) incl. stats, statuses and animations.

var is_party := false
var cid := ""           # character id (party) or enemy id
var display_name := ""
var base := {}          # max stats
var hp := 1
var mp := 0
var statuses := {}      # id -> turns left
var protector: Battler
var alive := true
var home := Vector3.ZERO
var sprite: PixelSprite
var hp_bar: MeshInstance3D
var hp_fill: MeshInstance3D
var is_boss := false
var endure_used := false
var once_used := {}
var battle
var chicken := true
var _t := 0.0
var _idle := true
var shadow: MeshInstance3D
var anim: SpriteAnim

func setup_party(id: String) -> void:
	is_party = true
	cid = id
	display_name = Game.char_name(id)
	base = Game.stats(id)
	hp = Game.chars[id]["hp"]
	mp = Game.chars[id]["mp"]
	alive = hp > 0
	_make_sprite(Game.char_sprite(id))
	sprite.set_flip(true)  # chickens face left toward the enemies
	if not alive:
		_ko_pose()

func setup_enemy(eid: String) -> void:
	is_party = false
	cid = eid
	var e: Dictionary = Data.ENEMIES[eid]
	display_name = e["name"]
	# enemies are tanky (longer fights) but hit softer (see Battle._hit)
	var hp_mult := 1.25 if e.get("boss", false) else 2.4
	base = {"hp": int(e["hp"] * hp_mult), "mp": 99, "atk": e["atk"], "def": e["def"], "mag": e["mag"], "res": e["res"], "spd": e["spd"], "crit": 5}
	hp = base["hp"]
	mp = 99
	is_boss = e.get("boss", false)
	chicken = false
	_make_sprite(e["sprite"])
	_make_hp_bar()

func _make_sprite(s: String) -> void:
	sprite = PixelSprite.make(Data.sprite_tex(s))
	add_child(sprite)
	anim = SpriteAnim.attach(sprite, s)
	shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(max(0.6, sprite.width), 0.35)
	shadow.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var t := Data.tex("res://assets/fx/shadow_blob.png")
	m.albedo_texture = t
	m.albedo_color = Color(0, 0, 0, 0.55) if t else Color(0, 0, 0, 0.3)
	shadow.material_override = m
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position.y = 0.02
	add_child(shadow)
	_t = randf() * 5.0

func _make_hp_bar() -> void:
	var w: float = clamp(sprite.width * 0.8, 0.6, 1.4)
	hp_bar = _bar_quad(Vector2(w + 0.04, 0.09), Color(0.05, 0.03, 0.03))
	hp_fill = _bar_quad(Vector2(w, 0.05), Color(0.85, 0.15, 0.15))
	hp_fill.material_override.render_priority = 3
	hp_bar.position = Vector3(0, -0.12, 0.3)
	hp_fill.position = Vector3(0, -0.12, 0.31)
	add_child(hp_bar)
	add_child(hp_fill)
	hp_fill.set_meta("w", w)

func _bar_quad(size: Vector2, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	m.render_priority = 2
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func update_bar() -> void:
	if hp_fill == null:
		return
	var w: float = hp_fill.get_meta("w")
	var r: float = clamp(float(hp) / base["hp"], 0.0, 1.0)
	hp_fill.scale.x = max(r, 0.001)
	hp_fill.position.x = -w * (1.0 - r) * 0.5
	hp_bar.visible = alive
	hp_fill.visible = alive

func _process(delta: float) -> void:
	_t += delta
	if anim:
		anim.active = _idle and alive
		anim.facing = -1.0 if sprite.is_flipped() else 1.0
	if _idle and alive and sprite and anim == null:
		var s := 1.0 + sin(_t * (2.6 if chicken else 1.8)) * (0.03 if chicken else 0.018)
		if has_status("betaeubt"):
			sprite.rotation.z = sin(_t * 6.0) * 0.12
		sprite.scale = Vector3(1.0 / sqrt(s), s, 1.0)

# ------------------------------------------------------------------ stats
func stat(k: String) -> float:
	var v: float = base.get(k, 0)
	match k:
		"atk":
			if has_status("atk_up"): v *= 1.3
			if has_status("atk_down"): v *= 0.75
		"def":
			if has_status("def_up"): v *= 1.45
			if has_status("def_down"): v *= 0.7
			if has_status("unverwuestlich"): v *= 2.0
			if has_status("verteidigt"): v *= 1.3
		"spd":
			if has_status("langsam"): v *= 0.6
			if has_status("spd_up"): v *= 1.3
		"mag":
			if has_status("atk_up"): v *= 1.15
		"res":
			if has_status("def_up"): v *= 1.25
	return v

func passive(key: String) -> float:
	return Game.passive(cid, key) if is_party else 0.0

func has_status(s: String) -> bool:
	return statuses.get(s, 0) > 0

func add_status(s: String, turns: int) -> void:
	statuses[s] = max(statuses.get(s, 0), turns)

func clear_bad() -> void:
	for s in statuses.keys():
		if Data.STATUS.get(s, {}).get("bad", false):
			statuses.erase(s)

func mp_cost(sid: String) -> int:
	var c: int = Data.skill(sid).get("mp", 0)
	return int(round(c * (1.0 + passive("mp_cost"))))

func sync_to_game() -> void:
	if is_party:
		Game.chars[cid]["hp"] = max(hp, 1) if alive else 1
		Game.chars[cid]["mp"] = mp

# ------------------------------------------------------------------ animation helpers
func top() -> Vector3:
	return global_position + Vector3(0, sprite.height + 0.15, 0)

func center() -> Vector3:
	return global_position + Vector3(0, sprite.height * 0.5, 0.05)

func step_forward(on: bool) -> void:
	var dir := -1.0 if is_party else 1.0
	var tw := create_tween()
	tw.tween_property(self, "position:x", home.x + (dir * 0.5 if on else 0.0), 0.15)

func lunge_to(target: Battler) -> void:
	_idle = false
	var dir := 1.0 if target.global_position.x > global_position.x else -1.0
	var dest := target.global_position - Vector3(dir * (target.sprite.width * 0.5 + sprite.width * 0.4 + 0.15), 0, -0.02)
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector3(1.15, 0.85, 1), 0.07)
	tw.tween_property(self, "global_position", dest, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(sprite, "position:y", 0.25, 0.09)
	tw.tween_property(sprite, "position:y", 0.0, 0.09)
	tw.parallel().tween_property(sprite, "scale", Vector3(0.9, 1.1, 1), 0.09)
	await tw.finished

func strike_anim() -> void:
	var tw := create_tween()
	var dir := -1.0 if is_party else 1.0
	tw.tween_property(sprite, "rotation:z", dir * -0.35, 0.06)
	tw.tween_property(sprite, "rotation:z", dir * 0.25, 0.06)
	tw.tween_property(sprite, "rotation:z", 0.0, 0.1)
	await tw.finished

func return_home() -> void:
	var tw := create_tween()
	tw.tween_property(self, "position", home, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "scale", Vector3.ONE, 0.2)
	await tw.finished
	_idle = true

func cast_anim() -> void:
	_idle = false
	sprite.set_emission(0.0)
	var tw := create_tween()
	tw.tween_property(sprite, "position:y", 0.35, 0.18).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_method(func(v): sprite.set_flash(v, Color(1, 0.95, 0.7)), 0.0, 0.6, 0.18)
	tw.tween_property(sprite, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_BOUNCE)
	tw.parallel().tween_method(func(v): sprite.set_flash(v, Color(1, 0.95, 0.7)), 0.6, 0.0, 0.2)
	await tw.finished
	_idle = true

func hurt_anim(crit := false) -> void:
	sprite.flash_hit(Color(1, 1, 1) if not crit else Color(1, 0.3, 0.2), 0.3)
	var tw := create_tween()
	var dir := 1.0 if is_party else -1.0
	var amt := 0.18 if crit else 0.1
	tw.tween_property(sprite, "position:x", dir * amt, 0.05)
	tw.tween_property(sprite, "position:x", -dir * amt * 0.6, 0.05)
	tw.tween_property(sprite, "position:x", dir * amt * 0.3, 0.05)
	tw.tween_property(sprite, "position:x", 0.0, 0.05)

func hop() -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "position:y", 0.3, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func die_anim() -> void:
	_idle = false
	if hp_bar:
		hp_bar.visible = false
		hp_fill.visible = false
	if is_party:
		_ko_pose()
		return
	sprite.flash_hit(Color(1, 0.1, 0.1), 0.5)
	var tw := create_tween()
	tw.tween_property(sprite, "rotation:z", -1.45 if global_position.x < 0 else 1.45, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "position:x", -sprite.height * 0.35, 0.45)
	tw.tween_interval(0.5)
	tw.tween_method(func(v): sprite.set_alpha(v), 1.0, 0.0, 0.7)
	tw.tween_callback(func(): visible = false)
	await tw.finished

func _ko_pose() -> void:
	_idle = false
	var tw := create_tween()
	tw.tween_property(sprite, "rotation:z", -1.5, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "position:y", 0.05, 0.3)
	tw.parallel().tween_property(sprite, "position:x", -sprite.height * 0.3, 0.3)
	sprite.set_tint(Color(0.6, 0.55, 0.6))

func revive_anim() -> void:
	sprite.set_tint(Color.WHITE)
	var tw := create_tween()
	tw.tween_property(sprite, "rotation:z", 0.0, 0.3)
	tw.parallel().tween_property(sprite, "position", Vector3.ZERO, 0.3)
	await tw.finished
	_idle = true

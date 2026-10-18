class_name Player
extends CharacterBody3D
## The chicken. 8-directional movement, hopping walk, interaction, party followers.

const SPEED := 3.4
const RUN := 5.6

var map
var sprite: PixelSprite
var facing := Vector3(1, 0, 0)
var _hop := 0.0
var _trail: Array[Vector3] = []
var followers: Array = []
var _step_t := 0.0
var frozen := false
var _prompt: Label3D
var _near: Node3D
var _think_t := 25.0
var anim: SpriteAnim
var _fanims: Array = []

const THOUGHTS := [
	"Nahrung? Nein. Ich nenne es pure Chemie.",
	"Ich muss überleben, um zu sterben.",
	"Denkt ihr oft an den Tod?",
	"Die Einsamkeit ist kein angenehmer Begleiter.",
	"Wie warm sich das Ertrinken wohl anfühlt?",
	"Eier legen ist auch keine Lösung.",
	"Riecht hier jemand Grillkohle? ... Nein. Gut.",
	"Ich frage mich, ob Touristen nach Huhn schmecken.",
	"Der Zeiger tickt. Tick. Tack. Schlacht.",
	"Wenn ich sterbe, will ich wenigstens mit Sambal.",
	"Paradies. Klingt nach einem Ort ohne Bratpfannen.",
]
const COMPANION_THOUGHTS := {
	"jimmy": ["Ich passe auf dich auf.", "Ich hab einer Mücke heute nichts getan. Bin stolz.", "Sind wir bald da? Meine Muskeln haben Hunger."],
	"vian": ["Ich schmecke Regen. Oder Blut.", "Mein linkes Auge sieht Ärger. Das rechte sieht nichts.", "Früher war mehr Dschungel."],
	"nugget": ["Der Fußring sagt, wir werden verfolgt.", "Ein Fenster so klein wie ein Ei ...", "Ich bin ein Sack Reis. Ich bin ein Sack Reis."],
	"paprika": ["In Wien hätte man mir applaudiert.", "Mehr Feuer! Das Publikum will Feuer!", "Ich spüre ein Finale nahen. Ein blutiges."],
}

func _think() -> void:
	## Random thought bubble from the chicken or a companion while exploring.
	var who: Node3D = self
	var text: String = THOUGHTS[randi() % THOUGHTS.size()]
	var comps := Game.party.filter(func(x): return x != "" and x != "ania")
	if not comps.is_empty() and randf() < 0.45:
		var cid: String = comps[randi() % comps.size()]
		var idx := comps.find(cid)
		if idx < followers.size():
			who = followers[idx]
			text = COMPANION_THOUGHTS[cid][randi() % COMPANION_THOUGHTS[cid].size()]
	var l := Label3D.new()
	l.text = text
	l.font = UI.font
	l.font_size = 20
	l.pixel_size = 0.0105
	l.modulate = Color(0.85, 0.95, 1.0)
	l.outline_size = 6
	l.outline_modulate = Color(0.04, 0.05, 0.1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 5
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.width = 260
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	who.add_child(l)
	l.position = Vector3(0, 1.35, 0)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(l, "position:y", 1.5, 0.4)
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.26
	sh.height = 0.8
	cs.shape = sh
	cs.position = Vector3(0, 0.4, 0)
	add_child(cs)
	sprite = PixelSprite.make(Data.sprite_tex(Game.char_sprite("ania")))
	add_child(sprite)
	anim = SpriteAnim.attach(sprite, Game.char_sprite("ania"))
	var sh2 := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.28)
	q.orientation = PlaneMesh.FACE_Y
	sh2.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var t := Data.tex("res://assets/fx/shadow_blob.png")
	m.albedo_texture = t
	m.albedo_color = Color(0, 0, 0, 0.5) if t else Color(0, 0, 0, 0.25)
	sh2.material_override = m
	sh2.position.y = 0.02
	sh2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sh2)
	_prompt = Label3D.new()
	_prompt.font = UI.font
	_prompt.font_size = 20
	_prompt.pixel_size = 0.011
	_prompt.outline_size = 6
	_prompt.outline_modulate = Color.BLACK
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.render_priority = 6
	_prompt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_prompt.modulate = Color(1, 0.9, 0.5)
	_prompt.text = "E"
	_prompt.visible = false
	map.add_child.call_deferred(_prompt)
	Game.party_changed.connect(refresh_party)
	refresh_party.call_deferred()

func refresh_party() -> void:
	sprite.set_tex(Data.sprite_tex(Game.char_sprite("ania")))
	for f in followers:
		f.queue_free()
	followers.clear()
	_fanims.clear()
	var i := 0
	for id in Game.party:
		if id == "" or id == "ania":
			continue
		var s := PixelSprite.make(Data.sprite_tex(Game.char_sprite(id)))
		var holder := Node3D.new()
		holder.add_child(s)
		_fanims.append(SpriteAnim.attach(s, Game.char_sprite(id)))
		map.add_child(holder)
		holder.global_position = global_position - facing * (0.8 * (i + 1))
		followers.append(holder)
		i += 1
	_trail.clear()
	for k in 60:
		_trail.append(global_position)

func can_move() -> bool:
	return not frozen and not UI.is_busy() and map and map.active

func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if can_move():
		var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		dir = Vector3(v.x, 0, v.y)
	var spd := RUN if Input.is_action_pressed("run") else SPEED
	if dir.length() > 0.1:
		facing = dir.normalized()
		velocity = dir.limit_length(1.0) * spd
		if abs(dir.x) > 0.15:
			sprite.set_flip(dir.x < 0)
	else:
		velocity = Vector3.ZERO
	move_and_slide()
	# ground height (shallow water etc.)
	var gh: float = map.ground_height(global_position)
	global_position.y = lerp(global_position.y, gh, 0.3)
	# hop animation
	var moving := velocity.length() > 0.2
	if anim:
		anim.active = not moving
		anim.facing = -1.0 if sprite.is_flipped() else 1.0
	for fa in _fanims:
		if fa:
			fa.active = not moving
	if moving:
		_hop += delta * (15.0 if spd == RUN else 12.0)
		var h: float = abs(sin(_hop))
		sprite.position.y = h * 0.09
		sprite.scale = Vector3(1.0 + (1.0 - h) * 0.08, 1.0 - (1.0 - h) * 0.08, 1)
		sprite.rotation.z = sin(_hop * 0.5) * 0.06
		_step_t -= delta
		if _step_t <= 0:
			_step_t = 0.26 if spd == RUN else 0.34
			Audio.sfx("step", randf_range(0.85, 1.2), 0.25)
		if global_position.distance_to(_trail[0]) > 0.08:
			_trail.push_front(global_position)
			_trail.pop_back()
	else:
		_hop = 0.0
		sprite.position.y = lerp(sprite.position.y, 0.0, 0.3)
		if anim == null:
			sprite.rotation.z = lerp(sprite.rotation.z, 0.0, 0.3)
	_update_followers(moving)
	_update_prompt()
	_tick_thoughts(delta, moving)

func _update_followers(moving: bool) -> void:
	for i in followers.size():
		var f: Node3D = followers[i]
		var idx := mini((i + 1) * 9, _trail.size() - 1)
		var target: Vector3 = _trail[idx]
		var prev := f.global_position
		f.global_position = f.global_position.lerp(target, 0.25)
		var s: PixelSprite = f.get_child(0)
		var dx := f.global_position.x - prev.x
		if abs(dx) > 0.004:
			s.set_flip(dx < 0)
			if i < _fanims.size() and _fanims[i]:
				_fanims[i].facing = -1.0 if dx < 0 else 1.0
		if moving:
			s.position.y = abs(sin(_hop + i * 1.3)) * 0.07
		else:
			s.position.y = lerp(s.position.y, 0.0, 0.3)

func _tick_thoughts(delta: float, moving: bool) -> void:
	if not can_move():
		return
	_think_t -= delta * (1.0 if moving else 0.4)
	if _think_t <= 0.0:
		_think_t = randf_range(28.0, 50.0)
		_think()

func _update_prompt() -> void:
	_near = map.find_interactable(global_position, facing) if can_move() else null
	if _near:
		_prompt.visible = true
		var h: float = 1.0
		if _near.get("sprite") and _near.sprite:
			h = _near.sprite.height
		_prompt.global_position = _near.global_position + Vector3(0, h + 0.35 + sin(Time.get_ticks_msec() * 0.008) * 0.05, 0)
		_prompt.text = "E"
	else:
		_prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not can_move():
		return
	if event.is_action_pressed("accept") and _near:
		get_viewport().set_input_as_handled()
		var n := _near
		_prompt.visible = false
		if n.has_method("face_towards"):
			n.face_towards(global_position)
		sprite.set_flip(n.global_position.x < global_position.x)
		map.active = false
		await n.interact()
		if is_instance_valid(map):
			map.active = true
	elif event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		map.open_menu()

func teleport(p: Vector3) -> void:
	global_position = p
	for i in _trail.size():
		_trail[i] = p
	for f in followers:
		f.global_position = p

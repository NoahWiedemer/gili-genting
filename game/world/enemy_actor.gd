class_name EnemyActor
extends Actor
## Visible overworld enemy: wanders around its home, chases the player, starts a battle on contact.

var home := Vector3.ZERO
var target := Vector3.ZERO
var speed := 1.3
var chase_speed := 2.5
var aggro := 3.2
var wait := 0.0
var cooldown := 0.0
var sleeping := false
var _hop := 0.0
var _zzz: Label3D
var _bark_t := 4.0
var _voice_t := 3.0

func init_enemy() -> void:
	home = global_position
	target = home
	interactable = false
	idle_anim = true
	speed = ent.get("speed", 1.3)
	chase_speed = minf(ent.get("chase", 2.5), 3.2)
	aggro = minf(ent.get("aggro", 3.2), 3.4)
	sleeping = ent.get("sleeping", false)
	if sleeping:
		_zzz = Label3D.new()
		_zzz.text = "z Z"
		_zzz.font = UI.font
		_zzz.font_size = 20
		_zzz.pixel_size = 0.011
		_zzz.modulate = Color(0.7, 0.8, 1.0)
		_zzz.outline_size = 6
		_zzz.outline_modulate = Color.BLACK
		_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_zzz.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_zzz.position = Vector3(0.3, sprite.height + 0.2, 0)
		add_child(_zzz)

func _process(delta: float) -> void:
	super._process(delta)
	if map == null or not map.active or map.player == null:
		return
	if cooldown > 0:
		cooldown -= delta
		return
	var pp: Vector3 = map.player.global_position
	var dist := global_position.distance_to(pp)
	if dist < 0.75:
		map.encounter(self)
		return
	if sleeping:
		if _zzz:
			_zzz.position.y = sprite.height + 0.2 + sin(_t * 2.0) * 0.08
		# sneaking (walking) keeps them asleep -> first strike; running wakes them up
		if dist < 2.6 and Input.is_action_pressed("run"):
			_wake()
		return
	_bark_t -= delta
	if _bark_t <= 0.0:
		_bark_t = randf_range(7.0, 16.0)
		if dist < 7.0:
			var q: Array = Data.ENEMIES[ent["group"][0]].get("quips", [])
			if not q.is_empty():
				bark(q[randi() % q.size()])
			Audio.voice(ent["group"][0], global_position)
	_voice_t -= delta
	if _voice_t <= 0.0:
		_voice_t = randf_range(5.0, 11.0)
		Audio.voice(ent["group"][0], global_position, 0.55)
	var goal := target
	var spd := speed
	if dist < aggro:
		goal = pp
		spd = chase_speed
		if marker == null or not marker.visible:
			set_marker("!", Color(1, 0.3, 0.25))
			Audio.sfx("ui_error", 1.4, 0.3)
			Audio.voice(ent["group"][0], global_position, 0.9)
	else:
		if marker and marker.visible:
			marker.visible = false
		wait -= delta
		if global_position.distance_to(target) < 0.2 and wait <= 0:
			wait = randf_range(1.0, 3.0)
			var r: float = ent.get("radius", 2.5)
			target = home + Vector3(randf_range(-r, r), 0, randf_range(-r, r))
		if wait > 0:
			goal = global_position
	var v := goal - global_position
	v.y = 0
	if v.length() > 0.05:
		var step := v.normalized() * spd * delta
		var nxt := global_position + step
		if map.is_walkable_pos(nxt):
			global_position = nxt
		else:
			target = home
		sprite.set_flip(v.x < 0)
		if anim:
			anim.facing = -1.0 if v.x < 0 else 1.0
		_hop += delta * 10.0
		sprite.position.y = abs(sin(_hop)) * 0.05
	else:
		sprite.position.y = 0

func _wake() -> void:
	sleeping = false
	if _zzz:
		_zzz.queue_free()
		_zzz = null
	set_marker("!", Color(1, 0.3, 0.25))
	Audio.sfx("ui_error", 1.4, 0.5)

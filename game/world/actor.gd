class_name Actor
extends Node3D
## A world character/object made of a PixelSprite. Base for NPCs, enemies, chests, pickups.

signal interacted

var sprite: PixelSprite
var ent := {}             # entity definition from the map
var map                   # Map node
var interact_radius := 1.3
var interactable := true
var bob := 0.0
var idle_anim := true
var _t := 0.0
var _base_scale := Vector3.ONE
var marker: Label3D
var shadow: MeshInstance3D
var anim: SpriteAnim

func setup_sprite(sprite_name: String, sway := 0.0, flip := false) -> void:
	sprite = PixelSprite.make(Data.sprite_tex(sprite_name), sway)
	sprite.set_flip(flip)
	add_child(sprite)
	_add_shadow()
	if ent.get("type", "") in ["npc", "enemy"]:
		anim = SpriteAnim.attach(sprite, sprite_name)
		if anim:
			anim.facing = -1.0 if flip else 1.0
	_t = randf() * 10.0

func _add_shadow() -> void:
	shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(max(0.5, sprite.width * 0.9), 0.3)
	q.orientation = PlaneMesh.FACE_Y
	shadow.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var t := Data.tex("res://assets/fx/shadow_blob.png")
	if t:
		m.albedo_texture = t
		m.albedo_color = Color(0, 0, 0, 0.5)
	else:
		m.albedo_color = Color(0, 0, 0, 0.25)
	shadow.material_override = m
	shadow.position = Vector3(0, 0.02, 0.02)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)

func set_marker(text: String, color := Color(1, 0.85, 0.3)) -> void:
	if marker == null:
		marker = Label3D.new()
		marker.font = UI.font
		marker.font_size = 20
		marker.pixel_size = 0.012
		marker.outline_size = 6
		marker.outline_modulate = Color(0, 0, 0, 1)
		marker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.no_depth_test = true
		marker.render_priority = 5
		add_child(marker)
	marker.text = text
	marker.modulate = color
	marker.visible = text != ""
	marker.position = Vector3(0, (sprite.height if sprite else 1.0) + 0.3, 0)

func _process(delta: float) -> void:
	_t += delta
	if sprite and idle_anim and anim == null:
		# subtle breathing squash
		var s := 1.0 + sin(_t * 2.4) * 0.025
		sprite.scale = Vector3(1.0 / sqrt(s), s, 1.0)
	if marker and marker.visible:
		marker.position.y = (sprite.height if sprite else 1.0) + 0.3 + sin(_t * 4.0) * 0.06

func bark(text: String, dur := 2.6) -> void:
	## Small floating speech text above the actor (ambient chatter).
	var l := Label3D.new()
	l.text = text
	l.font = UI.font
	l.font_size = 20
	l.pixel_size = 0.0105
	l.modulate = Color(1, 0.97, 0.88)
	l.outline_size = 6
	l.outline_modulate = Color(0.05, 0.03, 0.02)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 4
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.width = 260
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	l.position = Vector3(0, (sprite.height if sprite else 1.0) + 0.45, 0)
	l.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)

func face_towards(p: Vector3) -> void:
	if sprite:
		sprite.set_flip(p.x < global_position.x)
		if anim:
			anim.facing = -1.0 if p.x < global_position.x else 1.0

func interact() -> void:
	interacted.emit()
	var t: String = ent.get("type", "")
	if t == "npc":
		Audio.sfx_any(["talk_start", "interact"], 0.7)
		var spr: String = ent.get("sprite", "")
		if spr in ["cow", "turtle", "gecko", "jimmy"]:
			Audio.voice(spr, null, 0.8)
	elif t in ["prop", "sign", "stone", "mirror"]:
		Audio.sfx_any(["sign_read", "interact"], 0.6)
	match ent.get("type", ""):
		"door":
			var lk: String = ent.get("locked", "")
			if lk != "" and not Game.flag(lk):
				await UI.talk([["", ent.get("locked_text", "Verschlossen.")]])
				return
			Audio.sfx("door")
			map.active = false
			map.main.goto_map(ent["to"], ent.get("spawn", "door"))
			return
		"chest":
			var key := "got_%s_%s" % [map.id, ent["id"]]
			if Game.flag(key):
				await UI.talk([["", "Leer. Wie das Versprechen vom Paradies."]])
				return
			Game.set_flag(key)
			Audio.sfx("chest_open")
			sprite.set_tex(Data.sprite_tex("chest_open"))
			for it in ent.get("items", {}):
				Game.add_item(it, ent["items"][it])
			if ent.get("grains", 0) > 0:
				Game.add_grains(ent["grains"])
			Audio.sfx("item_get")
			if ent.has("event"):
				await Story.run(ent["event"], self)
			return
		"pickup":
			var key2 := "got_%s_%s" % [map.id, ent["id"]]
			Game.set_flag(key2)
			Audio.sfx_any(["pickup", "item_get"])
			if ent.has("item"):
				Game.add_item(ent["item"], ent.get("count", 1))
			if ent.has("event"):
				await Story.run(ent["event"], self)
			interactable = false
			queue_free()
			return
	if ent.has("event"):
		await Story.run(ent["event"], self)
	elif ent.has("lines"):
		await UI.talk(ent["lines"])

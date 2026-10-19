class_name Cutscene
extends Node3D
## In-engine cinematic stage: builds a small 3D set and offers tools for camera moves,
## actor movement/gestures, lights, particles and captions. Captions always wait for the player.

var cam: Camera3D
var atmos: Atmosphere
var terrain: Terrain
var actors := {}
var _look := Vector3.ZERO
var _shake := 0.0
var _cam_pos := Vector3.ZERO
var _focus: Node3D
var skip_requested := false

func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.1
	cam.far = 200.0
	add_child(cam)
	cam.current = true
	_focus = Node3D.new()
	add_child(_focus)

## Builds floor/walls from ASCII rows (same legend as maps) plus lighting & weather.
func build_set(env: String, rows: Array = [], weather: Array = [], water := false, sky := Color(-1, 0, 0)) -> void:
	atmos = Atmosphere.new()
	add_child(atmos)
	atmos.setup(env, _focus)
	if sky.r >= 0.0:
		atmos.env.background_color = sky
	for w in weather:
		atmos.add_weather(w)
	if not rows.is_empty():
		terrain = Terrain.new(rows)
		add_child(terrain.build(func(n): return Data.tex("res://assets/textures/%s.png" % n)))
	if water:
		var wm := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(160, 160)
		pm.subdivide_width = 60
		pm.subdivide_depth = 60
		wm.mesh = pm
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/water.gdshader")
		if env in ["storm", "moon", "dark"]:
			m.set_shader_parameter("shallow", Color(0.12, 0.42, 0.5))
			m.set_shader_parameter("mid", Color(0.04, 0.22, 0.32))
			m.set_shader_parameter("deep", Color(0.01, 0.06, 0.12))
			m.set_shader_parameter("min_alpha", 0.93)
			m.set_shader_parameter("wave_speed", 2.0)
		wm.material_override = m
		wm.position = Vector3(0, -0.12, 0)
		add_child(wm)

func set_dof(focus: float, amount := 0.12) -> void:
	cam.attributes = Dof.make(focus, 2.4, 2.2, amount)

# ------------------------------------------------------------------ actors & props
func actor(id: String, sprite: String, pos: Vector3, flip := false, animate := true) -> PixelSprite:
	var s := PixelSprite.make(Data.sprite_tex(sprite))
	add_child(s)
	s.position = pos
	s.set_flip(flip)
	if animate:
		var a := SpriteAnim.attach(s, sprite)
		if a:
			a.facing = -1.0 if flip else 1.0
	actors[id] = s
	return s

func prop(sprite: String, pos: Vector3, flip := false, sway := 0.0, scl := 1.0) -> PixelSprite:
	var s := PixelSprite.make(Data.sprite_tex(sprite), sway, scl)
	add_child(s)
	s.position = pos
	s.set_flip(flip)
	return s

func light(pos: Vector3, color: Color, energy: float, rng: float, flicker := false, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	l.position = pos
	add_child(l)
	if flicker:
		var f := Flicker.new()
		f.light = l
		l.add_child(f)
	return l

func spot(pos: Vector3, target: Vector3, color: Color, energy: float, angle := 25.0, rng := 20.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_angle = angle
	l.spot_range = rng
	l.shadow_enabled = true
	l.light_volumetric_fog_energy = 4.0
	add_child(l)
	l.look_at_from_position(pos, target, Vector3.UP if abs((target - pos).normalized().y) < 0.99 else Vector3.FORWARD)
	return l

## Walks/hops an actor to a position.
func move(id: String, to: Vector3, dur: float, hop := true) -> void:
	var s: PixelSprite = actors[id]
	s.set_flip(to.x < s.position.x)
	for c in s.get_children():
		if c is SpriteAnim:
			c.active = false
			c.facing = -1.0 if to.x < s.position.x else 1.0
	var tw := create_tween()
	tw.tween_property(s, "position", to, dur)
	if hop:
		var steps := int(dur / 0.16)
		var ht := create_tween()
		for i in steps:
			ht.tween_property(s, "position:y", to.y + 0.08, 0.08)
			ht.tween_property(s, "position:y", to.y, 0.08)
	await tw.finished
	for c in s.get_children():
		if c is SpriteAnim:
			c.active = true

func swap(id: String, sprite: String) -> void:
	var s: PixelSprite = actors[id]
	s.set_tex(Data.sprite_tex(sprite))

func fade_actor(id: String, to: float, dur: float) -> void:
	var s: PixelSprite = actors[id]
	var from: float = s.mat.get_shader_parameter("alpha")
	var tw := create_tween()
	tw.tween_method(func(v): s.set_alpha(v), from, to, dur)
	await tw.finished

func notes(pos: Vector3, count := 6, sym := "♪") -> void:
	## Little floating music notes / symbols rising up.
	for i in count:
		var l := Label3D.new()
		l.text = sym if randf() < 0.7 else "♫"
		l.font = UI.font
		l.font_size = 30
		l.pixel_size = 0.012
		l.modulate = Color(0.2, 0.18, 0.18)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		add_child(l)
		l.position = pos + Vector3(randf_range(-0.3, 0.3), 0.3, randf_range(-0.2, 0.2))
		var tw := create_tween()
		tw.tween_interval(i * 0.45)
		tw.tween_property(l, "position", l.position + Vector3(randf_range(-0.8, 0.8), 2.2, 0), 3.0).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(l, "modulate:a", 0.0, 3.0).set_delay(1.0)
		tw.tween_callback(l.queue_free)

# ------------------------------------------------------------------ camera
func cam_set(pos: Vector3, look: Vector3, fov := 40.0) -> void:
	_cam_pos = pos
	_look = look
	cam.fov = fov
	_apply_cam()

func cam_to(pos: Vector3, look: Vector3, dur: float, fov := -1.0, trans := Tween.TRANS_SINE) -> Tween:
	## Starts a camera move and returns the tween (await .finished if needed).
	var tw := create_tween().set_parallel(true).set_trans(trans).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "_cam_pos", pos, dur)
	tw.tween_property(self, "_look", look, dur)
	if fov > 0:
		tw.tween_property(cam, "fov", fov, dur)
	return tw

func orbit(center: Vector3, radius: float, height: float, from_deg: float, to_deg: float, dur: float) -> Tween:
	var tw := create_tween()
	tw.tween_method(func(a):
		var r := deg_to_rad(a)
		_cam_pos = center + Vector3(sin(r) * radius, height, cos(r) * radius)
		_look = center + Vector3(0, 0.5, 0), from_deg, to_deg, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tw

func shake(amount := 0.5) -> void:
	_shake = max(_shake, amount)

func _process(delta: float) -> void:
	_apply_cam()
	if _shake > 0.0:
		_shake = max(0.0, _shake - delta * 1.8)
	_focus.global_position = _look

func _apply_cam() -> void:
	var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.12
	cam.global_position = _cam_pos + off
	if not _cam_pos.is_equal_approx(_look):
		cam.look_at(_look + off * 0.5, Vector3.UP)

# ------------------------------------------------------------------ text & timing
func say(text: String, who := "") -> void:
	if skip_requested:
		return
	await UI.caption(text, who)

func wait(t: float) -> void:
	if skip_requested:
		return
	await get_tree().create_timer(t).timeout

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and not skip_requested:
		# double-tap Esc/Q to skip a cutscene
		if has_meta("skip_armed"):
			skip_requested = true
			UI.toast("Szene übersprungen")
			if UI._waiting or UI._typing:
				UI._skip = true
				UI._advance.emit()
		else:
			set_meta("skip_armed", true)
			UI.toast("Nochmal [Esc/Q] zum Überspringen")
			get_tree().create_timer(2.0).timeout.connect(func(): remove_meta("skip_armed") if has_meta("skip_armed") else null)

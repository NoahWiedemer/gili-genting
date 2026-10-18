class_name Atmosphere
extends Node3D
## Lighting presets (sun, ambient, fog, glow) and 3D weather particles.
## The weather is intentionally smooth & non-pixel: it deliberately breaks the pixel style.

var sun: DirectionalLight3D
var env: Environment
var world_env: WorldEnvironment
var preset := "day"
var _lightning := false
var _lightning_t := 3.0
var weather_root: Node3D
var follow: Node3D

const PRESETS := {
	"day": {"sun": Color(1.0, 0.94, 0.82), "sun_e": 1.35, "dir": Vector3(0.45, -0.8, -0.55), "amb": Color(0.55, 0.7, 0.85), "amb_e": 0.75,
		"bg": Color(0.42, 0.72, 0.86), "fog": Color(0.62, 0.82, 0.92), "fog_d": 0.006, "glow": 0.5, "exp": 1.0, "sat": 1.15, "con": 1.08, "water_glow": 0.0},
	"noon": {"sun": Color(1.0, 0.88, 0.62), "sun_e": 1.7, "dir": Vector3(0.25, -0.95, -0.3), "amb": Color(0.85, 0.72, 0.55), "amb_e": 0.65,
		"bg": Color(0.86, 0.72, 0.5), "fog": Color(0.92, 0.78, 0.55), "fog_d": 0.005, "glow": 0.5, "exp": 0.92, "sat": 1.05, "con": 1.16, "water_glow": 0.0},
	"dusk": {"sun": Color(1.0, 0.58, 0.36), "sun_e": 1.05, "dir": Vector3(0.75, -0.5, -0.5), "amb": Color(0.5, 0.42, 0.68), "amb_e": 0.8,
		"bg": Color(0.3, 0.18, 0.32), "fog": Color(0.55, 0.32, 0.42), "fog_d": 0.01, "glow": 0.9, "exp": 1.0, "sat": 1.15, "con": 1.1, "water_glow": 0.05},
	"storm": {"sun": Color(0.6, 0.7, 1.0), "sun_e": 0.7, "dir": Vector3(-0.3, -0.85, -0.45), "amb": Color(0.3, 0.38, 0.55), "amb_e": 1.0,
		"bg": Color(0.05, 0.08, 0.13), "fog": Color(0.12, 0.16, 0.24), "fog_d": 0.02, "glow": 0.9, "exp": 1.0, "sat": 0.85, "con": 1.15, "water_glow": 0.1},
	"moon": {"sun": Color(0.6, 0.72, 1.0), "sun_e": 0.75, "dir": Vector3(-0.4, -0.75, -0.55), "amb": Color(0.25, 0.3, 0.52), "amb_e": 1.0,
		"bg": Color(0.03, 0.04, 0.09), "fog": Color(0.05, 0.07, 0.14), "fog_d": 0.02, "glow": 1.0, "exp": 1.05, "sat": 1.0, "con": 1.1, "water_glow": 0.12},
	"dark": {"sun": Color(0.45, 0.55, 0.95), "sun_e": 0.4, "dir": Vector3(-0.4, -0.75, -0.55), "amb": Color(0.14, 0.17, 0.32), "amb_e": 0.8,
		"bg": Color(0.01, 0.01, 0.03), "fog": Color(0.02, 0.02, 0.05), "fog_d": 0.03, "glow": 1.1, "exp": 1.05, "sat": 0.95, "con": 1.15, "water_glow": 0.05},
	"interior": {"sun": Color(1.0, 0.8, 0.6), "sun_e": 0.0, "dir": Vector3(0.3, -0.9, -0.3), "amb": Color(0.5, 0.4, 0.34), "amb_e": 0.75,
		"bg": Color(0.02, 0.015, 0.01), "fog": Color(0.05, 0.03, 0.02), "fog_d": 0.0, "glow": 0.9, "exp": 1.0, "sat": 1.1, "con": 1.1, "water_glow": 0.0},
	"slaughter": {"sun": Color(1.0, 0.3, 0.25), "sun_e": 0.0, "dir": Vector3(0.3, -0.9, -0.3), "amb": Color(0.32, 0.18, 0.18), "amb_e": 0.5,
		"bg": Color(0.03, 0.0, 0.0), "fog": Color(0.12, 0.02, 0.02), "fog_d": 0.02, "glow": 1.0, "exp": 1.0, "sat": 1.0, "con": 1.2, "water_glow": 0.0},
	"void": {"sun": Color(1, 1, 1), "sun_e": 0.6, "dir": Vector3(0.2, -0.95, -0.25), "amb": Color(1, 1, 1), "amb_e": 1.4,
		"bg": Color(0.97, 0.96, 0.94), "fog": Color(0.97, 0.96, 0.94), "fog_d": 0.04, "glow": 0.2, "exp": 1.0, "sat": 1.0, "con": 1.0, "water_glow": 0.0},
	"eclipse": {"sun": Color(1.0, 0.35, 0.15), "sun_e": 0.55, "dir": Vector3(0.6, -0.5, -0.6), "amb": Color(0.35, 0.15, 0.2), "amb_e": 0.6,
		"bg": Color(0.08, 0.02, 0.02), "fog": Color(0.2, 0.06, 0.04), "fog_d": 0.02, "glow": 1.1, "exp": 1.0, "sat": 1.1, "con": 1.15, "water_glow": 0.0},
}

func setup(p: String, camera_target: Node3D) -> void:
	preset = p
	follow = camera_target
	var cfg: Dictionary = PRESETS.get(p, PRESETS["day"])
	sun = DirectionalLight3D.new()
	sun.light_color = cfg["sun"]
	sun.light_energy = cfg["sun_e"]
	sun.shadow_enabled = cfg["sun_e"] > 0.01
	sun.shadow_blur = 0.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 40.0
	sun.light_angular_distance = 0.5
	add_child(sun)
	var dir: Vector3 = cfg["dir"]
	sun.look_at_from_position(Vector3.ZERO, dir.normalized(), Vector3.UP if abs(dir.normalized().y) < 0.99 else Vector3.FORWARD)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = cfg["bg"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = cfg["amb"]
	env.ambient_light_energy = cfg["amb_e"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = cfg["exp"]
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = cfg["glow"]
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.3)
	env.fog_enabled = cfg["fog_d"] > 0.0
	env.fog_light_color = cfg["fog"]
	env.fog_density = cfg["fog_d"]
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.2
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = cfg["sat"]
	env.adjustment_contrast = cfg["con"]
	if p in ["storm", "moon", "dark", "slaughter", "eclipse", "dusk"]:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.012 if p != "slaughter" else 0.03
		env.volumetric_fog_albedo = cfg["fog"].lightened(0.3)
		env.volumetric_fog_emission = Color(0, 0, 0)
		env.volumetric_fog_anisotropy = 0.5
		env.volumetric_fog_length = 40.0
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	weather_root = Node3D.new()
	add_child(weather_root)

func water_glow() -> float:
	return PRESETS.get(preset, PRESETS["day"])["water_glow"]

func _process(delta: float) -> void:
	if follow and weather_root:
		weather_root.global_position = follow.global_position
	if _lightning:
		_lightning_t -= delta
		if _lightning_t <= 0.0:
			_lightning_t = randf_range(4.0, 11.0)
			_strike()

func _strike() -> void:
	var base := sun.light_energy
	var tw := create_tween()
	tw.tween_property(sun, "light_energy", 3.5, 0.05)
	tw.tween_property(sun, "light_energy", base, 0.12)
	tw.tween_property(sun, "light_energy", 2.6, 0.05)
	tw.tween_property(sun, "light_energy", base, 0.4)
	UI.flash(Color(0.8, 0.85, 1.0), 0.4, 0.35)
	get_tree().create_timer(randf_range(0.3, 1.2)).timeout.connect(func(): Audio.sfx("thunder", randf_range(0.85, 1.05), 0.8))

# ------------------------------------------------------------------ weather
func add_weather(kind: String) -> void:
	match kind:
		"rain":
			_rain()
			Audio.ambient("rain_loop")
		"storm":
			_rain(1300)
			_wind(40)
			_lightning = true
			Audio.ambient("rain_loop")
		"petals":
			_petals()
		"dust":
			_motes(Color(1.0, 0.85, 0.55), 160, 0.06, 1.6)
		"fireflies":
			_motes(Color(0.75, 1.0, 0.35), 70, 0.045, 5.0, true)
		"embers":
			_embers()
		"wind":
			_wind(24)
		"leaves":
			_leaves()
		"void":
			_motes(Color(0.1, 0.08, 0.08), 90, 0.05, 0.0)
		"ash":
			_motes(Color(0.6, 0.6, 0.6), 220, 0.04, 0.0)
		"butterflies":
			_butterflies()

func _soft_tex(path: String) -> Texture2D:
	return Data.tex("res://assets/fx/%s.png" % path)

func _particles(amount: int, lifetime: float, box: Vector3, offset: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 30, 60))
	p.position = offset
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	p.process_material = pm
	weather_root.add_child(p)
	return p

func _rain(amount := 1600) -> void:
	var p := _particles(amount, 0.9, Vector3(16, 0.5, 14), Vector3(0, 9, -2))
	var pm: ParticleProcessMaterial = p.process_material
	pm.direction = Vector3(0.15, -1, 0.05)
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -12, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.015, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.8, 1.0, 0.28)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = m
	p.draw_pass_1 = q
	# splashes
	var s := _particles(amount / 4, 0.25, Vector3(14, 0.0, 12), Vector3(0, 0.05, -1))
	var spm: ParticleProcessMaterial = s.process_material
	spm.direction = Vector3(0, 1, 0)
	spm.spread = 60.0
	spm.initial_velocity_min = 0.6
	spm.initial_velocity_max = 1.4
	spm.gravity = Vector3(0, -6, 0)
	spm.scale_min = 0.5
	var sq := QuadMesh.new()
	sq.size = Vector2(0.05, 0.05)
	var sm := m.duplicate()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.albedo_color = Color(0.85, 0.92, 1.0, 0.6)
	sq.material = sm
	s.draw_pass_1 = sq

func _petals() -> void:
	var p := _particles(60, 9.0, Vector3(14, 0.5, 10), Vector3(-3, 6, -2))
	var pm: ParticleProcessMaterial = p.process_material
	pm.direction = Vector3(1, -0.4, 0.2)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0.25, -0.35, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.angle_min = -180
	pm.angle_max = 180
	pm.angular_velocity_min = -90
	pm.angular_velocity_max = 90
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	pm.particle_flag_rotate_y = true
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _soft_tex("petal")
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1, 0.97, 0.9) if m.albedo_texture else Color(1, 0.9, 0.95)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.emission_enabled = true
	m.emission = Color(0.25, 0.22, 0.18)
	q.material = m
	p.draw_pass_1 = q

func _leaves() -> void:
	_petals()
	var p: GPUParticles3D = weather_root.get_child(weather_root.get_child_count() - 1)
	var m: StandardMaterial3D = (p.draw_pass_1 as QuadMesh).material
	m.albedo_texture = _soft_tex("leaf")
	m.albedo_color = Color(0.7, 1.0, 0.6)

func _motes(col: Color, amount: int, size: float, light: float, flicker := false) -> void:
	var p := _particles(amount, 6.0, Vector3(13, 2.0, 10), Vector3(0, 1.6, -1))
	var pm: ParticleProcessMaterial = p.process_material
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3(0, 0.02, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.2, 1))
	curve.add_point(Vector2(0.8, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	if flicker:
		pm.scale_min = 0.6
		pm.scale_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if light > 0.0 else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = _soft_tex("spark")
	m.albedo_color = Color(col.r * max(light, 1.0), col.g * max(light, 1.0), col.b * max(light, 1.0), 0.85)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	p.draw_pass_1 = q

func _embers() -> void:
	var p := _particles(90, 3.5, Vector3(10, 0.2, 8), Vector3(0, 0.2, -1))
	var pm: ParticleProcessMaterial = p.process_material
	pm.direction = Vector3(0.2, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0.1, 0.2, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _soft_tex("spark")
	m.albedo_color = Color(3.0, 1.2, 0.3)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	p.draw_pass_1 = q

func _wind(amount: int) -> void:
	var p := _particles(amount, 1.6, Vector3(4, 2.5, 8), Vector3(-14, 1.8, -2))
	var pm: ParticleProcessMaterial = p.process_material
	pm.direction = Vector3(1, 0.02, 0)
	pm.spread = 4.0
	pm.initial_velocity_min = 13.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	p.trail_enabled = true
	p.trail_lifetime = 0.35
	var rib := RibbonTrailMesh.new()
	rib.size = 0.035
	rib.sections = 6
	rib.section_length = 0.15
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.5, 1))
	curve.add_point(Vector2(1, 0))
	rib.curve = curve
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.28)
	m.use_particle_trails = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	rib.material = m
	p.draw_pass_1 = rib

func _butterflies() -> void:
	var p := _particles(14, 8.0, Vector3(10, 0.6, 7), Vector3(0, 0.9, -1))
	var pm: ParticleProcessMaterial = p.process_material
	pm.direction = Vector3(1, 0.2, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 2.0
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.25
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.2))
	grad.set_color(1, Color(0.4, 0.7, 1.0))
	grad.add_point(0.5, Color(1.0, 0.45, 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_initial_ramp = gt
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.1)
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec4 col;
void vertex() {
	col = COLOR;
	float flap = abs(sin(TIME * 14.0 + INSTANCE_CUSTOM.x * 40.0));
	VERTEX.x *= mix(0.15, 1.0, flap);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float wing = smoothstep(1.0, 0.7, length(vec2(abs(uv.x) - 0.45, uv.y * 1.3)));
	if (wing < 0.5) { discard; }
	ALBEDO = col.rgb * 1.4;
}"""
	m.shader = sh
	q.material = m
	p.draw_pass_1 = q

func add_cloud_shadows(center: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/cloud_shadow.gdshader")
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = center + Vector3(0, 0.025, 0)

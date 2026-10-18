class_name PixelSprite
extends MeshInstance3D
## Upright pixel-art quad anchored at its bottom center. Casts proper shadows.

const SHADER := preload("res://shaders/sprite.gdshader")

var mat: ShaderMaterial
var texture: Texture2D
var height := 1.0
var width := 1.0
var _flip := false

static func make(t: Texture2D, sway := 0.0, scale_mult := 1.0) -> PixelSprite:
	var s := PixelSprite.new()
	s.setup(t, sway, scale_mult)
	return s

func setup(t: Texture2D, sway := 0.0, scale_mult := 1.0) -> void:
	texture = t
	width = t.get_width() / Data.PPU * scale_mult
	height = t.get_height() / Data.PPU * scale_mult
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	q.center_offset = Vector3(0, height * 0.5, 0)
	mesh = q
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("tex", t)
	mat.set_shader_parameter("sway", sway)
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func set_tex(t: Texture2D) -> void:
	setup(t, mat.get_shader_parameter("sway"), 1.0)
	set_flip(_flip)

func set_flip(f: bool) -> void:
	_flip = f
	mat.set_shader_parameter("flip", f)

func is_flipped() -> bool:
	return _flip

func set_flash(v: float, c := Color.WHITE) -> void:
	mat.set_shader_parameter("flash", v)
	mat.set_shader_parameter("flash_color", c)

func set_alpha(v: float) -> void:
	mat.set_shader_parameter("alpha", v)

func set_emission(v: float) -> void:
	mat.set_shader_parameter("emission", v)

func set_tint(c: Color) -> void:
	mat.set_shader_parameter("tint", c)

func flash_hit(c := Color.WHITE, t := 0.25) -> void:
	var tw := create_tween()
	tw.tween_method(func(v): set_flash(v, c), 1.0, 0.0, t)

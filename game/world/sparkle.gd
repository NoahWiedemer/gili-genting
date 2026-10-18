class_name Sparkle
extends Node3D
## Little glittering star marking an item on the ground.

var _l: Label3D
var _t := 0.0

func _ready() -> void:
	_l = Label3D.new()
	_l.text = "✦"
	_l.font = UI.font
	_l.font_size = 20
	_l.pixel_size = 0.012
	_l.modulate = Color(1.6, 1.4, 0.7)
	_l.outline_size = 4
	_l.outline_modulate = Color(0.2, 0.1, 0, 0.8)
	_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(_l)
	_t = randf() * 5.0

func _process(delta: float) -> void:
	_t += delta
	_l.position.y = 0.35 + sin(_t * 3.0) * 0.06
	var s: float = 0.7 + 0.35 * absf(sin(_t * 2.2))
	_l.scale = Vector3(s, s, s)

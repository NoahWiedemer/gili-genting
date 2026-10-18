class_name Flicker
extends Node
## Makes an OmniLight flicker like fire, or pulse softly like a magic crystal.

var light: OmniLight3D
var pulse := false
var _base := 1.0
var _t := 0.0

func _ready() -> void:
	_base = light.light_energy
	_t = randf() * 10.0

func _process(delta: float) -> void:
	_t += delta
	if pulse:
		light.light_energy = _base * (0.75 + 0.25 * sin(_t * 2.2))
	else:
		light.light_energy = _base * (0.82 + 0.1 * sin(_t * 13.0) + 0.08 * sin(_t * 23.7 + 1.3) + randf_range(-0.04, 0.04))

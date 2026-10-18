class_name AntTrail
extends Node3D
## A line of tiny ants marching onto the dying grasshopper.

var target := Vector3.ZERO
var _ants: Array = []
var _t := 0.0

func _ready() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.04, 0.04)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 26:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.07, 0.03, 0.04)
		mi.mesh = b
		mi.material_override = m
		add_child(mi)
		_ants.append(mi)

func _process(delta: float) -> void:
	_t += delta * 0.12
	for i in _ants.size():
		var k := fmod(_t + float(i) / _ants.size(), 1.0)
		var start := Vector3(-4.5, 0.02, 1.5)
		var p := start.lerp(Vector3(0, 0.02, 0.05), k)
		p.z += sin(k * 18.0 + i) * 0.08
		if k > 0.85:
			p += Vector3(sin(i * 3.1) * 0.25, 0.05 + (k - 0.85) * 1.5 * abs(sin(i)), cos(i * 1.7) * 0.1)
		_ants[i].position = p

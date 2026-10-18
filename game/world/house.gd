class_name House
extends RefCounted
## Builds simple 3D huts/houses with pixel textures, gable roofs, glowing windows and a door.

const STYLES := {
	"bamboo": {"wall": "bamboo_wall", "roof": "thatch", "h": 1.9, "trim": "wood_dark"},
	"wood": {"wall": "wood_wall", "roof": "thatch", "h": 2.0, "trim": "wood_dark"},
	"plaster": {"wall": "plaster", "roof": "tin_roof", "h": 2.1, "trim": "wood_dark"},
	"barn": {"wall": "wood_wall", "roof": "tin_roof", "h": 2.8, "trim": "wood_dark", "tint": Color(0.85, 0.5, 0.42)},
	"slaughter": {"wall": "plaster", "roof": "tin_roof", "h": 2.6, "trim": "concrete", "tint": Color(0.85, 0.82, 0.8)},
	"ruin": {"wall": "wood_wall", "roof": "", "h": 1.4, "trim": "wood_dark", "tint": Color(0.75, 0.68, 0.6)},
	"shed": {"wall": "wood_wall", "roof": "tin_roof", "h": 1.8, "trim": "wood_dark"},
}

static func build(e: Dictionary, tex_loader: Callable, night: bool) -> Node3D:
	var root := Node3D.new()
	var x: float = e["x"]
	var z: float = e["z"]
	var w: float = e.get("w", 4)
	var d: float = e.get("d", 3)
	var style: Dictionary = STYLES.get(e.get("style", "bamboo"), STYLES["bamboo"])
	var h: float = e.get("h", style["h"])
	var tint: Color = style.get("tint", Color.WHITE)
	var door_x: float = e.get("door", x + floor(w / 2.0))
	var lit: bool = e.get("lit", night)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ruin: bool = e.get("style", "") == "ruin"
	# walls (with per-segment random height for ruins)
	var segs := []
	var seg := 0.5
	var px := x
	while px < x + w - 0.01:
		segs.append([Vector3(px, 0, z + d), Vector3(px + seg, 0, z + d)])  # south (front)
		segs.append([Vector3(px + seg, 0, z), Vector3(px, 0, z)])          # north (back)
		px += seg
	var pz := z
	while pz < z + d - 0.01:
		segs.append([Vector3(x + w, 0, pz + seg), Vector3(x + w, 0, pz)])  # east
		segs.append([Vector3(x, 0, pz), Vector3(x, 0, pz + seg)])          # west
		pz += seg
	var rng := RandomNumberGenerator.new()
	rng.seed = int(x * 31 + z * 17)
	for s in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var hh := h
		if ruin:
			hh = rng.randf_range(0.2, h)
			if rng.randf() < 0.25:
				continue
		# skip the doorway on the front wall
		if not ruin and abs(a.z - (z + d)) < 0.01 and abs(b.z - (z + d)) < 0.01:
			var mid := (a.x + b.x) * 0.5
			if mid > door_x and mid < door_x + 1.0:
				_wall_quad(walls, a, b, 1.35, hh, tint)
				continue
		_wall_quad(walls, a, b, 0.0, hh, tint)
	walls.generate_normals()
	var wm := MeshInstance3D.new()
	wm.mesh = walls.commit()
	wm.material_override = _mat(tex_loader.call(style["wall"]))
	root.add_child(wm)
	# floor patch inside door so we don't see void
	# roof
	if style["roof"] != "" and not ruin:
		var roof := SurfaceTool.new()
		roof.begin(Mesh.PRIMITIVE_TRIANGLES)
		var o := 0.35
		var ridge: float = h + minf(w, d) * 0.45 + 0.3
		var x0 := x - o
		var x1 := x + w + o
		var zf := z + d + o
		var zb := z - o
		var zm := z + d * 0.5
		var eave := h - 0.15
		# front slope (faces camera)
		_quad(roof, Vector3(x0, ridge, zm), Vector3(x1, ridge, zm), Vector3(x1, eave, zf), Vector3(x0, eave, zf), Color(1, 1, 1) * tint, d * 0.6)
		# back slope
		_quad(roof, Vector3(x1, ridge, zm), Vector3(x0, ridge, zm), Vector3(x0, eave, zb), Vector3(x1, eave, zb), Color(0.8, 0.8, 0.8) * tint, d * 0.6)
		roof.generate_normals()
		var rm := MeshInstance3D.new()
		rm.mesh = roof.commit()
		rm.material_override = _mat(tex_loader.call(style["roof"]))
		root.add_child(rm)
		# gable triangles
		var gab := SurfaceTool.new()
		gab.begin(Mesh.PRIMITIVE_TRIANGLES)
		for gx in [x, x + w]:
			var pts := [Vector3(gx, h, z + d), Vector3(gx, ridge - 0.1, zm), Vector3(gx, h, z)]
			if gx == x:
				pts = [Vector3(gx, h, z), Vector3(gx, ridge - 0.1, zm), Vector3(gx, h, z + d)]
			for i in 3:
				gab.set_color(tint * 0.9)
				gab.set_uv(Vector2(pts[i].z, -pts[i].y))
				gab.add_vertex(pts[i])
		gab.generate_normals()
		var gm := MeshInstance3D.new()
		gm.mesh = gab.commit()
		gm.material_override = _mat(tex_loader.call(style["wall"]))
		root.add_child(gm)
	# door + windows
	if not ruin:
		var door := MeshInstance3D.new()
		var dq := QuadMesh.new()
		dq.size = Vector2(0.86, 1.3)
		door.mesh = dq
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(0.05, 0.03, 0.02)
		if lit:
			dmat.emission_enabled = true
			dmat.emission = Color(1.0, 0.55, 0.25)
			dmat.emission_energy_multiplier = 0.6
		door.material_override = dmat
		door.position = Vector3(door_x + 0.5, 0.65, z + d + 0.005)
		root.add_child(door)
		var wins: Array = e.get("windows", [])
		if wins.is_empty() and w >= 3:
			if door_x - x >= 1.5:
				wins.append(x + 0.6)
			if x + w - (door_x + 1) >= 1.5:
				wins.append(x + w - 1.4)
		for wx in wins:
			var win := MeshInstance3D.new()
			var wq := QuadMesh.new()
			wq.size = Vector2(0.7, 0.55)
			win.mesh = wq
			var wmat := StandardMaterial3D.new()
			if lit:
				wmat.albedo_color = Color(1.0, 0.75, 0.4)
				wmat.emission_enabled = true
				wmat.emission = Color(1.0, 0.62, 0.28)
				wmat.emission_energy_multiplier = 2.2
			else:
				wmat.albedo_color = Color(0.08, 0.1, 0.14)
				wmat.roughness = 0.2
			win.material_override = wmat
			win.position = Vector3(wx + 0.4, 1.15, z + d + 0.01)
			root.add_child(win)
			if lit:
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.65, 0.35)
				l.light_energy = 1.4
				l.omni_range = 3.2
				l.position = Vector3(wx + 0.4, 1.1, z + d + 0.6)
				root.add_child(l)
		if lit:
			var dl := OmniLight3D.new()
			dl.light_color = Color(1.0, 0.6, 0.3)
			dl.light_energy = 1.2
			dl.omni_range = 2.6
			dl.position = Vector3(door_x + 0.5, 1.0, z + d + 0.5)
			root.add_child(dl)
	if e.has("sign"):
		var sl := Label3D.new()
		sl.text = e["sign"]
		sl.font = UI.title_font
		sl.font_size = 28
		sl.pixel_size = 0.012
		sl.outline_size = 6
		sl.outline_modulate = Color(0.1, 0.05, 0.02)
		sl.modulate = Color(1, 0.85, 0.5) if not lit else Color(1.4, 1.0, 0.55)
		sl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sl.position = Vector3(x + w * 0.5, h + 0.35, z + d + 0.45)
		root.add_child(sl)
	# collision
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, 3, d)
	cs.shape = bs
	cs.position = Vector3(x + w * 0.5, 1.5, z + d * 0.5)
	body.add_child(cs)
	root.add_child(body)
	return root

static func _mat(t: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func _wall_quad(st: SurfaceTool, a: Vector3, b: Vector3, y0: float, y1: float, tint: Color) -> void:
	var u0 := a.x + a.z
	var u1 := b.x + b.z
	var pts := [[Vector3(a.x, y1, a.z), Vector2(u0, -y1)], [Vector3(b.x, y1, b.z), Vector2(u1, -y1)], [Vector3(b.x, y0, b.z), Vector2(u1, -y0)],
		[Vector3(a.x, y1, a.z), Vector2(u0, -y1)], [Vector3(b.x, y0, b.z), Vector2(u1, -y0)], [Vector3(a.x, y0, a.z), Vector2(u0, -y0)]]
	for p in pts:
		var shade: float = 0.75 + 0.25 * clampf(p[0].y / 2.0, 0.0, 1.0)
		st.set_color(Color(tint.r * shade, tint.g * shade, tint.b * shade))
		st.set_uv(p[1])
		st.add_vertex(p[0])

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, e: Vector3, col: Color, vlen: float) -> void:
	var la := a.distance_to(e)
	var uvs := [Vector2(a.x, 0), Vector2(b.x, 0), Vector2(c.x, la), Vector2(e.x, la)]
	var pts := [a, b, c, e]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])

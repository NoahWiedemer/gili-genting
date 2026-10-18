class_name Terrain
extends RefCounted
## Builds diorama-style tile terrain meshes + collision from ASCII rows.

# char -> [texture, height, walkable, side_texture]
const GROUND := {
	".": ["sand", 0.0, true, "sand"],
	",": ["sand_wet", -0.06, true, "sand_wet"],
	"\"": ["grass", 0.0, true, "dirt_path"],
	";": ["jungle_floor", 0.0, true, "dirt_path"],
	":": ["dirt_path", 0.0, true, "dirt_path"],
	"=": ["cracked_earth", 0.0, true, "cracked_earth"],
	"_": ["grass_dry", 0.0, true, "cracked_earth"],
	"%": ["soil_rows", 0.0, true, "mud"],
	"o": ["stone_floor", 0.0, true, "rock"],
	"w": ["wood_planks", 0.0, true, "wood_dark"],
	"t": ["tile_floor", 0.0, true, "concrete"],
	"c": ["carpet", 0.0, true, "wood_dark"],
	"h": ["straw_floor", 0.0, true, "wood_dark"],
	"v": ["white_void", 0.0, true, "white_void"],
	"n": ["concrete", 0.0, true, "concrete"],
	"m": ["mud", -0.03, true, "mud"],
	"q": ["moss_stone", 0.0, true, "moss_stone"],
	"-": ["sand_wet", -0.28, true, "sand_wet"],
	"~": ["sand_wet", -1.5, false, "rock"],
	"#": ["rock_top", 0.9, false, "rock"],
	"R": ["rock_top", 1.6, false, "rock"],
	"C": ["cliff_dark", 1.4, false, "cliff_dark"],
	"W": ["wood_dark", 2.6, false, "wood_wall"],
	"B": ["thatch", 2.6, false, "bamboo_wall"],
	"P": ["plaster", 2.6, false, "plaster"],
	"N": ["concrete", 2.6, false, "concrete"],
	"V": ["white_void", 0.0, false, "white_void"],
	"X": ["", 0.0, false, ""],
	"K": ["rock_top", 2.2, true, "cliff_dark"],
	"G": ["grass_dry", 2.2, true, "cliff_dark"],
	"U": ["cliff_dark", 3.4, false, "cliff_dark"],
}

# prop chars -> [sprite, blocked, sway, scale, jitter]
const PROPS := {
	"Y": ["palm", true, 0.25, 1.0, 0.25],
	"T": ["jungle_tree", true, 0.12, 1.0, 0.25],
	"b": ["bush", true, 0.06, 1.0, 0.2],
	"f": ["frangipani", true, 0.06, 1.0, 0.2],
	"r": ["boulder", true, 0.0, 1.0, 0.15],
	"d": ["dead_tree", true, 0.03, 1.0, 0.2],
	"s": ["dry_shrub", false, 0.08, 1.0, 0.3],
	"g": ["tall_grass", false, 0.12, 1.0, 0.3],
	"F": ["fence", true, 0.0, 1.0, 0.0],
	"l": ["lantern", true, 0.0, 1.0, 0.0],
	"k": ["barrel", true, 0.0, 1.0, 0.1],
	"x": ["crates", true, 0.0, 1.0, 0.05],
	"u": ["umbrella", true, 0.0, 1.0, 0.1],
	"S": ["scarecrow", true, 0.02, 1.0, 0.1],
	"j": ["meathook", false, 0.0, 1.0, 0.0],
}

# furniture boxes: char -> [texture, height, inset]
const FURNITURE := {
	"D": ["wood_dark", 0.55, 0.12],
	"E": ["carpet", 0.4, 0.05],
	"L": ["wood_dark", 1.6, 0.08],
	"A": ["concrete", 0.8, 0.05],
}

var rows: Array = []
var w := 0
var d := 0
var heights := {}      # Vector2i -> float (walk/top height)
var walk := {}         # Vector2i -> bool
var ground_char := {}  # Vector2i -> char

func _init(r: Array) -> void:
	rows = r
	d = r.size()
	for row in r:
		w = max(w, row.length())

func char_at(x: int, z: int) -> String:
	if z < 0 or z >= d or x < 0:
		return "X"
	var row: String = rows[z]
	if x >= row.length():
		return "X"
	return row[x]

func _hash(x: int, z: int) -> float:
	var h := (x * 73856093) ^ (z * 19349663)
	return float(abs(h) % 1000) / 1000.0

func resolve_ground(x: int, z: int) -> String:
	## For props/furniture: most common walkable ground among neighbours.
	var counts := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := char_at(x + dx, z + dz)
			if GROUND.has(c) and GROUND[c][2]:
				counts[c] = counts.get(c, 0) + 1
	var best := "\""
	var bn := 0
	for c in counts:
		if counts[c] > bn:
			bn = counts[c]
			best = c
	return best

func analyze() -> void:
	for z in d:
		for x in w:
			var c := char_at(x, z)
			var p := Vector2i(x, z)
			var g := c
			if PROPS.has(c) or FURNITURE.has(c) or not GROUND.has(c):
				g = resolve_ground(x, z)
			ground_char[p] = g
			var info: Array = GROUND.get(g, GROUND["\""])
			var h: float = info[1]
			if g in ["#", "R", "C"]:
				h += floor(_hash(x, z) * 3.0) * 0.5
			if g in ["W", "B", "P", "N"] and z >= d - 1:
				h = 0.35  # cut-away front wall so the camera can look inside
			heights[p] = h
			var ok: bool = info[2]
			if PROPS.has(c) and PROPS[c][1]:
				ok = false
			if FURNITURE.has(c):
				ok = false
			if c == "X" or c == "V":
				ok = false
			walk[p] = ok

func height_at(x: int, z: int) -> float:
	return heights.get(Vector2i(x, z), -2.0)

func is_walkable(x: int, z: int) -> bool:
	return walk.get(Vector2i(x, z), false)

## Returns a Node3D with the terrain meshes (one per material) and static collision.
func build(tex_loader: Callable, edge_depth := -2.5) -> Node3D:
	analyze()
	var root := Node3D.new()
	root.name = "Terrain"
	var tools := {}
	var get_st := func(tex: String) -> SurfaceTool:
		if not tools.has(tex):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[tex] = st
		return tools[tex]
	for z in d:
		for x in w:
			var p := Vector2i(x, z)
			var g: String = ground_char[p]
			if g == "X":
				continue
			var info: Array = GROUND.get(g, GROUND["\""])
			if info[0] == "":
				continue
			var h: float = heights[p]
			var shade := 0.9 + _hash(x * 7, z * 3) * 0.14
			var st: SurfaceTool = get_st.call(info[0])
			_quad_top(st, x, z, h, Color(shade, shade, shade))
			# sides toward lower neighbours
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = p + dir
				var nh: float = edge_depth
				if heights.has(n) and ground_char[n] != "X":
					nh = heights[n]
				if nh < h - 0.001:
					var sst: SurfaceTool = get_st.call(info[3])
					_quad_side(sst, x, z, dir, nh, h, shade)
			# furniture
			var c := char_at(x, z)
			if FURNITURE.has(c):
				var fi: Array = FURNITURE[c]
				_box(get_st.call(fi[0]), Vector3(x + fi[2], h, z + fi[2]), Vector3(x + 1 - fi[2], h + fi[1], z + 1 - fi[2]))
	for tex in tools:
		var st: SurfaceTool = tools[tex]
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex_loader.call(tex)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95 if tex != "sand_wet" else 0.55
		if tex == "white_void":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.name = "T_" + tex
		root.add_child(mi)
	# collision
	var body := StaticBody3D.new()
	body.name = "Collision"
	root.add_child(body)
	for z in range(-1, d + 1):
		for x in range(-1, w + 1):
			var p := Vector2i(x, z)
			if walk.get(p, false):
				continue
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			var c := char_at(x, z)
			var small: bool = PROPS.has(c) and c in ["b", "f", "r", "k", "l", "u", "S", "x"]
			bs.size = Vector3(0.7, 4, 0.7) if small else Vector3(1, 4, 1)
			if PROPS.has(c) and c in ["Y", "T", "d"]:
				bs.size = Vector3(0.5, 4, 0.5)
			cs.shape = bs
			cs.position = Vector3(x + 0.5, 1.0, z + 0.5)
			body.add_child(cs)
	return root

func _quad_top(st: SurfaceTool, x: int, z: int, h: float, col: Color) -> void:
	var a := Vector3(x, h, z)
	var b := Vector3(x + 1, h, z)
	var c := Vector3(x + 1, h, z + 1)
	var e := Vector3(x, h, z + 1)
	st.set_color(col)
	for v in [[a, Vector2(x, z)], [b, Vector2(x + 1, z)], [c, Vector2(x + 1, z + 1)],
			[a, Vector2(x, z)], [c, Vector2(x + 1, z + 1)], [e, Vector2(x, z + 1)]]:
		st.set_uv(v[1])
		st.add_vertex(v[0])

func _quad_side(st: SurfaceTool, x: int, z: int, dir: Vector2i, y0: float, y1: float, shade: float) -> void:
	var p0: Vector3
	var p1: Vector3
	match dir:
		Vector2i(1, 0):
			p0 = Vector3(x + 1, 0, z + 1); p1 = Vector3(x + 1, 0, z)
		Vector2i(-1, 0):
			p0 = Vector3(x, 0, z); p1 = Vector3(x, 0, z + 1)
		Vector2i(0, 1):
			p0 = Vector3(x, 0, z + 1); p1 = Vector3(x + 1, 0, z + 1)
		_:
			p0 = Vector3(x + 1, 0, z); p1 = Vector3(x, 0, z)
	var u0 := p0.x + p0.z
	var u1 := p1.x + p1.z
	var dark := shade * 0.78
	var a := Vector3(p0.x, y1, p0.z)
	var b := Vector3(p1.x, y1, p1.z)
	var c := Vector3(p1.x, y0, p1.z)
	var e := Vector3(p0.x, y0, p0.z)
	var top := Color(shade * 0.92, shade * 0.92, shade * 0.92)
	var bot := Color(dark * 0.7, dark * 0.7, dark * 0.75)
	var verts := [[a, Vector2(u0, -y1), top], [b, Vector2(u1, -y1), top], [c, Vector2(u1, -y0), bot],
		[a, Vector2(u0, -y1), top], [c, Vector2(u1, -y0), bot], [e, Vector2(u0, -y0), bot]]
	for v in verts:
		st.set_color(v[2])
		st.set_uv(v[1])
		st.add_vertex(v[0])

func _box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var col := Color(1, 1, 1)
	var faces := [
		[Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)],
		[Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)],
		[Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z)],
		[Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z)],
		[Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z)],
	]
	for f in faces:
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_uv(uvs[i])
			st.add_vertex(f[i])

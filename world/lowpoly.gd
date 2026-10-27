extends RefCounted
# Builds flat-shaded low-poly meshes in code, so the game needs no external art.


static func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m


# Ring of points around the Y axis. If rng is given, points are randomly jittered (for rocks).
static func _ring(radius: float, y: float, sides: int, rng: RandomNumberGenerator = null) -> Array:
	var pts := []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		var r := radius
		var yy := y
		if rng != null:
			r *= rng.randf_range(0.85, 1.15)
			yy += rng.randf_range(-0.06, 0.06)
		pts.append(Vector3(cos(a) * r, yy, sin(a) * r))
	return pts


static func _cone(radius: float, height: float, y0: float, sides: int) -> Dictionary:
	var ring := _ring(radius, y0, sides)
	var apex := Vector3(0.0, y0 + height, 0.0)
	var base := Vector3(0.0, y0, 0.0)
	var tris := []
	for i in sides:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % sides]
		tris.append([a, b, apex])
		tris.append([a, b, base])
	return {"tris": tris, "center": Vector3(0.0, y0 + height * 0.3, 0.0)}


static func _frustum(r_bottom: float, r_top: float, y0: float, height: float, sides: int) -> Dictionary:
	var lo := _ring(r_bottom, y0, sides)
	var hi := _ring(r_top, y0 + height, sides)
	var tris := []
	for i in sides:
		var j := (i + 1) % sides
		tris.append([lo[i], lo[j], hi[j]])
		tris.append([lo[i], hi[j], hi[i]])
		tris.append([lo[i], lo[j], Vector3(0.0, y0, 0.0)])
		tris.append([hi[i], hi[j], Vector3(0.0, y0 + height, 0.0)])
	return {"tris": tris, "center": Vector3(0.0, y0 + height * 0.5, 0.0)}


static func _rock_part(rng: RandomNumberGenerator) -> Dictionary:
	var n := 7
	var bottom := _ring(0.75, 0.0, n, rng)
	var mid := _ring(1.0, 0.45, n, rng)
	var top := _ring(0.55, 0.85, n, rng)
	var apex := Vector3(rng.randf_range(-0.1, 0.1), 1.0, rng.randf_range(-0.1, 0.1))
	var base := Vector3(0.0, 0.0, 0.0)
	var tris := []
	for i in n:
		var j := (i + 1) % n
		tris.append([bottom[i], bottom[j], base])
		tris.append([bottom[i], bottom[j], mid[j]])
		tris.append([bottom[i], mid[j], mid[i]])
		tris.append([mid[i], mid[j], top[j]])
		tris.append([mid[i], top[j], top[i]])
		tris.append([top[i], top[j], apex])
	return {"tris": tris, "center": Vector3(0.0, 0.45, 0.0)}


# Turns parts (triangles + an inside point) into one mesh with flat normals.
# Each triangle is wound automatically so it faces away from the inside point.
static func _mesh_from(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for part in parts:
		var center: Vector3 = part["center"]
		for t in part["tris"]:
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var c: Vector3 = t[2]
			var n := (c - a).cross(b - a)
			var mid := (a + b + c) / 3.0
			if n.dot(mid - center) < 0.0:
				var tmp := b
				b = c
				c = tmp
				n = -n
			n = n.normalized()
			verts.push_back(a)
			verts.push_back(b)
			verts.push_back(c)
			norms.push_back(n)
			norms.push_back(n)
			norms.push_back(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func tree_trunk() -> ArrayMesh:
	return _mesh_from([_frustum(0.28, 0.2, 0.0, 1.8, 6)])


static func tree_foliage() -> ArrayMesh:
	return _mesh_from([
		_cone(1.5, 2.2, 1.3, 7),
		_cone(1.2, 1.9, 2.4, 7),
		_cone(0.85, 1.6, 3.5, 7),
	])


static func rock(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return _mesh_from([_rock_part(rng)])

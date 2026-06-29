class_name GWater
## WATER SYSTEM — a first-class ocean / sea / lake. Builds a large animated water body (the toon-water shader:
## sine waves + fresnel + a shore->deep colour gradient + a foam shoreline) that recenters on the player like the
## far-horizon skirt, with the shoreline/depth derived from the terrain so a beach + an ocean fall out naturally:
## where the terrain is BELOW the water `level` you see water (the seabed under it), where it's ABOVE you see land,
## and the meeting line foams. gl_compatibility/WebGL2-safe (opaque, no SCREEN_TEXTURE). NO collider — the player
## walks on the terrain; water is visual (add an invisible kill-plane separately if you want drowning).
##
## world.json:  "water": { "level": 0.0, "depth": 6, "shallow": [r,g,b], "deep": [r,g,b], "wave_amp": 0.22 }
## Pair with `terrain` (carve areas below `level` for the sea bed); a flat sea is `water` at `level` over flat ground.


## The shared toon-water ShaderMaterial (configured from the world's water cfg).
static func make_material(cfg: Dictionary) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://water.gdshader")
	if cfg.has("shallow"):
		sm.set_shader_parameter("shallow_color", _c(cfg["shallow"]))
	if cfg.has("deep"):
		sm.set_shader_parameter("deep_color", _c(cfg["deep"]))
	if cfg.has("foam"):
		sm.set_shader_parameter("foam_color", _c(cfg["foam"]))
	if cfg.has("wave_amp"):
		sm.set_shader_parameter("wave_amp", float(cfg["wave_amp"]))
	if cfg.has("wave_speed"):
		sm.set_shader_parameter("wave_speed", float(cfg["wave_speed"]))
	return sm


## Build the water body: a grid mesh at y=`level` covering `radius` metres around `centre`, with each vertex's
## COLOR.r = depth (0 at the shore → 1 in the deep, from the terrain height) so the shader tints + foams correctly.
static func body(centre: Vector3, radius: float, level: float, terrain: GTerrain, samples: int, cfg: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(8, samples)
	var step := (radius * 2.0) / float(n)
	var ds := maxf(1.0, float(cfg.get("depth", 6.0)))
	for iz in n:
		for ix in n:
			var x0 := centre.x - radius + float(ix) * step
			var z0 := centre.z - radius + float(iz) * step
			var x1 := x0 + step
			var z1 := z0 + step
			var a := _wp(x0, z0, level, terrain, ds)
			var b := _wp(x1, z0, level, terrain, ds)
			var c := _wp(x1, z1, level, terrain, ds)
			var d := _wp(x0, z1, level, terrain, ds)
			# top-facing winding (a,b,c)/(a,c,d) with up normals — same as the terrain surface
			_emit(st, a); _emit(st, b); _emit(st, c)
			_emit(st, a); _emit(st, c); _emit(st, d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = make_material(cfg)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# a water-grid vertex: world position at y=level + its baked depth (0 shore .. 1 deep)
static func _wp(x: float, z: float, level: float, terrain: GTerrain, ds: float) -> Dictionary:
	var th := terrain.height(x, z) if terrain != null else 0.0
	return {"p": Vector3(x, level, z), "d": clampf((level - th) / ds, 0.0, 1.0)}


static func _emit(st: SurfaceTool, v: Dictionary) -> void:
	st.set_color(Color(v["d"], 0.0, 0.0, 1.0))
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2((v["p"] as Vector3).x * 0.05, (v["p"] as Vector3).z * 0.05))
	st.add_vertex(v["p"])


static func _c(a) -> Color:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return Color(0.2, 0.4, 0.5)

class_name GBuild
## STRUCTURE BUILDER — composes shapes.gd (FORM) + surfaces.gd (SURFACE) into a complete building from ONE
## world.json spec. The profile + cap parameters make a suburban HOUSE, a Vegas TOWER, an Egyptian PYRAMID, a
## temple PYLON, a ziggurat, an obelisk — all from the SAME function, no per-theme generator. Returns a Node3D
## (base at y=0, centred at x=z=0) holding the composed meshes + a solid collider, ready to place on a lot.
##
## SCHEMA (world.json `structures: [ {...} ]`, a cell-level array):
##   pos            [x,z] cell-local placement (like props)
##   footprint      [w,d] base size in metres            (default [8,8])
##   floors         storeys                              (default 1)   -> height = floors*floor_height
##   height         explicit total height                (overrides floors)
##   floor_height   metres per storey                    (default 3.2)
##   profile        "vertical"|"batter"|"taper"|"setback"|"ziggurat"|"pyramid"   (the per-Z form)
##   batter/shrink/steps   profile tuning
##   cap            "flat"|"gable"|"hip"|"pyramid"|"pyramidion"|"dome"|"spire"    (the roof/top)
##   roof_height    explicit cap height
##   facade         "plain"|"windows" (or {type:"windows",glow:[r,g,b],lit:E})   (wall treatment)
##   material       surface preset/spec for the body (surfaces.gd)
##   roof_material  surface for the cap (defaults to material)
##   rot, scale     yaw degrees, uniform scale
##   collider       "box" (default) | "mesh" (walk-into shell)
##   sign_light     optional {color:[r,g,b], energy, range} -> an OmniLight pool at the roofline (neon spill)

const FLOOR_H := 3.2


static func structure(spec: Dictionary) -> Node3D:
	var root := Node3D.new()
	var foot := _v2(spec.get("footprint", [8, 8]))
	var floors := maxi(1, int(spec.get("floors", 1)))
	var fh := float(spec.get("floor_height", FLOOR_H))
	var height := float(spec.get("height", float(floors) * fh))
	var profile := String(spec.get("profile", "vertical")).to_lower()
	var cap := String(spec.get("cap", "flat")).to_lower()
	var facade = spec.get("facade", "plain")
	var body_mat := GSurf.surface(spec.get("material", "concrete"))
	var roof_mat := GSurf.surface(spec.get("roof_material", spec.get("material", "concrete")))

	var top_foot := foot   # footprint at the body's TOP, so the cap is sized to it

	match profile:
		"batter", "taper":
			var amt := float(spec.get("batter", 0.18 if profile == "batter" else 0.35))
			top_foot = foot * (1.0 - amt)
			var fr := GShapes.frustum(foot, top_foot, height)
			GShapes.set_material(fr, body_mat)
			root.add_child(fr)
		"pyramid":
			var py := GShapes.pyramid(foot, height)
			GShapes.set_material(py, body_mat)
			root.add_child(py)
			top_foot = Vector2.ZERO
		"setback", "ziggurat":
			var steps := maxi(2, int(spec.get("steps", 3)))
			var step_h := height / float(steps)
			var shrink := float(spec.get("shrink", 0.7 if profile == "ziggurat" else 0.82))
			var cur := foot
			var y := 0.0
			for s in steps:
				var blk: MeshInstance3D
				if profile == "ziggurat":
					blk = GShapes.frustum(cur, cur * 0.92, step_h)   # slight batter per tier
					GShapes.set_material(blk, body_mat)
				else:
					blk = GShapes.box(Vector3(cur.x, step_h, cur.y))
					_apply_facade(blk, facade, body_mat, cur, maxi(1, int(step_h / fh)), spec)
				blk.position.y = y
				root.add_child(blk)
				y += step_h
				cur = cur * shrink
			top_foot = cur / shrink
		_:   # "vertical" (default)
			var bx := GShapes.box(Vector3(foot.x, height, foot.y))
			_apply_facade(bx, facade, body_mat, foot, floors, spec)
			root.add_child(bx)

	_add_cap(root, cap, top_foot, height, roof_mat, spec)

	# optional sign light-pool at the roofline (the neon-spill / self-illuminated-city lever)
	if typeof(spec.get("sign_light", null)) == TYPE_DICTIONARY:
		var sl: Dictionary = spec["sign_light"]
		var lp := GSurf.sign_light(_col(sl.get("color", [1, 0.4, 0.7])),
			float(sl.get("energy", 2.0)), float(sl.get("range", maxf(foot.x, foot.y))))
		lp.position.y = height
		root.add_child(lp)

	# collider FIRST (root still at identity, so the AABB is clean), THEN transform — the collider rides along.
	GShapes.add_collider(root, String(spec.get("collider", "box")))
	var rot := float(spec.get("rot", 0.0))
	if rot != 0.0:
		root.rotation.y = deg_to_rad(rot)
	var sc := float(spec.get("scale", 1.0))
	if sc > 0.0 and sc != 1.0:
		root.scale = Vector3(sc, sc, sc)
	return root


# ─────────────────────────────── facade + cap ────────────────────────────────

static func _apply_facade(node: Node3D, facade, body_mat: StandardMaterial3D, foot: Vector2, floors: int, spec: Dictionary) -> void:
	var is_windows := false
	var fdict := {}
	if typeof(facade) == TYPE_STRING:
		is_windows = String(facade).to_lower() == "windows"
	elif typeof(facade) == TYPE_DICTIONARY:
		fdict = facade
		is_windows = String(fdict.get("type", "")).to_lower() == "windows"
	if is_windows:
		var bays := clampi(int(round(maxf(foot.x, foot.y) / 3.0)), 1, 8)
		var rows := clampi(floors, 1, 12)
		var glow := _col(fdict.get("glow", spec.get("window_glow", [1.0, 0.92, 0.7])))
		var lit := float(fdict.get("lit", spec.get("window_lit", 1.6)))
		GShapes.set_material(node, GSurf.window_facade(body_mat.albedo_color, glow, lit, bays, rows))
	else:
		GShapes.set_material(node, body_mat)


static func _add_cap(root: Node3D, cap: String, top_foot: Vector2, height: float, roof_mat: StandardMaterial3D, spec: Dictionary) -> void:
	if top_foot.x <= 0.01 or top_foot.y <= 0.01:
		return   # pyramid body already comes to a point — no cap
	var c: Node3D = null
	match cap:
		"gable":
			c = GShapes.roof_gable(top_foot, float(spec.get("roof_height", maxf(2.0, top_foot.y * 0.45))))
		"hip", "pyramid":
			c = GShapes.pyramid(top_foot, float(spec.get("roof_height", maxf(2.0, minf(top_foot.x, top_foot.y) * 0.5))))
		"pyramidion":
			c = GShapes.pyramid(top_foot, float(spec.get("roof_height", top_foot.x)))
		"dome":
			c = GShapes.dome(minf(top_foot.x, top_foot.y) * 0.5, float(spec.get("roof_height", minf(top_foot.x, top_foot.y) * 0.5)))
		"spire":
			c = GShapes.cylinder(minf(top_foot.x, top_foot.y) * 0.4, 0.0, float(spec.get("roof_height", height * 0.5)), 8)
		_:   # "flat" / unknown -> no cap
			return
	if c != null:
		c.position.y = height
		GShapes.set_material(c, roof_mat)
		root.add_child(c)


# ─────────────────────────────── helpers ────────────────────────────────

static func _v2(a) -> Vector2:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2(8, 8)


static func _col(a) -> Color:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return Color(0.7, 0.7, 0.72)

class_name AreaBuilder extends Node
## AREA BUILDER — turns one world.json area RECORD into a live scene: streams its .glb from
## R2 (parallel, behind the fade), instantiates ground/props/enemies, bakes nav, and
## registers interactables. Cache is shared across areas so re-entry is cheap. Returns the
## area root to free later. The .pck binds scripts+shaders; ASSETS stream from R2 at runtime.

const SKELETON := "/godot-assets/enemies/skeleton_warrior.glb"
const NPC_MODEL := "/godot-assets/characters/kk_Knight.glb"
const EnemyScript := preload("res://enemy.gd")

# named-prop palette: world.json `props: [{kind,pos}]` places these specific assets.
# Validate these paths against the LIVE /godot-assets/manifest.json before shipping.
const PALETTE := {
	"tree": "/godot-assets/props/kenney_nature/Tree_Bare_1.glb",
	"rock": "/godot-assets/props/kenney_nature/Rock_1.glb",
	"barrel": "/godot-assets/props/fs_village/prop_barrel_1.glb",
	"crate": "/godot-assets/props/fs_platformer/prop_crate.glb",
	"box": "/godot-assets/props/fs_platformer/prop_crate.glb",
	"torch": "/godot-assets/props/kk_dungeon/torch.glb",
	"stump": "/godot-assets/props/kenney_nature/Stump_1.glb",
	"log": "/godot-assets/props/kenney_nature/Log_1.glb",
	"pillar": "/godot-assets/props/fs_temple/pillar_large_arch.glb",
	"bush": "/godot-assets/props/fs_nature/bush_1.glb",
	"banner": "/godot-assets/props/kk_dungeon/banner_blue.glb",
	"plant": "/godot-assets/props/kk_hex/waterplant_A.glb",
}

# GROUND material presets — a cell's `ground` may be a NAMED surface ("sand", "asphalt", …) instead
# of a bare [r,g,b]. Every preset (and every legacy RGB) is rendered with a tiled procedural NORMAL
# map so the floor reads as a real surface with relief, NOT a dead flat colored plane (the #1
# "no desert / no real ground" cause). color/rough/tiling/bump are tuned per surface.
const GROUND_PRESETS := {
	"sand":     {"color": [0.78, 0.68, 0.46], "rough": 0.96, "tiling": 9.0,  "bump": 0.5},
	"desert":   {"color": [0.75, 0.63, 0.42], "rough": 0.97, "tiling": 8.0,  "bump": 0.55},
	"dune":     {"color": [0.80, 0.69, 0.47], "rough": 0.97, "tiling": 6.0,  "bump": 0.7},
	"asphalt":  {"color": [0.12, 0.12, 0.14], "rough": 0.82, "tiling": 16.0, "bump": 0.28},
	"road":     {"color": [0.11, 0.11, 0.13], "rough": 0.8,  "tiling": 16.0, "bump": 0.28},
	"concrete": {"color": [0.46, 0.46, 0.49], "rough": 0.9,  "tiling": 11.0, "bump": 0.2},
	"sidewalk": {"color": [0.54, 0.54, 0.57], "rough": 0.9,  "tiling": 11.0, "bump": 0.2},
	"grass":    {"color": [0.30, 0.48, 0.23], "rough": 1.0,  "tiling": 13.0, "bump": 0.45},
	"dirt":     {"color": [0.40, 0.31, 0.22], "rough": 0.98, "tiling": 11.0, "bump": 0.5},
	"mud":      {"color": [0.30, 0.24, 0.17], "rough": 0.7,  "tiling": 10.0, "bump": 0.45},
	"snow":     {"color": [0.90, 0.92, 0.96], "rough": 0.65, "tiling": 9.0,  "bump": 0.35},
	"stone":    {"color": [0.45, 0.45, 0.48], "rough": 0.85, "tiling": 8.0,  "bump": 0.45},
	"cobble":   {"color": [0.40, 0.39, 0.40], "rough": 0.78, "tiling": 7.0,  "bump": 0.65},
	"rock":     {"color": [0.42, 0.40, 0.40], "rough": 0.9,  "tiling": 7.0,  "bump": 0.6},
	"water":    {"color": [0.16, 0.32, 0.42], "rough": 0.12, "tiling": 12.0, "bump": 0.25},
}

# Lazy region payload: density-ONLY fields the optional per-area `region` loose JSON may
# overlay onto a LOCAL effective copy of the record. Graph/winnability fields (id, spawns,
# seams, chest, npc, enemies, enemy_type, size) are NEVER read from the region file — qgcheck
# only sees world.json, so overlaying them would blind the gate.
const REGION_OVERLAY_FIELDS := ["props", "scatter", "ground", "ambient", "name"]

var origin: String                  # https://preview.myapping.com (for /godot-assets/)
var world_url: String               # https://preview.myapping.com/world.json (for sibling loose files)
var cache := {}                     # url -> source Node (persists across areas)
var region_cache := {}              # "<basename>:<region_rev>" -> parsed Dictionary (persists; re-entry skips re-fetch)
var props_pool: Array = []          # prop urls from the manifest
var env: Environment
var _pending := 0
var _ground_mat_cache := {}         # spec-key -> StandardMaterial3D (textured floors shared across cells)


# returns {root: Node3D, enemies: Array} — async (downloads behind the fade)
func build_area(rec: Dictionary, scene_parent: Node, player: Node3D, world_main: Node,
		interaction, _rpg) -> Dictionary:
	# 0. lazy region payload: if this area names a loose `region` JSON file, fetch it and
	# shallow-overlay ONLY density fields onto a LOCAL effective copy. Graph fields stay on the
	# BASE record. Any failure (404 / net / parse) falls back to the base record inline.
	rec = await _apply_region(rec)

	var size := float(rec.get("size", 13))
	var enemy_n := int(rec.get("enemies", 0))
	var scatter_n := 0   # RANDOM SCATTER DISABLED — it was the source of the floating/glitchy clutter.
	# Areas now use ONLY the intentionally-placed `props` (named palette) + colors + chest/npc/seam.

	# 1. resolve the URLs this area needs, then download the missing ones in PARALLEL
	var chosen_props: Array = []
	for _i in range(scatter_n):
		if props_pool.is_empty():
			break
		chosen_props.append(props_pool[randi() % props_pool.size()])
	var urls: Array = []
	if enemy_n > 0:
		urls.append(origin + SKELETON)
	if rec.has("npc"):
		urls.append(origin + NPC_MODEL)
	for u in chosen_props:
		if not (u in urls):
			urls.append(u)
	# named props placed by world.json / AI edits: [{kind, pos}]
	var named: Array = []   # DECORATIVE PROPS DISABLED — they floated/glitched across inconsistent
	# source art. Areas now use colors + functional elements (chest/npc/seam/enemies) only.
	for np in named:
		var purl := _palette_url(np)
		if purl != "" and not (purl in urls):
			urls.append(purl)
	await _ensure(urls)

	# 2. build the area scene
	var root := Node3D.new()
	scene_parent.add_child(root)
	# Skip when the Weather3D system owns the sky/ambient (else it resets each area).
	if env and not env.has_meta("weather_owned"):
		var a = rec.get("ambient", [0.6, 0.6, 0.66])
		env.ambient_light_color = Color(a[0], a[1], a[2])
		env.background_color = Color(a[0] * 0.16, a[1] * 0.16, a[2] * 0.20)
	var nav := _build_room(root, size, rec.get("ground", [0.3, 0.33, 0.38]))

	var placed: Array[Vector2] = []
	for u in chosen_props:
		if not cache.has(u):
			continue
		var p3 := (cache[u] as Node).duplicate() as Node3D
		if p3 == null:
			continue
		root.add_child(p3)
		p3.rotation.y = randf() * TAU
		# size-classify the asset (the pool mixes decor with whole structures): SKIP a building
		# rather than crush it to a weird miniature; shrink merely-large decor so it fits the room.
		var nat := _world_aabb(p3)
		var maxdim: float = max(nat.size.x, max(nat.size.y, nat.size.z))
		if maxdim > 6.0:
			p3.queue_free()   # a building/structure — not scatter decoration
			continue
		if minf(nat.size.x, nat.size.z) < 0.2:
			p3.queue_free()   # a flat billboard/decal plane — reads as a floating white sliver
			continue
		if maxdim > 2.5:
			var sc: float = 2.5 / maxdim
			p3.scale = Vector3(sc, sc, sc)
		# spacing: keep clear of the spawn centre + already-placed props (no overlap / z-fighting)
		var xz := _scatter_spot(size, placed)
		p3.position = Vector3(xz.x, 0.0, xz.y)
		placed.append(xz)
		# GROUND IT: .glb origins sit at base / centre / offset — drop the model so its LOWEST
		# point rests on the floor (y=0), instead of pinning the raw origin there (the float/sink bug).
		var gb := _world_aabb(p3)
		# ONLY DROP a floater to the ground; never LIFT. Models are authored for y=0 placement —
		# many rocks/roots are meant to sit partially EMBEDDED (mesh extends below origin), so lifting
		# them makes them float. Correct only meshes that sit ENTIRELY above the ground.
		p3.position.y -= maxf(0.0, gb.position.y)
		_add_prop_collision(p3, root)   # solid obstacle (derived box)

	# named props (a specific tree/rock/etc. the AI or user placed at a position)
	for np in named:
		var purl := _palette_url(np)
		if purl == "" or not cache.has(purl):
			continue
		var n: Node = (cache[purl] as Node).duplicate()
		root.add_child(n)
		if n is Node3D:
			var n3 := n as Node3D
			var pos = np.get("pos", [0, 0, 0])
			n3.position = Vector3(clamp(float(pos[0]), -size + 1.0, size - 1.0), 0.0, clamp(float(pos[2]), -size + 1.0, size - 1.0))
			n3.rotation.y = randf() * TAU
			var ab2 := _world_aabb(n3)
			var md: float = max(ab2.size.x, max(ab2.size.y, ab2.size.z))
			if md > 2.8:
				var s2: float = 2.8 / md
				n3.scale = Vector3(s2, s2, s2)
			# ground it: drop so the model's base rests on the floor (origins vary across .glb assets)
			var gn := _world_aabb(n3)
			n3.position.y -= maxf(0.0, gn.position.y)   # only drop floaters; never lift (see scatter note)
			_add_prop_collision(n3, root)

	var enemies: Array = []
	if enemy_n > 0 and cache.has(origin + SKELETON):
		for i in range(enemy_n):
			var e := CharacterBody3D.new()
			e.set_script(EnemyScript)
			root.add_child(e)
			var ang := TAU * float(i) / float(enemy_n)
			e.global_position = Vector3(cos(ang) * (size * 0.45), 0.0, sin(ang) * (size * 0.45))
			e.setup(player, (cache[origin + SKELETON] as Node).duplicate(), world_main, i, enemy_n)
			enemies.append(e)

	nav.bake_navigation_mesh(false)   # runtime bake behind the fade

	# 3. interactables — registered with the interaction system, visuals under this root
	interaction.set_area_parent(root)
	if rec.has("chest"):
		var c: Dictionary = rec.chest
		interaction.add_chest(_v3(c.pos), c.get("contents", []), int(c.get("gold", 0)))
	if rec.has("npc"):
		var npc: Dictionary = rec.npc
		var model: Node = (cache[origin + NPC_MODEL] as Node).duplicate() if cache.has(origin + NPC_MODEL) else null
		interaction.add_npc(_v3(npc.pos), String(npc.get("id", "")), npc.name, npc.persona, npc.lines, model)
	for s in rec.get("seams", []):
		# a seam gate may be written `requires` OR `lock` — match the qgcheck validator (lockOf = requires||lock)
		var lk := String(s.get("requires", s.get("lock", "")))
		interaction.add_seam(_v3(s.pos), s.to, s.spawn, lk, s.get("label", "Door"))

	return {root = root, enemies = enemies}


# ---------------- lazy region payload ----------------

func _apply_region(rec: Dictionary) -> Dictionary:
	if not rec.has("region"):
		return rec
	var basename := String(rec.get("region", "")).strip_edges()
	if basename == "":
		return rec
	var region_rev := int(rec.get("region_rev", 0))
	var region: Dictionary = await _fetch_region(basename, region_rev)
	if region.is_empty():
		return rec   # fetch/parse failed — fall back to the base record inline
	var eff: Dictionary = rec.duplicate(true)
	for field in REGION_OVERLAY_FIELDS:
		if region.has(field):
			eff[field] = region[field]
	return eff


func _fetch_region(basename: String, region_rev: int) -> Dictionary:
	var key := basename + ":" + str(region_rev)
	if region_cache.has(key):
		var hit: Dictionary = region_cache[key]
		return hit
	var url := _region_base_dir() + basename + "?rev=" + str(region_rev)
	var req := HTTPRequest.new()
	req.timeout = 8.0   # a hung region fetch must not stall the area build behind the fade
	add_child(req)
	var err := req.request(url)
	if err != OK:
		req.queue_free()
		return {}
	var res = await req.request_completed   # [result, code, headers, body]
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return {}
	var raw := (res[3] as PackedByteArray).get_string_from_utf8()
	if raw.strip_edges() == "":
		return {}
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {}   # parse fail / non-object — caller falls back to base
	var region: Dictionary = parsed
	region_cache[key] = region   # cache so re-entry at the SAME rev doesn't re-fetch
	return region


func _region_base_dir() -> String:
	if world_url != "" and world_url.ends_with("world.json"):
		return world_url.substr(0, world_url.length() - "world.json".length())
	if origin != "":
		return origin + "/"
	return ""


# ---------------- parallel download ----------------

func _ensure(urls: Array) -> void:
	_pending = 0
	for u in urls:
		if cache.has(u):
			continue
		_pending += 1
		var req := HTTPRequest.new()
		add_child(req)
		req.request_completed.connect(_on_dl.bind(u, req))
		req.request(u)
	var guard := 0
	while _pending > 0 and guard < 1800:   # ~30s cap
		await get_tree().process_frame
		guard += 1


func _on_dl(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, url: String, req: HTTPRequest) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 0:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_buffer(body, "", st) == OK:
			cache[url] = doc.generate_scene(st)
	req.queue_free()
	_pending -= 1


# ---------------- build helpers ----------------

func _build_room(root: Node, size: float, ground_spec) -> NavigationRegion3D:
	var nav := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.7
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.navigation_mesh = nm
	root.add_child(nav)
	_ground_box(nav, Vector3(0, -0.5, 0), Vector3(size * 2, 1, size * 2), ground_spec)
	var ground_col := _spec_color(ground_spec)
	var wall := Color(ground_col.r * 0.7, ground_col.g * 0.7, ground_col.b * 0.78)
	_box(nav, Vector3(0, 1.5, -size), Vector3(size * 2, 4, 1), wall)
	_box(nav, Vector3(0, 1.5, size), Vector3(size * 2, 4, 1), wall)
	_box(nav, Vector3(-size, 1.5, 0), Vector3(1, 4, size * 2), wall)
	_box(nav, Vector3(size, 1.5, 0), Vector3(1, 4, size * 2), wall)
	return nav


func _box(parent: Node, pos: Vector3, sz: Vector3, col: Color, cast_shadow := true) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = _mat(col)
	if not cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # e.g. the chunk floor slab -> no self-acne
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)


func _add_prop_collision(prop: Node3D, parent: Node) -> void:
	# derive a solid box collider from the prop's mesh bounds
	var aabb := _world_aabb(prop)
	if aabb.size.x < 0.15 and aabb.size.z < 0.15:
		return                       # too thin to matter (decals/grass)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# clamp the footprint a touch so tall canopies (trees) don't block a huge radius
	box.size = Vector3(
		clamp(aabb.size.x, 0.2, 3.5),
		max(aabb.size.y, 0.4),
		clamp(aabb.size.z, 0.2, 3.5))
	cs.shape = box
	body.add_child(cs)
	parent.add_child(body)
	body.global_position = aabb.position + aabb.size * 0.5


func _world_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var wa: AABB = _rel_xform(root, mi) * mi.get_aabb()
			if first:
				merged = wa
				first = false
			else:
				merged = merged.merge(wa)
	return merged


# Transform of `node` in `root`'s local frame (product of local transforms from root down to node).
# Used instead of global_transform so the AABB is correct EVEN when the freshly-instanced subtree is
# not yet in the SceneTree (reading global_transform off-tree spams "!is_inside_tree()" + returns identity).
func _rel_xform(root: Node3D, node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p != null and p != root and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _scatter_spot(size: float, placed: Array) -> Vector2:
	var fallback := Vector2(randf_range(-size + 2.0, size - 2.0), randf_range(-size + 2.0, size - 2.0))
	for _try in range(6):
		var c := Vector2(randf_range(-size + 2.0, size - 2.0), randf_range(-size + 2.0, size - 2.0))
		if c.length() < 3.0:
			continue
		var ok := true
		for q: Vector2 in placed:
			if c.distance_to(q) < 2.2:
				ok = false
				break
		if ok:
			return c
	return fallback


func _palette_url(np) -> String:
	if typeof(np) != TYPE_DICTIONARY:
		return ""
	var kind := String(np.get("kind", "")).to_lower().strip_edges()
	return (origin + PALETTE[kind]) if PALETTE.has(kind) else ""


func _v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _col(a) -> Color:
	return Color(a[0], a[1], a[2])


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


# ---------------- textured ground (the "real surface, not a flat colored plane" system) ----------------

func _ground_box(parent: Node, pos: Vector3, sz: Vector3, spec, cast_shadow := false) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = _ground_mat(spec)
	if not cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)


func _ground_mat(spec) -> StandardMaterial3D:
	var key := var_to_str(spec)
	if _ground_mat_cache.has(key):
		return _ground_mat_cache[key]
	var p := _ground_params(spec)
	var m := StandardMaterial3D.new()
	m.albedo_color = p["color"]
	m.roughness = p["rough"]
	m.metallic = 0.0
	m.uv1_scale = Vector3(p["tiling"], p["tiling"], p["tiling"])
	m.normal_enabled = true
	m.normal_texture = _noise_normal(int(p["seed"]), float(p["bump"]))
	m.normal_scale = clampf(float(p["bump"]), 0.0, 1.0)
	_ground_mat_cache[key] = m
	return m


func _ground_params(spec) -> Dictionary:
	var out := {"color": Color(0.3, 0.33, 0.38), "rough": 0.92, "tiling": 10.0, "bump": 0.22, "seed": 1}
	if typeof(spec) == TYPE_STRING:
		var nm := String(spec).to_lower().strip_edges()
		if GROUND_PRESETS.has(nm):
			_apply_preset(out, GROUND_PRESETS[nm])
	elif typeof(spec) == TYPE_ARRAY and (spec as Array).size() >= 3:
		out["color"] = _col(spec)
	elif typeof(spec) == TYPE_DICTIONARY:
		var d: Dictionary = spec
		var nm2 := String(d.get("material", d.get("preset", ""))).to_lower().strip_edges()
		if GROUND_PRESETS.has(nm2):
			_apply_preset(out, GROUND_PRESETS[nm2])
		if d.has("color"):
			out["color"] = _col(d["color"])
		if d.has("rough"):
			out["rough"] = float(d["rough"])
		if d.has("tiling"):
			out["tiling"] = float(d["tiling"])
		if d.has("bump"):
			out["bump"] = float(d["bump"])
	out["seed"] = int(float(out["tiling"]) * 7.0) + int((out["color"] as Color).r * 255.0) + int((out["color"] as Color).b * 91.0)
	return out


func _apply_preset(out: Dictionary, pr: Dictionary) -> void:
	out["color"] = _col(pr["color"])
	out["rough"] = float(pr["rough"])
	out["tiling"] = float(pr["tiling"])
	out["bump"] = float(pr["bump"])


func _spec_color(spec) -> Color:
	return _ground_params(spec)["color"]


func _noise_normal(seed_i: int, bump: float) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.05
	fn.seed = seed_i
	fn.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = maxf(0.6, bump * 16.0)
	nt.noise = fn
	return nt

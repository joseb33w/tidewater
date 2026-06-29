extends Node3D
## TIDEWATER — a relaxed open-world coastal-town stroll. Chunk-streamed world (terrain beach +
## animated ocean), an animated third-person townsperson (joystick + WASD, drag-to-orbit camera),
## a wandering crowd you can talk to, a day->sunset->night->sunrise cycle, and localized audio.
##
## Built on the RPG streaming template: ChunkManager streams the world from world.json; this file
## keeps the player / camera / HUD persistent. Combat is stripped (no enemies) — USE talks to people.

const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4

# Third-person orbit camera (SpringArm rig).
const CAM_DIST := 7.5
const CAM_HEAD := 1.5
const CAM_PITCH_MIN := -1.30
const CAM_PITCH_MAX := -0.12
const LOOK_SENS := 0.006

const STROLL_SPEED := 4.2
# Visual-forward correction for the player model (matches ChunkManager.CHAR_FACE_OFFSET for the crowd).
const FACE_OFFSET := 0.0
const GOAL_CELL := Vector2(5, 1)
const GRID_CELL := 16.0

var origin := "https://preview.myapping.com"
var world_url := "https://preview.myapping.com/world.json"
var build_id := ""
var props_pool: Array = []

var world_data := {}
var quests_data := {}
var _world_raw := ""
var _polling := false

var env: Environment
var sun: DirectionalLight3D
var player: CharacterBody3D
var cam: Camera3D
var cam_rig: Node3D
var cam_spring: SpringArm3D
var cam_yaw := 0.0
var cam_pitch := -0.5
var look_idx := -1
var look_last := Vector2.ZERO

var avatar: Node3D
var anim: AnimationPlayer
var clip_idle := ""
var clip_walk := ""
var _step_t := 0.0

var rpg: RpgState
var builder: AreaBuilder
var interaction: InteractionSystem
var scene_manager: SceneManager
var quest: QuestSystem
var weather: Weather3D

var chunk_manager: ChunkManager
var chunk_mode := false
var auto_roam := false
var _roam_t := 0.0
var _won := false

var move_idx := -1
var move_origin := Vector2.ZERO
var move_vec := Vector2.ZERO

var hud_layer: CanvasLayer
var title_lbl: Label
var info_lbl: Label
var hint_lbl: Label
var toast_box: PanelContainer
var toast_lbl: Label
var use_btn: Button


func _ready() -> void:
	if OS.has_feature("web"):
		var o = JavaScriptBridge.eval("window.location.origin", true)
		if typeof(o) == TYPE_STRING and String(o) != "":
			origin = String(o)
		var dir = JavaScriptBridge.eval("window.location.href.replace(/[^/]*$/, '')", true)
		if typeof(dir) == TYPE_STRING and String(dir) != "":
			world_url = String(dir) + "world.json"
		var bid = JavaScriptBridge.eval("location.pathname.split('/').filter(Boolean)[0] || ''", true)
		if typeof(bid) == TYPE_STRING and String(bid) != "":
			build_id = String(bid)
		var soak = JavaScriptBridge.eval("window.location.search.indexOf('soak=1')>=0", true)
		if typeof(soak) == TYPE_BOOL and soak:
			auto_roam = true

	# force full-screen fill (web canvas size isn't final on frame 1)
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

	_build_env()
	_build_player()
	weather = Weather3D.new()
	add_child(weather)
	weather.setup(env, sun, cam_rig)
	_build_hud()
	get_window().size_changed.connect(_relayout_ui)
	AudioManager.show_tap_overlay()

	# ambient soundscape: a calm town track + a quiet sea-breeze bed; footsteps are per-step SFX.
	for i in [1, 2, 3]:
		var sp := "res://audio/step%d.ogg" % i
		if ResourceLoader.exists(sp):
			AudioManager.register_sfx("step%d" % i, load(sp))
	if ResourceLoader.exists("res://audio/music_town.ogg"):
		AudioManager.play_music(load("res://audio/music_town.ogg"), -10.0)
	if ResourceLoader.exists("res://audio/seabreeze.ogg"):
		AudioManager.play_ambient(load("res://audio/seabreeze.ogg"), -20.0)

	rpg = RpgState.new()
	add_child(rpg)

	builder = AreaBuilder.new()
	builder.origin = origin
	builder.world_url = world_url
	builder.env = env
	add_child(builder)

	interaction = InteractionSystem.new()
	add_child(interaction)

	scene_manager = SceneManager.new()
	add_child(scene_manager)

	quest = QuestSystem.new()
	add_child(quest)
	quest.setup(rpg)

	interaction.setup(player, rpg, scene_manager, quest, hud_layer)
	scene_manager.setup(player, builder, interaction, self, hud_layer)
	scene_manager.area_entered.connect(quest.notify_area)

	chunk_manager = ChunkManager.new()
	add_child(chunk_manager)
	chunk_manager.setup(player, builder, self, env, interaction, rpg)
	chunk_manager.area_entered.connect(quest.notify_area)
	chunk_manager.area_entered.connect(_on_area)

	var poll := Timer.new()
	poll.wait_time = 4.0
	poll.autostart = true
	poll.timeout.connect(_poll_world)
	add_child(poll)

	await get_tree().process_frame
	await get_tree().process_frame
	_relayout_ui()
	_boot()


func _boot() -> void:
	var man := HTTPRequest.new()
	add_child(man)
	man.request(origin + "/godot-assets/manifest.json")
	var mr = await man.request_completed
	man.queue_free()
	if mr[1] == 200:
		_parse_manifest(mr[3])
	builder.props_pool = props_pool

	var wq := HTTPRequest.new()
	add_child(wq)
	wq.request(world_url)
	var wr = await wq.request_completed
	wq.queue_free()
	if wr[1] != 200:
		info_lbl.text = "world.json fetch failed (HTTP %s)" % str(wr[1])
		return
	var raw := (wr[3] as PackedByteArray).get_string_from_utf8()
	var world = JSON.parse_string(raw)
	if not (world is Dictionary):
		info_lbl.text = "world.json parse error"
		return
	world_data = world
	_world_raw = raw
	_apply_weather(world)

	var qq := HTTPRequest.new()
	add_child(qq)
	qq.request(world_url.replace("world.json", "quests.json"))
	var qr = await qq.request_completed
	qq.queue_free()
	if qr[1] == 200:
		var qdata = JSON.parse_string((qr[3] as PackedByteArray).get_string_from_utf8())
		if qdata is Dictionary:
			quests_data = qdata
			quest.load_quests(qdata)
			var first_quest = quests_data.get("quests", [])
			if first_quest.size() > 0:
				quest.start(first_quest[0].get("id", ""))

	if String(world.get("mode", "")) == "chunk":
		chunk_mode = true
		scene_manager._fade.visible = false
		sun.shadow_enabled = true
		sun.shadow_normal_bias = 2.0
		sun.directional_shadow_max_distance = 42.0
		await chunk_manager.start(world)
	else:
		scene_manager.start(world)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if chunk_mode:
		_chunk_physics(delta)
		return
	if scene_manager == null or scene_manager.transitioning or scene_manager.current_root == null:
		return
	var v := _keyboard_vec() + move_vec
	if v.length() > 1.0:
		v = v.normalized()
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(v.x, 0.0, v.y)
	player.velocity = dir * STROLL_SPEED
	if dir.length() > 0.1:
		var look := player.global_position - dir
		player.look_at(Vector3(look.x, player.global_position.y, look.z), Vector3.UP)
	player.move_and_slide()
	_update_locomotion(Vector2(player.velocity.x, player.velocity.z).length(), delta)


func _chunk_physics(delta: float) -> void:
	var v := _keyboard_vec() + move_vec
	if auto_roam and chunk_manager != null:
		_roam_t += delta
		var rect := chunk_manager.grid_world_rect()
		var tt := fmod(_roam_t * 0.05, 2.0)
		var f := tt if tt <= 1.0 else (2.0 - tt)
		var target := Vector3(rect.position.x, 0.0, rect.position.y).lerp(
			Vector3(rect.end.x, 0.0, rect.end.y), f)
		var to := target - player.global_position
		v = Vector2(to.x, to.z)
	if v.length() > 1.0:
		v = v.normalized()
	var dir := Vector3(v.x, 0.0, v.y) if auto_roam else Basis(Vector3.UP, cam_yaw) * Vector3(v.x, 0.0, v.y)
	player.velocity = Vector3(dir.x * STROLL_SPEED, 0.0, dir.z * STROLL_SPEED)
	if dir.length() > 0.1:
		var look := player.global_position - dir
		player.look_at(Vector3(look.x, player.global_position.y, look.z), Vector3.UP)
	player.move_and_slide()
	# Kinematic grounding: ride the terrain heightfield directly so the player can NEVER fall through.
	# (A cell's terrain collider only exists AFTER its async asset stream finishes — gravity would drop
	# the player into the void before then. The heightfield is the same surface that's rendered.)
	if chunk_manager != null:
		var gp := player.global_position
		gp.y = chunk_manager.ground_height(gp.x, gp.z) + 0.05
		player.global_position = gp
	_update_locomotion(Vector2(player.velocity.x, player.velocity.z).length(), delta)


# Play walk while moving / idle while still, and fire footstep SFX on a stride timer.
func _update_locomotion(spd: float, delta: float) -> void:
	if anim != null:
		var moving := spd > 0.7
		if moving and clip_walk != "":
			if anim.current_animation != clip_walk:
				anim.play(clip_walk, 0.18)
		elif not moving and clip_idle != "":
			if anim.current_animation != clip_idle:
				anim.play(clip_idle, 0.25)
	if spd > 0.7:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.36
			var pick := "step%d" % (1 + (Time.get_ticks_msec() / 360) % 3)
			AudioManager.play_sfx(pick, -7.0, randf_range(0.92, 1.08))
	else:
		_step_t = 0.0


func _process(delta: float) -> void:
	if cam_rig and player:
		cam_rig.global_position = player.global_position + Vector3(0.0, CAM_HEAD, 0.0)
		cam_rig.rotation.y = cam_yaw
		cam_spring.rotation.x = cam_pitch
	if chunk_mode and chunk_manager != null:
		chunk_manager.tick(delta)
	_refresh_hud()


# ---------------- HUD ----------------

func _refresh_hud() -> void:
	if info_lbl == null or player == null:
		return
	var goal := Vector3(GOAL_CELL.x * GRID_CELL + GRID_CELL * 0.5, 0.0, GOAL_CELL.y * GRID_CELL + GRID_CELL * 0.5)
	var to := goal - player.global_position
	to.y = 0.0
	if _won:
		info_lbl.text = "You reached the lighthouse. Wander and enjoy Tidewater."
	else:
		info_lbl.text = "Stroll to the old lighthouse  -  %dm %s" % [int(to.length()), _compass(to)]


func _compass(v: Vector3) -> String:
	if v.length() < 1.0:
		return ""
	var ang := rad_to_deg(atan2(v.x, -v.z))   # 0 = north(-z), 90 = east(+x)
	if ang < 0.0:
		ang += 360.0
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return dirs[int(round(ang / 45.0)) % 8]


func _on_area(area_id: String) -> void:
	if area_id == "c%d_%d" % [int(GOAL_CELL.x), int(GOAL_CELL.y)] and not _won:
		_won = true
		_show_toast("You reached the old lighthouse on the point.\nIts beam sweeps the bay at dusk - enjoy the view.")


# ---------------- live hot-reload ----------------

func _poll_world() -> void:
	if scene_manager == null or scene_manager.transitioning or world_data.is_empty() or _polling:
		return
	_polling = true
	var req := HTTPRequest.new()
	add_child(req)
	req.request(world_url + "?t=" + str(Time.get_ticks_msec()))
	var res = await req.request_completed
	req.queue_free()
	_polling = false
	if res[1] != 200:
		return
	var raw := (res[3] as PackedByteArray).get_string_from_utf8()
	if raw == _world_raw or raw.strip_edges() == "":
		return
	var w = JSON.parse_string(raw)
	if not (w is Dictionary):
		return
	if chunk_mode:
		if not w.has("cells"):
			return
	elif not w.has("areas"):
		return
	_world_raw = raw
	world_data = w
	_apply_weather(w)
	if chunk_mode:
		chunk_manager.reload(world_data)
	else:
		scene_manager.reload(world_data)


# ---------------- input ----------------

func _input(event: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < half and move_idx == -1:
				move_idx = event.index
				move_origin = event.position
				move_vec = Vector2.ZERO
			elif event.position.x >= half and look_idx == -1:
				look_idx = event.index
				look_last = event.position
		else:
			if event.index == move_idx:
				move_idx = -1
				move_vec = Vector2.ZERO
			elif event.index == look_idx:
				look_idx = -1
	elif event is InputEventScreenDrag:
		if event.index == move_idx:
			move_vec = ((event.position - move_origin) / 80.0).limit_length(1.0)
		elif event.index == look_idx:
			_apply_look(event.position - look_last)
			look_last = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and move_idx == -1 and look_idx == -1:
		_apply_look(event.relative)


func _apply_look(d: Vector2) -> void:
	cam_yaw -= d.x * LOOK_SENS
	cam_pitch = clampf(cam_pitch - d.y * LOOK_SENS, CAM_PITCH_MIN, CAM_PITCH_MAX)


func _keyboard_vec() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1.0
	return v


# ---------------- manifest ----------------

func _parse_manifest(body: PackedByteArray) -> void:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		return
	for p in data.get("props", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		if String(p.get("category", "")) != "nature":
			continue
		var fn := String(p.get("file", "")).get_file().to_lower()
		if "terrain" in fn or "path" in fn or "cliff" in fn or "beach" in fn or "railway" in fn or "road" in fn or "fence" in fn:
			continue
		var u := _norm(String(p.get("file", "")))
		if u != "" and "/godot-assets/props/" in u:
			props_pool.append(u)


func _norm(s: String) -> String:
	if s.begins_with("http"):
		return s
	if s.begins_with("/"):
		return origin + s
	if "/" in s:
		return origin + "/godot-assets/" + s
	return ""


func _apply_weather(world: Dictionary) -> void:
	if weather == null:
		return
	var sky = world.get("sky", null)
	if sky is Dictionary:
		weather.apply(sky)


# ---------------- world build (persistent player/env/hud) ----------------

func _build_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.7, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82   # the bright day sky + light pastels blow out at 1.0 — pull it down
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.2
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -45.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.collision_layer = L_PLAYER
	player.collision_mask = L_WORLD | L_ENEMY
	add_child(player)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.9
	player.add_child(cs)

	# the townsperson avatar: Meshy character if present, else a library KayKit fallback (retargeted)
	var model_path := "res://models/tidewater_player.glb"
	if not ResourceLoader.exists(model_path):
		model_path = "res://models/kk_player.glb"
	var ps = load(model_path)
	if ps != null:
		avatar = (ps as PackedScene).instantiate() as Node3D
		avatar.rotation.y = FACE_OFFSET
		player.add_child(avatar)
		_seat_avatar(avatar)
		anim = _find_anim_player(avatar)
		if anim == null or anim.get_animation_list().is_empty():
			anim = AnimRig.attach(avatar, {"idle": "Idle_A", "walk": "Walking_A"}, ["idle", "walk"])
			clip_idle = "idle"
			clip_walk = "walk"
		else:
			clip_idle = _match_clip(anim, ["idle", "stand", "breath"])
			clip_walk = _match_clip(anim, ["walk", "run", "move"])
		for cn in [clip_idle, clip_walk]:
			if cn != "":
				var a := anim.get_animation(cn)
				if a != null:
					a.loop_mode = Animation.LOOP_LINEAR
		if anim != null and clip_idle != "":
			anim.play(clip_idle)
	else:
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.34
		cm.height = 1.7
		body.mesh = cm
		body.position.y = 0.9
		body.material_override = _mat(Color(0.3, 0.6, 0.95))
		player.add_child(body)

	cam_rig = Node3D.new()
	add_child(cam_rig)
	cam_spring = SpringArm3D.new()
	cam_spring.spring_length = CAM_DIST
	cam_spring.collision_mask = L_WORLD
	cam_spring.margin = 0.3
	cam_spring.rotation.x = cam_pitch
	cam_rig.add_child(cam_spring)
	cam = Camera3D.new()
	cam.fov = 64.0
	cam_spring.add_child(cam)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _match_clip(ap: AnimationPlayer, keys: Array) -> String:
	var clips := ap.get_animation_list()
	for k in keys:
		for c in clips:
			if String(k) in String(c).to_lower():
				return String(c)
	return String(clips[0]) if clips.size() > 0 else ""


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


func _seat_avatar(node: Node3D) -> void:
	node.position.y -= _subtree_aabb(node).position.y


func _subtree_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var wa: AABB = mi.global_transform * mi.get_aabb()
			if first:
				merged = wa
				first = false
			else:
				merged = merged.merge(wa)
	return merged


# ---------------- HUD build + responsive layout ----------------

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)

	title_lbl = Label.new()
	title_lbl.text = "Tidewater"
	title_lbl.add_theme_font_size_override("font_size", 30)
	title_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0.12, 0.2, 0.85))
	title_lbl.add_theme_constant_override("outline_size", 8)
	hud_layer.add_child(title_lbl)

	info_lbl = Label.new()
	info_lbl.add_theme_font_size_override("font_size", 20)
	info_lbl.add_theme_color_override("font_color", Color(0.94, 0.98, 1.0))
	info_lbl.add_theme_color_override("font_outline_color", Color(0, 0.1, 0.18, 0.85))
	info_lbl.add_theme_constant_override("outline_size", 6)
	hud_layer.add_child(info_lbl)

	hint_lbl = Label.new()
	hint_lbl.text = "Drag LEFT to move   -   Drag RIGHT to look   -   USE to talk"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 19)
	hint_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	hint_lbl.add_theme_color_override("font_outline_color", Color(0, 0.1, 0.18, 0.9))
	hint_lbl.add_theme_constant_override("outline_size", 6)
	hud_layer.add_child(hint_lbl)
	var hint_tw := hint_lbl.create_tween()
	hint_tw.tween_interval(7.0)
	hint_tw.tween_property(hint_lbl, "modulate:a", 0.0, 1.5)

	use_btn = Button.new()
	use_btn.text = "USE"
	use_btn.add_theme_font_size_override("font_size", 30)
	use_btn.pressed.connect(func() -> void: interaction.try_use())
	hud_layer.add_child(use_btn)

	toast_box = PanelContainer.new()
	toast_box.visible = false
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 22)
	mc.add_theme_constant_override("margin_right", 22)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 16)
	toast_box.add_child(mc)
	toast_lbl = Label.new()
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.add_theme_font_size_override("font_size", 24)
	toast_lbl.add_theme_color_override("font_color", Color(1, 0.97, 0.88))
	mc.add_child(toast_lbl)
	hud_layer.add_child(toast_box)


func _relayout_ui() -> void:
	if hud_layer == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var ins := _safe_insets()
	var top := maxf(14.0, ins.get("top", 0.0))
	var left := maxf(16.0, ins.get("left", 0.0))
	var right := maxf(16.0, ins.get("right", 0.0))
	var bottom := maxf(16.0, ins.get("bottom", 0.0))
	if title_lbl:
		title_lbl.position = Vector2(left, top)
	if info_lbl:
		info_lbl.position = Vector2(left, top + 40.0)
	if hint_lbl:
		hint_lbl.size = Vector2(vp.x, 28.0)
		hint_lbl.position = Vector2(0.0, vp.y * 0.5 - 130.0)
	if use_btn:
		var bw := 200.0
		var bh := 120.0
		use_btn.size = Vector2(bw, bh)
		use_btn.position = Vector2(vp.x - bw - right, vp.y - bh - bottom - 24.0)
	if toast_box:
		toast_box.reset_size()
		var ts := toast_box.size
		if ts.x < 1.0:
			ts = Vector2(min(vp.x - 60.0, 560.0), 90.0)
		toast_box.position = Vector2((vp.x - ts.x) * 0.5, vp.y * 0.34)


func _show_toast(text: String) -> void:
	if toast_lbl == null:
		return
	toast_lbl.text = text
	toast_box.visible = true
	toast_box.modulate.a = 1.0
	_relayout_ui()
	var tw := toast_box.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(toast_box, "modulate:a", 0.0, 1.5)
	tw.tween_callback(func() -> void: toast_box.visible = false)


func _safe_insets() -> Dictionary:
	if not OS.has_feature("web"):
		return {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}
	var js := """(() => { const d = document.createElement('div');
	  d.style.cssText = 'position:fixed;top:env(safe-area-inset-top);bottom:env(safe-area-inset-bottom);left:env(safe-area-inset-left);right:env(safe-area-inset-right)';
	  document.body.appendChild(d); const r = getComputedStyle(d);
	  const o = {top:parseFloat(r.top)||0, bottom:parseFloat(r.bottom)||0, left:parseFloat(r.left)||0, right:parseFloat(r.right)||0};
	  d.remove(); return JSON.stringify(o); })()"""
	var raw := str(JavaScriptBridge.eval(js, true))
	var parsed = JSON.parse_string(raw) if raw != "" else null
	if parsed is Dictionary:
		var pd: Dictionary = parsed
		return pd
	return {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}


# ---------------- unused-combat hooks kept for streamer parity (no enemies in this world) ----------------

func take_damage(_d: float) -> void:
	pass


func on_enemy_killed(_type: String) -> void:
	pass

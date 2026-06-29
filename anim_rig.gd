class_name AnimRig extends RefCounted
## Shared KayKit Rig_Medium retarget. The Knight AND the streamed skeletons all use the
## same `Rig_Medium` skeleton (23 bones), but NONE of them carry embedded clips — the
## clips live in the packed `kk_rig_medium_*` libraries. This copies those clip resources
## onto a fresh AnimationPlayer attached to any Rig_Medium model, so one clip set drives
## the hero and every enemy. Verified headless: copied tracks (path `Rig_Medium/Skeleton3D:bone`)
## resolve against the model and animate the skeleton.

const LIBS := [
	"res://models/kk_rig_medium_general.glb",
	"res://models/kk_rig_medium_movementbasic.glb",
	"res://models/kk_rig_medium_combatmelee.glb",
]

static var _clips := {}          # source clip name -> Animation (cached, duplicated)

static func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null

static func _load_clips() -> void:
	if not _clips.is_empty():
		return
	for path in LIBS:
		var ps = load(path)
		if ps == null:
			continue
		var inst := (ps as PackedScene).instantiate()
		var ap := _find_ap(inst)
		if ap != null:
			for nm in ap.get_animation_list():
				if not _clips.has(nm):
					_clips[nm] = ap.get_animation(nm).duplicate()
		inst.queue_free()

## Attach an AnimationPlayer to `model` exposing aliases mapped to source clip names.
## `mapping`: {alias: source_clip_name}. `loops`: aliases that should loop.
static func attach(model: Node3D, mapping: Dictionary, loops: Array) -> AnimationPlayer:
	_load_clips()
	var ap := AnimationPlayer.new()
	ap.name = "RigPlayer"
	model.add_child(ap)
	ap.root_node = ap.get_path_to(model)          # tracks are relative to the model root
	var lib := AnimationLibrary.new()
	for alias in mapping:
		var src := String(mapping[alias])
		if _clips.has(src):
			var a: Animation = (_clips[src] as Animation).duplicate()
			a.loop_mode = Animation.LOOP_LINEAR if alias in loops else Animation.LOOP_NONE
			lib.add_animation(StringName(alias), a)
	ap.add_animation_library("", lib)
	return ap

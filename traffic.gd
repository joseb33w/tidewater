class_name TrafficCar extends Node3D
## AMBIENT TRAFFIC — a car that drives along a lane (a world-space line A→B) at constant speed and LOOPS, riding
## the terrain and facing its heading. Spawned along a cell's `roads` so a city's streets have moving cars (the
## "living city" cue). Pure transform movement (no physics) so many can run cheaply; the player's drivable car is
## a separate gameplay feature. The car MODEL is a child of this node; `setup()` wires the lane.

var a: Vector3 = Vector3.ZERO     # lane start (world)
var b: Vector3 = Vector3.ZERO     # lane end (world)
var speed := 6.0
var terrain: GTerrain = null
var _u := 0.0                     # progress 0..1 along the lane
var _len := 1.0


func setup(start: Vector3, end: Vector3, spd: float, t: GTerrain, u0 := 0.0) -> void:
	a = start
	b = end
	speed = maxf(0.5, spd)
	terrain = t
	_u = clampf(u0, 0.0, 1.0)
	_len = maxf(0.1, a.distance_to(b))
	# face the lane direction up front so it doesn't spawn sideways
	var dir := (b - a).normalized()
	rotation.y = atan2(dir.x, dir.z)
	_apply()
	set_process(true)


func _process(delta: float) -> void:
	_u += (speed * delta) / _len
	if _u > 1.0:
		_u -= 1.0   # loop back to the lane start (the neighbour cell's cars continue the street)
	_apply()


func _apply() -> void:
	var p := a.lerp(b, _u)
	var gy := terrain.height(p.x, p.z) if terrain != null else 0.0
	position = Vector3(p.x, gy + 0.12, p.z)   # ride just above the road surface

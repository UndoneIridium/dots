extends Node3D

const SPHERE_RADIUS = 1.0
const ZOOM_MIN = 1.12
const ZOOM_MAX = 6.0
const ZOOM_SPEED = 0.08
const PINCH_SPEED = 0.004
const ZOOM_SMOOTH = 8.0
const ROTATE_SPEED = 0.005

const TICK_SPEED = 5.0
var tick_timer = 0.0

# Set to true when server is implemented
const USE_SERVER = false

const DOT_LIFETIME = 100  # ticks before a dot dies

# All dots and their per-dot data
var dots = []
var dot_data = {}
# dot_data[dot] = {
#     "age": int,          — ticks lived
#     "behavior": String,  — current active behavior (placeholder for per-dot behavior later)
# }

var player_dot = null
var current_behavior = "idle"

@onready var camera = $Camera3D
@onready var chant_button = $UI/ChantButton
@onready var chant_modal = $UI/ChantModal
@onready var chant_input = $UI/ChantModal/VBox/ChantInput
@onready var confirm_button = $UI/ChantModal/VBox/ButtonRow/ConfirmButton
@onready var cancel_button = $UI/ChantModal/VBox/ButtonRow/CancelButton

# Zoom state
var zoom_target = 3.0
var zoom_distance = 3.0

# Orbit state
var orbit_yaw = 0.0
var orbit_pitch = 0.0
var is_orbiting = false

# Pinch state
var touch_positions = {}
var pinch_last_distance = 0.0

# Single finger drag (mobile orbit)
var single_touch_active = false
var single_touch_index = -1

const INTENT_MAP = {
	"multiply": "reproduce", "sex": "reproduce", "reproduce": "reproduce",
	"breed": "reproduce", "spawn": "reproduce", "clone": "reproduce", "divide": "reproduce",
	"build": "construct", "create": "construct", "invent": "construct",
	"construct": "construct", "make": "construct", "design": "construct", "forge": "construct",
	"explore": "explore", "wander": "explore", "move": "explore",
	"travel": "explore", "roam": "explore", "search": "explore",
	"attack": "aggressive", "dominate": "aggressive", "fight": "aggressive",
	"conquer": "aggressive", "destroy": "aggressive", "war": "aggressive",
	"defend": "defend", "protect": "defend", "guard": "defend",
	"shield": "defend", "fortify": "defend",
	"gather": "gather", "collect": "gather", "harvest": "gather",
	"mine": "gather", "farm": "gather",
}

func _ready():
	_spawn_player_dot()
	_update_camera()
	chant_button.pressed.connect(_open_chant)
	confirm_button.pressed.connect(_confirm_chant)
	cancel_button.pressed.connect(_close_chant)
	chant_input.text_submitted.connect(_on_chant_submitted)

func _open_chant():
	chant_modal.visible = true
	chant_input.clear()
	chant_input.grab_focus()

func _close_chant():
	chant_modal.visible = false
	chant_input.clear()

func _confirm_chant():
	_process_input(chant_input.text)
	_close_chant()

func _on_chant_submitted(text: String):
	_process_input(text)
	_close_chant()

func _process(delta):
	zoom_distance = lerp(zoom_distance, zoom_target, ZOOM_SMOOTH * delta)
	zoom_distance = max(zoom_distance, ZOOM_MIN)
	_update_camera()
	# Behavior tick
	tick_timer += delta
	if tick_timer >= TICK_SPEED:
		tick_timer = 0.0
		_age_dots()
		if current_behavior != "idle":
			_apply_behavior(current_behavior)

func _focus_on_colony():
	var center = Vector3.ZERO
	for dot in dots:
		center += dot.position.normalized()
	if dots.size() > 0:
		center = (center / dots.size()).normalized()
	orbit_yaw = atan2(center.x, center.z)
	orbit_pitch = asin(clamp(center.y, -1.0, 1.0))

func _update_camera():
	var pitch_clamped = clamp(orbit_pitch, -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
	var x = zoom_distance * cos(pitch_clamped) * sin(orbit_yaw)
	var y = zoom_distance * sin(pitch_clamped)
	var z = zoom_distance * cos(pitch_clamped) * cos(orbit_yaw)
	camera.position = Vector3(x, y, z)
	camera.look_at(Vector3.ZERO, Vector3.UP)

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			is_orbiting = event.pressed
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom(-ZOOM_SPEED)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(ZOOM_SPEED)

	if event is InputEventMouseMotion and is_orbiting:
		orbit_yaw -= event.relative.x * ROTATE_SPEED
		orbit_pitch += event.relative.y * ROTATE_SPEED

	if event is InputEventScreenTouch:
		if event.pressed:
			touch_positions[event.index] = event.position
			if touch_positions.size() == 1:
				single_touch_active = true
				single_touch_index = event.index
		else:
			touch_positions.erase(event.index)
			pinch_last_distance = 0.0
			if event.index == single_touch_index:
				single_touch_active = false
				single_touch_index = -1

	if event is InputEventScreenDrag:
		touch_positions[event.index] = event.position
		if touch_positions.size() == 1 and single_touch_active:
			orbit_yaw -= event.relative.x * ROTATE_SPEED
			orbit_pitch += event.relative.y * ROTATE_SPEED
		elif touch_positions.size() >= 2:
			single_touch_active = false
			var keys = touch_positions.keys()
			var t0 = touch_positions[keys[0]]
			var t1 = touch_positions[keys[1]]
			var current_dist = t0.distance_to(t1)
			if pinch_last_distance > 0.0:
				var delta = pinch_last_distance - current_dist
				_zoom(delta * PINCH_SPEED)
			pinch_last_distance = current_dist

func _zoom(delta: float):
	zoom_target = clamp(zoom_target + delta, ZOOM_MIN, ZOOM_MAX)

func _process_input(text: String):
	if USE_SERVER:
		_send_chant_to_server(text)  # TODO: implement when server is ready
	else:
		_process_chant_locally(text)

func _send_chant_to_server(_text: String):
	pass  # HTTP call to server goes here

func _process_chant_locally(text: String):
	var lower = text.to_lower().strip_edges()
	var behavior = INTENT_MAP.get(lower, "idle")
	current_behavior = behavior
	print("Input: '%s' → Behavior: %s" % [text, behavior])
	_apply_behavior(behavior)

func _apply_behavior(behavior: String):
	var current_dots = dots.duplicate()
	match behavior:
		"reproduce":
			for dot in current_dots:
				_spawn_dot_near(dot)
		"construct":
			print("TODO: construct")
		"explore":
			for dot in current_dots:
				_move_dot_randomly(dot)
		"aggressive":
			print("TODO: aggressive")
		"defend":
			print("TODO: defend")
		"gather":
			print("TODO: gather")
		"idle":
			print("Idle")

func _spawn_player_dot():
	var angle = randf() * TAU
	player_dot = _create_dot(Vector3(sin(angle), 0.0, cos(angle)))
	_focus_on_colony()

func _spawn_dot_near(reference_dot: Node3D):
	if reference_dot == null:
		return
	var dir = reference_dot.position.normalized()
	var up = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var tangent = dir.cross(up).normalized()
	var bitangent = dir.cross(tangent).normalized()
	var angle = randf() * TAU
	var nudge = (tangent * cos(angle) + bitangent * sin(angle)) * 0.018
	var new_dir = (dir + nudge).normalized()
	_create_dot(new_dir)
	_focus_on_colony()

func _move_dot_randomly(dot: Node3D):
	if dot == null:
		return
	var dir = dot.position.normalized()
	var tangent = dir.cross(Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1))).normalized()
	var nudge_amount = randf_range(0.02, 0.06)
	var new_dir = (dir + tangent * nudge_amount).normalized()
	_place_dot_on_sphere(dot, new_dir)

func _create_dot(direction: Vector3) -> Node3D:
	var dot = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.015, 0.006, 0.015)
	dot.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.CYAN
	mat.emission_enabled = true
	mat.emission = Color.CYAN
	mat.emission_energy_multiplier = 0.8
	dot.material_override = mat
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(dot)
	dots.append(dot)
	dot_data[dot] = {
		"age": 0,
		"behavior": "idle",
	}
	_place_dot_on_sphere(dot, direction)
	return dot

func _age_dots():
	var to_remove = []
	for dot in dots:
		dot_data[dot]["age"] += 1
		if dot_data[dot]["age"] >= DOT_LIFETIME:
			to_remove.append(dot)
	for dot in to_remove:
		dots.erase(dot)
		dot_data.erase(dot)
		if dot == player_dot:
			player_dot = dots[0] if dots.size() > 0 else null
		dot.queue_free()

func _place_dot_on_sphere(dot: Node3D, direction: Vector3):
	var dir = direction.normalized()
	dot.position = dir * (SPHERE_RADIUS + 0.0075)
	var basis = Basis()
	basis.y = dir
	basis.x = basis.y.cross(Vector3.FORWARD if abs(dir.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	basis.z = basis.x.cross(basis.y).normalized()
	dot.transform.basis = basis

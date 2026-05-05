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

const USE_SERVER = false
const DOT_LIFETIME = 100
const CCE_DILUTION = 0.7
const CHANT_WEIGHT = 0.08  # how much each chant shifts a weight
const CHANT_FILE = "res://chant.json"

# Baseline dial values
const DIAL_BASELINE = {
	"range": 0.5,
	"intensity": 0.5,
	"frequency": 1.0,
	"affinity": 0.0
}

# Neutral CCE for a new dot with no cultural history
const NEUTRAL_CCE = {
	"motion": {
		"wander": 0.0,
		"face_target": 0.0,
	},
	"action": {
		"mark_surface": 0.0,
		"build_upward": 0.0,
		"gather": 0.0,
		"defend": 0.0,
		"attack": 0.0,
		"reproduce": 0.0
	},
	"dials": {
		"range": 0.5,
		"intensity": 0.5,
		"frequency": 1.0,
		"affinity": 0.0,
		"spiral": 0.0
	}
}

var dots = []
var dot_data = {}
# dot_data[dot] = {
#   "age": int,
#   "cce": {
#     "motion": { wander, cluster, spread, face_target, spiral },
#     "action": { mark_surface, build_upward, gather, defend, attack, reproduce },
#     "dials": { range, intensity, frequency, affinity }
#   }
# }

var player_dot = null

@onready var camera = $Camera3D
@onready var chant_button = $UI/ChantButton
@onready var chant_modal = $UI/ChantModal
@onready var chant_input = $UI/ChantModal/VBox/ChantInput
@onready var confirm_button = $UI/ChantModal/VBox/ButtonRow/ConfirmButton
@onready var cancel_button = $UI/ChantModal/VBox/ButtonRow/CancelButton
@onready var dev_bar = $UI/DevBar

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

# Single finger drag
var single_touch_active = false
var single_touch_index = -1

func _ready():
	_spawn_player_dot()
	_update_camera()
	chant_button.pressed.connect(_open_chant)
	confirm_button.pressed.connect(_confirm_chant)
	cancel_button.pressed.connect(_close_chant)
	chant_input.text_submitted.connect(_on_chant_submitted)
	dev_bar.placeholder_text = "dev chant..."
	dev_bar.text_submitted.connect(_on_dev_chant)

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

func _on_dev_chant(text: String):
	_process_input(text)
	dev_bar.clear()

func _process(delta):
	zoom_distance = lerp(zoom_distance, zoom_target, ZOOM_SMOOTH * delta)
	zoom_distance = max(zoom_distance, ZOOM_MIN)
	_update_camera()
	tick_timer += delta
	if tick_timer >= TICK_SPEED:
		tick_timer = 0.0
		_check_chant_file()
		_age_dots()
		_tick_all_dots()

# --- Chant file (Claude bridge) ---

func _check_chant_file():
	if not FileAccess.file_exists(CHANT_FILE):
		return
	var file = FileAccess.open(CHANT_FILE, FileAccess.READ)
	if file == null:
		return
	var content = file.get_as_text().strip_edges()
	file.close()
	if content == "" or content == "{}":
		return
	var json = JSON.new()
	var err = json.parse(content)
	if err != OK:
		print("chant.json parse error")
		return
	var recipe = json.get_data()
	_apply_recipe(recipe)
	# Clear the file after reading
	var clear = FileAccess.open(CHANT_FILE, FileAccess.WRITE)
	if clear:
		clear.store_string("{}")
		clear.close()

func _apply_recipe(recipe: Dictionary):
	print("Applying recipe: ", recipe)
	for dot in dots:
		var cce = dot_data[dot]["cce"]
		# Apply motion weight deltas
		if recipe.has("motion"):
			for key in recipe["motion"]:
				if cce["motion"].has(key):
					cce["motion"][key] = clamp(cce["motion"][key] + recipe["motion"][key], 0.0, 1.0)
		# Apply action weight deltas
		if recipe.has("action"):
			for key in recipe["action"]:
				if cce["action"].has(key):
					cce["action"][key] = clamp(cce["action"][key] + recipe["action"][key], 0.0, 1.0)
		# Apply dial deltas
		if recipe.has("dials"):
			for key in recipe["dials"]:
				if cce["dials"].has(key):
					cce["dials"][key] = clamp(cce["dials"][key] + recipe["dials"][key], 0.0, 1.0)

# --- In-game chant (local fallback while testing) ---

func _process_input(text: String):
	if USE_SERVER:
		_send_chant_to_server(text)
	else:
		_process_chant_locally(text)

func _send_chant_to_server(_text: String):
	pass

func _process_chant_locally(text: String):
	# Simple local recipes for testing without Claude bridge
	var lower = text.to_lower().strip_edges()
	var recipe = _local_recipe(lower)
	if recipe.is_empty():
		print("No local recipe for: ", text)
		return
	_apply_recipe(recipe)

func _local_recipe(word: String) -> Dictionary:
	match word:
		"wander", "explore", "roam":
			return { "motion": { "wander": CHANT_WEIGHT }, "dials": { "range": 0.05 } }
		"spiral":
			return { "dials": { "spiral": 0.1 } }
		"reproduce", "multiply", "sex", "breed":
			return { "action": { "reproduce": CHANT_WEIGHT } }
		"attack", "fight", "war":
			return { "action": { "attack": CHANT_WEIGHT }, "dials": { "intensity": 0.05 } }
		"defend", "protect", "guard":
			return { "action": { "defend": CHANT_WEIGHT } }
		"gather", "collect", "harvest":
			return { "action": { "gather": CHANT_WEIGHT } }
		"build", "construct":
			return { "action": { "build_upward": CHANT_WEIGHT } }
		"mark", "paint":
			return { "action": { "mark_surface": CHANT_WEIGHT } }
		"far", "farther", "distant":
			return { "dials": { "range": 0.1 } }
		"close", "near", "tight":
			return { "dials": { "range": -0.1 } }
		"fierce", "sharp", "strong":
			return { "dials": { "intensity": 0.1 } }
		"gentle", "soft", "slow":
			return { "dials": { "intensity": -0.1 } }
		_:
			return {}

# --- Per-dot CCE tick ---

func _tick_all_dots():
	for dot in dots:
		_tick_dot(dot)

func _tick_dot(dot: Node3D):
	var cce = dot_data[dot]["cce"]

	# Build weighted pool from motion + action
	var pool = {}
	for key in cce["motion"]:
		if cce["motion"][key] > 0.0:
			pool[key] = cce["motion"][key]
	for key in cce["action"]:
		if cce["action"][key] > 0.0:
			pool[key] = cce["action"][key]

	# If pool is empty dot idles
	if pool.is_empty():
		return

	# Weighted random selection
	var total = 0.0
	for key in pool:
		total += pool[key]
	var roll = randf() * total
	var chosen = ""
	var cumulative = 0.0
	for key in pool:
		cumulative += pool[key]
		if roll <= cumulative:
			chosen = key
			break

	if chosen == "":
		return

	_execute_primitive(dot, chosen, cce["dials"])

func _execute_primitive(dot: Node3D, primitive: String, dials: Dictionary):
	var range_val = dials.get("range", 0.5)
	var intensity = dials.get("intensity", 0.5)
	var spiral = dials.get("spiral", 0.0)

	match primitive:
		"wander":
			var nudge_amount = lerp(0.01, 0.08, range_val)
			var dir = dot.position.normalized()
			var tangent: Vector3
			if spiral > 0.1:
				# Spiral modifier — bias tangent direction consistently
				var up = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
				tangent = dir.cross(up).normalized()
				nudge_amount *= (1.0 + spiral)
			else:
				tangent = dir.cross(Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1))).normalized()
			var new_dir = (dir + tangent * nudge_amount).normalized()
			_place_dot_on_sphere(dot, new_dir)
		"reproduce":
			var chance = lerp(0.1, 0.9, intensity)
			if randf() < chance:
				_spawn_dot_near(dot)
		"defend":
			var dir = dot.position.normalized()
			var center = _colony_center()
			var toward = (center - dir).normalized()
			var new_dir = (dir + toward * 0.01).normalized()
			_place_dot_on_sphere(dot, new_dir)

func _colony_center() -> Vector3:
	var center = Vector3.ZERO
	for dot in dots:
		center += dot.position.normalized()
	if dots.size() > 0:
		center = (center / dots.size()).normalized()
	return center

# --- Camera ---

func _focus_on_colony():
	var center = _colony_center()
	orbit_yaw = atan2(center.x, center.z)
	orbit_pitch = asin(clamp(center.y, -1.0, 1.0))

func _update_camera():
	var pitch_clamped = clamp(orbit_pitch, -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
	var x = zoom_distance * cos(pitch_clamped) * sin(orbit_yaw)
	var y = zoom_distance * sin(pitch_clamped)
	var z = zoom_distance * cos(pitch_clamped) * cos(orbit_yaw)
	camera.position = Vector3(x, y, z)
	camera.look_at(Vector3.ZERO, Vector3.UP)

# --- Input ---

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

# --- Dot management ---

func _spawn_player_dot():
	var angle = randf() * TAU
	player_dot = _create_dot(Vector3(sin(angle), 0.0, cos(angle)), null)
	_focus_on_colony()

func _spawn_dot_near(parent: Node3D):
	if parent == null:
		return
	var dir = parent.position.normalized()
	var up = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var tangent = dir.cross(up).normalized()
	var bitangent = dir.cross(tangent).normalized()
	var angle = randf() * TAU
	var nudge = (tangent * cos(angle) + bitangent * sin(angle)) * 0.018
	var new_dir = (dir + nudge).normalized()
	_create_dot(new_dir, parent)
	_focus_on_colony()

func _create_dot(direction: Vector3, parent) -> Node3D:
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

	# Inherit parent CCE at dilution rate, or start neutral
	var cce = _deep_copy_cce(NEUTRAL_CCE)
	if parent != null and dot_data.has(parent):
		var parent_cce = dot_data[parent]["cce"]
		for layer in ["motion", "action"]:
			for key in cce[layer]:
				cce[layer][key] = parent_cce[layer][key] * CCE_DILUTION
		for key in cce["dials"]:
			cce["dials"][key] = parent_cce["dials"][key] * CCE_DILUTION

	dot_data[dot] = { "age": 0, "cce": cce }
	_place_dot_on_sphere(dot, direction)
	return dot

func _deep_copy_cce(source: Dictionary) -> Dictionary:
	var copy = {}
	for layer in source:
		if source[layer] is Dictionary:
			copy[layer] = {}
			for key in source[layer]:
				copy[layer][key] = source[layer][key]
		else:
			copy[layer] = source[layer]
	return copy

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

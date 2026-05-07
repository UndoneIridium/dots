extends Node3D

const SPHERE_RADIUS = 1.0
const ZOOM_MIN = 1.12
const ZOOM_MAX = 6.0
const ZOOM_SPEED = 0.08
const PINCH_SPEED = 0.004
const ZOOM_SMOOTH = 8.0
const ROTATE_SPEED = 0.005

const TICK_SPEED = 1.0
var tick_timer = 0.0

const USE_SERVER = false
const DOT_LIFETIME = 100
const CCE_DILUTION = 0.7
const CHANT_WEIGHT = 0.08
const CHANT_FILE = "res://chant.json"

# Combat
const COMBAT_TICKS = 3
var combat_clusters = []  # [{"pairs": [{"attacker": dot, "defender": dot}], "ticks_remaining": int}]
var combat_locked = {}    # dot -> true, skips primitive roll while in combat
var cluster_by_defender = {}  # defender dot -> cluster reference (O(1) lookup)

# Spatial grid
const GRID_RES = 200
const CELL_STEP = TAU / float(GRID_RES)  # one grid cell width in radians
var spatial_grid = {}  # cell_key (Vector2i) -> array of dots
var dot_cell = {}      # dot -> current cell_key, for incremental grid updates

# Attack
const ATTACK_DETECT_RADIUS = 10  # in grid cells

# Per-colony population cap (testing aid)
const MAX_POPULATION_PER_COLONY = 1000
var colony_counts = {}  # colony_id -> current dot count

# Tuning constants (formerly magic numbers)
const SPAWN_NUDGE = 0.018
const DEFEND_STEP = 0.01
const DOT_SURFACE_OFFSET = 0.0075
const PARALLEL_EPSILON = 0.0001
const MAX_CCE_FOR_SATURATION = 1.5

const NEUTRAL_CCE = {
	"motion": {
		"wander": 0.0,
		# "face_target": reserved \u2014 not yet wired
	},
	"action": {
		# Reserved primitives \u2014 not yet wired, kept for forward compatibility
		"mark_surface": 0.0,
		"build_upward": 0.0,
		"gather": 0.0,
		# Active primitives
		"defend": 0.0,
		"attack": 0.0,
		"reproduce": 0.0
	},
	"dials": {
		"range": 0.5,
		"intensity": 0.5,
		# "frequency", "affinity": reserved \u2014 not yet read by any primitive
		"spiral": 0.0
	}
}

const CCE_COLORS = {
	"wander": Color(1.0, 0.75, 0.1),
	"reproduce": Color(0.3, 0.9, 0.3),
	"defend": Color(0.2, 0.5, 1.0),
	"attack": Color(1.0, 0.2, 0.2),
}
const CCE_NEUTRAL_COLOR = Color(1.0, 1.0, 1.0)

# Active chant aliases. Dead primitives (gather/build/mark) intentionally absent
# until their execution paths exist.
const CHANT_RECIPES = {
	"wander":    { "motion": { "wander": CHANT_WEIGHT }, "dials": { "range": 0.05 } },
	"explore":   { "motion": { "wander": CHANT_WEIGHT }, "dials": { "range": 0.05 } },
	"roam":      { "motion": { "wander": CHANT_WEIGHT }, "dials": { "range": 0.05 } },
	"spiral":    { "dials": { "spiral": 0.1 } },
	"reproduce": { "action": { "reproduce": CHANT_WEIGHT } },
	"multiply":  { "action": { "reproduce": CHANT_WEIGHT } },
	"sex":       { "action": { "reproduce": CHANT_WEIGHT } },
	"breed":     { "action": { "reproduce": CHANT_WEIGHT } },
	"attack":    { "action": { "attack": CHANT_WEIGHT }, "dials": { "intensity": 0.05 } },
	"fight":     { "action": { "attack": CHANT_WEIGHT }, "dials": { "intensity": 0.05 } },
	"war":       { "action": { "attack": CHANT_WEIGHT }, "dials": { "intensity": 0.05 } },
	"defend":    { "action": { "defend": CHANT_WEIGHT } },
	"protect":   { "action": { "defend": CHANT_WEIGHT } },
	"guard":     { "action": { "defend": CHANT_WEIGHT } },
	"far":       { "dials": { "range": 0.1 } },
	"farther":   { "dials": { "range": 0.1 } },
	"distant":   { "dials": { "range": 0.1 } },
	"close":     { "dials": { "range": -0.1 } },
	"near":      { "dials": { "range": -0.1 } },
	"tight":     { "dials": { "range": -0.1 } },
	"fierce":    { "dials": { "intensity": 0.1 } },
	"sharp":     { "dials": { "intensity": 0.1 } },
	"strong":    { "dials": { "intensity": 0.1 } },
	"gentle":    { "dials": { "intensity": -0.1 } },
	"soft":      { "dials": { "intensity": -0.1 } },
	"slow":      { "dials": { "intensity": -0.1 } }
}

var dots = []
var dot_data = {}
# dot_data[dot] = {
#   "age": int,           # ticks lived, dies at DOT_LIFETIME
#   "colony": int,        # colony ID
#   "cce": { "motion": {...}, "action": {...}, "dials": {...} }
# }

var player_dot = null
const LOCAL_COLONY = 0
const ENEMY_COLONY = 1

var revealed_colonies = {LOCAL_COLONY: true}
var known_colonies = {LOCAL_COLONY: true}  # tracks all spawned colony IDs for fog early-exit
const FOG_COLOR = Color(0.25, 0.25, 0.25)
const FOG_EMISSION = Color(0.1, 0.1, 0.1)

const COLONY1_CCE = {
	"motion": {
		"wander": 0.40,
	},
	"action": {
		"mark_surface": 0.0,
		"build_upward": 0.0,
		"gather": 0.0,
		"defend": 0.0,
		"attack": 0.40,
		"reproduce": 0.32
	},
	"dials": {
		"range": 0.5,
		"intensity": 0.5,
		"spiral": 0.0
	}
}

const COLONY0_CCE = {
	"motion": {
		"wander": 0.40,
	},
	"action": {
		"mark_surface": 0.0,
		"build_upward": 0.0,
		"gather": 0.0,
		"defend": 0.0,
		"attack": 0.30,
		"reproduce": 0.32
	},
	"dials": {
		"range": 0.5,
		"intensity": 0.5,
		"spiral": 0.0
	}
}

@onready var camera = $Camera3D
@onready var chant_button = $UI/ChantButton
@onready var chant_modal = $UI/ChantModal
@onready var chant_input = $UI/ChantModal/VBox/ChantInput
@onready var confirm_button = $UI/ChantModal/VBox/ButtonRow/ConfirmButton
@onready var cancel_button = $UI/ChantModal/VBox/ButtonRow/CancelButton
@onready var dev_bar = $UI/DevBar
@onready var hud = $UI/HUD

var zoom_target = 3.0
var zoom_distance = 3.0
var orbit_yaw = 0.0
var orbit_pitch = 0.0
var is_orbiting = false
var touch_positions = {}
var pinch_last_distance = 0.0
var single_touch_active = false
var single_touch_index = -1

# Cached per-tick colony center (colony 0 only)
var _cached_colony_center = Vector3.ZERO

func _ready():
	_spawn_player_dot()
	_spawn_enemy_colony()
	_update_camera()
	_update_hud()
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
		# Spatial grid is now incrementally maintained \u2014 no rebuild needed
		_cached_colony_center = _compute_colony_center(LOCAL_COLONY)
		_check_fog_of_war()
		_tick_combat_clusters()
		_tick_all_dots()
		_update_hud()

# --- Chant file ---

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
	var clear = FileAccess.open(CHANT_FILE, FileAccess.WRITE)
	if clear:
		clear.store_string("{}")
		clear.close()

func _apply_recipe(recipe: Dictionary):
	print("Applying recipe: ", recipe)
	for dot in dots:
		if dot_data[dot]["colony"] != LOCAL_COLONY:
			continue
		var cce = dot_data[dot]["cce"]
		if recipe.has("motion"):
			for key in recipe["motion"]:
				if cce["motion"].has(key):
					cce["motion"][key] = clamp(cce["motion"][key] + recipe["motion"][key], 0.0, 1.0)
		if recipe.has("action"):
			for key in recipe["action"]:
				if cce["action"].has(key):
					cce["action"][key] = clamp(cce["action"][key] + recipe["action"][key], 0.0, 1.0)
		if recipe.has("dials"):
			for key in recipe["dials"]:
				if cce["dials"].has(key):
					cce["dials"][key] = clamp(cce["dials"][key] + recipe["dials"][key], 0.0, 1.0)
		_update_dot_color(dot)
	_update_hud()

func _update_hud():
	if dots.is_empty():
		hud.text = "dots: 0"
		return
	var totals = {}
	var count = 0
	for dot in dots:
		if dot_data[dot]["colony"] != LOCAL_COLONY:
			continue
		count += 1
		var cce = dot_data[dot]["cce"]
		for key in cce["motion"]:
			totals[key] = totals.get(key, 0.0) + cce["motion"][key]
		for key in cce["action"]:
			totals[key] = totals.get(key, 0.0) + cce["action"][key]
	if count == 0:
		hud.text = "p0: 0 (wiped out)"
		return
	var sorted_keys = totals.keys()
	sorted_keys.sort_custom(func(a, b): return totals[a] > totals[b])
	var p1_count = colony_counts.get(ENEMY_COLONY, 0)
	var lines = ["p0: %d   p1: %d" % [count, p1_count]]
	var shown = 0
	for key in sorted_keys:
		var avg = totals[key] / count
		if avg > 0.001:
			lines.append("%s  %.2f" % [key, avg])
			shown += 1
			if shown >= 3:
				break
	hud.text = "\n".join(lines)

# --- Chant input ---

func _process_input(text: String):
	if USE_SERVER:
		push_warning("USE_SERVER enabled but server is not implemented")
		_send_chant_to_server(text)
	else:
		_process_chant_locally(text)

func _send_chant_to_server(_text: String):
	pass

func _process_chant_locally(text: String):
	var lower = text.to_lower().strip_edges()
	if not CHANT_RECIPES.has(lower):
		print("No local recipe for: ", text)
		return
	_apply_recipe(CHANT_RECIPES[lower])

# --- Per-dot CCE tick ---

func _tick_all_dots():
	for dot in dots:
		if combat_locked.has(dot):
			continue
		_tick_dot(dot)

func _tick_dot(dot: Node3D):
	var cce = dot_data[dot]["cce"]
	var pool = {}
	for key in cce["motion"]:
		if cce["motion"][key] > 0.0:
			pool[key] = cce["motion"][key]
	for key in cce["action"]:
		if cce["action"][key] > 0.0:
			pool[key] = cce["action"][key]
	if pool.is_empty():
		return
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
				var up = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
				tangent = dir.cross(up).normalized()
				nudge_amount *= (1.0 + spiral)
			else:
				tangent = dir.cross(Vector3(randf_range(-1,1), randf_range(-1,1), randf_range(-1,1))).normalized()
			var new_dir = (dir + tangent * nudge_amount).normalized()
			_place_dot_on_sphere(dot, new_dir, true)
		"reproduce":
			var chance = lerp(0.1, 0.9, intensity)
			if randf() < chance:
				_spawn_dot_near(dot, dot_data[dot]["colony"])
		"attack":
			_execute_attack(dot, intensity)
		"defend":
			var dir = dot.position.normalized()
			var toward = (_cached_colony_center - dir).normalized()
			var new_dir = (dir + toward * DEFEND_STEP).normalized()
			_place_dot_on_sphere(dot, new_dir, true)
		# gather, build_upward, mark_surface, face_target: reserved \u2014 no-op

func _execute_attack(dot: Node3D, intensity: float):
	var my_colony = dot_data[dot]["colony"]
	var my_dir = dot.position.normalized()
	var target = _find_nearest_foreign_in_radius(my_dir, my_colony, ATTACK_DETECT_RADIUS)
	if target == null:
		return
	if combat_locked.has(dot) or combat_locked.has(target):
		return
	var foreign_nearby = _get_foreign_dots_near(my_dir, my_colony)
	if target in foreign_nearby:
		_initiate_combat(dot, target, intensity)
	else:
		_march_toward(dot, my_dir, target, my_colony)

func _initiate_combat(attacker: Node3D, defender: Node3D, intensity: float):
	combat_locked[attacker] = true
	combat_locked[defender] = true
	var ticks = COMBAT_TICKS - (1 if intensity > 0.7 else 0)
	# O(1) lookup: does this defender already have a cluster?
	if cluster_by_defender.has(defender):
		var cluster = cluster_by_defender[defender]
		cluster["pairs"].append({"attacker": attacker, "defender": defender})
	else:
		var cluster = {"pairs": [{"attacker": attacker, "defender": defender}], "ticks_remaining": ticks}
		combat_clusters.append(cluster)
		cluster_by_defender[defender] = cluster

func _march_toward(dot: Node3D, my_dir: Vector3, target: Node3D, my_colony: int):
	var target_dir = target.position.normalized()
	var toward = target_dir - my_dir
	if toward.length_squared() < PARALLEL_EPSILON:
		return
	toward = toward.normalized()
	var tangent = my_dir.cross(toward)
	if tangent.length_squared() < PARALLEL_EPSILON:
		return
	tangent = tangent.cross(my_dir).normalized()
	var new_dir = (my_dir + tangent * CELL_STEP).normalized()
	if not _is_foreign_in_exact_cell(new_dir, my_colony):
		_place_dot_on_sphere(dot, new_dir)

# --- Combat ---

func _tick_combat_clusters():
	var to_remove_clusters = []
	var to_delete = {}
	var to_advance = []
	for cluster in combat_clusters:
		cluster["ticks_remaining"] -= 1
		if cluster["ticks_remaining"] <= 0:
			# Track which defenders already have a winning attacker claiming their cell
			var cell_claimed_by = {}
			for pair in cluster["pairs"]:
				var attacker = pair["attacker"]
				var defender = pair["defender"]
				# dot_data.has() is sufficient \u2014 _remove_dot erases it before queue_free
				if not dot_data.has(attacker) or not dot_data.has(defender):
					continue
				if to_delete.has(attacker) or to_delete.has(defender):
					continue
				var a_power = dot_data[attacker]["cce"]["action"].get("attack", 0.0) + dot_data[attacker]["cce"]["action"].get("defend", 0.0)
				var d_power = dot_data[defender]["cce"]["action"].get("attack", 0.0) + dot_data[defender]["cce"]["action"].get("defend", 0.0)
				if a_power >= d_power:
					to_delete[defender] = true
					# First winning attacker against this defender claims the cell
					if not cell_claimed_by.has(defender):
						cell_claimed_by[defender] = attacker
						to_advance.append({"winner": attacker, "target_dir": defender.position.normalized()})
				else:
					to_delete[attacker] = true
			for pair in cluster["pairs"]:
				combat_locked.erase(pair["attacker"])
				combat_locked.erase(pair["defender"])
				cluster_by_defender.erase(pair["defender"])
			to_remove_clusters.append(cluster)
	for cluster in to_remove_clusters:
		combat_clusters.erase(cluster)
	for dot in to_delete:
		_remove_dot(dot)
	# Advance winners into vacated cells
	for adv in to_advance:
		var winner = adv["winner"]
		if dot_data.has(winner):
			_place_dot_on_sphere(winner, adv["target_dir"])

func _remove_dot(dot: Node3D):
	if not dot_data.has(dot):
		return
	# Incrementally remove from spatial grid
	if dot_cell.has(dot):
		var key = dot_cell[dot]
		if spatial_grid.has(key):
			spatial_grid[key].erase(dot)
			if spatial_grid[key].is_empty():
				spatial_grid.erase(key)
		dot_cell.erase(dot)
	# Resolve combat clusters this dot was in
	var to_remove_clusters = []
	for cluster in combat_clusters:
		var involved = false
		for pair in cluster["pairs"]:
			if pair["attacker"] == dot or pair["defender"] == dot:
				involved = true
				var survivor = pair["defender"] if pair["attacker"] == dot else pair["attacker"]
				combat_locked.erase(survivor)
		if involved:
			var still_active = false
			for pair in cluster["pairs"]:
				if pair["attacker"] != dot and pair["defender"] != dot:
					if dot_data.has(pair["attacker"]) and dot_data.has(pair["defender"]):
						still_active = true
						break
			if not still_active:
				# Clean up index for any defenders in this cluster
				for pair in cluster["pairs"]:
					if cluster_by_defender.get(pair["defender"]) == cluster:
						cluster_by_defender.erase(pair["defender"])
				to_remove_clusters.append(cluster)
	for cluster in to_remove_clusters:
		combat_clusters.erase(cluster)
	dots.erase(dot)
	var removed_colony = dot_data[dot]["colony"]
	colony_counts[removed_colony] = max(0, colony_counts.get(removed_colony, 0) - 1)
	dot_data.erase(dot)
	combat_locked.erase(dot)
	if dot == player_dot:
		player_dot = dots[0] if dots.size() > 0 else null
	dot.queue_free()

# --- Color ---

func _update_dot_color(dot: Node3D):
	var colony = dot_data[dot]["colony"]
	var mat = dot.material_override as StandardMaterial3D
	if not mat:
		return
	if not revealed_colonies.get(colony, false):
		mat.albedo_color = FOG_COLOR
		mat.emission = FOG_EMISSION
		return
	var cce = dot_data[dot]["cce"]
	var total = 0.0
	var weighted = Color(0, 0, 0, 0)
	for key in CCE_COLORS:
		var weight = 0.0
		if cce["motion"].has(key):
			weight = cce["motion"][key]
		elif cce["action"].has(key):
			weight = cce["action"][key]
		if weight > 0.0:
			weighted.r += CCE_COLORS[key].r * weight
			weighted.g += CCE_COLORS[key].g * weight
			weighted.b += CCE_COLORS[key].b * weight
			total += weight
	var saturation = clamp(total / MAX_CCE_FOR_SATURATION, 0.0, 1.0)
	var hue_color = CCE_NEUTRAL_COLOR
	if total > 0.0:
		hue_color = Color(weighted.r / total, weighted.g / total, weighted.b / total)
	var color = CCE_NEUTRAL_COLOR.lerp(hue_color, saturation)
	mat.albedo_color = color
	mat.emission = color

func _update_all_dot_colors():
	for dot in dots:
		_update_dot_color(dot)

func _compute_colony_center(colony: int) -> Vector3:
	var center = Vector3.ZERO
	var count = 0
	for dot in dots:
		if dot_data[dot]["colony"] == colony:
			center += dot.position.normalized()
			count += 1
	if count > 0:
		return (center / count).normalized()
	return Vector3.ZERO

# --- Fog of war ---

func _check_fog_of_war():
	# Cheap early exit: known set size matches revealed set size
	if revealed_colonies.size() >= known_colonies.size():
		return
	# TESTING: keep ENEMY_COLONY perpetually fogged for visual contrast
	return
	for dot in dots:
		var colony = dot_data[dot]["colony"]
		if colony == LOCAL_COLONY or revealed_colonies.get(colony, false):
			continue
		var key = _cell_key(dot.position.normalized())
		for du in [-1, 0, 1]:
			for dv in [-1, 0, 1]:
				var neighbor = Vector2i((key.x + du) % GRID_RES, (key.y + dv) % GRID_RES)
				if spatial_grid.has(neighbor):
					for occupant in spatial_grid[neighbor]:
						if dot_data.has(occupant) and dot_data[occupant]["colony"] == LOCAL_COLONY:
							revealed_colonies[colony] = true
							print("Colony %d revealed!" % colony)
							_update_all_dot_colors()
							return

# --- Spatial grid (incrementally maintained) ---

func _cell_key(dir: Vector3) -> Vector2i:
	var d = dir.normalized()
	var u = int((atan2(d.x, d.z) / TAU + 0.5) * GRID_RES) % GRID_RES
	var v = int((asin(clamp(d.y, -1.0, 1.0)) / PI + 0.5) * GRID_RES) % GRID_RES
	return Vector2i(u, v)

func _grid_insert(dot: Node3D, key: Vector2i):
	if not spatial_grid.has(key):
		spatial_grid[key] = []
	spatial_grid[key].append(dot)
	dot_cell[dot] = key

func _grid_update_position(dot: Node3D):
	# Called after a dot moves \u2014 rehomes it in the grid if its cell changed
	var new_key = _cell_key(dot.position.normalized())
	var old_key = dot_cell.get(dot, null)
	if old_key == new_key:
		return
	if old_key != null and spatial_grid.has(old_key):
		spatial_grid[old_key].erase(dot)
		if spatial_grid[old_key].is_empty():
			spatial_grid.erase(old_key)
	_grid_insert(dot, new_key)

func _is_cell_occupied(dir: Vector3) -> bool:
	var key = _cell_key(dir)
	return spatial_grid.has(key) and spatial_grid[key].size() > 0

func _is_foreign_in_exact_cell(dir: Vector3, my_colony: int) -> bool:
	var key = _cell_key(dir)
	if not spatial_grid.has(key):
		return false
	for occupant in spatial_grid[key]:
		if dot_data.has(occupant) and dot_data[occupant]["colony"] != my_colony:
			return true
	return false

func _is_blocked_by_foreign(dir: Vector3, my_colony: int) -> bool:
	var key = _cell_key(dir)
	for du in [-1, 0, 1]:
		for dv in [-1, 0, 1]:
			var neighbor = Vector2i((key.x + du) % GRID_RES, (key.y + dv) % GRID_RES)
			if spatial_grid.has(neighbor):
				for occupant in spatial_grid[neighbor]:
					if dot_data.has(occupant) and dot_data[occupant]["colony"] != my_colony:
						return true
	return false

func _find_nearest_foreign_in_radius(dir: Vector3, my_colony: int, radius: int):
	var key = _cell_key(dir)
	var best = null
	var best_dist = INF
	for du in range(-radius, radius + 1):
		for dv in range(-radius, radius + 1):
			var neighbor = Vector2i((key.x + du) % GRID_RES, (key.y + dv) % GRID_RES)
			if spatial_grid.has(neighbor):
				for occupant in spatial_grid[neighbor]:
					if dot_data.has(occupant) and dot_data[occupant]["colony"] != my_colony:
						var occ_key = dot_cell.get(occupant, _cell_key(occupant.position.normalized()))
						var d = float((key - occ_key).length_squared())
						if d < best_dist:
							best_dist = d
							best = occupant
	return best

func _get_foreign_dots_near(dir: Vector3, my_colony: int) -> Array:
	var result = []
	var key = _cell_key(dir)
	for du in [-1, 0, 1]:
		for dv in [-1, 0, 1]:
			var neighbor = Vector2i((key.x + du) % GRID_RES, (key.y + dv) % GRID_RES)
			if spatial_grid.has(neighbor):
				for occupant in spatial_grid[neighbor]:
					if dot_data.has(occupant) and dot_data[occupant]["colony"] != my_colony:
						result.append(occupant)
	return result

# --- Dot management ---

func _age_dots():
	var to_remove = []
	for dot in dots:
		dot_data[dot]["age"] += 1
		if dot_data[dot]["age"] >= DOT_LIFETIME:
			to_remove.append(dot)
	for dot in to_remove:
		_remove_dot(dot)

func _spawn_player_dot():
	var angle = randf() * TAU
	player_dot = _create_dot(Vector3(sin(angle), 0.0, cos(angle)), null, LOCAL_COLONY, COLONY0_CCE)
	_focus_on_colony()

func _spawn_enemy_colony():
	var player_dir = player_dot.position.normalized()
	var up = Vector3.UP if abs(player_dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var perp = player_dir.cross(up).normalized()
	var enemy_dir = (player_dir * cos(PI / 4.0) + perp * sin(PI / 4.0)).normalized()
	known_colonies[ENEMY_COLONY] = true
	_create_dot(enemy_dir, null, ENEMY_COLONY, COLONY1_CCE)

func _spawn_dot_near(parent: Node3D, colony: int = LOCAL_COLONY):
	if parent == null:
		return
	if colony_counts.get(colony, 0) >= MAX_POPULATION_PER_COLONY:
		return
	var dir = parent.position.normalized()
	var up = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var tangent = dir.cross(up).normalized()
	var bitangent = dir.cross(tangent).normalized()
	var angle = randf() * TAU
	var nudge = (tangent * cos(angle) + bitangent * sin(angle)) * SPAWN_NUDGE
	var new_dir = (dir + nudge).normalized()
	if not _is_cell_occupied(new_dir) and not _is_blocked_by_foreign(new_dir, colony):
		_create_dot(new_dir, parent, colony, {}, true)

func _create_dot(direction: Vector3, parent, colony: int = LOCAL_COLONY, preset_cce: Dictionary = {}, full_inheritance: bool = false) -> Node3D:
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

	var cce = _deep_copy_cce(NEUTRAL_CCE)
	if not preset_cce.is_empty():
		cce = _deep_copy_cce(preset_cce)
	elif parent != null and dot_data.has(parent):
		var parent_cce = dot_data[parent]["cce"]
		var dilution = 1.0 if full_inheritance else CCE_DILUTION
		for layer in ["motion", "action"]:
			for key in cce[layer]:
				if parent_cce[layer].has(key):
					cce[layer][key] = parent_cce[layer][key] * dilution
		for key in cce["dials"]:
			if parent_cce["dials"].has(key):
				cce["dials"][key] = parent_cce["dials"][key] * dilution

	dot_data[dot] = { "age": 0, "cce": cce, "colony": colony }
	known_colonies[colony] = true
	colony_counts[colony] = colony_counts.get(colony, 0) + 1
	_place_dot_on_sphere(dot, direction)
	# Insert into spatial grid (initial placement)
	_grid_insert(dot, _cell_key(dot.position.normalized()))
	_update_dot_color(dot)
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

# --- Camera ---

func _focus_on_colony():
	var center = _compute_colony_center(LOCAL_COLONY)
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

func _place_dot_on_sphere(dot: Node3D, direction: Vector3, check_foreign: bool = false) -> bool:
	if check_foreign:
		var my_colony = dot_data[dot]["colony"]
		if _is_blocked_by_foreign(direction, my_colony):
			return false
	var dir = direction.normalized()
	dot.position = dir * (SPHERE_RADIUS + DOT_SURFACE_OFFSET)
	var new_basis = Basis()
	new_basis.y = dir
	new_basis.x = new_basis.y.cross(Vector3.FORWARD if abs(dir.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT).normalized()
	new_basis.z = new_basis.x.cross(new_basis.y).normalized()
	dot.transform.basis = new_basis
	# Update spatial grid for the new position (only if dot is fully registered)
	if dot_data.has(dot) and dot_cell.has(dot):
		_grid_update_position(dot)
	return true

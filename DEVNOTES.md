# Noema — Dev Notes
	
	## Project Overview
	Godot 4 mobile game (landscape, iOS/Android). Single shared persistent sphere world where players influence colonies of dots via natural language chants. No direct control — chants accumulate as CCE (Cumulative Chant Exposure) which drives probabilistic dot behavior.
	
	Design bible: `Noema_Design_Bible_v0.4.docx` in repo root.
	
	---
	
	## Architecture
	
	### Client (Godot 4)
	- Single scene: `main.tscn` / `main.gd`
	- Mobile renderer, 1920x1080 landscape
	- USE_SERVER = false (local prototype mode)
	- When USE_SERVER = true, chants route to server via HTTP (not yet implemented)
	
	### Scene Structure
	- Node3D (Main) — main.gd attached
	  - WorldSphere (MeshInstance3D) — white sphere, radius 1.0
	  - SphereBody (StaticBody3D + CollisionShape) — collision for sphere surface
	  - Camera3D — orbital, driven by yaw/pitch angles
	  - DirectionalLight3D — soft (energy 0.3), shadows on
	  - WorldEnvironment — ambient light 0.85 to lift dark side
	  - UI (CanvasLayer)
	    - ChantButton — bottom center, opens modal
	    - ChantModal — center screen text input (Panel > VBox > LineEdit + buttons)
	    - DevBar (LineEdit) — always-visible bottom bar for dev chanting, Enter to submit
	
	---
	
	## CCE System
	
	### Dot Data Structure
	```
	dot_data[dot] = {
	  "age": int,           # ticks lived, dies at DOT_LIFETIME (100)
	  "cce": {
	    "motion": { "wander": float, "face_target": float },
	    "action": { "mark_surface": float, "build_upward": float, "gather": float,
	                "defend": float, "attack": float, "reproduce": float },
	    "dials":  { "range": float, "intensity": float, "frequency": float,
	                "affinity": float, "spiral": float }
	  }
	}
	```
	
	### Key Constants
	- DOT_LIFETIME = 100 ticks
	- TICK_SPEED = 5.0 seconds (active play rate — passive tick rate not yet implemented)
	- CCE_DILUTION = 0.7 (children inherit 70% of parent CCE)
	- CHANT_WEIGHT = 0.08 (weight delta per chant)
	- DIAL_BASELINE: range 0.5, intensity 0.5, frequency 1.0, affinity 0.0, spiral 0.0
	
	### Per-Tick Dot Behavior
	Each tick every dot:
	1. Builds a weighted pool from motion + action CCE weights
	2. Picks ONE primitive by weighted random roll
	3. Executes that primitive with dial modifiers applied
	4. Dies if age >= DOT_LIFETIME
	
	### Active Primitives (wired)
	- wander — random surface nudge, range dial controls distance, spiral dial biases direction
	- reproduce — probabilistic spawn adjacent dot, intensity dial controls chance
	- defend — moves toward colony center
	
	### Inactive Primitives (CCE accumulates, no execution yet)
	- attack — needs foreign dot detection
	- gather — needs resource system
	- build_upward — needs surface marking system
	- mark_surface — needs surface marking system
	- face_target — needs target system
	
	### Dial Notes
	- spiral is a wander modifier (not a standalone primitive) — high spiral makes wander orbit consistently
	- range: 0=tiny nudge, 1=large movement
	- intensity: 0=low effect, 1=high effect (e.g. reproduce chance lerps 0.1-0.9)
	
	---
	
	## CCE Color System
	Dot color reflects dominant CCE weights (blended proportionally):
	- wander → amber (1.0, 0.75, 0.1)
	- reproduce → green (0.3, 0.9, 0.3)
	- defend → blue (0.2, 0.5, 1.0)
	- attack → red (1.0, 0.2, 0.2)
	- neutral → white
	
	Children born with inherited CCE color already applied.
	Foreign dots in bleed range: visual system stubbed, not yet implemented.
	
	---
	
	## Claude Chant Bridge
	For testing LLM-style chant interpretation without a server:
	- Game polls `res://chant.json` each tick
	- Claude writes a CCE recipe JSON to that file via MCP
	- Game applies recipe, clears file
	- `chant.json` is gitignored (live file)
	
	Recipe format:
	```json
	{
	  "motion": { "wander": 0.1 },
	  "action": { "reproduce": 0.08 },
	  "dials": { "range": 0.1, "intensity": 0.05, "frequency": 0.0, "affinity": 0.0 }
	}
	```
	
	In-game DevBar uses local recipe dict as fallback (single words only).
	
	---
	
	## Local Recipe Dict (current trigger words)
	- wander/explore/roam → wander + range +0.05
	- spiral → spiral dial +0.1
	- reproduce/multiply/sex/breed → reproduce
	- attack/fight/war → attack + intensity +0.05
	- defend/protect/guard → defend
	- gather/collect/harvest → gather
	- build/construct → build_upward
	- mark/paint → mark_surface
	- far/farther/distant → range +0.1
	- close/near/tight → range -0.1
	- fierce/sharp/strong → intensity +0.1
	- gentle/soft/slow → intensity -0.1
	
	---
	
	## Camera
	- Orbital: yaw/pitch angles, always looks at Vector3.ZERO
	- RMB drag (desktop) / single finger drag (mobile) to orbit
	- Scroll wheel (desktop) / pinch (mobile) to zoom
	- Zoom: MIN 1.12 (just above surface), MAX 6.0
	- Smooth lerp zoom via zoom_target / zoom_distance split
	- Touch positions tracked manually in Dictionary (Godot 4 — no Input.get_touch_position)
	- Focus on colony runs once at startup only — camera does not reset during play
	
	---
	
	## Git / Deployment
	- Repo: https://github.com/UndoneIridium/dots
	- Commits via OS.execute git through Godot MCP (godot-mcp-pro)
	- Repo creation via gh CLI: /opt/homebrew/bin/gh
	- Node.js at /opt/homebrew/bin/node (used for docx generation only, not in game)
	- npm docx package installed temporarily for bible generation, then removed
	
	---
	
	## Known Issues / TODO
	- Passive tick rate not implemented (server-side concern)
	- CCE blending between colonies not implemented (needs foreign dot detection)
	- attack/gather/build/mark_surface primitives silently do nothing
	- No resource system
	- No surface marking system
	- No multiplayer / server layer
	- Foreign dot rendering stubbed but not wired
	- Population cap not implemented (reproduce will grow unbounded)

---

## Session Notes — 2026-05-06

### HUD
- Added `UI/HUD` Label node (top-left, always visible)
- Shows dot count and top 3 dominant CCE behaviors averaged across all dots
- Updates on chant apply and once at startup

### Spatial Grid (foreign dot exclusion)
- `spatial_grid`: Dictionary mapping `Vector2i` cell keys → `Array` of dots
- `GRID_RES = 200` (cells per axis, tunable)
- `_cell_key(dir)` quantizes a sphere direction to a grid coordinate
- `_rebuild_spatial_grid()` called once per tick after aging
- `_is_blocked_by_foreign(dir, colony)` — blocks movement/spawn into cells occupied by a different colony
- `_get_foreign_dots_near(dir, colony)` — returns all foreign dots in cell + 8 neighbors (ready for combat)
- `_is_cell_occupied(dir)` — checks exact cell only; blocks same-colony spawn stacking
- Spawn now requires target cell to be empty (any colony) — prevents FPS tank from dot stacking
- Naturally caps reproduce-heavy colonies at area saturation; must wander to expand
- Scales well for client-side prototype; server will own territory logic at scale

### Colony 1 (enemy test colony)
- Spawns 45° from colony 0 on the equator
- Preset CCE: attack 0.40, wander 0.40, reproduce 0.32
- `ENEMY_COLONY = 1` constant; colony ID stored in `dot_data[dot]["colony"]`
- Children inherit full CCE (no dilution) for testing — revert via `CCE_DILUTION` flag when ready
- `_create_dot()` now accepts `colony` and `preset_cce` params

### Fog of War
- Foreign colonies render as dim grey (0.25, 0.25, 0.25) until contact with colony 0
- `revealed_colonies` dictionary; colony 0 always revealed
- `_check_fog_of_war()` runs each tick after grid rebuild
- On first contact, colony is permanently revealed and all dot colors update
- Per-colony revelation (not per-dot)

### CCE Color Magnitude
- Color now lerps from white toward hue based on total CCE weight sum
- `MAX_CCE_FOR_SATURATION = 1.5` — dots with low total CCE appear washed out
- Diluted children correctly appear less saturated than parents

### Combat Design (decided, not yet implemented)
- Probabilistic: attacker rolls `attack` primitive, finds foreign dot via grid
- Combat power = attack CCE + defend CCE for each dot
- Higher total wins; ties go to attacker
- Both dots deleted if mutual attack resolves same tick (MAD)
- Pending deletions list processed after all primitives resolve
- attack primitive still a no-op pending implementation

### Known Issues / TODO
- Passive tick rate not implemented (server-side concern)
- attack/gather/build/mark_surface primitives silently do nothing (combat designed, not wired)
- No resource system
- No surface marking system
- No multiplayer / server layer
- CCE dilution disabled for ENEMY_COLONY (testing only — re-enable when tuning)
- HUD shows combined CCE across all colonies — should separate per-colony
	

---

## Session Notes — 2026-05-06 (cont.)

### Combat System (implemented)
- `COMBAT_TICKS = 3` — combat resolves after 3 ticks; intensity > 0.7 shortens to 2
- `combat_clusters` array — each entry: `{pairs: [{attacker, defender}], ticks_remaining}`
- `combat_locked` dict — dots in combat skip their primitive roll
- Attack primitive now a deliberate march: detects enemies within `ATTACK_DETECT_RADIUS = 10` cells, steps one cell per tick toward nearest, locks on contact
- `CELL_STEP` constant defines one grid-cell march distance
- March uses `_is_foreign_in_exact_cell` (exact cell only) so attacker advances right to the line
- Wander/defend still use full 8-neighbor `_is_blocked_by_foreign` for separation
- Cluster timer shared — multiple attackers can pile onto one defender, all resolve together
- Attacker wins ties; both deleted on mutual combat (MAD)
- `_remove_dot()` now cleans up combat clusters immediately when a dot is removed mid-combat — prevents zombie locked dots
- `_apply_recipe()` now filters to LOCAL_COLONY only — chants no longer affect enemy colony
- TICK_SPEED reduced to 1.0 for testing (was 5.0)
- `_is_foreign_in_exact_cell(dir, colony)` added — exact cell foreign check for march logic

### Known Issues / TODO
- Passive tick rate not implemented (server-side concern)
- gather/build/mark_surface primitives silently do nothing
- No resource system
- No surface marking system
- No multiplayer / server layer
- CCE dilution disabled for ENEMY_COLONY (testing only)
- HUD shows combined CCE across all colonies — should separate per-colony
- Client FPS tanks at ~8k dots — expected, server will own simulation at scale

---

## Session Notes — 2026-05-07

### Code Audit Pass
- Removed `face_target` from NEUTRAL_CCE (no execution path)
- Removed `frequency`, `affinity` dials (unused)
- Removed `DIAL_BASELINE` (unused)
- Promoted magic numbers to constants: `SPAWN_NUDGE`, `DEFEND_STEP`, `DOT_SURFACE_OFFSET`, `PARALLEL_EPSILON`, `MAX_CCE_FOR_SATURATION`
- `_local_recipe()` match statement → `CHANT_RECIPES` data-driven dict
- Reserved primitives (gather/build/mark) intentionally absent from chant aliases until execution paths exist
- `USE_SERVER` now `push_warning`s if accidentally enabled
- Stale `is_instance_valid` checks removed from grid lookups (now relying solely on `dot_data.has`, since `_remove_dot` is synchronous)
- `_apply_recipe` and `_update_hud` consolidated single-pass
- `_create_dot` parent CCE inheritance guards against missing keys (forward-compat for differently-shaped colony presets)

### Combat Cluster Index
- `cluster_by_defender = {}` provides O(1) lookup of "is this defender already in a cluster?"
- `_initiate_combat` uses index instead of nested O(n×m) scan over all clusters
- Index maintained on cluster create, append, resolution, and dot removal

### Incremental Spatial Grid
- `dot_cell = {}` tracks each dot's current cell key
- `_grid_insert(dot, key)` and `_grid_update_position(dot)` helpers
- `_place_dot_on_sphere` calls `_grid_update_position` after every move
- `_create_dot` inserts on creation, `_remove_dot` removes on death
- Per-tick `_rebuild_spatial_grid` call eliminated
- Big per-tick performance win at high dot counts

### Colony Population Tracking
- `colony_counts = {}` — colony_id → live dot count
- Maintained on `_create_dot` and `_remove_dot`
- `MAX_POPULATION_PER_COLONY = 1000` testing aid; `_spawn_dot_near` rejects if at cap
- HUD shows both p0 and p1 counts; updates every tick now (was chant-apply only)

### Fog of War (testing override)
- `_check_fog_of_war` short-circuits with `return` after the early-exit so ENEMY_COLONY stays grey for visual contrast during testing
- Remove the bare `return` to restore normal reveal-on-contact behavior

### Colony 0 Preset
- `COLONY0_CCE` constant added: wander 0.40, attack 0.30, reproduce 0.32 (vs. p1's 0.40/0.40/0.32)
- All p0 spawns use `full_inheritance: true` for stable testing
- `_spawn_player_dot` seeds with the preset

### Combat Resolution: Winner Advances
- When attacker wins, advances into defender's vacated cell after `_remove_dot` clears the spatial grid entry
- Multi-attacker case: first winner against a given defender claims the cell; others stay put (free to march toward new targets next tick)
- Implemented via `cell_claimed_by` per cluster + `to_advance` resolved after deletions

### Observations from Testing
- p1 with split CCE (wander 0.40 / attack 0.40) drifts uncommitted dots away from front during long runs
- With 1000-cap, p1 starves the front line as wandering dots can't be replaced by reproduction
- Without cap, p1 reproduction would replenish — but front line cohesion is still a real design issue worth thinking about (e.g. needing a "march toward enemy" or rallying behavior beyond detection radius)
- Combat math otherwise validates: p1's higher attack consistently wins individual engagements; observable issue is throughput/cohesion not correctness

### Known Issues / TODO
- gather/build/mark_surface primitives silently do nothing
- No resource system / surface marking system
- No multiplayer / server layer
- CCE dilution disabled for both colonies during testing (full_inheritance for both)
- p1 keeps using fog color even after contact (testing override — easy revert)
- Combat lock burden + wander competition causes aggressive colonies to lose front-line cohesion over long runs (design observation, not bug)
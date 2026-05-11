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


---

## Session Notes — 2026-05-09

### Rally Banners (combat cohesion fix)
- `RALLY_RADIUS = 30` cells, `BANNER_TTL = 6` ticks
- `banners` array: `{cell, colony, ticks_remaining}` — no visual, pure data
- Dropped on `_initiate_combat` for BOTH attacker and defender colonies at the contact cell
- Refresh-on-redrop semantics: existing banner at same cell+colony has TTL refreshed instead of duplicated
- Friendly-only pull: when a dot rolls `attack` and finds no foreign in `ATTACK_DETECT_RADIUS`, falls back to `_march_toward_banner` which targets nearest same-colony banner within `RALLY_RADIUS`
- Banner cell→sphere direction conversion via `_cell_to_dir` (inverse of `_cell_key`)
- `_torus_cell_dist_sq` helper for wrap-around grid distance
- `_march_toward` refactored to share tangent-step math with banner march via `_march_toward_dir`
- Validated by long-run match: p1 (0.40 attack) cleanly encircled and wiped p0 (0.30 attack) — the cohesion fix lets attacker CCE concentrate at the front rather than diffusing into wandering

### Walls / Blocks (Step 1 of defense system)
- "Block" is the user-facing term; `is_wall` flag and `wall_*` names retained for code load-bearing
- `WALL_DEFEND_VALUE = 0.5`, `WALL_DECAY_TICKS = 300`, `WALL_MESH_SIZE = (0.015, 0.003, 0.015)` (half a dot's height), `WALL_HEIGHT_STEP = 0.003`
- `wall_counts` dict tracks per-colony wall count separately from `colony_counts` (walls don't count toward population)
- `_create_wall(cell, colony)` creates a wall as a special dot: `is_wall: true`, immobile, no primitive ticking, separate decay counter, defend = 0.5
- Walls live in spatial_grid like normal dots; a wall cell appears occupied so dots can't move/spawn into it
- Wall-aware combat resolution: when an attacker beats a wall, the wall is removed but the attacker only advances if the cell becomes empty (i.e., the stack is exhausted)
- `_age_dots` branches on `is_wall`: walls decrement decay counter, dots increment age
- HUD now shows wall count: `p0: N (walls: M)   p1: K`
- `build_upward` added to `CCE_COLORS` (gray-purple)
- Enemy colony spawn commented out for build dev work (single-colony test environment)

### Build Banner Mechanic (block clustering / monuments)
- `BUILD_BANNER_RADIUS = 15`, `BUILD_BANNER_TTL = 6`, `BUILD_START_CHANCE = 0.05`, `BUILD_AT_BANNER_STACK_PREF = 0.8`
- `build_banners` array with unique IDs (separate from rally `banners`)
- Per-dot `build_banners_used` set tracks which banners a dot has already contributed to
- `_execute_build` flow:
  - Look for nearest unused build banner in radius
  - If found and at/adjacent: build in own cell, refresh banner, mark used
  - If found but not adjacent: march toward banner, no build this tick
  - If none found: 5% chance to start new monument (place block in own cell, drop banner, founder marks it used)
- Build always places in dot's own cell — no 8-neighbor scattering, builders that walked to the banner cluster their blocks at that cell
- Stack height: `_create_wall` counts existing same-colony walls in target cell to determine `stack_index`, places new wall at `radius + offset + stack_index * WALL_HEIGHT_STEP` along surface normal
- Active monuments don't crumble: when a new wall is added to a stack, all existing walls in the cell have their decay timer refreshed. Abandoned stacks decay top-down naturally.
- Founder placement defaults to own cell (changed from "any empty adjacent")

### Combat Mechanics Summary (current state)
Each tick, every dot rolls one primitive from its CCE pool weighted by current values. Rolling `attack` searches a 10-cell radius for any foreign dot, marches toward the nearest one if found (or marches toward the nearest friendly rally banner within 30 cells if not), and initiates combat on contact, which drops a 6-tick rally banner at the contact cell for both colonies and locks the attacker and defender in a 3-tick combat cluster (2 ticks if attacker intensity > 0.7). When the cluster expires, each pair compares `attack + defend` power deterministically with ties going to the attacker — the loser dies, the winner advances into the vacated cell unless the cell still contains other entities (e.g. remaining walls in a stack). Pile-ons against a single defender all resolve against that one defender's power.

In actual play, chants don't reshape spawning at all — they add CHANT_WEIGHT (0.08) to every existing same-colony dot's CCE on each chant — so a player chanting "attack" makes their living army incrementally more aggressive while reproduction continues diluting offspring at 70% of parent CCE per generation. Combat strength is a race between the player's chants pumping the existing population up and dilution pulling new dots back down toward neutral. Rally banners act as the connective tissue, taking the diffuse attack-CCE the chant has spread across the colony and concentrating it onto wherever contact actually happens.

### Defense Wall Design (Step 2, NOT YET IMPLEMENTED)
Future work, recorded for continuity:
- Defense banners (separate from build banners) drop anticipatorily based on threat scoring
- Threat score per cell ~= enemy_count * mean_enemy_attack_cce * proximity_falloff
- Banner shape is a rectangular line, perpendicular to threat bearing, sitting between colony center and threat
- Non-combat dots positioned on the line, then build under themselves (rider variant) — wall absorbs first combat, rider fights second
- Rider drops with 1-tick stun when wall destroyed
- Combat banners (existing rally system) suppress build_upward in their radius — no walling during active combat
- Threat scoring: cheapest viable function; possibly periodic global scan every ~5 ticks rather than per-tick per-dot

### Known Issues / TODO
- gather/mark_surface primitives silently do nothing
- No resource system / surface marking system
- No multiplayer / server layer
- CCE dilution still 0.7 — interacts non-trivially with reproduction (intensity falls off generationally, reproduction success collapses) — may want USE_DILUTION flag for clean static-CCE testing
- Defense banners and threat scoring unimplemented
- Rider mechanic for stacked wall+dot unimplemented
- Monument visualization: dots visually overlap with walls they just built (rider rendering not yet wired)
- p1 keeps using fog color even after contact (testing override)
- HUD shows combined CCE across all colonies — should separate per-colony
- Combat is deterministic (a + d power compared, ties to attacker) — probabilistic combat discussed but not implemented; would interact with dilution and noise floor at high generations



---

## Session Notes — continued (post-rally / build-banner work)

### Testing Iteration on Build Mechanic

After first build implementation, observed:
- Walls were forming as lines, not monuments
- Stacking wasn't happening visually
- Builders were placing into 8-neighbors rather than clustering

Iterated through several changes:

1. **First iteration — 8-neighbor scatter with attraction radius**: Builders scanned 8 neighbors, preferred placing in cells adjacent to existing same-colony walls, with a wider 3-cell attraction radius for isolated builders. Produced lines, not monuments.

2. **Second iteration — build banners with 8-neighbor placement**: Added `build_banners` (separate from rally `banners`) with `BUILD_BANNER_RADIUS = 15`, `BUILD_BANNER_TTL = 6`, `BUILD_START_CHANCE = 0.05`. Builders rolling build_upward find nearest unused banner in radius and march to it; if no banner, 5% chance to start one. Per-dot `build_banners_used` set prevents re-using same banner. Still produced lines.

3. **Third iteration — build in own cell**: Changed both founder and follower to build in their own cell. Removed all 8-neighbor scattering. Added `WALL_HEIGHT_STEP` and stack_index tracking — each new wall in a cell renders at `radius + offset + stack_index * WALL_HEIGHT_STEP`. Active monuments refresh decay on all walls in the cell when a new one is added (abandoned ones decay top-down). Monuments started forming, BUT still produced vertical lines aligned with sphere poles.

### Diagnosis of Vertical Line Pattern

The vertical-line bias (lines always grow toward poles, never east-west) is structural:

- Player dot spawns at the equator (`y = 0`)
- Colony grows from there via wander
- When a dot trips the 5% founder roll, it's wherever it happened to be in the spread cloud
- Follower dots roll build elsewhere in the cloud and march toward the banner
- Most followers approach the banner from the direction of the colony center
- Since the spawn cloud is roughly equatorial, founders tend to be slightly north or south of the cloud's centroid
- Followers therefore approach the banner from a consistent direction (pole-ward → equator-ward, or vice versa)
- When a follower's `_is_at_or_adjacent` check returns true, they're typically in the cell on the approach-side of the banner
- They `_create_wall(my_cell, my_colony)` — their *own* cell, which is 1 step away from the banner in the approach direction
- Next follower arrives, lands in the same cell (now occupied by a wall, but they're a dot not a wall so they can co-exist), builds in own cell again — stacks the lateral
- Result: a line extending from the banner toward the colony center, growing pole-ward because of the equatorial spawn

The implementation drifted from the original spec. Original spec was "80/20 stack vs lateral" — but "stack" meant "build at the banner cell" not "build in own cell which happens to be the banner cell sometimes." Builders standing adjacent to the banner build in their *own* cell (lateral), so they essentially never stack the founder block.

### Proposed Fix (UNRESOLVED — START HERE NEXT SESSION)

When a builder is at_or_adjacent to a banner:
- 80% of the time: build at the **banner cell** itself (stacks on founder block — vertical growth)
- 20% of the time: build in the **builder's own cell** (lateral spread in a random direction, since followers arrive from different angles)

This should produce real monuments: tall columns with occasional horizontal protrusions. The protrusions are in random directions because of natural variance in which builders trigger the 20% roll.

Implementation: change `_execute_build` so the at-banner case does:
```
if randf() < BUILD_AT_BANNER_STACK_PREF:
    _create_wall(banner_cell, my_colony)
else:
    _create_wall(my_cell, my_colony)
```

This matches the original 80/20 spec intent and decouples build placement from approach direction.

### UI: Manual Zoom Slider

Added a VSlider node (`UI/ZoomSlider`) for trackpad-zoom workaround on macOS:
- Range: 1.12 (closest) to 3.0 (starting/farthest)
- Vertical orientation, top-left of HUD
- Wired bidirectionally: trackpad/scroll updates slider via `set_value_no_signal`, slider drag updates `zoom_target` directly
- `ZOOM_MAX = 6.0` retained in code but unreachable via slider (cap is 3.0)

### Files Touched
- `main.gd`: rally banners, build primitive, build banners, wall stacking, zoom slider wiring
- `main.tscn`: added `UI/ZoomSlider` (VSlider)
- `DEVNOTES.md`: this file


---

## Session Notes \u2014 2026-05-11 (build mechanic diagnostic)

### Applied the 80/20 fix

Applied the spec'd fix from the previous session: at-banner builders now 80% stack at `banner_cell`, 20% build laterally. Stacking immediately started working visually \u2014 individual towers grew vertically at founder blocks. But towers grew **too fast** with no horizontal spread.

### Scaled stack pref by height

Added `STACK_HEIGHT_SOFTCAP = 10`. Stack preference now decays linearly:
```
stack_pref = BUILD_AT_BANNER_STACK_PREF * clamp(1 - height/STACK_HEIGHT_SOFTCAP, 0, 1)
```
- h=0 \u2192 80% stack / 20% lateral
- h=5 \u2192 40% / 60%
- h\u226510 \u2192 0% / 100%

New helper `_count_walls_in_cell(cell, colony)` for the height check. Same-colony walls only, so an enemy wall in the cell doesn't slow your tower.

### Lateral helper (`_pick_lateral_cell`)

The lateral branch was still building in `my_cell` \u2014 i.e. wherever the follower happened to be standing. Since most followers approach the banner from the same direction (colony cloud geometry), every "lateral" build piled into the same approach-side cell. Added `_pick_lateral_cell(banner_cell, colony)`: pick a random neighbor of the banner, preferring cells with no same-colony walls; fall back to a random neighbor if all 8 are full.

### Lines persisted \u2014 diagnostic logging

Visible behavior after all three fixes: stacking works, but lines still form alongside the towers, growing roughly north. Added test-mode infrastructure to figure out why:

- `TEST_MODE` flag, `TEST_POPULATION = 15`, `LOG_FILE = res://build_log.txt`
- `_spawn_test_population()` seeds 15 dots near the founder, forces all of them to `reproduce = 0` so population stays fixed
- `dot_id` (1..15) assigned per dot via `_next_dot_id` counter
- `_log(line)` appends to LOG_FILE (truncated at session start)
- Every primitive roll logged in `_tick_dot` with `dot_id`, cell, primitive name
- Every wall placement logged in `_create_wall` with builder_id, cell, reason (founder/stack/lateral), and post-build height
- `_tick_num` counter for chronological ordering

### Diagnosis from the log

30 ticks of clean data revealed two distinct issues:

1. **Founder chain** \u2014 `build_banners_used` (the per-dot set tracking which banners a dot has already contributed to) is the line generator. When a dot uses banner A, A is permanently dead to them. Next time they roll build, no eligible banner is in range \u2192 fall through to founder path \u2192 5% start a new monument **right where they're standing**, which is adjacent to A's footprint. Repeat: A, then B next to A, then C next to B, etc. The "lines" are actually a chain of distinct founder towers each just 1-2 cells from the last.

2. **Lateral helper produces height-6 "lateral" builds** \u2014 example from log: `[t26] wall: builder=7 cell=(164,98) reason=lateral height=6`. Tower B's banner sits at cell B, and one of B's neighbors is tower A's cell with 6 walls already on it. `_pick_lateral_cell` falls back through to A when... actually it shouldn't, since A is non-empty. Suspected cause: the banner driving builder 7 is somewhere whose neighborhood includes (164,98), and the lateral helper's empty-check is working but the founder chain has positioned banners such that "lateral" builds keep landing on existing tall stacks. Net effect either way: laterals are reinforcing existing tall towers instead of growing footprints.

### Proposed fixes (UNRESOLVED \u2014 START HERE NEXT SESSION)

A. **Kill the founder chain.** Remove `build_banners_used` tracking entirely. Dots can return to the same banner repeatedly. The 80/20 stack-vs-lateral logic and height-scaling provide enough variety; the cool-down is doing more harm than good. Founder path then only triggers when there's genuinely no monument anywhere within `BUILD_BANNER_RADIUS`.

B. **Expand lateral search to radius 2.** When all 8 banner-neighbors are non-empty, search the ring at distance 2 before falling back. Prevents laterals from stacking onto existing tall towers and actually grows the monument footprint outward.

Do A first \u2014 it may make B unnecessary if the founder chain was the primary driver. Re-run the 15-dot test, read the log, decide if B is still needed.

### Files Touched
- `main.gd`: 80/20 stack fix, `STACK_HEIGHT_SOFTCAP` scaling, `_pick_lateral_cell`, `_count_walls_in_cell`, test-mode infrastructure (`TEST_MODE`, `_log`, `_spawn_test_population`, `_next_dot_id`, `_tick_num`, log calls in `_tick_dot` and `_create_wall`)
- `build_log.txt`: created (game runtime output, gitignore candidate)
- `DEVNOTES.md`: this file

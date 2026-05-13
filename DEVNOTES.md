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



---

## Session Notes — 2026-05-12 (the "lines" were a rendering artifact)

### What we thought was happening

Coming into the session, the prior diagnosis blamed the `build_banners_used` cooldown for producing a founder chain — distinct founder towers each 1-2 cells from the last, reading as a "line." Plan A was to remove the cooldown.

### What was actually happening

Did the cooldown removal anyway (it's a real, independent bug — founders should be allowed back to refresh their own banner). Lines persisted.

Then widened `_is_at_or_adjacent` from `dist_sq <= 2` (3×3) to `dist_sq <= 8` (~5×5) and switched the lateral branch from `_pick_lateral_cell` back to `my_cell`. Lines still persisted.

Pulled the log and tabulated wall-counts per cell:

```
       114 115 116 117 118
y=95    4   7  16   2   3
y=96    8  10   8  11   1
y=97    6  10  16  11   3
y=98    6  13  16   2   2
y=99    3   4   5  11   7
```

A perfect 5×5 footprint. No line. But the user was still seeing parallel "lines" with "one dot's distance" of space between them.

The clue was the *exact* spacing: one dot wide.

- Wall mesh: `0.015 × 0.003 × 0.015`
- Cell spacing at the equator: `TAU/GRID_RES = TAU/200 ≈ 0.0314`
- Wall footprint is exactly half a cell

Adjacent cells with tall stacks render as adjacent pillars, each half a cell wide, with the other half-cell of empty space between them. Three adjacent stacked columns (x=115, 116, 117) read as three parallel rails separated by one-dot gaps. The "lines from two monuments would have met if extended" was also the same artifact — both monuments place walls on the same global lat/long grid, so the pillar-and-gap pattern aligns globally.

It was never a build logic problem. The mechanic was actually working — the 5×5 grid above is genuinely circular-ish with spikes, which is the desired behavior. The rendering just hid it.

### The fix

Single-line change:

```
const WALL_MESH_SIZE = Vector3(0.031, 0.003, 0.031)  # match cell spacing
```

Walls now tile cleanly. Adjacent cells with walls touch. The 5×5 footprint reads as a solid monument with varied-height spikes instead of striped rails.

### Cleanups also made

- `build_banners_used` writes removed from `_execute_build` (both the at-banner and founder branches). The field is still initialized in `_create_dot` and still filtered in `_find_eligible_build_banner` — dormant plumbing, costs nothing, easy to re-enable if needed.
- `_is_at_or_adjacent` widened to `dist_sq <= 8` so builders within ~2-3 cells of a banner participate. Reasonable on its own merits even though it wasn't the actual fix.
- Lateral branch builds in `my_cell` instead of `_pick_lateral_cell(banner_cell)`. Restores the original 80/20 spec intent ("stack at banner / build where you stand"). `_pick_lateral_cell` and `_count_walls_in_cell` are now unused but retained.
- TEST_MODE / LOG_ENABLED split: `TEST_MODE` controls the fixed 15-dot test population, `LOG_ENABLED` controls log writes. Lets us log organic runs without the test-population override. Currently `TEST_MODE = false`, `LOG_ENABLED = true`.

### Visual scale observation (not addressed)

Walls (0.031) are now visibly chunkier than dots (0.015) because the wall mesh now matches the cell, but the dot mesh is still half a cell. Three options discussed:

1. Scale up the world (radius, grid_res, all meshes proportionally) — lots of camera retuning.
2. Double `GRID_RES` to 400 so cell width ≈ dot width — clean, but every radius constant (`RALLY_RADIUS`, `BUILD_BANNER_RADIUS`, `ATTACK_DETECT_RADIUS`) is in cells and would need ~2× to preserve angular behavior.
3. Leave it. Walls being chunkier reads as worldbuilding — dots are living, walls are constructed.

Chose 3 for now. Easy to revisit if it starts looking wrong.

### Lessons

- Tabulating wall-cell counts as a 2D grid would have caught this in one minute on session start. Inferring spatial shape from chronological event logs missed the obvious cell-coordinate structure.
- The wall-mesh-size assumption (half a dot's height, ergo half-cell footprint) was load-bearing in a way nobody had documented. Comment now says "match cell spacing."
- Past-me's diagnoses across sessions had the right vibe (founders chain, approach bias) but the actual cause was downstream rendering. Build logic was probably fine after the iteration-3 fix; we've been iterating on a phantom.

### Known Issues / TODO

- gather/mark_surface primitives silently do nothing
- No resource system / surface marking system
- No multiplayer / server layer
- CCE dilution still 0.7 — interacts non-trivially with reproduction
- Defense banners and threat scoring unimplemented
- Rider mechanic for stacked wall+dot unimplemented
- HUD shows combined CCE across all colonies — should separate per-colony
- Combat is deterministic — probabilistic combat discussed but not implemented
- `_pick_lateral_cell` and `_count_walls_in_cell` are now dead code; remove on a future cleanup pass if confirmed unused
- Wall mesh visual scale relative to dot mesh — left at chunky-walls for now



---

## Session Notes — 2026-05-12 (cont., monument size cap)

### The stickiness problem

Once a banner is dropped, every nearby builder refreshes its TTL on placement. With ~half the colony rolling `build_upward` and a dense cluster around the founder, TTL essentially never decrements — banner is immortal. Result: the colony develops a magnet for the first monument site and never spreads.

### Approach: cap monument size by CCE, throughput by population

User's framing: cap should reflect the colony's *build character* (CCE alone), not population. A small population just takes longer to fill the cap, or never reaches it before the banner times out. A large population fills it fast and moves on. This expresses what the colony "wants to build."

Decided on a per-banner wall count cap. When count hits cap, banner expires immediately (TTL → 0). Builders downstream search for other banners or fall through to the 5% founder roll, naturally redistributing the colony spatially.

### Implementation

- `BUILD_MONUMENT_BASE = 10.0`, `BUILD_MONUMENT_SCALE = 200.0`
- `_compute_colony_avg_build_cce(colony)` averages `build_upward` across **all** living non-wall dots of the colony (entire population, not just active builders — selection bias would inflate the snapshot)
- At founder placement (`_drop_build_banner`), snapshot `wall_cap = round(BASE + SCALE * avg_build)` into the banner
- Banner now has `wall_cap` and `wall_count` fields
- In `_execute_build` at-banner branch: after `_create_wall`, increment `wall_count`. If it hits cap, expire the banner instead of refreshing
- Logging on banner creation and expiry, includes cap and avg_build snapshot

Cap numbers:
- avg=0.10 → cap=30
- avg=0.40 (current `COLONY0_CCE` preset) → cap=90
- avg=0.80 → cap=170

### Test plan (next session)

Three things to validate, in order:

1. **Does the cap fire?** With dilution still off (full_inheritance true for organic spawns), all dots stay at build=0.40 indefinitely, every banner gets cap=90. First monument should hit 90 walls and expire. Founders should fire in new locations. Run and watch logs for `banner: id=X completed at 90/90 walls — expiring` events.

2. **Does the cap scale with CCE?** Re-enable dilution (flip `full_inheritance` back to `false` in `_spawn_dot_near`). avg_build erodes over generations toward zero. Each successive banner should have a smaller cap. Eventually founders rarely fire because caps approach zero and dilution overcomes spawn CCE.

3. **Does chant counter dilution?** Add `build`/`construct` chants to `CHANT_RECIPES` (currently absent — past devnotes flagged this as a deliberate omission while build was unwired, but build is wired now). Chanting `build` adds `CHANT_WEIGHT = 0.08` to every living dot's build_upward, fighting dilution and pumping cap back up.

Doing (1) first in isolation lets us confirm the cap mechanic works without dilution as a confound.

### Files touched

- `main.gd`: BUILD_MONUMENT_BASE/SCALE constants, banner cap/count fields, `_compute_colony_avg_build_cce` helper, cap-check in `_execute_build`, log lines on banner create/expire
- `DEVNOTES.md`: this file

### Known issues / TODO

- Build chant recipes still missing — needed for test (3) and for player to actually influence monument size at runtime
- `_pick_lateral_cell` and `_count_walls_in_cell` still present as dead code (the lateral helper isn't called; the count helper is still used for stack-height softcap calculation, keep it)
- gather/mark_surface primitives still no-ops
- No monument_id on walls yet — wanted this in this session but bumped for next. Banner has an id and now a cap, walls don't carry it through. Easy add when needed for lineage queries.
- Dilution still off by default (full_inheritance true in `_spawn_dot_near`) — flip when ready for test (2)

### Files Touched

- `main.gd`: WALL_MESH_SIZE bump, removed `build_banners_used` writes, widened `_is_at_or_adjacent`, lateral builds in own cell, TEST_MODE/LOG_ENABLED split
- `DEVNOTES.md`: this file


---

## Session Notes — 2026-05-12 (cont., end-of-session discussion: wall mesh variants)

No code changed in this segment. Capturing the discussion thread so it survives the session boundary.

### Reframe: build was always about combat defense

The original intent for the build primitive was **walls during combat**, not monuments. Monuments are what build-CCE dots do when no enemy is around — a side effect of having a primitive with no immediate threat to respond to. We spent the last several sessions getting monument behavior to work, which validates the primitive's mechanics, but the *gameplay* purpose is fortification under attack. Easy to lose sight of with no enemy colony spawned.

### Idea: blocks have varying mesh sizes by context

Trigger: user observed that the old skinny mesh (0.015) was nice-looking *for a wall* and bad for a monument block. What if both exist?

Discussed three variants, in increasing ambition:

**Variant 1 — two block types, decided at placement.**
- Defense block: thin/long mesh, e.g. `(0.031, 0.003, 0.008)`. Placed when a build roll fires inside a rally banner's radius (combat context).
- Monument block: full-cell mesh `(0.031, 0.003, 0.031)`. Placed when no rally banner is in range (peaceful build).
- Same `is_wall: true`, same combat math, just a `mesh_variant` field on the wall.

**Variant 2 — block dimensions scale with CCE.**
- Mesh size correlates with build CCE concentration in the local cloud.
- High concentration → thicker walls, sparse → thinner.
- Several tunable axes, harder to read at a glance. Probably not v1.

**Variant 3 — blocks have orientation, not just footprint.**
- Defense block is a thin slab perpendicular to the threat vector.
- Multiple defense blocks join into a continuous wall facing the enemy.
- Flanking a wall means hitting its short edge.
- Coolest version, also the most geometry work (corners, joining, orientation tracking).

### Lean: variant 1 for v1

Smallest readable change. Rally banner infrastructure already tracks "is combat happening here," so the routing is nearly free. Slots into the original Step 2 design — instead of rally banners *suppressing* build_upward in combat, they *redirect* it to defense walls. The colony doesn't lose its action during combat; it expresses it as fortification.

### Mechanical pairing that fell out of the discussion

If defense walls don't stack and only spread laterally, while monument blocks stack but don't spread as aggressively, the *mechanical* difference matches the *visual* difference matches the *gameplay* difference:

- Defense walls: horizontal line, covers ground, urgent
- Monument blocks: vertical pillar, concentrates, leisurely

A colony that has lived through combat will have both side by side — old monuments from peaceful times, defense walls from when the enemy came. Terrain becomes a record of the colony's history. Worldbuilding for nearly free.

### Open questions parked for later

- Do defense walls and monument blocks coexist in the same cell? Probably not — different cells, different purposes.
- What happens to a defense wall after the threat is gone? Decays? Stays as a permanent fortification? Becomes a monument block?
- Wall orientation (variant 3) is appealing — revisit once variant 1 is in and we see how walls feel.

### Backend / scale anxiety check-in

User raised this and we talked through it briefly. Summary: the client is the design tool. Every mechanic we test locally either survives (and becomes a server requirement) or dies (and saves us server work). The right time for a server-shape sketch is after the next playable slice — combat + build + cap, with both colonies live. Then we write a one-pager on server responsibilities, tick model, message protocol, sharding. For now: keep going on game mechanics.

### Next session

Test plan from earlier in the session still stands. In order:

1. Validate cap fires (dilution off, all caps ≈ 90, banners expire on completion, founders fire elsewhere)
2. Re-enable dilution, watch caps shrink generation over generation
3. Add `build` / `construct` chant recipes, confirm chant counters dilution and bumps caps

Then revisit wall mesh variants once we have an enemy colony in play to actually exercise the combat-build pathway.

- `build_log.txt`: regenerated each session (gitignore candidate if not already)



---

## Session Notes — 2026-05-13 (cap validation, overshoot fix, build rate observation)

### Test 1: cap fires (PASSED)

Ran with dilution off (full_inheritance true) and the per-monument cap as shipped last session. All 18 founders over 85 ticks placed at avg_build=0.400 → cap=90, as expected. The redistribution loop works: when a banner hits cap, builders within radius dry up, fall through to the 5% founder roll, and new monuments start elsewhere.

### Overshoot bug (caught, fixed)

First run of test 1 surfaced an issue from the existing log without needing a fresh session: every banner overshot its cap by 8–24 walls on the cap-hit tick. Mechanism: `_execute_build`'s cap branch sets `banner["ticks_remaining"] = 0`, but the banner stays in the array until `_tick_build_banners()` cleans it up next tick. Within the current tick, every remaining builder who rolls `build_upward` still finds the banner via `_find_eligible_build_banner`, builds another wall, re-trips the cap check, and re-logs "expiring."

One-line fix: added `if banner["ticks_remaining"] <= 0: continue` to the eligibility loop. Banners marked for expiry are now invisible to lookup for the rest of the tick; cleanup still happens via the normal TTL decrement next tick. No state machine surface added — the immediate-removal alternative would have required tracking array indices and creating two exit paths.

Validation: rerun showed each banner with exactly one expire log line at exactly 90/90 walls. Zero overshoot.

### Spatial behavior at avg_build=0.40

After fix, tabulated 18 founders across 85 ticks. Footprint of all walls: 9×27 cells, with the main mass tightly clustered around the original founder. 14 of 18 founders fell within ~10 cells of the first one — they're not "starting farther away," they're starting *inside the previous monument's footprint*, because the 5% founder roll fires from wherever the builder happens to be standing, and builders cluster around the cell they were just at.

Two visible clusters emerged: a large mass at y=88–101 and a smaller one at y=109–114, separated by an 8-row gap of zeros. The southern cluster started at t64 when one wandering dot got far enough from the main cloud to be alone when its founder roll fired — a rare event, but the actual redistribution mechanism in action.

Cell wall counts at the hot spots: (11,92)=77, (10,94)=70, (10,92)=54, (10,95)=51, (10,91)=51. Stacks max around 77 because `STACK_HEIGHT_SOFTCAP=10` decays stack pref toward zero, so once a tower is height ~10 the builders are essentially all going lateral. Lateral:stack:founder ratio over the run was 1387:139:18 (~90:9:1).

### Build rate observation

**Even at build=0.40, build rate is faster than desired.** 1544 walls placed across 85 ticks with a single colony. The blending-into-cities effect the user noted is downstream of this — many overlapping monument footprints stacking up in the same general area. Tuning levers identified but not exercised:

- `BUILD_BANNER_RADIUS = 15` — smaller would make builders give up sooner and fall through to founder roll, dispersing the colony spatially.
- `BUILD_START_CHANCE = 0.05` — controls how often a "no banner in range" builder actually starts a new one.
- Anti-clustering check on founder placement — refuse founder if within some radius of an existing recent banner.
- Lowering `COLONY0_CCE.build_upward` from 0.40.

Tests 2 (re-enable dilution) and 3 (build chants) are deferred. Decision: pivot to **combat wall mechanic** next session — the original gameplay purpose of build_upward — rather than continue monument tuning.

### Files touched

- `main.gd`: added `ticks_remaining <= 0` skip in `_find_eligible_build_banner`
- `DEVNOTES.md`: this file

### Known issues / TODO

- Build rate at build=0.40 is faster than desired — tuning deferred until combat walls give us a reason to revisit
- Founders cluster inside dead monument footprints — no anti-clustering check yet
- Tests 2 (dilution generational decay) and 3 (build chant counter) skipped — pivot to combat walls instead
- Build chant recipes still missing
- `_pick_lateral_cell` still dead code (`_count_walls_in_cell` is live — used by stack-height softcap)
- gather/mark_surface primitives still no-ops
- HUD shows combined CCE across all colonies — should separate per-colony
- Combat is deterministic — probabilistic variant discussed but not implemented
- No monument_id on walls yet

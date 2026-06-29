# PLAN — Tidewater (coastal-town stroll)

## Goal
A small open-world, chunk-streamed, mobile-web Godot 4.6.3 game: a coastal-town slice you stroll
through — a sandy beach sloping into an animated foamy ocean, 2–3 blocks of composed seaside
buildings with palms and streetlights, an animated third-person townsperson (joystick + WASD,
drag-to-orbit camera), a small wandering crowd you can talk to, a day→sunset→night→sunrise cycle
that lights the town at night, and localized distance-faded audio (ocean waves, crowd murmur,
footsteps). Library assets for the bulk; Meshy for the player and townsfolk. No cars, no enterable
buildings, no backend.

## Approach
Built on the `godot-tmpl-rpg` streaming template in CHUNK mode (`world.json` `mode:"chunk"`):
- `terrain` block + a new **coastal ramp** (terrain.gd) so the land slopes down through the beach
  into the sea; `water` block draws the animated toon-water ocean with a foam shoreline.
- Parametric `structures` (build_structure.gd) for the pastel seaside buildings (lit windows) and
  the lighthouse beacon; `fs_terrain` library kit for palms / docks / shells.
- New per-cell `lamps` (chunk_manager.gd) = pole + emissive head + a warm `OmniLight` pool that
  lights the town at night.
- `populate` + `WanderAgent` for the wandering crowd; per-cell `npc` for the talkable townsfolk,
  wired to the shared LLM brain (npc.myapping.com).
- Meshy rigged+animated characters (idle/walk): the player (packed) + the townsfolk/crowd (streamed
  from `/<BUILD_ID>/models/`).
- Day→sunset→night→sunrise via the template Weather system (`sky` cycle).
- Localized audio: waves on the shore, crowd murmur on the crowd, footsteps on the player; calm
  music + a quiet sea-breeze bed.

## Out of scope
Cars/traffic, enterable building interiors, any backend/persistence (single-player local).

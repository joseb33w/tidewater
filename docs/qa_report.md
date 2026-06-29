# Tidewater — Adversarial QA Report

**VERDICT: PASS — 0 P0 ship-blockers.**
A calm, no-combat coastal-town stroll that boots clean, renders a rich populated seaside town, moves/faces/orbits correctly, fills the screen in both orientations, and is winnable. The issues below are all minor / by-design / sandbox-limited — none block ship.

Evidence is from driving the **live preview** (https://preview.myapping.com/cloud-ndekj25tgxn5ms6kytu5/) in headless Chromium (SwiftShader, mobile viewports) plus the official `verify.mjs` harness against `out/`, plus source + GLB inspection.

---

## P0 SHIP-BLOCKERS
**None found.** Every ship-blocker class for a walk-around 3D build was checked and cleared:
backwards/moonwalking hero -> correct, frozen T-pose -> animated, gray-box world -> rich, broken mobile fill -> fills, dead controls -> work, fall-through -> kinematically grounded, real console error -> clean.

---

## Dimension-by-dimension

| Check | Result | Evidence |
|-------|--------|----------|
| Engine boots / clean console | PASS | Live boot OK; console = Godot banner + OpenGL info + SwiftShader stall warnings only. No SCRIPT/Parse/Uncaught/`!is_inside_tree`. |
| Clips resolve / no T-pose | PASS | player + npc1/2/3 GLBs each carry idle+walk clips + skin + texture; player->_update_locomotion, crowd->WanderAgent, NPCs->_idle_animate play them. |
| Movement + facing | PASS | W (away from cam) -> BACK visible; S -> FACE visible. Distance HUD ticked = real movement; camera follows. Not a backwards hero. |
| World richness/density | PASS (small by-design) | Pastel buildings w/ lit windows + roofs, a varied textured crowd, streetlamps, benches, docks, beach shells, textured sand + shadows. 30 dense cells. |
| Visual / art correctness | PASS | Triplanar terrain, parametric building materials, emissive lamps, lit WorldEnvironment + procedural sky, shadows, ocean shader. No untextured gameplay primitives. |
| Mobile fill (portrait + landscape) | PASS | 400x860 & 860x400: fills all 4 corners, no letterbox; HUD on-screen, non-overlapping at both aspects. |
| Camera orbit + feet-on-floor + no void | PASS | Drag yaws ~90+, pitch clamped (no floor-stare); feet rest with shadow; real sky every frame. |
| Winnability (qgcheck) | PASS | qgcheck green (30 areas). Goal reach_cell [5,1] = a real lighthouse; quests reach_area c5_1 matches. |
| Talk / dialogue | PASS (logic) | 6 talkable NPCs w/ persona + lines; USE -> _talk shows lines + async POST to npc.myapping.com. |
| Day->night cycle lights town | PASS | Verified via deterministic short-cycle probe: dark night sky + streetlamps warmly lighting the town (warm OmniLights + emissive heads; sun 0.16 at night). |
| Ocean + foam shoreline | PASS | Real animated toon-water: depth gradient + white foam band where sea meets the sandy slope; recenters on player. |
| Audio present | WARN (sandbox) | Infra + per-action calls present (footsteps, music, sea-breeze, positional crowd/wave loops). Inaudible in muted headless. |

---

## Minor / by-design / informational (NOT ship-blockers)

1. **Verifier static lints are non-issues here.** "SMALL world / NO roads" = by design (a *small* no-car seaside town). "flat-tint character" = FALSE POSITIVE (cast.gd recolor duplicates the material and lerps albedo 0.12, texture-preserving; crowd renders full textures).
2. **SwiftShader over-exposes pastel walls** to near-white close-up (software-GL tonemap clip); on a real GPU these are the intended soft pastels.
3. **HUD font is small at landscape 860x400** (fixed sizes vs short height); readable, minor.
4. **Night arrives ~122s into the loop** (day 80s + sunset 42s before night), not ~80s; loops fine — shorten `sky.cycle` seconds if you want night sooner.

---

## Could not verify (sandbox limits — not defects)
- Real audio playback (container muted); infra + calls confirmed by code.
- True-GPU colour/fidelity (SwiftShader washes/over-exposes).
- Real multi-touch dual-stick feel (drove via keys + mouse-drag, same code paths).
- Walking all the way to the lighthouse toast live (screenshots stall during multi-cell streaming; goal wiring + reachability verified instead).
- NPC-brain reply text (external service; local lines present regardless).

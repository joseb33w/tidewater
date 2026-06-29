#!/usr/bin/env bash
# Fetch the binary game assets that aren't committed (see .gitignore). The bulk of the world
# (palms, docks, shells, the wandering crowd, the talkable townsfolk) STREAMS from R2 at runtime
# and needs nothing here; this only pulls what gets PACKED into the export: the player avatar, the
# KayKit fallback rig, and the audio loops.
set -euo pipefail
cd "$(dirname "$0")/.."

CDN="https://preview.myapping.com/godot-assets"
PREVIEW="https://preview.myapping.com/cloud-ndekj25tgxn5ms6kytu5"   # Meshy assets hosted here

mkdir -p models audio

echo "→ player avatar (Meshy) + KayKit fallback + animation libraries"
curl -sfL "$PREVIEW/models/tidewater_player.glb" -o models/tidewater_player.glb || echo "  (Meshy player unavailable — KayKit fallback will be used)"
curl -sfL "$CDN/characters/kk_Rogue.glb" -o models/kk_player.glb
for f in kk_rig_medium_general kk_rig_medium_movementbasic kk_rig_medium_combatmelee; do
  curl -sfL "$CDN/animations/$f.glb" -o "models/$f.glb"
done

echo "→ audio loops"
curl -sfL "$CDN/audio/realistic/ambient/ocean_surf.ogg" -o audio/waves.ogg
curl -sfL "$CDN/audio/realistic/ambient/town_crowd.ogg" -o audio/crowd.ogg
curl -sfL "$CDN/audio/realistic/ambient/wind_real.ogg"  -o audio/seabreeze.ogg
curl -sfL "$CDN/audio/realistic/music/calm_town.ogg"    -o audio/music_town.ogg
for i in 1 2 3; do curl -sfL "$CDN/audio/realistic/sfx/foot_dirt$i.ogg" -o "audio/step$i.ogg"; done

echo "✓ assets fetched. Next: ./godot --headless --import && ./godot --headless --export-release Web out/index.html"

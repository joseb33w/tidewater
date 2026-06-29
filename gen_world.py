#!/usr/bin/env python3
# Generates world.json for Tidewater — a chunk-streamed coastal-town slice.
import json, random

BUILD_ID = "cloud-ndekj25tgxn5ms6kytu5"
def npc_model(n): return f"/{BUILD_ID}/models/tidewater_npc{n}.glb"
CROWD_SET = [npc_model(1), npc_model(2), npc_model(3)]

random.seed(42)
PALM = [f"props/fs_terrain/beach_prop_tree_palm_{i}.glb" for i in (1, 2, 3)]
SHELLS = ["props/fs_terrain/beach_prop_shell_1.glb", "props/fs_terrain/beach_prop_shell_2.glb",
          "props/fs_terrain/beach_prop_starfish_1.glb", "props/fs_terrain/beach_prop_starfish_2.glb",
          "props/fs_terrain/beach_prop_coconut_1.glb"]
DOCK = "props/fs_terrain/beach_prop_docks_straight.glb"
BENCH = "props/kk_city/bench.glb"

# pastel coastal wall + roof palette (kept clearly COLORED, not near-white, so they don't blow out)
WALLS = [[0.82,0.80,0.74],[0.86,0.78,0.55],[0.50,0.74,0.70],[0.88,0.55,0.45],[0.56,0.72,0.84],[0.80,0.70,0.50]]
ROOFS = [[0.66,0.30,0.22],[0.24,0.32,0.46],[0.16,0.42,0.42],[0.36,0.38,0.42],[0.60,0.26,0.22]]

def building(seed, pos, rot, floors=None, footprint=None):
    r = random.Random(seed)
    floors = floors if floors is not None else r.choice([2, 2, 3, 3, 4])
    fw = footprint or [r.uniform(6.5, 8.5), r.uniform(6.0, 8.0)]
    wall = r.choice(WALLS)
    roof = r.choice(ROOFS)
    cap = r.choice(["hip", "gable", "hip", "flat"])
    return {
        "pos": [round(pos[0],1), round(pos[1],1)],
        "footprint": [round(fw[0],1), round(fw[1],1)],
        "floors": floors, "floor_height": 3.2, "rot": rot,
        "profile": "vertical", "cap": cap,
        "facade": {"type": "windows", "glow": [1.0, 0.88, 0.62], "lit": 1.7},
        "material": {"color": wall, "rough": 0.92, "bump": 0.28, "tile": 3.0},
        "roof_material": {"color": roof, "rough": 0.7, "bump": 0.4, "tile": 1.6},
        "collider": "box",
    }

def lamp(x, z): return {"pos": [x, z]}

cells = []
def add(gx, gz, **kw):
    rec = {"cell": [gx, gz]}
    rec.update(kw)
    cells.append(rec)

GX = range(0, 6)
SPAWN = (2, 3)
LIGHT = (5, 1)  # lighthouse / goal cell

for gx in GX:
    for gz in range(1, 6):
        rec = {}
        scatter = []
        props = []
        lamps = []
        populate = []
        npc = None
        structures = []

        if gz == 1:  # BEACH (sand sloping into the sea)
            scatter.append({"url": PALM[(gx) % 3], "count": 3})
            scatter.append({"url": PALM[(gx + 1) % 3], "count": 2})
            # scattered shells/starfish as individual props (small, grounded)
            props.append({"url": SHELLS[gx % len(SHELLS)], "pos": [random.uniform(-6,6), random.uniform(-6,6)], "collider": "none"})
            props.append({"url": SHELLS[(gx+2) % len(SHELLS)], "pos": [random.uniform(-6,6), random.uniform(-6,6)], "collider": "none"})
            # a waves-sound emitter on every beach cell, localized to the shore (seaward edge)
            props.append({"url": DOCK, "pos": [random.uniform(-5,5), -6.5], "collider": "box", "sound": "waves"})
            if (gx, gz) == LIGHT:
                # the lighthouse: a tall white tapered tower + red dome + a beacon light
                structures.append({
                    "pos": [0, 2], "footprint": [5.0, 5.0], "height": 16.0,
                    "profile": "taper", "batter": 0.30, "cap": "dome", "roof_height": 3.0,
                    "facade": "plain",
                    "material": {"color": [0.86, 0.86, 0.83], "rough": 0.85, "bump": 0.2, "tile": 4.0},
                    "roof_material": {"color": [0.74, 0.18, 0.16], "rough": 0.6, "bump": 0.2, "tile": 2.0},
                    "collider": "box",
                    "sign_light": {"color": [1.0, 0.93, 0.75], "energy": 6.0, "range": 22.0},
                })
                props.append({"url": DOCK, "pos": [0, -6.5], "collider": "box", "sound": "waves"})

        elif gz == 2:  # PROMENADE (waterfront)
            scatter.append({"url": PALM[gx % 3], "count": 4})
            lamps += [lamp(-5, 2), lamp(5, 2)]
            props.append({"url": BENCH, "pos": [-3, -3], "collider": "box"})
            props.append({"url": BENCH, "pos": [3, -3], "collider": "box"})
            props.append({"url": DOCK, "pos": [random.uniform(-5,5), -7], "collider": "box", "sound": "waves"})
            populate.append({"set": CROWD_SET, "count": 3, "behaviour": "wander",
                             "radius": 6.5, "speed": 1.3, "sound": "crowd", "vary": True})
            # a couple of seaside cafe/shop buildings (low) set back from the water
            if gx % 2 == 0:
                structures.append(building(700 + gx, [-3, 5.5], 180, floors=2, footprint=[7.5, 6.5]))
            else:
                structures.append(building(710 + gx, [3, 5.5], 180, floors=2, footprint=[7.0, 6.0]))

        elif gz in (3, 4):  # TOWN BLOCKS
            scatter.append({"url": PALM[(gx + gz) % 3], "count": 2})
            lamps += [lamp(-5, 0), lamp(5, 0)]
            props.append({"url": BENCH, "pos": [0, -6], "collider": "box"})
            cnt = 3 if gz == 3 else 2
            populate.append({"set": CROWD_SET, "count": cnt, "behaviour": "wander",
                             "radius": 6.5, "speed": 1.3, "sound": "crowd", "vary": True})
            if (gx, gz) == SPAWN:
                # keep the spawn cell centre CLEAR; one building at the back edge only
                structures.append(building(900, [5.5, 5.5], 200, floors=3, footprint=[6.5, 6.0]))
            else:
                structures.append(building(100 + gx * 7 + gz, [-2.5, 4.5], 180, footprint=[7.5, 7.0]))
                if (gx + gz) % 2 == 0:
                    structures.append(building(300 + gx * 7 + gz, [4.5, -3.5], 0, floors=2, footprint=[6.0, 6.0]))

        elif gz == 5:  # BACK OF TOWN
            scatter.append({"url": PALM[gx % 3], "count": 3})
            lamps += [lamp(0, 0)]
            structures.append(building(500 + gx, [0, 4], 180, floors=2, footprint=[7.0, 6.5]))

        # NPCs (talkable townsfolk) at chosen spots
        if (gx, gz) == (1, 1):
            npc = {"id": "beachcomber", "name": "Maren", "pos": [2, 1], "model": npc_model(2),
                   "persona": "Maren, a cheerful beachcomber gathering shells on Tidewater's sandy beach; warm and easygoing, talks about the tide, the gulls and good shells; reply in one short sentence",
                   "lines": ["Maren: Lovely tide today, isn't it?", "Maren: Found three sand dollars before lunch!"]}
        elif (gx, gz) == (1, 2):
            npc = {"id": "cafe", "name": "Tomas", "pos": [-3, 0], "model": npc_model(1),
                   "persona": "Tomas, the owner of a little seaside cafe on the Tidewater promenade; friendly, proud of his iced coffee, loves the sunset over the bay; reply in one short sentence",
                   "lines": ["Tomas: Welcome to the promenade!", "Tomas: Best iced coffee in Tidewater, I promise."]}
        elif (gx, gz) == SPAWN:
            npc = {"id": "guide", "name": "Pilar", "pos": [-4, 0], "model": npc_model(3),
                   "persona": "Pilar, a friendly Tidewater local out for an evening stroll; chatty and welcoming, suggests visiting the old lighthouse on the eastern point; reply in one short sentence",
                   "lines": ["Pilar: New in Tidewater? Take a stroll!", "Pilar: The old lighthouse on the point is worth the walk east."]}
        elif (gx, gz) == (4, 3):
            npc = {"id": "shop", "name": "Dev", "pos": [3, 2], "model": npc_model(1),
                   "persona": "Dev, a chatty souvenir shopkeeper in the Tidewater town square; upbeat, recommends postcards and seashell trinkets; reply in one short sentence",
                   "lines": ["Dev: Postcards! Get your Tidewater postcards!", "Dev: A seashell for the road?"]}
        elif (gx, gz) == (3, 4):
            npc = {"id": "musician", "name": "Juno", "pos": [-3, 3], "model": npc_model(2),
                   "persona": "Juno, a relaxed street musician strumming guitar in Tidewater; mellow and a little poetic about dusk and the sea; reply in one short sentence",
                   "lines": ["Juno: This one's for the sunset.", "Juno: Stick around for the night lights."]}
        elif (gx, gz) == (4, 1):
            npc = {"id": "fisher", "name": "Cap", "pos": [-2, 3], "model": npc_model(3),
                   "persona": "Cap, a weathered old fisherman by the Tidewater docks; salty but kind, tells short tales of the bay; reply in one short sentence",
                   "lines": ["Cap: Caught a beauty at dawn.", "Cap: The bay's calm tonight — good walking."]}

        if scatter: rec["scatter"] = scatter
        if props: rec["props"] = props
        if lamps: rec["lamps"] = lamps
        if populate: rec["populate"] = populate
        if structures: rec["structures"] = structures
        if npc: rec["npc"] = npc
        add(gx, gz, **rec)

world = {
    "mode": "chunk",
    "title": "Tidewater",
    "grid": {"cell_size": 16},
    "start_cell": [SPAWN[0], SPAWN[1]],
    "goal": {"type": "reach_cell", "target": [LIGHT[0], LIGHT[1]]},
    "items": {},
    "default_npc_model": npc_model(1),
    "terrain": {
        "amplitude": 0.5, "frequency": 0.06, "seed": 7, "octaves": 3,
        "material": {"color": [0.78, 0.66, 0.44], "rough": 0.97, "bump": 0.55, "tile": 5.0},
        "coast": {"axis": "z", "shore": 16.0, "slope": 0.18, "land": 2.4, "sea": -7.0}
    },
    "water": {"level": 0.0, "depth": 7.0,
              "shallow": [0.32, 0.66, 0.66], "deep": [0.05, 0.20, 0.40],
              "foam": [0.95, 0.98, 1.0], "wave_amp": 0.18, "wave_speed": 0.8},
    "sky": {"loop": True, "cycle": [
        {"time": "day", "weather": "clear", "seconds": 80},
        {"time": "sunset", "weather": "clear", "seconds": 42},
        {"time": "night", "weather": "clear", "seconds": 55},
        {"time": "sunrise", "weather": "clear", "seconds": 40}
    ]},
    "cells": cells,
}

with open("world.json", "w") as f:
    json.dump(world, f, indent=1)
print(f"wrote world.json — {len(cells)} cells")

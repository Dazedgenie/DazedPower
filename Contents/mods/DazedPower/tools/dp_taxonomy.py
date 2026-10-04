"""The parts taxonomy of Dazed Utilities: Power -- the one description of every kind, mount, tier and state,
which lays out the sprite sheet (dazedpower_01), names the items and stamps the tiledef. DP_Parts.lua mirrors
it; tools/tests/parts_test.lua fails if the two drift.

Sheet: one row per (kind, mount, tier, state[, piece]), one column per facing (E, S, W, N). APPEND ONLY once
released: inserting a row repoints every object standing in a save.
"""

COLS = 4
FACINGS = ("E", "S", "W", "N")
TILESET = "dazedpower_01"
# The engine takes at most 512 tiles per tileset, so the sheet spills onto dazedpower_02, _03...
SHEET_TILES = 512
TILESETS = ["dazedpower_%02d" % (i + 1) for i in range(4)]


def sprite_name(n):
    """Engine sprite name for overall sheet index n."""
    return "%s_%d" % (TILESETS[n // SHEET_TILES], n % SHEET_TILES)
GROUP = "Dazed Power"
PIECES_XL = 4                       # a 2x2 array: pieces 1..4 = NW, NE, SW, SE of its footprint

KINDS = ["array", "bank", "controller", "transformer", "lamp", "pedal", "windmill", "steam", "windsock", "vane",
         "propane", "petrol", "gauge", "rod", "bench", "hydro"]
MOUNTS = {
    "array": ["ground", "tracker", "xl"], "bank": ["ground", "wall"], "controller": ["ground"],
    "transformer": ["ground"], "lamp": ["garden", "street"], "pedal": ["ground"], "windmill": ["ground"],
    "steam": ["ground"], "windsock": ["ground"], "vane": ["ground"], "propane": ["ground"], "petrol": ["ground"],
    "gauge": ["wall"], "rod": ["ground"], "bench": ["ground"], "hydro": ["ground"],
}
THREE = ["makeshift", "salvaged", "workshop"]
TIERS = {
    "array": THREE, "bank": THREE, "controller": ["makeshift", "workshop"], "transformer": ["standard"],
    "lamp": ["makeshift", "workshop"], "pedal": THREE, "windmill": THREE, "steam": THREE,
    "windsock": ["basic"], "vane": ["basic"], "propane": THREE, "petrol": THREE,
    "gauge": ["standard"], "rod": ["standard"], "bench": ["standard"], "hydro": ["standard"],
}
STATES = {
    "array": ["clear", "snow", "cracked"], "controller": ["off", "on"], "transformer": ["off", "on"],
    "lamp": ["off", "on"], "pedal": ["off", "on"], "windmill": ["still", "turning", "furled", "broken"],
    "steam": ["cold", "warming", "running", "broken"], "windsock": ["limp", "half", "full"], "vane": ["set"],
    "propane": ["off", "running", "broken"], "petrol": ["off", "running", "broken"],
    "gauge": ["off", "low", "mid", "full"], "rod": ["set"], "bench": ["off", "on"], "hydro": ["still", "turning"],
}
BANK_CELLS = {"ground": {"makeshift": 3, "salvaged": 6, "workshop": 8}, "wall": {"makeshift": 2, "salvaged": 3, "workshop": 4}}


def states_for(kind, mount, tier):
    if kind != "bank": return STATES[kind]
    return ["c%d" % i for i in range(BANK_CELLS[mount][tier] + 1)]


def rows():
    """[(kind, mount, tier, state, piece)] in sheet order; piece is 1 except for the XL array (1..4)."""
    out = []
    for kind in KINDS:
        for mount in MOUNTS[kind]:
            for tier in TIERS[kind]:
                for state in states_for(kind, mount, tier):
                    pieces = PIECES_XL if (kind == "array" and mount == "xl") else 1
                    for piece in range(1, pieces + 1):
                        out.append((kind, mount, tier, state, piece))
    return out


ROWS = rows()
ROW_OF = {r: i for i, r in enumerate(ROWS)}


def sprite_index(kind, mount, tier, state, facing, piece=1):
    return ROW_OF[(kind, mount, tier, state, piece)] * COLS + FACINGS.index(facing)


# Items: Base.<name>; the controller has a record per facing and per on/off state (see DP_Parts.lua).
ITEM = {
    "array": {"ground": {"makeshift": "DazedArrayMakeshift", "salvaged": "DazedArraySalvaged", "workshop": "DazedArrayWorkshop"},
              "tracker": {"makeshift": "DazedTrackerMakeshift", "salvaged": "DazedTrackerSalvaged", "workshop": "DazedTrackerWorkshop"},
              "xl": {"makeshift": "DazedArrayXLMakeshift", "salvaged": "DazedArrayXLSalvaged", "workshop": "DazedArrayXLWorkshop"}},
    "bank": {"ground": {"makeshift": "DazedBankMakeshift", "salvaged": "DazedBankSalvaged", "workshop": "DazedBankWorkshop"},
             "wall": {"makeshift": "DazedWallBankMakeshift", "salvaged": "DazedWallBankSalvaged", "workshop": "DazedWallBankWorkshop"}},
    "controller": {"ground": {"makeshift": "DazedControllerMakeshift", "workshop": "DazedControllerWorkshop"}},
    "transformer": {"ground": {"standard": "DazedTransformer"}},
    "lamp": {"garden": {"makeshift": "DazedGardenLampMakeshift", "workshop": "DazedGardenLampWorkshop"},
             "street": {"makeshift": "DazedStreetLampMakeshift", "workshop": "DazedStreetLampWorkshop"}},
    "pedal": {"ground": {"makeshift": "DazedPedalMakeshift", "salvaged": "DazedPedalSalvaged", "workshop": "DazedPedalWorkshop"}},
    "windmill": {"ground": {"makeshift": "DazedWindMakeshift", "salvaged": "DazedWindSalvaged", "workshop": "DazedWindWorkshop"}},
    "steam": {"ground": {"makeshift": "DazedSteamMakeshift", "salvaged": "DazedSteamSalvaged", "workshop": "DazedSteamWorkshop"}},
    "windsock": {"ground": {"basic": "DazedWindsock"}},
    "vane": {"ground": {"basic": "DazedWeatherVane"}},
    "propane": {"ground": {"makeshift": "DazedPropaneMakeshift", "salvaged": "DazedPropaneSalvaged", "workshop": "DazedPropaneWorkshop"}},
    "petrol": {"ground": {"makeshift": "DazedPetrolMakeshift", "salvaged": "DazedPetrolSalvaged", "workshop": "DazedPetrolWorkshop"}},
    "gauge": {"wall": {"standard": "DazedPowerGauge"}},
    "rod": {"ground": {"standard": "DazedGroundingRod"}},
    "bench": {"ground": {"standard": "DazedChargerBench"}},
    "hydro": {"ground": {"standard": "DazedWaterWheel"}},
}
# Items that are not world parts.
OTHER_ITEMS = ["DazedPowerManual", "DazedPowerManualAdv", "DazedAlmanac", "DazedAmplifier",
               "DazedGearKitLow", "DazedGearKitStock", "DazedGearKitRacing"]

TIER_WORD = {"makeshift": "Makeshift", "salvaged": "Salvaged", "workshop": "Workshop", "standard": "", "basic": ""}
# Display names (CustomName on the tile, DisplayName of the item), by kind and mount; {T} is the tier word.
NAME = {
    ("array", "ground"): "{T} Solar Array", ("array", "tracker"): "{T} Tracking Array", ("array", "xl"): "{T} Large Solar Array",
    ("bank", "ground"): {"makeshift": "Makeshift Battery Crate", "salvaged": "Salvaged Battery Bank", "workshop": "Workshop Battery Cabinet"},
    ("bank", "wall"): {"makeshift": "Makeshift Wall Cells", "salvaged": "Salvaged Wall Battery Box", "workshop": "Workshop Wall Cabinet"},
    ("controller", "ground"): "{T} Charge Controller", ("transformer", "ground"): "Transformer",
    ("lamp", "garden"): "{T} Solar Garden Lamp", ("lamp", "street"): "{T} Solar Street Lamp",
    ("pedal", "ground"): "{T} Pedal Generator", ("windmill", "ground"): {"makeshift": "Makeshift Windmill", "salvaged": "Salvaged Windmill", "workshop": "Workshop Wind Turbine"},
    ("steam", "ground"): {"makeshift": "Makeshift Steam Engine", "salvaged": "Salvaged Steam Engine", "workshop": "Workshop Steam Plant"},
    ("windsock", "ground"): "Windsock", ("vane", "ground"): "Weather Vane",
    ("propane", "ground"): {"makeshift": "Makeshift Propane Generator", "salvaged": "Salvaged Standby Generator", "workshop": "Workshop Standby Generator"},
    ("petrol", "ground"): "{T} Petrol Generator",
    ("gauge", "wall"): "Wall Power Gauge",
    ("rod", "ground"): "Grounding Rod", ("bench", "ground"): "Battery Charger Bench", ("hydro", "ground"): "Micro-Hydro Wheel",
}
# Weight in kg (PickUpWeight is kg x 10). Anything over 30 comes apart into parts (DazedCore.Heavy).
WEIGHT = {
    ("array", "ground"): {"makeshift": 14, "salvaged": 18, "workshop": 20},
    ("array", "tracker"): {"makeshift": 22, "salvaged": 28, "workshop": 32},
    ("array", "xl"): {"makeshift": 48, "salvaged": 60, "workshop": 70},
    ("bank", "ground"): {"makeshift": 22, "salvaged": 32, "workshop": 38},
    ("bank", "wall"): {"makeshift": 14, "salvaged": 20, "workshop": 24},
    ("controller", "ground"): {"makeshift": 9, "workshop": 11}, ("transformer", "ground"): {"standard": 26},
    ("lamp", "garden"): {"makeshift": 2.5, "workshop": 3.5}, ("lamp", "street"): {"makeshift": 18, "workshop": 22},
    ("pedal", "ground"): {"makeshift": 22, "salvaged": 26, "workshop": 30},
    ("windmill", "ground"): {"makeshift": 24, "salvaged": 32, "workshop": 40},
    ("steam", "ground"): {"makeshift": 30, "salvaged": 40, "workshop": 50},
    ("windsock", "ground"): {"basic": 3}, ("vane", "ground"): {"basic": 5},
    ("propane", "ground"): {"makeshift": 30, "salvaged": 45, "workshop": 60},
    ("petrol", "ground"): {"makeshift": 30, "salvaged": 45, "workshop": 60},
    ("gauge", "wall"): {"standard": 1.5},
    ("rod", "ground"): {"standard": 4}, ("bench", "ground"): {"standard": 18}, ("hydro", "ground"): {"standard": 26},
}


def display_name(kind, mount, tier):
    n = NAME[(kind, mount)]
    if isinstance(n, dict): return n[tier]
    return n.replace("{T} ", TIER_WORD[tier] + " " if TIER_WORD[tier] else "").strip()


def item_of(kind, mount, tier):
    return ITEM[kind][mount][tier]


def all_items():
    out = []
    for kind in KINDS:
        for mount in MOUNTS[kind]:
            for tier in TIERS[kind]:
                out.append(item_of(kind, mount, tier))
    for f in ("E", "W", "N"):
        for tier in TIERS["controller"]:
            out.append(item_of("controller", "ground", tier) + f)
    for tier in TIERS["controller"]:
        for f in ("", "E", "W", "N"):
            out.append(item_of("controller", "ground", tier) + "On" + f)
    return out + OTHER_ITEMS


if __name__ == "__main__":
    print("%d rows, %d sprites, %d items" % (len(ROWS), len(ROWS) * COLS, len(all_items())))
    last = None
    for i, r in enumerate(ROWS):
        if (r[0], r[1]) != last:
            last = (r[0], r[1]); print("row %3d  sprite %4d  %s/%s" % (i, i * COLS, r[0], r[1]))

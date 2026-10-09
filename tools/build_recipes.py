"""Write scripts/dazedpower_recipes.txt (Make and Scrap for every world part), scripts/dazedpower_misc_items.txt
(the handbooks with what they teach, the almanac, gear kits, amplifier) and the Recipes.json names, from the
taxonomy. Edit the tables here, not the generated files.

    python3 tools/build_recipes.py
"""
import json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import dp_taxonomy as T  # noqa: E402

MEDIA = HERE.parent / "Contents/mods/DazedPower/common/media"
SCREW = "item 1 tags[base:screwdriver] mode:keep flags[Prop1]"
PLIERS = "item 1 tags[base:pliers] mode:keep flags[MayDegradeVeryLight]"
MASK = "item 1 tags[base:weldingmask] mode:keep"
HAMMER = "item 1 tags[base:hammer] mode:keep"


def torch(n): return "item %d [Base.BlowTorch]" % n
def it(n, name): return "item %d [Base.%s]" % (n, name)
def destroy(name): return "item 1 [Base.%s] mode:destroy" % name


# (kind, mount, tier): dict(action, time, skill, xp, inputs, scrap, learn)   learn: None, "basic" or "adv"
R = {}

def make(kind, mount, tier, time, skill, xp, inputs, scrap, learn, action="MakingElectrical", scrapTime=400, scrapXp="Electricity:10"):
    R[(kind, mount, tier)] = dict(action=action, time=time, skill=skill, xp=xp, inputs=inputs, scrap=scrap, learn=learn,
                                  scrapTime=scrapTime, scrapXp=scrapXp)

# ---- static arrays
make("array", "ground", "makeshift", 550, "Electricity:2", "Electricity:20",
     [SCREW, PLIERS, it(2, "ElectronicsScrap"), it(3, "SmallSheetMetal"), it(2, "Wire"), it(4, "Screws"), it(2, "DuctTape")],
     ["item 1 Base.ElectronicsScrap", "item 1 Base.SmallSheetMetal"], "basic")
make("array", "ground", "salvaged", 900, "Electricity:4;MetalWelding:2", "Electricity:45;MetalWelding:15",
     [SCREW, torch(2), MASK, it(4, "ElectronicsScrap"), it(2, "SheetMetal"), it(2, "MetalBar"), it(3, "ElectricWire"), it(4, "Screws")],
     ["item 2 Base.ElectronicsScrap", "item 1 Base.SheetMetal", "item 2 Base.Screws"], "basic")
make("array", "ground", "workshop", 1200, "Electricity:7;MetalWelding:3", "Electricity:90;MetalWelding:25",
     [SCREW, torch(2), MASK, it(8, "ElectronicsScrap"), it(2, "Aluminum"), it(2, "SheetMetal"), it(4, "ElectricWire"), it(6, "Screws")],
     ["item 4 Base.ElectronicsScrap", "item 1 Base.Aluminum", "item 3 Base.Screws"], "adv")
# ---- tracking arrays: a static array of the grade on a turning frame with a drive
make("array", "tracker", "makeshift", 700, "Electricity:3;Mechanics:1", "Electricity:30;Mechanics:10",
     [SCREW, PLIERS, destroy("DazedArrayMakeshift"), it(2, "EngineParts"), it(2, "MetalBar"), it(2, "ElectronicsScrap"), it(2, "Wire"), it(4, "Screws")],
     ["item 1 Base.ElectronicsScrap", "item 1 Base.SmallSheetMetal", "item 1 Base.MetalBar", "item 1 Base.EngineParts"], "basic")
make("array", "tracker", "salvaged", 1100, "Electricity:5;MetalWelding:3;Mechanics:2", "Electricity:55;MetalWelding:20;Mechanics:15",
     [SCREW, torch(2), MASK, destroy("DazedArraySalvaged"), it(3, "EngineParts"), it(3, "MetalBar"), it(3, "ElectronicsScrap"), it(2, "ElectricWire"), it(6, "Screws")],
     ["item 2 Base.ElectronicsScrap", "item 1 Base.SheetMetal", "item 2 Base.MetalBar", "item 1 Base.EngineParts"], "basic")
make("array", "tracker", "workshop", 1500, "Electricity:8;MetalWelding:4;Mechanics:3", "Electricity:110;MetalWelding:30;Mechanics:25",
     [SCREW, torch(3), MASK, destroy("DazedArrayWorkshop"), it(4, "EngineParts"), it(2, "Aluminum"), it(3, "MetalBar"), it(4, "ElectronicsScrap"), it(3, "ElectricWire"), it(8, "Screws")],
     ["item 4 Base.ElectronicsScrap", "item 1 Base.Aluminum", "item 2 Base.MetalBar", "item 2 Base.EngineParts"], "adv")
# ---- the 2x2 array: four static arrays of the grade on one welded frame
make("array", "xl", "makeshift", 1200, "Electricity:3;MetalWelding:2", "Electricity:40;MetalWelding:20",
     [SCREW, torch(2), MASK, "item 4 [Base.DazedArrayMakeshift] mode:destroy", it(4, "MetalBar"), it(2, "MetalPipe"), it(2, "Wire"), it(8, "Screws")],
     ["item 4 Base.ElectronicsScrap", "item 4 Base.SmallSheetMetal", "item 2 Base.MetalBar"], "basic", scrapTime=800)
make("array", "xl", "salvaged", 1600, "Electricity:5;MetalWelding:4", "Electricity:70;MetalWelding:40",
     [SCREW, torch(3), MASK, "item 4 [Base.DazedArraySalvaged] mode:destroy", it(6, "MetalBar"), it(2, "MetalPipe"), it(3, "ElectricWire"), it(10, "Screws")],
     ["item 8 Base.ElectronicsScrap", "item 4 Base.SheetMetal", "item 3 Base.MetalBar", "item 4 Base.Screws"], "basic", scrapTime=800)
make("array", "xl", "workshop", 2000, "Electricity:8;MetalWelding:5", "Electricity:130;MetalWelding:60",
     [SCREW, torch(4), MASK, "item 4 [Base.DazedArrayWorkshop] mode:destroy", it(6, "MetalBar"), it(2, "Aluminum"), it(2, "MetalPipe"), it(4, "ElectricWire"), it(12, "Screws")],
     ["item 16 Base.ElectronicsScrap", "item 4 Base.Aluminum", "item 3 Base.MetalBar", "item 6 Base.Screws"], "adv", scrapTime=800)
# ---- banks
make("bank", "ground", "makeshift", 420, "Electricity:1;Woodwork:2", "Electricity:15;Woodwork:20",
     [HAMMER, SCREW, it(4, "Plank"), it(6, "Nails"), it(2, "Wire"), it(1, "ElectricWire")],
     ["item 2 Base.Plank", "item 3 Base.Nails", "item 1 Base.Wire"], "basic")
make("bank", "ground", "salvaged", 700, "Electricity:3;MetalWelding:3", "Electricity:25;MetalWelding:30",
     [SCREW, torch(2), MASK, it(4, "MetalBar"), it(2, "SheetMetal"), it(2, "ElectricWire"), it(6, "Screws")],
     ["item 2 Base.MetalBar", "item 1 Base.SheetMetal", "item 2 Base.Screws"], "basic")
make("bank", "ground", "workshop", 1000, "Electricity:6;MetalWelding:4", "Electricity:70;MetalWelding:40",
     [SCREW, torch(2), MASK, it(6, "SheetMetal"), it(4, "ElectronicsScrap"), it(3, "ElectricWire"), it(8, "Screws")],
     ["item 2 Base.SheetMetal", "item 1 Base.MetalBar", "item 3 Base.Screws", "item 1 Base.ElectronicsScrap"], "adv")
make("bank", "wall", "makeshift", 360, "Electricity:1;Woodwork:2", "Electricity:12;Woodwork:16",
     [HAMMER, SCREW, it(3, "Plank"), it(4, "Nails"), it(1, "Wire"), it(1, "ElectricWire")],
     ["item 1 Base.Plank", "item 2 Base.Nails"], "basic")
make("bank", "wall", "salvaged", 560, "Electricity:3;MetalWelding:2", "Electricity:22;MetalWelding:20",
     [SCREW, torch(2), MASK, it(2, "MetalBar"), it(2, "SheetMetal"), it(2, "ElectricWire"), it(5, "Screws")],
     ["item 1 Base.MetalBar", "item 1 Base.SheetMetal", "item 2 Base.Screws"], "basic")
make("bank", "wall", "workshop", 860, "Electricity:6;MetalWelding:3", "Electricity:60;MetalWelding:30",
     [SCREW, torch(2), MASK, it(4, "SheetMetal"), it(3, "ElectronicsScrap"), it(3, "ElectricWire"), it(6, "Screws")],
     ["item 1 Base.SheetMetal", "item 2 Base.Screws", "item 1 Base.ElectronicsScrap"], "adv")
# ---- controllers and the transformer
make("controller", "ground", "makeshift", 800, "Electricity:3", "Electricity:60",
     [SCREW, PLIERS, it(6, "ElectronicsScrap"), destroy("CarBatteryCharger"), it(3, "ElectricWire"), it(1, "SheetMetal"), it(4, "Screws")],
     ["item 3 Base.ElectronicsScrap", "item 1 Base.SheetMetal", "item 2 Base.ElectricWire"], "basic")
make("controller", "ground", "workshop", 1100, "Electricity:8", "Electricity:110",
     [SCREW, PLIERS, it(10, "ElectronicsScrap"), destroy("DazedControllerMakeshift"), it(2, "Aluminum"), it(4, "ElectricWire"), it(6, "Screws")],
     ["item 5 Base.ElectronicsScrap", "item 1 Base.Aluminum", "item 3 Base.ElectricWire"], "adv")
make("transformer", "ground", "standard", 800, "Electricity:5;MetalWelding:2", "Electricity:60;MetalWelding:15",
     [SCREW, PLIERS, torch(2), MASK, it(3, "SheetMetal"), it(6, "ElectricWire"), it(4, "ElectronicsScrap"), it(6, "Screws")],
     ["item 2 Base.ElectronicsScrap", "item 1 Base.SheetMetal", "item 3 Base.ElectricWire", "item 3 Base.Screws"], "basic")
# ---- lamps: Makeshift ones need no book
make("lamp", "garden", "makeshift", 300, "Electricity:1", "Electricity:10",
     [SCREW, it(1, "LightBulb"), "item 1 [Base.Battery] flags[ItemCount] mode:destroy", it(2, "ElectronicsScrap"), it(1, "SmallSheetMetal"), it(2, "Screws")],
     ["item 1 Base.ElectronicsScrap", "item 1 Base.SmallSheetMetal"], None)
make("lamp", "garden", "workshop", 500, "Electricity:3", "Electricity:30",
     [SCREW, PLIERS, it(1, "LightBulb"), "item 2 [Base.Battery] flags[ItemCount] mode:destroy", it(4, "ElectronicsScrap"), it(1, "Aluminum"), it(1, "SmallSheetMetal"), it(3, "Screws")],
     ["item 2 Base.ElectronicsScrap", "item 1 Base.Aluminum"], "adv")
make("lamp", "street", "makeshift", 700, "Electricity:3;MetalWelding:2", "Electricity:30;MetalWelding:15",
     [SCREW, PLIERS, torch(2), MASK, it(1, "LightBulb"), "item 1 [Base.CarBattery1;Base.CarBattery2;Base.CarBattery3] flags[ItemCount] mode:destroy",
      it(2, "MetalPipe"), it(1, "SheetMetal"), it(4, "ElectronicsScrap"), it(2, "ElectricWire"), it(4, "Screws")],
     ["item 2 Base.ElectronicsScrap", "item 1 Base.MetalPipe", "item 2 Base.Screws"], None)
make("lamp", "street", "workshop", 1000, "Electricity:5;MetalWelding:3", "Electricity:60;MetalWelding:25",
     [SCREW, PLIERS, torch(2), MASK, it(1, "LightBulb"), "item 1 [Base.CarBattery1;Base.CarBattery2;Base.CarBattery3] flags[ItemCount] mode:destroy",
      it(2, "MetalPipe"), it(2, "SheetMetal"), it(2, "Aluminum"), it(6, "ElectronicsScrap"), it(3, "ElectricWire"), it(6, "Screws")],
     ["item 3 Base.ElectronicsScrap", "item 1 Base.MetalPipe", "item 1 Base.Aluminum", "item 3 Base.Screws"], "adv")
# ---- the sources, as Dazed Power had them (the Workshop build takes the Salvaged one)
make("pedal", "ground", "makeshift", 600, "Electricity:2", "Electricity:22",
     [SCREW, PLIERS, it(2, "ElectronicsScrap"), it(4, "SmallSheetMetal"), it(2, "MetalBar"), it(2, "Wire"), it(4, "Screws"), it(2, "DuctTape")],
     ["item 1 Base.ElectronicsScrap", "item 1 Base.SmallSheetMetal", "item 1 Base.MetalBar"], "basic", scrapTime=420)
make("pedal", "ground", "salvaged", 950, "Electricity:4;MetalWelding:2", "Electricity:48;MetalWelding:15",
     [SCREW, torch(2), MASK, it(4, "ElectronicsScrap"), it(2, "SheetMetal"), it(3, "MetalBar"), it(3, "ElectricWire"), it(4, "Screws")],
     ["item 2 Base.ElectronicsScrap", "item 1 Base.SheetMetal", "item 1 Base.MetalBar"], "basic", scrapTime=420, scrapXp="Electricity:12")
make("pedal", "ground", "workshop", 1200, "Electricity:8;MetalWelding:4", "Electricity:110;MetalWelding:25",
     [SCREW, torch(2), MASK, destroy("DazedPedalSalvaged"), it(6, "ElectronicsScrap"), it(2, "Aluminum"), it(4, "ElectricWire"), it(6, "Screws")],
     ["item 3 Base.ElectronicsScrap", "item 1 Base.Aluminum"], "adv", scrapTime=420, scrapXp="Electricity:16")
make("windmill", "ground", "makeshift", 650, "Electricity:2", "Electricity:25",
     [SCREW, PLIERS, it(3, "ElectronicsScrap"), it(3, "SmallSheetMetal"), it(3, "MetalBar"), it(3, "Wire"), it(6, "Screws"), it(2, "DuctTape")],
     ["item 1 Base.ElectronicsScrap", "item 1 Base.SmallSheetMetal", "item 1 Base.MetalBar"], "basic", scrapTime=450)
make("windmill", "ground", "salvaged", 1000, "Electricity:4;MetalWelding:3", "Electricity:50;MetalWelding:20",
     [SCREW, torch(2), MASK, it(5, "ElectronicsScrap"), it(3, "SheetMetal"), it(4, "MetalBar"), it(4, "ElectricWire"), it(6, "Screws")],
     ["item 2 Base.ElectronicsScrap", "item 1 Base.SheetMetal", "item 2 Base.MetalBar"], "basic", scrapTime=450, scrapXp="Electricity:12")
make("windmill", "ground", "workshop", 1400, "Electricity:8;MetalWelding:5", "Electricity:120;MetalWelding:35",
     [SCREW, torch(3), MASK, destroy("DazedWindSalvaged"), it(8, "ElectronicsScrap"), it(4, "Aluminum"), it(4, "MetalBar"), it(6, "ElectricWire"), it(8, "Screws")],
     ["item 3 Base.ElectronicsScrap", "item 2 Base.Aluminum", "item 1 Base.MetalBar"], "adv", scrapTime=450, scrapXp="Electricity:16")
make("steam", "ground", "makeshift", 900, "Electricity:3;MetalWelding:3", "Electricity:35;MetalWelding:30",
     [SCREW, torch(2), MASK, it(4, "ElectronicsScrap"), it(4, "SheetMetal"), it(4, "MetalBar"), it(3, "Wire"), it(6, "Screws")],
     ["item 2 Base.ElectronicsScrap", "item 2 Base.SheetMetal", "item 1 Base.MetalBar"], "basic", scrapTime=500, scrapXp="Electricity:12")
make("steam", "ground", "salvaged", 1300, "Electricity:5;MetalWelding:5", "Electricity:60;MetalWelding:45",
     [SCREW, torch(3), MASK, it(6, "ElectronicsScrap"), it(6, "SheetMetal"), it(6, "MetalBar"), it(4, "ElectricWire"), it(8, "Screws")],
     ["item 3 Base.ElectronicsScrap", "item 3 Base.SheetMetal", "item 2 Base.MetalBar"], "basic", scrapTime=500, scrapXp="Electricity:14")
make("steam", "ground", "workshop", 1800, "Electricity:8;MetalWelding:7", "Electricity:130;MetalWelding:80",
     [SCREW, torch(4), MASK, destroy("DazedSteamSalvaged"), it(8, "ElectronicsScrap"), it(6, "Aluminum"), it(4, "SheetMetal"), it(6, "ElectricWire"), it(10, "Screws")],
     ["item 4 Base.ElectronicsScrap", "item 3 Base.Aluminum", "item 2 Base.SheetMetal"], "adv", scrapTime=500, scrapXp="Electricity:18")
for gas in ("propane", "petrol"):
    make(gas, "ground", "makeshift", 900, "Electricity:3;Mechanics:2", "Electricity:30;Mechanics:20",
         [SCREW, PLIERS, it(4, "EngineParts"), it(2, "MetalPipe"), it(2, "MetalBar"), it(3, "ElectronicsScrap"), it(3, "ElectricWire"), it(6, "Screws"), it(2, "DuctTape")],
         ["item 2 Base.EngineParts", "item 2 Base.ElectronicsScrap", "item 1 Base.MetalPipe"], "basic", scrapTime=500, scrapXp="Electricity:12")
    make(gas, "ground", "salvaged", 1300, "Electricity:5;Mechanics:3;MetalWelding:2", "Electricity:60;Mechanics:35;MetalWelding:15",
         [SCREW, torch(2), MASK, it(8, "EngineParts"), it(4, "SheetMetal"), it(2, "MetalPipe"), it(6, "ElectronicsScrap"), it(5, "ElectricWire"), it(10, "Screws")],
         ["item 4 Base.EngineParts", "item 3 Base.ElectronicsScrap", "item 2 Base.SheetMetal"], "basic", scrapTime=600, scrapXp="Electricity:16")
    make(gas, "ground", "workshop", 1800, "Electricity:7;Mechanics:5;MetalWelding:4", "Electricity:120;Mechanics:70;MetalWelding:40",
         [SCREW, torch(3), MASK, destroy(T.item_of(gas, "ground", "salvaged")), it(6, "EngineParts"), it(4, "Aluminum"), it(4, "SheetMetal"), it(8, "ElectronicsScrap"), it(6, "ElectricWire"), it(12, "Screws")],
         ["item 6 Base.EngineParts", "item 5 Base.ElectronicsScrap", "item 2 Base.Aluminum", "item 2 Base.SheetMetal"], "adv", scrapTime=700, scrapXp="Electricity:20")
make("windsock", "ground", "basic", 250, None, None,
     [PLIERS, it(3, "RippedSheets"), it(1, "MetalPipe"), it(1, "Wire"), it(1, "DuctTape")], None, None)
make("vane", "ground", "basic", 350, None, None,
     [SCREW, PLIERS, it(1, "SmallSheetMetal"), it(1, "MetalBar"), it(1, "MetalPipe"), it(2, "Screws")], None, None)

make("gauge", "wall", "standard", 300, "Electricity:2", "Electricity:15",
     [SCREW, PLIERS, it(2, "ElectronicsScrap"), it(1, "SmallSheetMetal"), it(1, "ElectricWire"), it(2, "Screws")],
     ["item 1 Base.ElectronicsScrap", "item 1 Base.SmallSheetMetal"], "basic", scrapTime=250, scrapXp="Electricity:5")

make("rod", "ground", "standard", 250, "Electricity:2", "Electricity:10",
     [SCREW, PLIERS, it(2, "MetalPipe"), it(2, "ElectricWire"), it(1, "Screws")],
     ["item 1 Base.MetalPipe"], "basic", scrapTime=200, scrapXp="Electricity:4")
make("bench", "ground", "standard", 500, "Electricity:3", "Electricity:25",
     [SCREW, PLIERS, it(3, "ElectronicsScrap"), it(2, "SheetMetal"), it(2, "ElectricWire"), it(4, "Screws"), it(2, "Plank")],
     ["item 2 Base.ElectronicsScrap", "item 1 Base.SheetMetal"], "basic", scrapTime=300, scrapXp="Electricity:8")
make("hydro", "ground", "standard", 900, "Electricity:4;MetalWelding:2", "Electricity:45;MetalWelding:20",
     [SCREW, torch(2), MASK, it(4, "ElectronicsScrap"), it(4, "SheetMetal"), it(3, "MetalBar"), it(3, "ElectricWire"), it(6, "Screws")],
     ["item 2 Base.ElectronicsScrap", "item 2 Base.SheetMetal", "item 1 Base.MetalBar"], "adv", scrapTime=450, scrapXp="Electricity:12")

make("fence", "ground", "standard", 700, "Electricity:3;MetalWelding:2", "Electricity:30;MetalWelding:15",
     [SCREW, PLIERS, torch(1), MASK, it(3, "MetalPipe"), it(1, "SheetMetal"), it(3, "ElectricWire"), it(2, "ElectronicsScrap"), it(4, "Screws")],
     ["item 2 Base.MetalPipe", "item 1 Base.ElectronicsScrap"], "adv", scrapTime=350, scrapXp="Electricity:8")
make("cooler", "wall", "standard", 900, "Electricity:4", "Electricity:45",
     [SCREW, PLIERS, it(2, "EngineParts"), it(2, "SheetMetal"), it(4, "ElectronicsScrap"), it(2, "ElectricWire"), it(1, "MetalPipe"), it(4, "Screws")],
     ["item 1 Base.EngineParts", "item 2 Base.ElectronicsScrap", "item 1 Base.SheetMetal"], "adv", scrapTime=450)
make("heater", "ground", "standard", 500, "Electricity:3", "Electricity:25",
     [SCREW, PLIERS, it(2, "ElectronicsScrap"), it(1, "SheetMetal"), it(2, "ElectricWire"), it(1, "SmallSheetMetal"), it(3, "Screws")],
     ["item 1 Base.ElectronicsScrap", "item 1 Base.SheetMetal"], "basic", scrapTime=300, scrapXp="Electricity:8")

# Items that are not parts: (name, recipe lines) -- the gear kits and nothing else is crafted
MISC_RECIPES = [
    ("DazedGearKitLow", 300, "Electricity:2", "Electricity:12", [SCREW, it(1, "ElectronicsScrap"), it(2, "MetalBar"), it(2, "Screws")], "basic"),
    ("DazedGearKitStock", 300, "Electricity:2", "Electricity:12", [SCREW, it(1, "ElectronicsScrap"), it(2, "MetalBar"), it(2, "Screws")], "basic"),
    ("DazedGearKitRacing", 400, "Electricity:6", "Electricity:30", [SCREW, it(2, "ElectronicsScrap"), it(3, "MetalBar"), it(2, "Aluminum"), it(3, "Screws")], "adv"),
]

RECIPE = """    craftRecipe {name}
    {{
        timedAction     = {action},
        time            = {time},{skill}
        Tags            = AnySurfaceCraft,
        category        = {category},{xp}{learn}
        inputs
        {{
{inputs}
        }}
        outputs
        {{
{outputs}
        }}
    }}
"""


def recipe(name, action, time, skill, xp, inputs, outputs, learn, category="Electrical"):
    return RECIPE.format(name=name, action=action, time=time,
                         skill=("\n        SkillRequired   = %s," % skill) if skill else "",
                         xp=("\n        xpAward         = %s," % xp) if xp else "",
                         learn="\n        NeedToBeLearn   = true," if learn else "", category=category,
                         inputs="\n".join("            %s," % i for i in inputs),
                         outputs="\n".join("            %s," % o for o in outputs))


def main():
    out = ["module Base", "{", "    /* Dazed Power recipes. GENERATED by tools/build_recipes.py -- edit its tables, not this file. */", ""]
    names, basic, adv = {}, [], []
    for kind in T.KINDS:
        for mount in T.MOUNTS[kind]:
            for tier in T.TIERS[kind]:
                r = R[(kind, mount, tier)]
                item = T.item_of(kind, mount, tier)
                disp = T.display_name(kind, mount, tier)
                out.append(recipe("Make" + item, r["action"], r["time"], r["skill"], r["xp"], r["inputs"], ["item 1 Base." + item], r["learn"]))
                names["Make" + item] = "Build " + disp
                if r["learn"] == "basic": basic.append("Make" + item)
                if r["learn"] == "adv": adv.append("Make" + item)
                if r["scrap"]:
                    out.append(recipe("Scrap" + item, "DismantleElectrical", r["scrapTime"], None, r["scrapXp"], [SCREW, destroy(item)], r["scrap"], False))
                    names["Scrap" + item] = "Scrap " + disp
    for name, time, skill, xp, inputs, learn in MISC_RECIPES:
        out.append(recipe("Make" + name, "MakingElectrical", time, skill, xp, inputs, ["item 1 Base." + name], True))
        (basic if learn == "basic" else adv).append("Make" + name)
    out.append("}")
    (MEDIA / "scripts/dazedpower_recipes.txt").write_text("\n".join(out) + "\n", encoding="utf-8")
    names.update({"MakeDazedGearKitLow": "Make Low-Ratio Gear Kit", "MakeDazedGearKitStock": "Make Stock Gear Kit",
                  "MakeDazedGearKitRacing": "Make Racing Gear Kit"})
    tr = MEDIA / "lua/shared/Translate/EN/Recipes.json"
    old = json.loads(tr.read_text(encoding="utf-8")) if tr.exists() else {}
    keep = {k: v for k, v in old.items() if not (k.startswith("MakeDazed") or k.startswith("ScrapDazed"))}
    keep.update(names)
    tr.write_text(json.dumps(keep, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
    write_misc(basic, adv)
    write_lists(basic, adv)
    print("%d recipes; basic handbook teaches %d, advanced %d" % (len(names), len(basic), len(adv)))


def lua_list(names):
    return "{\n" + "".join('    "%s",\n' % n for n in names) + "}"


def write_lists(basic, adv):
    """The handbooks' lists for Lua, and the Makeshift builds the Electrician profession starts knowing."""
    elec = [n for n in basic if "Makeshift" in n]
    body = ("-- Dazed Power recipe lists. GENERATED by tools/build_recipes.py -- edit its tables, not this file.\n"
            "DazedPower = DazedPower or {}\nDazedPower.RecipeLists = {\n"
            "    BASIC = %s,\n    ADVANCED = %s,\n    ELECTRICIAN = %s,\n}\nreturn DazedPower.RecipeLists\n"
            % tuple(lua_list(x).replace("\n", "\n    ").rstrip() for x in (basic, adv, elec)))
    (MEDIA / "lua/shared/DazedPower/DP_RecipeLists.lua").write_text(body, encoding="utf-8")


MISC = """module Base
{{
    /* Dazed Power items that are not world parts. GENERATED by tools/build_recipes.py (the handbooks' recipe
       lists come from its tables). */

    item DazedPowerManual
    {{
        DisplayName         = Dazed Power Handbook,
        DisplayCategory     = RecipeResource,
        ItemType            = base:literature,
        Weight              = 0.5,
        Icon                = DazedPowerManual,
        BoredomChange       = -18,
        StressChange        = -10,
        LearnedRecipes      = {basic},
        StaticModel         = Magazine,
        WorldStaticModel    = MagazineElec1Ground,
        Tags                = base:magazine,
        OnCreate            = ItemCodeOnCreate.onCreateRecipeMagazine,
    }}

    item DazedPowerManualAdv
    {{
        DisplayName         = Workshop Power Systems,
        DisplayCategory     = RecipeResource,
        ItemType            = base:literature,
        Weight              = 0.5,
        Icon                = DazedPowerManualAdv,
        BoredomChange       = -20,
        StressChange        = -12,
        LearnedRecipes      = {adv},
        StaticModel         = Magazine,
        WorldStaticModel    = MagazineElec2Ground,
        Tags                = base:magazine,
        OnCreate            = ItemCodeOnCreate.onCreateRecipeMagazine,
    }}

    item DazedAlmanac
    {{
        DisplayName         = Knox County Almanac,
        DisplayCategory     = RecipeResource,
        ItemType            = base:literature,
        Weight              = 0.4,
        Icon                = DazedAlmanac,
        BoredomChange       = -20,
        StressChange        = -12,
        LearnedRecipes      = DazedPowerSkyReading,
        StaticModel         = Book,
        WorldStaticModel    = BookClosedGround,
        Tags                = base:magazine,
        OnCreate            = ItemCodeOnCreate.onCreateRecipeMagazine,
    }}

    item DazedAmplifier
    {{
        DisplayName         = Generator Amplifier,
        DisplayCategory     = Electronics,
        ItemType            = base:normal,
        Weight              = 1.5,
        Icon                = DazedAmplifier,
        Tooltip             = Tooltip_DazedAmplifier,
        MetalValue          = 40.0,
        Tags                = base:hasmetal,
    }}

    item DazedGearKitLow
    {{
        DisplayName         = Low-Ratio Gear Kit,
        DisplayCategory     = Electronics,
        ItemType            = base:normal,
        Weight              = 3.0,
        Icon                = DazedGearKitLow,
        Tooltip             = Tooltip_DazedGearKitLow,
        Tags                = base:hasmetal,
    }}

    item DazedGearKitStock
    {{
        DisplayName         = Stock Gear Kit,
        DisplayCategory     = Electronics,
        ItemType            = base:normal,
        Weight              = 3.0,
        Icon                = DazedGearKitStock,
        Tooltip             = Tooltip_DazedGearKitStock,
        Tags                = base:hasmetal,
    }}

    item DazedGearKitRacing
    {{
        DisplayName         = Racing Gear Kit,
        DisplayCategory     = Electronics,
        ItemType            = base:normal,
        Weight              = 3.0,
        Icon                = DazedGearKitRacing,
        Tooltip             = Tooltip_DazedGearKitRacing,
        Tags                = base:hasmetal,
    }}
}}
"""


def write_misc(basic, adv):
    (MEDIA / "scripts/dazedpower_misc_items.txt").write_text(MISC.format(basic=";".join(basic), adv=";".join(adv)), encoding="utf-8")


if __name__ == "__main__":
    main()

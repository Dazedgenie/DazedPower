"""Build the sprite sheet, tiledef, part items and icons of Dazed Utilities: Power from the taxonomy.

    python3 tools/build_sheet.py            # writes dazedpower_tiles.tiles(.txt), texturepacks/dazedpower.pack,
                                            # scripts/dazedpower_items.txt, textures/Item_*.png, Moveables/ItemName keys
    python3 tools/build_sheet.py --append   # only adds the rows the committed pack and tiledef lack, on a new page

Art comes from tools/art/<index>.png (128x256 cells named by NEW sprite index) when present, else from the
stand-ins: the two source packs tools/art/src/offgrid.pack and offgridmore.pack (Off-Grid's and More Power's
sheets, renamed), mapped by kind, mount, tier and state. Trackers borrow the static array's art, the 2x2 array
puts a static array on each of its four squares, and Workshop lamps borrow the Makeshift lamp's, until
tools/blender/dp_render.py renders the real ones.
"""
import io, json, re, sys
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent.parent / "DazedCore/tools/pzformat"))
import dp_taxonomy as T  # noqa: E402
from tiledef import TileDefinitions, Tile, Tileset  # noqa: E402
from packfile import TexturePack, PackEntry, PackPage  # noqa: E402

MEDIA = HERE.parent / "common/media"
ART = HERE / "art"
SRC = ART / "src"
CW, CH = 128, 256

# ---------------------------------------------------------------- the old sheets, as stand-in art
OG_KINDS = ["array", "bank", "controller", "transformer", "lamp", "backup"]
OG_MOUNTS = {"array": ["ground", "flat"], "bank": ["ground", "wall"], "controller": ["ground"], "transformer": ["ground"],
             "lamp": ["ground"], "backup": ["ground"]}
OG_TIERS = {"array": ["makeshift", "standard", "premium"], "bank": ["makeshift", "standard", "premium"],
            "controller": ["basic", "mppt"], "transformer": ["standard"], "lamp": ["garden", "street"],
            "backup": ["valutech", "old", "lectromax", "premium"]}
OG_STATES = {"array": ["clear", "snow", "cracked"], "controller": ["off", "on"], "transformer": ["off", "on"],
             "lamp": ["off", "on"], "backup": ["off", "on"]}
OG_CELLS = {"ground": {"makeshift": 3, "standard": 6, "premium": 8}, "wall": {"makeshift": 2, "standard": 3, "premium": 4}}
MP_KINDS = ["pedal", "windmill", "steam", "windsock", "vane", "propane", "petrol"]
MP_TIERS = {k: ["makeshift", "salvaged", "manufactured"] for k in MP_KINDS}
MP_TIERS["windsock"] = MP_TIERS["vane"] = ["basic"]
MP_STATES = {k: T.STATES[k] for k in MP_KINDS}


def old_rows():
    og, mp = {}, {}
    i = 0
    for kind in OG_KINDS:
        for mount in OG_MOUNTS[kind]:
            for tier in OG_TIERS[kind]:
                states = OG_STATES.get(kind) or ["c%d" % c for c in range(OG_CELLS[mount][tier] + 1)]
                for state in states:
                    og[(kind, mount, tier, state)] = i; i += 1
    i = 0
    for kind in MP_KINDS:
        for tier in MP_TIERS[kind]:
            for state in MP_STATES[kind]:
                mp[(kind, "ground", tier, state)] = i; i += 1
    return og, mp


OG_ROW, MP_ROW = old_rows()
OLD_TIER = {"makeshift": "makeshift", "salvaged": "standard", "workshop": "premium"}
OLD_CTRL = {"makeshift": "basic", "workshop": "mppt"}
MP_TIER = {"makeshift": "makeshift", "salvaged": "salvaged", "workshop": "manufactured"}


GAUGE_LED = {"off": (70, 70, 70, 255), "low": (220, 60, 40, 255), "mid": (235, 170, 40, 255), "full": (70, 210, 90, 255)}


def gauge_stand_in(state, facing):
    """A stand-in wall gauge: the Workshop wall cabinet's render at half size, with a lamp showing the state."""
    from PIL import ImageDraw
    src = ART / ("%d.png" % T.sprite_index("bank", "wall", "workshop", "c0", facing))
    out = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    if not src.exists(): return out
    im = Image.open(src).convert("RGBA")
    if im.size != (CW, CH): im = im.resize((CW, CH), Image.LANCZOS)
    bb = im.getbbox()
    if not bb: return out
    part = im.crop(bb)
    small = part.resize((max(1, part.width // 2), max(1, part.height // 2)), Image.LANCZOS)
    cx, cy = (bb[0] + bb[2]) // 2, (bb[1] + bb[3]) // 2
    out.alpha_composite(small, (cx - small.width // 2, cy - small.height // 2))
    ImageDraw.Draw(out).ellipse((cx - 3, cy - 3, cx + 3, cy + 3), fill=GAUGE_LED[state])
    return out


def gauge_icon():
    """A stand-in 32x32 icon: a dark plate with a dial and a green needle."""
    from PIL import ImageDraw
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((3, 4, 28, 27), 4, fill=(88, 92, 96, 255), outline=(40, 42, 44, 255))
    d.pieslice((7, 8, 24, 25), 180, 360, fill=(220, 226, 210, 255))
    d.line((16, 17, 22, 11), fill=(40, 160, 70, 255), width=2)
    d.rectangle((10, 20, 21, 23), fill=(30, 34, 30, 255))
    return im


def tinted(src, tint, strength=0.45):
    """The old cell `src` (a PNG in tools/art) pulled toward `tint`, as a stand-in for a part with no render yet."""
    im = Image.open(src).convert("RGBA")
    if im.size != (CW, CH): im = im.resize((CW, CH), Image.LANCZOS)
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a: px[x, y] = tuple(int(c * (1 - strength) + t * strength) for c, t in zip((r, g, b), tint)) + (a,)
    return im


def rod_stand_in(facing):
    """A stand-in grounding rod: a thin copper pole with a bright tip, the same from every side."""
    from PIL import ImageDraw
    out = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    cx, base = CW // 2, 196
    d.ellipse((cx - 9, base - 4, cx + 9, base + 4), fill=(70, 62, 52, 255))
    d.rectangle((cx - 2, base - 96, cx + 2, base), fill=(176, 108, 58, 255))
    d.rectangle((cx + 1, base - 96, cx + 2, base), fill=(130, 78, 40, 255))
    d.ellipse((cx - 4, base - 102, cx + 4, base - 94), fill=(232, 190, 120, 255))
    return out


def bench_stand_in(state, facing):
    """A stand-in charger bench: the Makeshift battery crate's render with a lamp for its state."""
    from PIL import ImageDraw
    src = ART / ("%d.png" % T.sprite_index("bank", "ground", "makeshift", "c0", facing))
    out = tinted(src, (60, 90, 70), 0.25) if src.exists() else Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    bb = out.getbbox()
    if bb:
        cx, cy = (bb[0] + bb[2]) // 2, bb[1] + (bb[3] - bb[1]) // 3
        ImageDraw.Draw(out).ellipse((cx - 3, cy - 3, cx + 3, cy + 3), fill=(70, 210, 90, 255) if state == "on" else (70, 70, 70, 255))
    return out


def hydro_stand_in(state, facing):
    """A stand-in water wheel: the Makeshift windmill's render pulled toward blue."""
    src = ART / ("%d.png" % T.sprite_index("windmill", "ground", "makeshift", "turning" if state == "turning" else "still", facing))
    return tinted(src, (70, 120, 190), 0.4) if src.exists() else Image.new("RGBA", (CW, CH), (0, 0, 0, 0))


HEATER_BODY = (206, 200, 186)


def heater_stand_in(state, facing):
    """A stand-in floor space heater: a small iso box whose front grille glows orange while it runs."""
    from PIL import ImageDraw
    out = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    hx, hy = (0.30, 0.13) if facing in ("S", "N") else (0.13, 0.30)
    hpx = 46                                        # body height in pixels

    def pt(x, y, z=0):
        return (64 + (x - y) * 64, 224 + (x + y) * 32 - z)

    def shade(c, k):
        return tuple(int(v * k) for v in c) + (255,)
    top = [pt(-hx, -hy, hpx), pt(hx, -hy, hpx), pt(hx, hy, hpx), pt(-hx, hy, hpx)]
    south = [pt(-hx, hy), pt(hx, hy), pt(hx, hy, hpx), pt(-hx, hy, hpx)]
    east = [pt(hx, -hy), pt(hx, hy), pt(hx, hy, hpx), pt(hx, -hy, hpx)]
    d.polygon([pt(-hx - 0.04, -hy - 0.04), pt(hx + 0.04, -hy - 0.04), pt(hx + 0.04, hy + 0.04), pt(-hx - 0.04, hy + 0.04)],
              fill=(40, 40, 40, 90))
    d.polygon(south, fill=shade(HEATER_BODY, 0.82), outline=(70, 66, 60, 255))
    d.polygon(east, fill=shade(HEATER_BODY, 0.66), outline=(70, 66, 60, 255))
    d.polygon(top, fill=shade(HEATER_BODY, 1.0), outline=(70, 66, 60, 255))
    glow = (255, 128, 40, 255) if state == "on" else (58, 54, 50, 255)
    if facing in ("S", "E"):
        # the grille: bars across the front face, inset from its edges
        for i in range(5):
            z = 10 + i * 6
            if facing == "S":
                a, b = pt(-hx * 0.75, hy, z), pt(hx * 0.75, hy, z)
            else:
                a, b = pt(hx, -hy * 0.75, z), pt(hx, hy * 0.75, z)
            d.line([a, b], fill=glow, width=3)
    # the knob and its lamp on the top
    kx, ky = pt(hx * 0.5, 0, hpx)
    d.ellipse((kx - 3, ky - 2, kx + 3, ky + 2), fill=(50, 50, 50, 255))
    lx, ly = pt(-hx * 0.5, 0, hpx)
    d.ellipse((lx - 2, ly - 2, lx + 2, ly + 2), fill=(240, 80, 40, 255) if state == "on" else (80, 80, 80, 255))
    return out


def new_icon(kind):
    """A stand-in 32x32 icon for the grounding rod, the charger bench and the water wheel."""
    from PIL import ImageDraw
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if kind == "heater":
        d.rounded_rectangle((6, 6, 25, 27), 3, fill=HEATER_BODY + (255,), outline=(70, 66, 60, 255))
        for y in range(11, 24, 3): d.line((9, y, 22, y), fill=(255, 128, 40, 255), width=1)
        d.ellipse((19, 7, 23, 10), fill=(50, 50, 50, 255))
        return im
    if kind == "rod":
        d.rectangle((15, 4, 17, 27), fill=(176, 108, 58, 255)); d.ellipse((13, 2, 19, 8), fill=(232, 190, 120, 255))
        d.ellipse((9, 26, 23, 30), fill=(70, 62, 52, 255))
    elif kind == "bench":
        d.rectangle((4, 14, 27, 20), fill=(120, 86, 52, 255)); d.rectangle((6, 20, 8, 28), fill=(80, 58, 36, 255)); d.rectangle((23, 20, 25, 28), fill=(80, 58, 36, 255))
        d.rectangle((9, 8, 16, 14), fill=(60, 64, 70, 255)); d.rectangle((19, 8, 24, 14), fill=(60, 64, 70, 255)); d.ellipse((12, 9, 14, 11), fill=(70, 210, 90, 255))
    else:
        d.ellipse((5, 5, 27, 27), outline=(110, 120, 130, 255), width=3); d.ellipse((13, 13, 19, 19), fill=(70, 120, 190, 255))
        d.line((16, 5, 16, 27), fill=(110, 120, 130, 255), width=2); d.line((5, 16, 27, 16), fill=(110, 120, 130, 255), width=2)
    return im


def stand_in(kind, mount, tier, state, facing, piece):
    """(sheet, old index) of the stand-in cell for a new sprite."""
    f = T.FACINGS.index(facing)
    if kind in ("rod", "bench", "hydro", "heater"):
        return "new", (kind, state, facing)
    if kind == "gauge":
        return "gen", (state, facing)
    if kind == "array":
        return "og", OG_ROW[("array", "ground", OLD_TIER[tier], state)] * 4 + f
    if kind == "bank":
        return "og", OG_ROW[("bank", mount, OLD_TIER[tier], state)] * 4 + f
    if kind == "controller":
        return "og", OG_ROW[("controller", "ground", OLD_CTRL[tier], state)] * 4 + f
    if kind == "transformer":
        return "og", OG_ROW[("transformer", "ground", "standard", state)] * 4 + f
    if kind == "lamp":
        return "og", OG_ROW[("lamp", "ground", mount, state)] * 4 + f
    return "mp", MP_ROW[(kind, "ground", MP_TIER.get(tier, tier), state)] * 4 + f


def old_icon(kind, mount, tier):
    """The old icon file name a new item borrows."""
    og = {("array", "makeshift"): "OffGridArraySalvage", ("array", "salvaged"): "OffGridArray", ("array", "workshop"): "OffGridArrayMono",
          ("bank-ground", "makeshift"): "OffGridBankCrate", ("bank-ground", "salvaged"): "OffGridBank", ("bank-ground", "workshop"): "OffGridBankSealed",
          ("bank-wall", "makeshift"): "OffGridWallCrate", ("bank-wall", "salvaged"): "OffGridWallBank", ("bank-wall", "workshop"): "OffGridWallSealed",
          ("controller", "makeshift"): "OffGridController", ("controller", "workshop"): "OffGridControllerMPPT",
          ("transformer", "standard"): "OffGridTransformer", ("lamp-garden", "makeshift"): "OffGridGardenLamp", ("lamp-garden", "workshop"): "OffGridGardenLamp",
          ("lamp-street", "makeshift"): "OffGridStreetLamp", ("lamp-street", "workshop"): "OffGridStreetLamp",
          ("pedal", "makeshift"): "OffGridPedalMakeshift", ("pedal", "salvaged"): "OffGridPedalSalvaged", ("pedal", "workshop"): "OffGridPedalGen",
          ("windmill", "makeshift"): "OffGridWindMakeshift", ("windmill", "salvaged"): "OffGridWindSalvaged", ("windmill", "workshop"): "OffGridWindTurbine",
          ("steam", "makeshift"): "OffGridSteamMakeshift", ("steam", "salvaged"): "OffGridSteamSalvaged", ("steam", "workshop"): "OffGridSteamEngine",
          ("windsock", "basic"): "OffGridWindsock", ("vane", "basic"): "OffGridWeatherVane",
          ("propane", "makeshift"): "OffGridPropaneMakeshift", ("propane", "salvaged"): "OffGridPropaneSalvaged", ("propane", "workshop"): "OffGridPropaneGen",
          ("petrol", "makeshift"): "OffGridPetrolMakeshift", ("petrol", "salvaged"): "OffGridPetrolSalvaged", ("petrol", "workshop"): "OffGridPetrolGen"}
    key = kind if kind not in ("bank", "lamp") else kind + "-" + mount
    return og[(key, tier)]


# ---------------------------------------------------------------- tile properties
WOOD = {"Material": "WoodPlank", "Material2": "MetalScrap", "MaterialType": "Wood_Solid"}
METAL = {"Material": "MetalPlates", "Material2": "MetalScrap", "MaterialType": "Metal_Large"}
LIGHT_RADIUS = {("garden", "makeshift"): 4, ("garden", "workshop"): 6, ("street", "makeshift"): 12, ("street", "workshop"): 16}
GRID_POS = {1: "0,0", 2: "1,0", 3: "0,1", 4: "1,1"}


def group_of(kind, mount, tier, state):
    """The engine builds one sprite grid per GroupName+CustomName and facing, so each 2x2 state needs its own group."""
    if kind == "array" and mount == "xl" and state != T.states_for(kind, mount, tier)[0]:
        return T.GROUP + " " + state.capitalize()
    return T.GROUP


def tile_props(kind, mount, tier, state, facing, piece, index):
    p = {"CustomName": T.display_name(kind, mount, tier), "GroupName": group_of(kind, mount, tier, state), "Facing": facing,
         "BlocksPlacement": ""}
    wood = (tier == "makeshift" and kind in ("bank", "pedal", "windmill"))
    p.update(WOOD if wood else METAL)
    p.update({"IsMoveAble": "", "CustomItem": "Base." + T.item_of(kind, mount, tier),
              "PickUpWeight": str(int(round(T.WEIGHT[(kind, mount)][tier] * 10))), "PickUpLevel": "0",
              "MoveType": "WallObject" if mount == "wall" else "Object"})
    f = T.FACINGS.index(facing)
    for name, fi in zip(("Eoffset", "Soffset", "Woffset", "Noffset"), range(4)):
        p[name] = str(fi - f)
    if kind == "array":
        p["solidtrans"] = ""; p["ItemHeight"] = "56" if mount != "tracker" else "72"
        if mount == "xl":
            p["SpriteGridPos"] = GRID_POS[piece]; p["ForceSingleItem"] = ""
    elif kind == "bank":
        if mount == "wall": p["IsHigh"] = ""; p["ItemHeight"] = "60"
        else:
            p["solid" if tier == "workshop" else "solidtrans"] = ""; p["ItemHeight"] = "94"
    elif kind == "gauge":
        p["IsHigh"] = ""; p["ItemHeight"] = "60"
    elif kind == "rod":
        p["solidtrans"] = ""; p["ItemHeight"] = "100"
    elif kind == "bench":
        p["solidtrans"] = ""; p["ItemHeight"] = "56"
    elif kind == "hydro":
        p["solidtrans"] = ""; p["ItemHeight"] = "80"
    elif kind == "fence":
        p["solid"] = ""; p["ItemHeight"] = "70"
    elif kind == "cooler":
        p["IsHigh"] = ""; p["ItemHeight"] = "60"
    elif kind == "heater":
        p["solidtrans"] = ""; p["ItemHeight"] = "40"
    elif kind == "controller":
        p["solidtrans"] = ""; p["ItemHeight"] = "88"; p["GeneratorSound"] = "DazedPowerQuiet"
    elif kind == "transformer":
        p["solidtrans"] = ""; p["ItemHeight"] = "88"
    elif kind == "lamp":
        p.update({"lightswitch": "", "lightR": "255", "lightG": "232", "lightB": "196",
                  "LightRadius": str(LIGHT_RADIUS[(mount, tier)])})
    elif kind == "pedal":
        p["solidtrans"] = ""; p["ItemHeight"] = "88"
    else:
        p["solidtrans"] = ""
    return p


# ---------------------------------------------------------------- building
def load_cell(pack, sheet, name):
    pg = pack.pages[0]
    by = {e.name: e for e in pg.entries}
    e = by[name]
    c = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    c.paste(sheet.crop((e.x, e.y, e.x + e.w, e.y + e.h)), (e.ox, e.oy))
    return c


def cell_from_pack(pack, name):
    """One sprite of a multi-page pack back as a full 128x256 cell, or None when the pack lacks it."""
    for pg in pack.pages:
        for e in pg.entries:
            if e.name == name:
                sheet = Image.open(io.BytesIO(pg.png)).convert("RGBA")
                c = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
                c.paste(sheet.crop((e.x, e.y, e.x + e.w, e.y + e.h)), (e.ox, e.oy))
                return c
    return None


def pow2(n):
    """The smallest power of two at least n, at most 2048."""
    p = 1
    while p < n and p < 2048: p *= 2
    return p


def shelf_pages(cells, first=0):
    """Shelf-pack the cells onto as many 2048x2048 pages as they need (tallest first), numbered from `first`."""
    sprites = []
    for n in sorted(cells):
        cell = cells[n]
        bb = cell.getbbox() or (0, 0, 1, 1)
        sprites.append((PackEntry(T.sprite_name(n), 0, 0, bb[2] - bb[0], bb[3] - bb[1], bb[0], bb[1], CW, CH), cell.crop(bb)))
    order = sorted(range(len(sprites)), key=lambda i: -sprites[i][0].h)
    pages, cur = [], None
    x = y = shelf = 0
    for i in order:
        e, im = sprites[i]
        if cur is None or (x + e.w + 2 > 2048 and y + shelf + 2 + e.h + 2 > 2048):
            cur = {"img": Image.new("RGBA", (2048, 2048), (0, 0, 0, 0)), "entries": []}
            pages.append(cur); x = y = shelf = 0
        elif x + e.w + 2 > 2048:
            x, y, shelf = 0, y + shelf + 2, 0
        cur["img"].paste(im, (x, y))
        cur["entries"].append(PackEntry(e.name, x, y, e.w, e.h, e.ox, e.oy, CW, CH))
        x += e.w + 2; shelf = max(shelf, e.h)
    out = []
    for k, pg in enumerate(pages):
        if k == len(pages) - 1:
            # The last page holds only what is left over, so it shrinks to the power-of-two size that fits it.
            used_w = max(e.x + e.w for e in pg["entries"]); used_h = max(e.y + e.h for e in pg["entries"])
            pg["img"] = pg["img"].crop((0, 0, pow2(used_w), pow2(used_h)))
        buf = io.BytesIO(); pg["img"].save(buf, "PNG")
        out.append(PackPage("dazedpower_page%d" % (first + k), buf.getvalue(), pg["entries"], 1))
    return out


def build_pack(cells, out):
    """Pack the cells and write the pack."""
    pk = TexturePack.read(SRC / "offgrid.pack")               # a pack to shape the new one on
    pk.pages = shelf_pages(cells)
    pk.write(out)
    return len(pk.pages)


# Kinds whose only art is the committed pack (no tools/art cells or stand-in yet).
PACK_ONLY = ("fence", "cooler")


def new_cell(kind, state, facing):
    return (rod_stand_in(facing) if kind == "rod" else bench_stand_in(state, facing) if kind == "bench"
            else heater_stand_in(state, facing) if kind == "heater" else hydro_stand_in(state, facing))


def write_tiledef(tiles):
    td = TileDefinitions.read(SRC / "offgrid_tiles.tiles")
    # one tileset per 512 tiles (the engine's limit), 128 rows each
    per = T.SHEET_TILES
    td.tilesets = [Tileset(T.TILESETS[k], T.TILESETS[k] + ".png", T.COLS, len(tiles[k * per:(k + 1) * per]) // T.COLS, k + 1,
                           tiles[k * per:(k + 1) * per]) for k in range((len(tiles) + per - 1) // per)]
    td.write(MEDIA / "dazedpower_tiles.tiles")
    (MEDIA / "dazedpower_tiles.tiles.txt").write_text(td.to_text(), encoding="utf-8")


def append_main():
    """Add only the sheet rows the committed pack and tiledef lack: every existing page and tile stays byte for byte."""
    pack_path = MEDIA / "texturepacks/dazedpower.pack"
    pk = TexturePack.read(pack_path)
    have = {e.name for pg in pk.pages for e in pg.entries}
    old = [t for ts in TileDefinitions.read(MEDIA / "dazedpower_tiles.tiles").tilesets for t in ts.tiles]
    cells, tiles, drift = {}, list(old), 0
    for ri, (kind, mount, tier, state, piece) in enumerate(T.ROWS):
        for fi, facing in enumerate(T.FACINGS):
            n = ri * T.COLS + fi
            props = tile_props(kind, mount, tier, state, facing, piece, n)
            if n < len(old):
                # Kept as it is; a difference only means this script and the committed tiledef disagree.
                if old[n].props != props: drift += 1
                continue
            if T.sprite_name(n) in have: sys.exit("%s is already packed but has no tile" % T.sprite_name(n))
            own = ART / ("%d.png" % n)
            if own.exists():
                im = Image.open(own).convert("RGBA")
                cells[n] = im if im.size == (CW, CH) else im.resize((CW, CH), Image.LANCZOS)
            else:
                sheet, o = stand_in(kind, mount, tier, state, facing, piece)
                if sheet != "new": sys.exit("no art or stand-in for %s/%s" % (kind, state))
                cells[n] = new_cell(*o)
            tiles.append(Tile(props))
    if not cells:
        print("nothing to append"); return
    pk.pages += shelf_pages(cells, len(pk.pages))
    pk.write(pack_path)
    write_tiledef(tiles)
    write_icons(only_missing=True)
    write_items()
    write_translations()
    print("appended %d sprites on a new page; %d existing tiles differ from tile_props (kept)" % (len(cells), drift))


def main():
    og = TexturePack.read(SRC / "offgrid.pack"); og_sheet = Image.open(io.BytesIO(og.pages[0].png)).convert("RGBA")
    mp = TexturePack.read(SRC / "offgridmore.pack"); mp_sheet = Image.open(io.BytesIO(mp.pages[0].png)).convert("RGBA")
    og_stem = og.pages[0].entries[0].name.rsplit("_", 1)[0]
    mp_stem = mp.pages[0].entries[0].name.rsplit("_", 1)[0]
    committed = TexturePack.read(MEDIA / "texturepacks/dazedpower.pack")
    cells, tiles = {}, []
    for ri, (kind, mount, tier, state, piece) in enumerate(T.ROWS):
        for fi, facing in enumerate(T.FACINGS):
            n = ri * T.COLS + fi
            own = ART / ("%d.png" % n)
            if own.exists():
                im = Image.open(own).convert("RGBA")
                if im.size != (CW, CH): im = im.resize((CW, CH), Image.LANCZOS)
                cells[n] = im
            else:
                if kind in PACK_ONLY:
                    cells[n] = cell_from_pack(committed, T.sprite_name(n))
                    if cells[n] is None: sys.exit("%s has no art in the committed pack" % T.sprite_name(n))
                    tiles.append(Tile(tile_props(kind, mount, tier, state, facing, piece, n)))
                    continue
                sheet, old = stand_in(kind, mount, tier, state, facing, piece)
                if sheet == "gen": cells[n] = gauge_stand_in(*old)
                elif sheet == "new": cells[n] = new_cell(*old)
                elif sheet == "og": cells[n] = load_cell(og, og_sheet, "%s_%d" % (og_stem, old))
                else: cells[n] = load_cell(mp, mp_sheet, "%s_%d" % (mp_stem, old))
            tiles.append(Tile(tile_props(kind, mount, tier, state, facing, piece, n)))
    pages = build_pack(cells, MEDIA / "texturepacks/dazedpower.pack")
    write_tiledef(tiles)
    write_icons()
    write_items()
    write_translations()
    print("sheet %dx%d = %d sprites on %d 2048x2048 page(s); %d items" % (T.COLS, len(T.ROWS), len(cells), pages, len(T.all_items())))


def write_icons(only_missing=False):
    """The item icons: own art, else a drawn stand-in, else the old pack's; `only_missing` leaves existing files alone."""
    (MEDIA / "textures").mkdir(exist_ok=True)
    for kind in T.KINDS:
        for mount in T.MOUNTS[kind]:
            for tier in T.TIERS[kind]:
                item = T.item_of(kind, mount, tier)
                own = ART / "icons" / (item + ".png")
                dest = MEDIA / "textures" / ("Item_%s.png" % item)
                if (only_missing or kind in PACK_ONLY) and dest.exists(): continue
                if not own.exists() and kind == "gauge":
                    gauge_icon().save(dest); continue
                if not own.exists() and kind in ("rod", "bench", "hydro", "heater"):
                    new_icon(kind).save(dest); continue
                src = own if own.exists() else SRC / "icons" / ("Item_%s.png" % old_icon(kind, mount, tier))
                Image.open(src).convert("RGBA").save(dest)
    for new, old in (("DazedPowerManual", "OffGridManual"), ("DazedPowerManualAdv", "OffGridManualAdv"), ("DazedAlmanac", "OffGridAlmanac"),
                     ("DazedAmplifier", "OffGridAmplifier"), ("DazedGearKitLow", "OffGridGearKitLow"),
                     ("DazedGearKitStock", "OffGridGearKitStock"), ("DazedGearKitRacing", "OffGridGearKitRacing")):
        own = ART / "icons" / (new + ".png")
        dest = MEDIA / "textures" / ("Item_%s.png" % new)
        if only_missing and dest.exists(): continue
        src = own if own.exists() else SRC / "icons" / ("Item_%s.png" % old)
        Image.open(src).convert("RGBA").save(dest)


ITEM_TEMPLATE = """    item {name}
    {{
        DisplayName         = {display},
        DisplayCategory     = Electronics,
        ItemType            = base:moveable,
        Weight              = {weight},
        Icon                = {icon},
        WorldObjectSprite   = {sprite},
        ConditionMax        = 100,
        MetalValue          = {metal},
        Tooltip             = Tooltip_{tip},{heavy}
        Tags                = {tags},{extra}
    }}
"""


def write_items():
    out = ["module Base", "{",
           "    /* Dazed Power world parts. GENERATED by tools/build_sheet.py from tools/dp_taxonomy.py -- edit the",
           "       taxonomy, not this file. Handbooks, the almanac, gear kits and the amplifier are in dazedpower_misc_items.txt. */", ""]
    for kind in T.KINDS:
        for mount in T.MOUNTS[kind]:
            for tier in T.TIERS[kind]:
                name = T.item_of(kind, mount, tier)
                w = T.WEIGHT[(kind, mount)][tier]
                first = T.states_for(kind, mount, tier)[0]
                sprite = T.sprite_name(T.sprite_index(kind, mount, tier, first, "S"))
                heavy = "\n        RequiresEquippedBothHands = true," if w >= 10 else ""
                tags = ("base:heavyitem;" if w >= 10 else "") + "base:hasmetal;base:showcondition"
                extra = ""
                if kind == "controller":
                    tags += ";base:generator"
                    extra = "\n        ConditionLowerChanceOneIn = 100000,\n        SoundRadius         = 1,\n        SoundVolume         = 1,"
                out.append(ITEM_TEMPLATE.format(name=name, display=T.display_name(kind, mount, tier), weight="%.1f" % w,
                                                icon=name, sprite=sprite, metal="%.1f" % (w * 2.5), tip=name, heavy=heavy,
                                                tags=tags, extra=extra))
                if kind == "controller":
                    # one record per facing and running state keeps the engine's sprite->item map complete (see DP_Parts)
                    for state in ("off", "on"):
                        for facing in T.FACINGS:
                            if state == "off" and facing == "S": continue
                            vname = name + ("On" if state == "on" else "") + ("" if facing == "S" else facing)
                            vs = T.sprite_name(T.sprite_index(kind, mount, tier, state, facing))
                            out.append(ITEM_TEMPLATE.format(name=vname, display=T.display_name(kind, mount, tier), weight="%.1f" % w,
                                                            icon=name, sprite=vs, metal="%.1f" % (w * 2.5), tip=name, heavy="",
                                                            tags=tags, extra=extra))
    out.append("}")
    (MEDIA / "scripts/dazedpower_items.txt").write_text("\n".join(out) + "\n", encoding="utf-8")


def write_translations():
    tr = MEDIA / "lua/shared/Translate/EN"
    names = json.loads((tr / "ItemName.json").read_text(encoding="utf-8")) if (tr / "ItemName.json").exists() else {}
    moves = json.loads((tr / "Moveables.json").read_text(encoding="utf-8")) if (tr / "Moveables.json").exists() else {}
    names = {k: v for k, v in names.items() if not k.startswith("Base.Dazed") or k.split(".")[1] in T.OTHER_ITEMS}
    moves = {k: v for k, v in moves.items() if not k.startswith("Dazed_Power_")}
    for kind in T.KINDS:
        for mount in T.MOUNTS[kind]:
            for tier in T.TIERS[kind]:
                item, disp = T.item_of(kind, mount, tier), T.display_name(kind, mount, tier)
                names["Base." + item] = disp
                if kind == "controller":
                    for suffix in ("E", "W", "N", "On", "OnE", "OnW", "OnN"): names["Base." + item + suffix] = disp
                for state in T.states_for(kind, mount, tier):
                    moves[(group_of(kind, mount, tier, state) + " " + disp).replace(" ", "_")] = disp
    (tr / "ItemName.json").write_text(json.dumps(names, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
    (tr / "Moveables.json").write_text(json.dumps(moves, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    append_main() if "--append" in sys.argv[1:] else main()

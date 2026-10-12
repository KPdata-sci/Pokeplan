"""Pack the pictures the dashboard shows into two sprite sheets.

Usage: python3 build_sprites.py <sprites checkout> [max_dex]

<sprites checkout> is a clone of github.com/PokeAPI/sprites; only two folders
are read, so a sparse checkout of these is enough:
  sprites/pokemon/other/official-artwork/<dex>.png   -> sprites.webp
  sprites/items/<item-code>.png                       -> items.png

Each sheet uses one treatment for every picture so they look alike:
  Pokémon  official artwork, empty border trimmed, scaled to fill the same
           square and centred. Tile n (dex number n) is at column (n-1) % COLS,
           row (n-1) // COLS.
  Items    the games' bag icons (pixel art), centred on a 32 px tile with no
           resampling; the page doubles them with crisp pixels. Tile order is
           the "codes" list in sprites.json.
"""
import json, pathlib, sys
from PIL import Image

TILE, PAD, COLS = 128, 6, 32
ITEM_TILE, ITEM_COLS = 32, 32

root = pathlib.Path(sys.argv[1])
max_dex = int(sys.argv[2]) if len(sys.argv) > 2 else 1025
here = pathlib.Path(__file__).parent

# Pokémon
art = root / "sprites/pokemon/other/official-artwork"
sheet = Image.new("RGBA", (COLS * TILE, -(-max_dex // COLS) * TILE), (0, 0, 0, 0))
inner = TILE - 2 * PAD
for n in range(1, max_dex + 1):
    im = Image.open(art / f"{n}.png").convert("RGBA")
    im = im.crop(im.getchannel("A").getbbox())
    scale = inner / max(im.size)
    im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
    x = (n - 1) % COLS * TILE + (TILE - im.width) // 2
    y = (n - 1) // COLS * TILE + (TILE - im.height) // 2
    sheet.alpha_composite(im, (x, y))
sheet.save(here / "sprites.webp", "WEBP", quality=78, method=6)

# Items
files = sorted((root / "sprites/items").glob("*.png"))
codes = []
isheet = Image.new("RGBA", (ITEM_COLS * ITEM_TILE, -(-len(files) // ITEM_COLS) * ITEM_TILE), (0, 0, 0, 0))
for f in files:
    im = Image.open(f).convert("RGBA")
    box = im.getchannel("A").getbbox()
    if not box:
        continue
    im = im.crop(box)
    if max(im.size) > ITEM_TILE:  # a few icons are bigger than the tile: shrink, keep pixels crisp
        k = ITEM_TILE / max(im.size)
        im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.NEAREST)
    i = len(codes)
    x = i % ITEM_COLS * ITEM_TILE + (ITEM_TILE - im.width) // 2
    y = i // ITEM_COLS * ITEM_TILE + (ITEM_TILE - im.height) // 2
    isheet.alpha_composite(im, (x, y))
    codes.append(f.stem)
isheet = isheet.crop((0, 0, isheet.width, -(-len(codes) // ITEM_COLS) * ITEM_TILE))
isheet.save(here / "items.png", optimize=True)

(here / "sprites.json").write_text(json.dumps({
    "tile": TILE, "cols": COLS, "count": max_dex,
    "items": {"tile": ITEM_TILE, "cols": ITEM_COLS, "codes": codes},
}, separators=(",", ":")))
for f in ("sprites.webp", "items.png"):
    print(f, (here / f).stat().st_size)

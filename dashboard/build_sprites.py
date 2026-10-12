"""Pack the official artwork for every species into one sprite sheet, sprites.webp.

Usage: python3 build_sprites.py <path to sprites/pokemon/other/official-artwork> [max_dex]

The artwork comes from github.com/PokeAPI/sprites (sparse-checkout that folder).
Every picture gets the same treatment so they look alike on the page: the empty
border is trimmed, the Pokémon is scaled to fill the same square, and it is
centred on a transparent tile. Tile n (dex number n) sits at column (n-1) % COLS,
row (n-1) // COLS. The page reads TILE and COLS from the data blob.
"""
import json, pathlib, sys
from PIL import Image

TILE, PAD, COLS = 128, 6, 32

src = pathlib.Path(sys.argv[1])
max_dex = int(sys.argv[2]) if len(sys.argv) > 2 else 1025
here = pathlib.Path(__file__).parent
rows = -(-max_dex // COLS)
sheet = Image.new("RGBA", (COLS * TILE, rows * TILE), (0, 0, 0, 0))
inner = TILE - 2 * PAD
for n in range(1, max_dex + 1):
    im = Image.open(src / f"{n}.png").convert("RGBA")
    im = im.crop(im.getchannel("A").getbbox())
    scale = inner / max(im.size)
    im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
    x = (n - 1) % COLS * TILE + (TILE - im.width) // 2
    y = (n - 1) // COLS * TILE + (TILE - im.height) // 2
    sheet.alpha_composite(im, (x, y))
out = here / "sprites.webp"
sheet.save(out, "WEBP", quality=78, method=6)
(here / "sprites.json").write_text(json.dumps({"tile": TILE, "cols": COLS, "count": max_dex}))
print(out, out.stat().st_size)

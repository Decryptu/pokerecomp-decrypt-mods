#!/usr/bin/env python3
"""Carries a painting from the houses that have been done to the ones that have not.

    tools/house_learn.py <houses.json> [out.json]

Ninety per cent of the houses left are layouts already painted. The reviewer
asked for this after twenty-seven of them and they were right to: the game draws
its buildings out of a small vocabulary of 8px tiles, and A TILE ID ON ONE
TILESET IS ALWAYS THE SAME PICTURE, so how a person painted it once is how it
should be painted everywhere it means the same thing.

WHAT IS TRANSFERRED IS THE 8x8 BLOCK, not a word, so a tile the painting cuts
diagonally carries its diagonal with it. That is the whole reason this works at
all: at tile resolution there would be nothing to copy that was worth copying.

MEANING IS NOT THE TILE, IT IS THE TILE IN ITS PLACE, which is the trap the
reference wrote down and this repository repeats: one id is the awning course of
one house and the eave of another. So a match is looked for in this order, and
the first that answers UNANIMOUSLY wins:

    1. a whole REGION of one painted drawing, tile for tile, wherever it sits
       inside this one. A house plus a extra column is the same house.
    2. the tile with its four neighbours
    3. the tile with the one above and the one below
    4. the tile with the one above, then with the one below
    5. the tile alone
    6. the tile alone, by majority, which is the only step that can be outvoted

MEASURED BEFORE IT WAS SHIPPED, by holding each painted drawing out and
predicting it from the other twenty-six: 1343 tiles predicted, 98% of them exact,
629 tiles fixed that the automatic pre-fill had wrong and 13 broken that it had
right. Re-run that check with `--check` after any change to the ladder above.

NOTHING PAINTED BY HAND IS TOUCHED. A drawing whose paint differs from its own
pre-fill is one a person has worked on, and it is only ever read FROM.

The result is a `houses.json` with the same shape, so it goes straight back into
`tools/house_page.py <dir> <out.json>` and on into `tools/house_pins.gd`.
"""

import json
import pathlib
import sys
from collections import Counter, defaultdict

TILE = 8
## How many keys the ladder has. The last is the only one allowed a majority.
LEVELS = 5


def block(house, row, column, field="paint"):
    """The 8x8 paint of one tile, as a tuple of eight strings."""
    return tuple(house[field][row * TILE + y][column * TILE:(column + 1) * TILE]
                 for y in range(TILE))


def ladder(house, row, column):
    """The keys a tile is looked up by, most specific first."""
    grid = house["tiles"]
    ts = house["tileset"]
    tile = grid[row][column]
    up = grid[row - 1][column] if row > 0 else -1
    down = grid[row + 1][column] if row + 1 < len(grid) else -1
    left = grid[row][column - 1] if column > 0 else -1
    right = grid[row][column + 1] if column + 1 < len(grid[0]) else -1
    return [(ts, tile, up, down, left, right), (ts, tile, up, down),
            (ts, tile, up), (ts, tile, down), (ts, tile)]


def learn(pool):
    tables = [defaultdict(Counter) for _ in range(LEVELS)]
    for house in pool:
        for row in range(len(house["tiles"])):
            for column in range(len(house["tiles"][0])):
                painted = block(house, row, column)
                for level, key in enumerate(ladder(house, row, column)):
                    tables[level][key][painted] += 1
    return tables


def regions(house, pool, filled):
    """Whole painted drawings found tile for tile inside this one."""
    high, wide = len(house["tiles"]), len(house["tiles"][0])
    for other in pool:
        oh, ow = len(other["tiles"]), len(other["tiles"][0])
        if oh > high or ow > wide:
            continue
        for oy in range(high - oh + 1):
            for ox in range(wide - ow + 1):
                if any(other["tiles"][r][c] != house["tiles"][oy + r][ox + c]
                       for r in range(oh) for c in range(ow)):
                    continue
                for r in range(oh):
                    for c in range(ow):
                        filled.setdefault((oy + r, ox + c), block(other, r, c))


def predict(house, pool, tables):
    filled = {}
    regions(house, pool, filled)
    for row in range(len(house["tiles"])):
        for column in range(len(house["tiles"][0])):
            if (row, column) in filled:
                continue
            for level, key in enumerate(ladder(house, row, column)):
                found = tables[level].get(key)
                if found and len(found) == 1:
                    filled[(row, column)] = next(iter(found))
                    break
            else:
                # The one step that can be outvoted, and the one that earns the
                # last half of the coverage. Measured worth it: it predicts 53
                # more tiles per held-out drawing and gets 5 of them wrong.
                found = tables[LEVELS - 1].get((house["tileset"],
                                                house["tiles"][row][column]))
                if found:
                    filled[(row, column)] = found.most_common(1)[0][0]
    return filled


def apply(house, filled):
    """The painting with every predicted tile written into it."""
    rows = [list(r) for r in house["paint"]]
    for (row, column), painted in filled.items():
        for y in range(TILE):
            for x in range(TILE):
                rows[row * TILE + y][column * TILE + x] = painted[y][x]
    return ["".join(r) for r in rows]


def check(touched):
    """Hold each painted drawing out and predict it from the others."""
    tiles = right = wrong = fixed = broke = 0
    for index, house in enumerate(touched):
        pool = touched[:index] + touched[index + 1:]
        for (row, column), painted in predict(house, pool, learn(pool)).items():
            tiles += 1
            truth = block(house, row, column)
            before = block(house, row, column, "guess")
            if painted == truth:
                right += 1
            else:
                wrong += 1
                if before == truth:
                    broke += 1
            if before != truth and painted == truth:
                fixed += 1
    print("held out one drawing at a time, predicted from the other %d:"
          % (len(touched) - 1))
    print("  %d tiles predicted, %d exact (%.0f%%), %d wrong"
          % (tiles, right, 100.0 * right / max(tiles, 1), wrong))
    print("  %d tiles fixed that the automatic pre-fill had wrong" % fixed)
    print("  %d tiles broken that it had right" % broke)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    source = pathlib.Path(sys.argv[1])
    saved = json.loads(source.read_text())
    if saved.get("unit") != "pixel":
        print("unexpected unit %r: this reads pixel only" % saved.get("unit"))
        return 1
    houses = saved["houses"]
    touched = [h for h in houses if h["paint"] != h["guess"]]
    untouched = [h for h in houses if h["paint"] == h["guess"]]
    if not touched:
        print("nothing painted yet, so there is nothing to carry")
        return 1
    print("%d drawings painted, %d not" % (len(touched), len(untouched)))

    if "--check" in sys.argv:
        check(touched)
        return 0

    tables = learn(touched)
    carried = 0
    tiles = 0
    total = 0
    for house in untouched:
        filled = predict(house, touched, tables)
        wide = len(house["tiles"][0]) * len(house["tiles"])
        total += wide
        if not filled:
            continue
        house["paint"] = apply(house, filled)
        house["seeded"] = True
        tiles += len(filled)
        if house["paint"] != house["guess"]:
            carried += 1
    print("carried into %d of the %d untouched drawings, %d of their %d tiles "
          "(%.0f%%)" % (carried, len(untouched), tiles, total,
                        100.0 * tiles / max(total, 1)))
    print("covering %d more placements"
          % sum(h["placements"] for h in untouched if h.get("seeded")))
    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 \
        else source.with_name("houses_carried.json")
    out.write_text(json.dumps(saved))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())

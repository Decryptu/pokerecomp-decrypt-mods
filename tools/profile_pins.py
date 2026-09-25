#!/usr/bin/env python3
"""Edits a generation's `shape/gen<n>/profile.gd` TILESETS table in place.

The table is a dictionary literal and a hand edit that wraps a long list wrong
does not parse, so this parses it, changes it and writes it back the way
`pass_pins.py` lays lists out.

    tools/profile_pins.py <1|2> show [tileset]
    tools/profile_pins.py <1|2> set <tileset> <class> [tile ...]   the whole list; none removes it
    tools/profile_pins.py <1|2> add <tileset> <class> <tile ...>
    tools/profile_pins.py <1|2> drop <tileset> <tile ...>          out of every class it is in

A tileset is its cartridge name, `POKECENTER`, the same on every cache.
"""

import pathlib
import re
import sys

WIDTH = 88


def path(generation):
    return pathlib.Path(__file__).resolve().parent.parent \
        / ("mods/voxel3d/shape/gen%s/profile.gd" % generation)


def parse(text):
    start = text.index("const TILESETS: Dictionary = {")
    end = text.index("\n}\n", start) + 3
    table = {}
    tileset = None
    for found in re.finditer(r'\n\t&"([A-Z_0-9]+)": \{|&"([a-z_0-9]+)": \[([^\]]*)\]', text[start:end]):
        if found.group(1):
            tileset = found.group(1)
            table[tileset] = {}
        else:
            table[tileset][found.group(2)] = list(dict.fromkeys(
                int(t) for t in re.findall(r"\d+", found.group(3))
            ))
    return text[:start], table, text[end:]


def serialise(table):
    lines = ["const TILESETS: Dictionary = {"]
    for tileset in table:
        pins = {name: tiles for name, tiles in table[tileset].items() if tiles}
        if not pins:
            continue
        lines.append('\t&"%s": {' % tileset)
        for name in pins:
            lines.extend(_list_lines(name, pins[name]))
        lines.append("\t},")
    lines.append("}")
    return "\n".join(lines) + "\n"


def _list_lines(name, tiles):
    line = '\t\t&"%s": [%s],' % (name, ", ".join(str(t) for t in tiles))
    if len(line.expandtabs(4)) <= WIDTH:
        return [line]
    out = ['\t\t&"%s": [' % name]
    row = "\t\t\t"
    for tile in tiles:
        if len(row.expandtabs(4)) + len(str(tile)) + 2 > WIDTH:
            out.append(row.rstrip())
            row = "\t\t\t"
        row += "%d, " % tile
    out.append(row.rstrip())
    out.append("\t\t],")
    return out


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("1", "2"):
        print(__doc__)
        return 1
    target = path(sys.argv[1])
    head, table, tail = parse(target.read_text())
    command = sys.argv[2]
    if command == "show":
        for tileset in sorted(table):
            if len(sys.argv) > 3 and tileset != sys.argv[3]:
                continue
            print(tileset, table[tileset])
        return 0
    tileset = sys.argv[3]
    pins = table.setdefault(tileset, {})
    if command == "set":
        pins[sys.argv[4]] = list(dict.fromkeys(int(t) for t in sys.argv[5:]))
    elif command == "add":
        pins[sys.argv[4]] = list(dict.fromkeys(
            pins.get(sys.argv[4], []) + [int(t) for t in sys.argv[5:]]
        ))
    elif command == "drop":
        gone = {int(t) for t in sys.argv[4:]}
        for name in list(pins):
            pins[name] = [t for t in pins[name] if t not in gone]
    else:
        print(__doc__)
        return 1
    target.write_text(head + serialise(table) + tail)
    return 0


if __name__ == "__main__":
    sys.exit(main())

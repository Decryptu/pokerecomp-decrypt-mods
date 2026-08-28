#!/usr/bin/env python3
"""Fails on code that is too long, too branchy or too commented.

New code meets the ceilings. What was already over them is listed in
`bloat_debt.txt`, which may only ever shrink: a function on that list that now
passes must come off it, and one that is not on it may not go over. So the debt
is paid down and never added to.

`--top N` ranks the worst without failing. `--debt` rewrites the list, which is
only correct when the entries it drops were genuinely fixed.
"""
import argparse, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEBT = pathlib.Path(__file__).with_name("bloat_debt.txt")


def named(path):
    """Repo-relative, so a debt entry means the same however the path arrived."""
    try:
        return pathlib.Path(path).resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path

CC_MAX = 10
LEN_MAX = 60
COMMENT_MAX = 8
# Below this many comment lines a file is short enough that the ratio lies.
COMMENT_FLOOR = 15

BRANCH = re.compile(r"\b(?:if|elif|for|while|and|or)\b")
FUNC = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)")


def code_of(line):
    out, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c in "\"'":
            quote, i = c, i + 1
            while i < n and line[i] != quote:
                i += 2 if line[i] == "\\" else 1
            i += 1
            continue
        if c == "#":
            break
        out.append(c)
        i += 1
    return "".join(out)


def functions(lines):
    found, current = [], None
    for number, raw in enumerate(lines, 1):
        code = code_of(raw)
        named = FUNC.match(code)
        if named:
            if current:
                found.append(current)
            current = {"name": named.group(1), "line": number, "cc": 1, "len": 1}
            continue
        if not current:
            continue
        if raw.strip():
            current["len"] = number - current["line"] + 1
        current["cc"] += len(BRANCH.findall(code))
    if current:
        found.append(current)
    return found


def scan(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    comments = sum(1 for line in lines if line.lstrip().startswith("#"))
    ratio = round(100 * comments / max(len(lines), 1))
    return comments, ratio, functions(lines)


def main():
    parse = argparse.ArgumentParser()
    parse.add_argument("--top", type=int, default=0)
    parse.add_argument("--debt", action="store_true")
    parse.add_argument("paths", nargs="*")
    args = parse.parse_args()
    paths = args.paths or subprocess.run(
        ["git", "ls-files", "*.gd"], capture_output=True, text=True
    ).stdout.split()

    breaches, ranked, over = [], [], set()
    for full in paths:
        path = named(full)
        comments, ratio, found = scan(full)
        if ratio > COMMENT_MAX and comments > COMMENT_FLOOR:
            breaches.append((path, f"{path}: {ratio}% comment lines, over {COMMENT_MAX}%"))
        for one in found:
            key = f"{path}:{one['name']}"
            where = f"{path}:{one['line']} {one['name']}"
            ranked.append((one["cc"], one["len"], where))
            if one["cc"] > CC_MAX:
                breaches.append((key, f"{where}: complexity {one['cc']}, ceiling {CC_MAX}"))
            if one["len"] > LEN_MAX:
                breaches.append((key, f"{where}: {one['len']} lines, ceiling {LEN_MAX}"))
            if one["cc"] > CC_MAX or one["len"] > LEN_MAX:
                over.add(key)

    if args.top:
        for cc, length, where in sorted(ranked, reverse=True)[: args.top]:
            print(f"{cc:4} {length:4}  {where}")
        return 0

    if args.debt:
        DEBT.write_text("".join(f"{one}\n" for one in sorted(over)))
        print(f"{DEBT.name}: {len(over)} functions")
        return 0

    listed = set(DEBT.read_text().split()) if DEBT.exists() else set()
    unpaid = [text for key, text in breaches if key not in listed]
    # A partial scan cannot tell a function it did not read from a fixed one.
    paid = [] if args.paths else sorted(listed - over)
    for text in unpaid:
        print(text)
    for key in paid:
        print(f"{key}: under the ceiling now; run tools/bloat.py --debt")
    return 1 if unpaid or paid else 0


sys.exit(main())

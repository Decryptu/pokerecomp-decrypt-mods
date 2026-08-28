#!/usr/bin/env python3
"""Fails on code that is too long, too branchy or too commented.

Ceilings are per function and per file. `--list` prints every breach instead of
the first, and `--top N` ranks the worst without failing.
"""
import argparse, re, subprocess, sys

CC_MAX = 10
LEN_MAX = 60
COMMENT_MAX = 8
## Below this many comment lines a file is short enough that the ratio lies.
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
	parse.add_argument("paths", nargs="*")
	args = parse.parse_args()
	paths = args.paths or subprocess.run(
		["git", "ls-files", "*.gd"], capture_output=True, text=True
	).stdout.split()

	breaches, ranked = [], []
	for path in paths:
		comments, ratio, found = scan(path)
		if ratio > COMMENT_MAX and comments > COMMENT_FLOOR:
			breaches.append(f"{path}: {ratio}% comment lines, ceiling {COMMENT_MAX}%")
		for one in found:
			where = f"{path}:{one['line']} {one['name']}"
			ranked.append((one["cc"], one["len"], where))
			if one["cc"] > CC_MAX:
				breaches.append(f"{where}: complexity {one['cc']}, ceiling {CC_MAX}")
			if one["len"] > LEN_MAX:
				breaches.append(f"{where}: {one['len']} lines, ceiling {LEN_MAX}")

	if args.top:
		for cc, length, where in sorted(ranked, reverse=True)[: args.top]:
			print(f"{cc:4} {length:4}  {where}")
		return 0
	for line in breaches:
		print(line)
	return 1 if breaches else 0


sys.exit(main())

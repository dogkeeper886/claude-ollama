#!/usr/bin/env python3
"""Check config files against the shape in CONF.template beside this script.

Each line is blank, a comment or key=value. Blank lines split the file into
groups. A group opens with one comment, "# <key pattern>: <options>", whose
later lines continue it indented "#   ", and then holds its keys. Each key
matches the group's pattern and appears once. When the options open with a
list such as "on | off", each value is one of them.

Usage: python3 check-conf.py [file ...]   (no files: every .conf file in the repo)
Prints each error as <file>:<line>: <message>, and exits 1 when there is any.
"""
import os
import re
import sys

# Importing gitrepo would otherwise leave a __pycache__ folder in the repo.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gitrepo import repo_files, repo_root  # noqa: E402

KEY_LINE = re.compile(r"^([^\s=#]+)=(.*)$")
HEADER = re.compile(r"^# (\S+): (\S.*)$")
CONTINUATION = re.compile(r"^#   \S")
# An option may hold a dot only inside it, so "on | off." ends at "off".
OPTION = r"[\w-]+(?:\.[\w-]+)*"
OPTIONS = re.compile(rf"^({OPTION}(?: \| {OPTION})+)(?:[.,;]|$)")
PLACEHOLDER = re.compile(r"<[^<>]+>")


def key_regex(pattern):
    """A key pattern as a regex: each <placeholder> stands for a run of non-space characters."""
    return re.compile("^" + r"[^\s=]+".join(re.escape(p) for p in PLACEHOLDER.split(pattern)) + "$")


def groups_of(lines):
    groups, current = [], []
    for n, line in enumerate(lines, 1):
        if line.strip():
            current.append((n, line))
        elif current:
            groups.append(current)
            current = []
    if current:
        groups.append(current)
    return groups


def check(path):
    errors = []
    seen = {}
    with open(path, errors="replace") as f:
        lines = f.read().splitlines()
    for group in groups_of(lines):
        key_start = next((i for i, (_, line) in enumerate(group) if not line.startswith("#")), len(group))
        comments, keys = group[:key_start], group[key_start:]
        pattern = pattern_text = options = None
        if not comments:
            errors.append((group[0][0], "keys with no comment above them; open the group with '# <key pattern>: <options>'"))
        else:
            n, first = comments[0]
            m = HEADER.match(first)
            if m:
                pattern_text, pattern = m.group(1), key_regex(m.group(1))
                listed = OPTIONS.match(m.group(2))
                options = listed.group(1).split(" | ") if listed else None
            else:
                errors.append((n, "a group's comment opens with '# <key pattern>: <options>'"))
            for n, line in comments[1:]:
                if not CONTINUATION.match(line):
                    errors.append((n, "a comment's later lines continue it, indented '#   '"))
            if not keys:
                errors.append((comments[0][0], "a comment with no keys below it"))
        for n, line in keys:
            if line.startswith("#"):
                errors.append((n, "a comment below a key; comments go only above a group's keys"))
                continue
            m = KEY_LINE.match(line)
            if not m:
                errors.append((n, "not key=value, with no space in the key or around '='"))
                continue
            key, value = m.groups()
            if key in seen:
                errors.append((n, f"{key} repeats line {seen[key]}"))
            else:
                seen[key] = n
            if pattern and not pattern.match(key):
                errors.append((n, f"{key} doesn't match the group's pattern {pattern_text}"))
            if not value:
                errors.append((n, f"{key} has no value"))
            elif re.search(r"\s#", value):
                errors.append((n, f"{key}'s value holds a comment; comments go only above a group's keys"))
            elif value != value.strip():
                errors.append((n, f"{key}'s value has spaces around it"))
            elif options and value not in options:
                errors.append((n, f"{key}={value}: the options are {' | '.join(options)}"))
    return sorted(errors)


def main():
    if sys.argv[1:]:
        paths = sys.argv[1:]
    else:
        root = repo_root()
        paths = [os.path.relpath(os.path.join(root, p)) for p in repo_files(root, "*.conf")]
        if not paths:
            print(f"{root}: no .conf files")
    failed = False
    for path in paths:
        errors = check(path)
        for n, message in errors:
            print(f"{path}:{n}: {message}")
        if errors:
            failed = True
        else:
            print(f"{path}: ok")
    sys.exit(1 if failed else 0)


main()

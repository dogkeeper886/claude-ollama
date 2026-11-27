#!/usr/bin/env python3
"""Keep DOCS-MAP.md, the map of a repo's Markdown and config files, in step with the repo.

With no map, it creates one from DOCS-MAP.template.md beside this script. With a
map, it checks that the map holds only the template's fields in the template's
format; on any error it prints the errors and exits 1 without writing. It then
appends an entry for each .md or .conf file the map lacks, and prints the appended,
gone and unfilled entries, plus live checks for each file the map already held.

Usage: python3 map-docs.py [dir]   (dir defaults to the current directory)
"""
import os
import re
import subprocess
import sys
from datetime import datetime

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "DOCS-MAP.template.md")
MAP = "DOCS-MAP.md"
# Fields the script drafts and checks; the template may add others, which start as placeholders.
PURPOSE, STALE, DRIFTS = "purpose", "stale when", "drifts when these change"
ITEM = re.compile(r"^( *)- (.*)$")
KEYED = re.compile(r"^([^:]+):(?: (.*))?$")
PLACEHOLDER = re.compile(r"^<.*>$")
# A file reference: a code span or a link target that holds a slash or a file extension.
REF = re.compile(r"`([^`\s]+)`|\]\(([^)\s#]+)")
PATHLIKE = re.compile(r"/|\.\w{1,5}$")


def run(cmd):
    # stdout/stderr/universal_newlines rather than capture_output/text: RHEL 8 ships Python 3.6.
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=True).stdout


start = sys.argv[1] if len(sys.argv) > 1 else "."
ROOT = run(["git", "-C", start, "rev-parse", "--show-toplevel"]).strip()
if not ROOT:
    sys.exit(f"{start} is not inside a git repo")


def git(*args):
    return run(["git", "-C", ROOT, *args])


def paths(out):
    return {p for p in out.split("\0") if p}


def read(path):
    with open(os.path.join(ROOT, path), errors="replace") as f:
        return f.read()


def last_commit(path):
    t = git("log", "-1", "--format=%ct", "--", path).strip()
    return int(t) if t else None


def day(ts):
    return datetime.fromtimestamp(ts).strftime("%Y-%m-%d")


def heading(text):
    lines = text.splitlines()
    if lines and lines[0] == "---":  # skip frontmatter
        end = next((i for i, l in enumerate(lines[1:], 1) if l == "---"), 0)
        lines = lines[end + 1:]
    first = next((l[2:].strip() for l in lines if l.startswith("# ")), None)
    return first or next((l.strip() for l in lines if l.strip()), "(empty)")


def checkboxes(text):
    return (len(re.findall(r"^\s*[-*] \[ \]", text, re.M)),
            len(re.findall(r"^\s*[-*] \[[xX]\]", text, re.M)))


def refs(doc, text):
    """Each file reference in text, mapped to its repo path, or to None when no such file exists."""
    found = {}
    for m in REF.finditer(text):
        r = (m.group(1) or m.group(2)).rstrip(".,:;")
        if not r or "://" in r or r[0] in "~$-<" or not PATHLIKE.search(r):
            continue
        for base in (ROOT, os.path.join(ROOT, os.path.dirname(doc))):
            p = os.path.normpath(os.path.join(base, r))
            if os.path.exists(p):
                found[r] = os.path.relpath(p, ROOT)
                break
        else:
            found[r] = None
    return found


def nested(key, values, pad):
    if not values:
        return [f"{pad}- {key}: none"]
    return [f"{pad}- {key}:"] + [f"{pad}  - {v}" for v in values]


def read_template():
    """The template's fields in order, as [key, takes nested items, placeholder]."""
    fields = []
    with open(TEMPLATE) as f:
        for line in f.read().splitlines():
            m = ITEM.match(line)
            if m and len(m.group(1)) == 2:
                key, value = KEYED.match(m.group(2)).groups()
                fields.append([key, value is None, value])
            elif m and len(m.group(1)) == 4:
                fields[-1][2] = m.group(2)
    return fields


def parse_map(text, fields):
    """The map's entries by path, and its format errors against the template."""
    keys = [f[0] for f in fields]
    lists = {f[0] for f in fields if f[1]}
    entries, errors = {}, []
    entry, last, open_list = None, None, None

    def close():
        if entry is None:
            return
        for k in keys:
            if k not in entry:
                errors.append(f"line {entry['_line']}: {entry['path']} lacks the field {k}")
            elif entry[k] == []:
                errors.append(f"line {entry['_line']}: {entry['path']}: {k} needs nested items or none")

    for n, line in enumerate(text.splitlines(), 1):
        m = ITEM.match(line)
        indent = len(m.group(1)) if m else None
        if not line.strip():
            errors.append(f"line {n}: blank line")
            continue
        if indent not in (0, 2, 4):
            errors.append(f"line {n}: not a list item at an indent of 0, 2 or 4 spaces")
            continue
        km = KEYED.match(m.group(2))
        if indent == 0:
            close()
            entry, last, open_list = None, None, None
            if not km or km.group(1) != "path" or not km.group(2):
                errors.append(f"line {n}: an entry starts with '- path: <file>'")
            elif km.group(2) in entries:
                errors.append(f"line {n}: {km.group(2)} has a second entry")
            else:
                entry = {"path": km.group(2), "_line": n}
                entries[entry["path"]] = entry
        elif indent == 2:
            open_list = None
            if entry is None:
                errors.append(f"line {n}: a field outside an entry")
                continue
            k = km.group(1) if km else m.group(2)
            value = (km.group(2) or "").strip() if km else ""
            if k not in keys:
                errors.append(f"line {n}: '{k}' is not a field; the template allows: {', '.join(keys)}")
                continue
            if k in entry:
                errors.append(f"line {n}: {k} appears twice in {entry['path']}")
                continue
            # A misplaced or misshapen field still counts as present, so it isn't also reported missing.
            if last and keys.index(k) < keys.index(last):
                errors.append(f"line {n}: {k} comes before {last} in the template")
            if k in lists and value not in ("", "none"):
                errors.append(f"line {n}: {k} takes nested items or none, not a value")
            elif k not in lists and not value:
                errors.append(f"line {n}: {k} needs a value")
            entry[k] = [] if k in lists and not value else value
            open_list = entry[k] if isinstance(entry[k], list) else None
            last = k
        elif open_list is None:
            errors.append(f"line {n}: a nested item outside a list field")
        else:
            open_list.append(m.group(2).strip())
    close()
    errors.sort(key=lambda e: int(e.split()[1].rstrip(":")))
    return entries, errors


def draft(doc, fields):
    """A new entry for doc, in the template's order, with what the script can fill."""
    text = read(doc)
    open_items, done_items = checkboxes(text)
    lines = [f"- path: {doc}"]
    for key, is_list, placeholder in fields:
        # A .conf file's first comment gives options, not the file's purpose, so it starts unfilled.
        if key == PURPOSE and doc.endswith(".md"):
            lines.append(f"  - {key}: {heading(text)}")
        elif key == STALE and open_items + done_items:
            lines.append(f"  - {key}: all its checkboxes are checked")
        elif key == DRIFTS:
            present = sorted({p for p in refs(doc, text).values() if p and p != MAP})
            lines += nested(key, present, "  ")
        elif is_list:
            lines += nested(key, [placeholder], "  ")
        else:
            lines.append(f"  - {key}: {placeholder}")
    return lines


def live(doc, entry, tracked):
    """The checks the agent weighs against an existing entry."""
    full = os.path.join(ROOT, doc)
    text, mtime = read(doc), os.path.getmtime(full)
    if doc in tracked:
        edited = bool(git("status", "--porcelain", "--", doc).strip())
        state = "tracked, uncommitted edits" if edited else "tracked"
        since = mtime if edited else last_commit(doc)
    else:
        state, since = "untracked", mtime
    open_items, done_items = checkboxes(text)
    drifts = entry.get(DRIFTS) if isinstance(entry.get(DRIFTS), list) else []
    named_by = [f for f in git("grep", "-l", "-F", "--untracked", "-e", doc,
                               "--", ".", ":!*.jsonl", ":!" + MAP).splitlines() if f != doc]
    lines = [f"  - path: {doc}", f"    - git: {state}", f"    - last change: {day(since)}",
             f"    - open checkboxes: {f'{open_items} of {open_items + done_items}' if open_items + done_items else 'none'}"]
    lines += nested("drift files changed since this doc",
                    [p for p in drifts if os.path.exists(os.path.join(ROOT, p)) and (last_commit(p) or 0) > since], "    ")
    lines += nested("drift files missing", [p for p in drifts if not os.path.exists(os.path.join(ROOT, p))], "    ")
    lines += nested("named but missing", sorted(r for r, p in refs(doc, text).items() if not p), "    ")
    lines += nested("named by", named_by, "    ")
    return lines


fields = read_template()
keys = [f[0] for f in fields]
tracked = paths(git("ls-files", "-z"))
skip = {MAP, os.path.relpath(TEMPLATE, ROOT)}
docs = sorted(paths(git("ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.md", "*.conf")) - skip)
map_path = os.path.join(ROOT, MAP)

created = not os.path.exists(map_path)
text = "" if created else read(MAP)
entries, errors = parse_map(text, fields)
if errors:
    print("\n".join(nested("format errors", errors, "")))
    sys.exit(1)

new = [d for d in docs if d not in entries]
if new:
    with open(map_path, "a") as f:
        if text and not text.endswith("\n"):
            f.write("\n")
        for d in new:
            f.write("\n".join(draft(d, fields)) + "\n")
    entries, errors = parse_map(read(MAP), fields)
    if errors:
        print("\n".join(nested("format errors after appending", errors, "")))
        sys.exit(1)

unfilled = []
for path, entry in entries.items():
    for k in keys:
        values = entry[k] if isinstance(entry[k], list) else [entry[k]]
        if any(PLACEHOLDER.match(v) for v in values):
            unfilled.append(f"{path}: {k}")

existing = [p for p in entries if p in docs and p not in new]
report = [f"- map: {'created' if created else 'updated' if new else 'unchanged'}"]
report += nested("appended", new, "")
report += nested("gone", [p for p in entries if p not in docs], "")
report += nested("unfilled", unfilled, "")
report += ["- existing:"] + sum((live(p, entries[p], tracked) for p in existing), []) if existing else ["- existing: none"]
print("\n".join(report))

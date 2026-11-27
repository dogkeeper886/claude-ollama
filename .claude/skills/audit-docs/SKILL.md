---
description: >-
  A repo's Markdown files each serve a purpose: a plan carries a task, and a
  README describes the product. The code moves on, and each file stays as
  written. A finished plan reads as pending work, and a README describes code
  that changed. The next agent follows the stale file. This skill asks the
  agent to map each Markdown file's purpose and its stale and drift
  conditions, audit each file against the repo and recommend its outcome by
  the steps below.
---

Audit a repo's Markdown files:
1. Run `map-docs.py` beside this file from the repo root.
2. Fix each format error it reports in `DOCS-MAP.md` against `DOCS-MAP.template.md` beside this file, until it reports none.
3. Fill each field it reports unfilled, from the file's content and git history.
4. Check each existing file's purpose and its stale and drift conditions against the repo and the script's live checks.
5. Recommend one outcome per file: keep, update the file, update its entry, or delete the file.
6. Keep every file that code, a build or a test reads, or that another document links to.
7. Show the user a table of each file's path, outcome and evidence.
8. Mark each file to delete that git does not track, since its deletion cannot be undone.
9. Ask once for the whole list of outcomes, and act only on a yes.
10. Remove the entry of each deleted or gone file from `DOCS-MAP.md`.
11. Report with the `reporting-outcomes` skill, naming each deleted file and the commit that still holds it.

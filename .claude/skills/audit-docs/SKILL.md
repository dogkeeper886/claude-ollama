---
description: >-
  A repo's Markdown and config files each serve a purpose: a plan carries a
  task, a README describes the product, and a config file sets the values a
  program reads. The code moves on, and each file stays as written. A finished
  plan reads as pending work, a README describes code that changed, and a
  config file gathers notes and keys its program no longer reads. The next
  agent follows the stale file. This skill asks the agent to map each file's
  purpose and its stale and drift conditions, hold each config file to one
  shape, audit each file against the repo and recommend its outcome by the
  steps below.
---

Audit a repo's Markdown and config files:
1. Run `map-docs.py` beside this file from the repo root.
2. Fix each format error it reports in `DOCS-MAP.md` against `DOCS-MAP.template.md` beside this file, until it reports none.
3. Fill each field it reports unfilled, from the file's content and git history.
4. Review each `.conf` file's comments with the `reviewing-script-comments` skill.
5. Fix each error that `check-conf.py` beside this file reports on the repo's `.conf` files, against `CONF.template` beside this file, until it reports none.
6. Check each existing file's purpose and its stale and drift conditions against the repo and the script's live checks.
7. Recommend one outcome per file: keep, update the file, update its entry, or delete the file.
8. Keep every file that code, a build or a test reads, or that another document links to.
9. Show the user a table of each file's path, outcome and evidence.
10. Mark each file to delete that git does not track, since its deletion cannot be undone.
11. Ask once for the whole list of outcomes, and act only on a yes.
12. Remove the entry of each deleted or gone file from `DOCS-MAP.md`.
13. Report with the `reporting-outcomes` skill, naming each deleted file and the commit that still holds it.

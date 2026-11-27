---
description: >-
  load.conf lists what a claude-ollama session loads out of the box: Claude
  Code's built-in skills and plugins, and claude-ollama's own features, each on
  or off. Anthropic adds, renames and drops built-in skills and plugins between
  Claude Code releases. A list read from an older release, or from a machine
  with its own plugins and skills, names items that no longer load and misses
  the new ones, so load.conf stops matching the session. This skill asks the
  agent to regenerate load.conf from a fresh Claude Code config by the steps
  below.
---

Regenerate load.conf:
1. Create two empty folders in the scratchpad, one for a Claude Code config and one to work in.
2. From the empty working folder, run `claude --model <a model on the server> -p "/context" --no-session-persistence` with `CLAUDE_CONFIG_DIR` set to the empty config folder, `ANTHROPIC_BASE_URL` to the server, `ANTHROPIC_AUTH_TOKEN=ollama` and `ANTHROPIC_API_KEY` empty.
3. Read the built-in skills from the Skills table the run prints.
4. Read the built-in plugins from `pluginUsage` in the config folder's `.claude.json`.
5. Keep the value of each skill and plugin that `load.conf` already holds.
6. Drop each skill and plugin the run no longer lists.
7. Ask the user once for the value of each new skill and plugin.
8. Leave the `tool.*` and `feature.*` groups as they stand, since claude-ollama chooses them.
9. Write `load.conf` in its current shape: one group each for skills, plugins, tools and features.
10. Fix each error that `.claude/skills/audit-docs/check-conf.py` reports on `load.conf`, until it reports none.
11. Report with the `reporting-outcomes` skill, naming each added and dropped item.

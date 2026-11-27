---
description: >-
  A part of code stays steady when it depends only on steadier things, and
  takes them as explicit inputs. Each new need pulls in whatever is nearest: a
  global, an environment variable read deep inside, an outside program's
  option. The part then breaks when that thing changes, and no one can run it
  alone to find out. This skill asks the agent to judge each dependency by one
  question, is it steadier than the part and passed in explicitly, by the steps
  below.
---

Judge dependencies:
1. List each part's dependencies: what it imports or calls, what it reads from the environment and files, and the outside programs and APIs it uses.
2. Rank each dependency's steadiness: the language and its standard tools, then the repo's own code, then outside programs and APIs that change between releases.
3. Mark a dependency bad when it is less steady than the part and sits outside one confined place.
4. Mark a dependency bad when the part reads it implicitly: a global, an environment variable deep inside, a fixed path.
5. Mark each cycle between parts bad.
6. Write each bad dependency's smallest fix: confine it to one place, pass it in, or break the cycle.
7. Return each bad dependency as its file and line, the evidence and the fix.

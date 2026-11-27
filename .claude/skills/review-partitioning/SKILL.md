---
description: >-
  Code is easy to change when each part changes for one reason. Parts form as
  the code grows, along whatever seam the first author found. One change then
  spreads across many files and docs, or one file collects every change, and
  each edit risks the copies the editor missed. This skill asks the agent to
  judge each part by one question, does it change for one reason, by the steps
  below.
---

Judge partitioning:
1. List the changes the code is likely to see, from its git history and the inputs it reads that change between releases.
2. Count the parts each change touches: files, functions, tables and docs.
3. Mark a change bad when it touches more than one part.
4. Mark a part bad when most of the listed changes touch it.
5. Write each finding's smallest fix: gather what changes together into one part, or split the part every change touches.
6. Return each finding as its file and line, the change and the parts it touches, and the fix.

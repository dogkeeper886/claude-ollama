---
description: >-
  Good code holds up under five questions: does each unit do one thing, does
  each part change for one reason, does each part depend only on steadier
  things, does each name say what it holds, and does each comment say what the
  code can't. An agent reviews code by its own ideas, asking whichever question
  comes to mind first. The review judges by taste, mixes the questions, and
  misses the ones the agent never asked. This skill asks the agent to judge the
  code by all five, each in its own skill, by the steps below.
---

Review code by five questions:
1. List the files to review: the files the user names, else the files git reports changed.
2. Judge the files with the `review-clean-code` skill.
3. Judge the files with the `review-partitioning` skill.
4. Judge the files with the `review-dependency` skill.
5. Judge the files with the `review-names` skill.
6. Judge the files with the `review-comments` skill.
7. Show the user one table of every bad finding: its file and line, the question it failed, the evidence and the smallest fix.
8. Ask once which fixes to apply, and apply only those on a yes.
9. Report with the `reporting-outcomes` skill, naming each question that found nothing.

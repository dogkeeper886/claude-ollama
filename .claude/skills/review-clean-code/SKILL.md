---
description: >-
  A unit of code reads easily when it does one thing at one level of detail.
  Code grows by additions, and each addition lands in the unit already open.
  The unit ends up mixing parsing, network calls and formatting, keeping
  branches nothing reaches and repeating blocks, so the reader traces all of it
  to learn what it does. This skill asks the agent to judge each unit by one
  question, does it do one thing at one level of detail, by the steps below.
---

Judge clean code:
1. List each unit in the files: each function, and each block a script runs in order.
2. Predict what each unit does from its name, or from its leading comment when it has no name.
3. Read each unit's body against the prediction.
4. Mark a unit bad when its body does more than the prediction, mixes levels of detail, keeps a branch nothing reaches, or repeats another block.
5. Write each bad unit's smallest fix: a split, an extraction or a deletion.
6. Return each bad unit as its file and line, the evidence and the fix.

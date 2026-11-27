---
description: >-
  A good comment says what the code can't: a reason, a contract, a range or a
  trap. An agent comments code by its own ideas, describing each line it
  writes and noting each change it makes. The comments repeat the code, gather
  history and drift from their lines, so the reader trusts none of them. This
  skill asks the agent to judge each comment by one question, does it say
  something the code can't, by the steps below.
---

Judge comments:
1. List each comment in the code.
2. Read each comment's code as if the comment were deleted.
3. Mark a comment bad when the code without it tells the reader the same.
4. Mark a comment bad when it holds a history, a note, or a claim the code no longer matches.
5. Write each bad comment's fix: delete it, or rewrite it as the reason, contract, range or trap the code can't show.
6. Return each bad comment as its file and line, the evidence and the fix.

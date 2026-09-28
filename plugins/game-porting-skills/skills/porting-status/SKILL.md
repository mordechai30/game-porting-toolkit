---
name: porting-status
description: Show the current porting status. Reads the goal document, porting-memory.md, and latest handoff note to report where things stand. Read-only — does not continue any work.
---

You are checking the current porting status. This is read-only — do NOT continue any work or start any implementation.

## Gather Status

Locate the agent's **artifact directory** at `<project-root>/.porting/` (defined in `porting-methodology`). All artifacts live there. Load the `porting-methodology` skill if not already in context.

Read the following files and report their contents:

1. **Goal document** (`goal-*.md` in the artifact directory) — if it exists, show the milestone tracker with current status of each milestone.

2. **porting-memory.md** — if it exists, show the watch list and feature status table.

3. **Latest handoff note** (`porting-handoff-*.md` in the artifact directory) — if one exists, show what was done, what's deferred, and known issues.

4. **Discovery report** (`discovery-report.md` in the artifact directory) — if it exists, note that discovery is complete.

If none of these files exist, report: "No porting artifacts found. Run `/porting-discover` to begin."

## Output

```
## Porting Status

### Current Goal
[Goal name and target, or "No active goal"]

### Milestones
[Table from goal document showing each milestone and its status]

### Current Phase
[Which phase the current milestone is in, or "Not started"]

### Feature Status
[Feature domain table from porting-memory.md]

### Watch List
[Active watch list items from porting-memory.md]

### Last Handoff
[Summary from latest handoff note — what was done, what's next]

### Remaining STUB Count
[If a backend directory is identifiable, run `grep -r "STUB" <dir> | wc -l` to count remaining stubs]
```

Do NOT start any work after reporting status. This is informational only.

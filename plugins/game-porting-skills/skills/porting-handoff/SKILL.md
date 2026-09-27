---
name: porting-handoff
description: Close out the current milestone. Prompts the user to commit, updates porting-memory.md (watch list and feature status), writes a handoff note, updates the goal document milestone status, and requests a context reset.
disable-model-invocation: false
---

You are entering Phase 4: Handoff for the current milestone.

Locate the agent's **artifact directory** at `<project-root>/.porting/` (defined in `porting-methodology`). All artifacts live there. Load the `porting-methodology` skill if not already in context.

## Step 1: Prompt Commit

Ask the user to commit any uncommitted work before proceeding:

> "Before writing the handoff, please commit any uncommitted changes."

Wait for the user to confirm the commit is done.

## Step 2: Update porting-memory.md

Read `porting-memory.md` from the artifact directory and update it:

### Watch List
- **Add** any unresolved issues, known risks, or critical notes discovered during this milestone that the next session needs to be aware of.
- **Remove** any items that were resolved during this milestone.
- Keep items concise — one line per item with enough context to understand without reading the full history.

### Feature Status
- **Update** the feature domain table to reflect what was implemented, stubbed, or progressed during this milestone.
- Status values: Not started, Stubbed, Partial, Implemented.
- Add brief notes for domains that changed (e.g., "Implemented — buffer creation, upload via compute encoder").

### Curated Knowledge
- **Add** any important architectural discoveries, engine-specific conventions, or key decisions made during this milestone that would be useful in future sessions.
- Keep the total porting-memory.md under 200 lines. If it's growing too large, compress older notes and move detailed content to separate files in the artifact directory.

## Step 3: Write Handoff Note

Determine the current goal name from the goal document (`goal-<name>.md`). Write a handoff note to the artifact directory as `porting-handoff-<goal-name>-M<x>.md` (e.g., `handoff-basic-rendering-M2.md`):

```markdown
# Handoff: [Milestone Name]

## What Was Done
[One-paragraph summary of the milestone — what was implemented, what's now working]

## Ground Truth Comparison
[Full report of ground truth reference checks performed during validation. For each artifact compared:]
- [Which reference artifact was used (translation-layer capture, RenderDoc XML, etc.)]
- [What was compared (pass structure, draw counts, output textures, resource bindings)]
- [What matched and what diverged]
- [Whether divergences are expected (features not yet implemented) or need investigation]
- [If no ground truths were compared, state why (non-rendering milestone, artifacts unavailable)]

## What's Deferred
[Specific TODOs and STUBs created, with grep patterns]
- `grep "STUB(M<next>)"` — [description of what these stubs are]

## Known Issues
[Bugs, artifacts, validation warnings not yet fixed]

## Watch For
[Things that will trip you up next milestone — specific, actionable warnings]

## Key Decisions Made
[Why something was done a certain way, so the next session doesn't undo it]

## Skills Needed Next
[Which skills the agent should load for the next milestone]
```

## Step 4: Update Goal Document

Read the goal document (`goal-*.md` in the artifact directory) and update the current milestone's status to "Complete".

## Step 5: Notify User

Present a summary of all artifacts created or updated:

```
## Handoff Summary

### Artifacts Updated
- porting-memory.md — [what changed: watch list items added/removed, feature status updates, knowledge added]
- Handoff note — written to <project-root>/.porting/porting-handoff-<goal-name>-M<x>.md
- Goal document — milestone [name] marked Complete

### Next Milestone
[Name and success criterion of the next milestone, or "All milestones complete — run /porting-plan-goal"]

### Watch List (current state)
[Show the current watch list from porting-memory.md so the user can review]
```

## Step 6: Request Context Reset

After the user has reviewed the handoff summary:

> "Milestone complete. Please start a new session for the next milestone."

Do NOT continue working on the next milestone in this session. The one-session-per-milestone model keeps each milestone's changes bounded and reviewable.

---
name: porting-start-milestone
description: Begin the next milestone. Reads the goal document and latest handoff note, loads relevant skills, studies code paths, and produces a preparation summary for user review. Does NOT write code.
---

You are entering Phase 1: Prepare for the current milestone.

## Pre-flight Check

Locate the agent's **artifact directory** at `<project-root>/.porting/` (defined in `porting-methodology`). All artifacts live there. Load the `porting-methodology` skill if not already in context.

1. **Check for a goal document** (`goal-*.md` in the artifact directory). If none exists, tell the user: "No goal document found. Run `/porting-plan-goal` first." and stop.

2. **Read the goal document.** Find the first milestone with status "Not started" or "In progress":
   - If one is "In progress", resume it.
   - If one is "Not started", start it — update its status to "In progress" in the goal document.
   - If all milestones are complete, tell the user: "All milestones for this goal are complete. Run `/porting-plan-goal` to define the next porting goal." and stop.

3. **Read porting-memory.md** — review the watch list and feature status. Note any items relevant to this milestone.

4. **Read the latest handoff note** (`porting-handoff-*.md` in the artifact directory, if one exists). This is your memory from the last session — what was done, what's deferred, known issues, what to watch for.

## Load and Read Skills

Then load domain skills based on what the current milestone will involve. Use the skill-loading table defined in the `porting-methodology` skill, the goal document's milestone description, and the handoff note's "skills needed next" recommendation to decide. Load what's relevant — not everything.

**You MUST actually read each loaded skill — not just list it.** After loading a skill, read through its key sections (workflow patterns, API patterns, anti-patterns, common pitfalls). Extract the specific patterns and conventions that apply to this milestone's work items. You will cite these in your preparation summary.

Do NOT ask the user questions whose answers are already in your loaded skills. If a skill documents the API pattern, the binding convention, or the architectural approach — use that answer. Only ask the user about things that are genuinely undiscoverable from the codebase and loaded skills combined.

## Study the Code

This is where the planned scope is validated against the actual codebase. Be thorough — everything needed to meet the success criterion must be identified here, not discovered during execution.

1. **Identify work items:**
   - Check the handoff note's deferred list
   - Search for `STUB` comments from previous milestones that this milestone resolves: `grep -r "STUB" <backend-directory>`
   - Review the milestone's success criterion from the goal document

2. **Trace dependencies for each work item.** Read the code paths that will change — the functions, their call sites, the data they consume and produce. Identify everything required to make the success criterion pass: prerequisite infrastructure, data flow dependencies, format conversions, resource creation paths.

3. **Check scope against the milestone principle.** Each milestone should target one feature. If the work items span multiple unrelated features, the milestone is too large. Flag this to the user and propose splitting — either by carving out new milestones or by deferring items that fit naturally into existing future milestones.

4. **Ask the user** about anything undiscoverable — binding conventions, engine-specific constants, architectural decisions you can't verify from the codebase or loaded skills. Do not guess.

## Output: Preparation Summary

Present a preparation summary to the user. **The Work Items list is the scope contract for this milestone** — only these items will be implemented during `/porting-execute`.

```
## Milestone Preparation: [milestone name]

### Goal
[From goal document — milestone success criterion]

### Skills Loaded
[For each skill loaded, list:
- Skill name and why it's needed for this milestone
- Key patterns from the skill that apply to the work items (cite specific API calls, conventions, or anti-patterns you found by reading the skill)]

### Work Items
[Complete list of what will be implemented this milestone — from STUBs, handoff note, dependency tracing, and milestone scope. This list is the scope contract for /porting-execute.]

### Code Paths Affected
[Key files and functions that will be modified]

### Watch List Items (from porting-memory.md)
[Any relevant items from the watch list that affect this milestone]

### Questions for User
[Anything undiscoverable or uncertain — ask before starting. Do NOT include questions answered by your loaded skills.]
```

## Gate

**Do NOT proceed to writing code.** Wait for the user to review the preparation summary, answer questions, and explicitly approve.

The user's approval sets the scope boundary for this milestone. The `/porting-execute` phase will implement only the approved work items.

**After the user approves:** Update porting-memory.md with the current milestone's success criterion and approved work items. Keep it concise (a few lines) — this ensures the scope contract survives in persistent memory throughout the execute phase. Remember that porting-memory.md must stay under 200 lines total.

Once the user approves, tell them: "Preparation approved. Run `/porting-execute` to begin implementation."

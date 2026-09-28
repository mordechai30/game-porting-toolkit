---
name: porting-plan-goal
description: Define the next porting goal. Reads the discovery report and current porting state, proposes a goal with milestones, and creates a goal document.
---


You are defining a porting goal for the Apple platform porting agent.

## Pre-flight Check

Locate the agent's **artifact directory** at `<project-root>/.porting/` (defined in `porting-methodology`). All artifacts live there.

1. **Check if a discovery report exists** (`discovery-report.md` in the artifact directory). If it does not exist, tell the user: "No discovery report found. Run `/porting-discover` first." and stop.

2. **Check if a previous goal document exists** (`goal-*.md` in the artifact directory). If one exists and is not marked complete, tell the user: "An active porting goal already exists: [goal name]. Complete it before planning a new one, or confirm you want to replace it." Wait for the user's response.

**Announce:** "Planning next porting goal."

## Load Skills

**Read these skill files NOW:**
1. **porting-methodology** — Read `skills/porting-methodology/SKILL.md`. Understand the porting goal system, milestone lifecycle, and the recommended bring-up order (foundation + rendering milestones).
2. **translating-to-metal4-api** — Read `skills/translating-to-metal4-api/SKILL.md`. Understand the Metal 4 API surface to inform milestone scoping.

## Step 1: Assess Current State

Read the discovery report and any existing goal documents to understand:
- What has already been ported (if anything)
- Which feature domains are implemented vs. stubbed
- What the discovery report identified as blockers or risks
- Platform readiness status
- Available reference artifacts (Frame captures using Game Porting Toolkit's Evaluation environment for Windows games, RenderDoc XML, traces)
- Stub candidates identified during discovery

**If this is the first porting goal** (no previous goals exist):
- The feature coverage matrix from the discovery report defines the full scope
- Use the recommended bring-up order from the methodology (foundation milestones M0-M3, then rendering milestones M4+) as the milestone template
- Skip foundation milestones the engine already provides (check Platform Readiness in the discovery report)
- **If the discovery report flagged "No abstraction — single-API codebase":** the porting strategy must be decided with the user before defining milestones. Present the options and their trade-offs:
  - **Abstraction layer first** — introduce a graphics API abstraction (HAL/RHI) that both the existing API and Metal can implement behind. Largest upfront effort, but cleanest long-term result. Early milestones are refactoring, not Metal code.
  - **Thin translation shim** — create a minimal translation layer that maps the existing API's types and calls to Metal equivalents. Less refactoring than a full abstraction. Good when the codebase is small or the port is one-directional.
  - **Direct replacement** — replace API calls in-place with Metal equivalents, controlled by `#ifdef` or build configuration. Least upfront effort, but results in interleaved platform-specific code.
  - **Hybrid** — abstract at key boundaries (device, command buffer, resource creation) while doing direct replacement for simpler calls.

  The user decides. The choice fundamentally shapes milestone structure — an abstraction-first approach front-loads refactoring milestones before any Metal code, while direct replacement starts writing Metal immediately.

**If this is a subsequent porting goal** (previous goals completed):
- Review the completed goal documents and the agent's `porting-memory.md` (especially the **feature status** table) to understand what's already implemented
- Identify the feature delta — what new features does this goal add?
- Propose the goal with the smallest feature delta that produces a verifiable result

## Step 2: Propose a Goal

Present the proposed goal to the user with:

1. **Goal name** — short, descriptive (e.g., "basic-rendering", "compute-pipeline", "advanced-materials")
2. **Target** — what should be working when this goal is complete (be specific and verifiable)
3. **Selection rationale** — why this goal, why now (simplest viable target, builds on prior work, exercises specific features)
4. **Proposed milestones** — ordered list with clear success criteria for each

   **Milestone sizing rule: one targeted feature per milestone.** Each milestone should focus on a single capability (e.g., "depth buffer", "compute dispatch", "windowing"). Do not bundle multiple unrelated features into one milestone. If a milestone description requires "and" between unrelated features, split it.

   For the **first porting goal**, base milestones on the bring-up order from the methodology:

   **Foundation milestones** (skip any the engine already provides):
   - M0: Build — project compiles and links with stubs (use the Stub Candidates list from the discovery report)
   - M1: Content Pipeline — shaders compile to metallibs, assets loadable
   - M2: Window + Main Loop — window opens, main loop ticks, frame callbacks fire
   - M3: Input — one input method functional

   **Rendering milestones:**
   - M4: Device + Capabilities
   - M5: Presentation + First Clear
   - M6: Shader Loading + Pipelines
   - M7: Vertex Drawing
   - M8: Full Scene
   - M9: Polish

   Adapt as needed — combine or split milestones based on the engine's architecture. Not every step needs its own milestone. If a RenderDoc capture is available, use the PIX marker pass hierarchy to inform the ordering of rendering milestones.

   For **subsequent goals**, milestones are feature-specific (e.g., "compute encoder and dispatch", "indirect draw support", "advanced vertex formats"). When the feature delta is primarily one new capability that the rest of the pipeline depends on, consolidate milestones aggressively.

5. **Skills needed** — which skills should be loaded across this goal's milestones
6. **Known risks** — anything from the discovery report or previous goals that could complicate this work

**Wait for the user to review and approve the proposed goal.** The user may adjust scope, milestones, or priorities. Iterate until agreed.

## Step 3: Scope Discussion

After presenting the proposal, discuss with the user:

1. **Is the scope right?** Too ambitious? Too narrow?
2. **Are the milestones correctly ordered?** Any dependencies the agent missed?
3. **Are there decisions to make?** Language choice (if not already decided), specific approaches, constraints?
4. **Anything the agent should know?** Engine-specific conventions, magic numbers, known gotchas from the user's experience?

Incorporate the user's feedback into the goal document. Do not create the document until the user approves.

## Step 4: Create Goal Document

Once the user approves, create the goal document in the artifact directory as `goal-[name].md`:

```markdown
# Porting Goal: [Goal Name]

## Target
[What should be working when this goal is complete — specific and verifiable]

## Selection Rationale
[Why this goal was chosen]

## Key Decisions
[Decisions and constraints agreed with the user for this goal. For the first goal, this includes language choice, off-limits subsystems, and other constraints from the scope discussion. For subsequent goals, carry forward prior decisions and note any changes.]

## Milestones

| # | Name | Success Criterion | Status |
|---|------|-------------------|--------|
| M0 | ... | ... | Not started |
| M1 | ... | ... | Not started |
| ... | ... | ... | ... |

## Architecture Notes
[Key codebase discoveries from the discovery report that apply across all milestones — binding index conventions, descriptor layout, engine-specific patterns, etc.]

## Skills
[Which skills should be loaded for this goal's milestones]
```

After creating the goal document, update the agent's `porting-memory.md` with:

- **Watch List** — initialize with any known risks or concerns from the discovery report. This section is updated during each milestone's handoff phase. Items are added when discovered, removed when resolved.
- **Feature Status** — initialize from the discovery report's feature coverage matrix and any foundation work needed. Add all relevant domains with status "Not started". This section is updated during each milestone's handoff phase to track implementation progress. Tailor the domains to the specific project — the example below is illustrative, not exhaustive.

```markdown
# Watch List
[Unresolved issues, known risks, and critical notes that persist across milestones]

# Feature Status
[Tracks implementation progress across feature domains. Domains are project-specific — derived from the discovery report's feature coverage matrix and foundation milestones.]

| Feature Domain | Status | Notes |
|----------------|--------|-------|
| Build / Linking | Not started | |
| Content Pipeline | Not started | |
| Windowing / Main Loop | Not started | |
| Input | Not started | |
| Device / Init | Not started | |
| Pipeline State | Not started | |
| Command Encoding | Not started | |
| Synchronization | Not started | |
| Presentation | Not started | |
| ... | ... | ... |

Status values: Not started, Stubbed, Partial, Implemented
```

This `porting-memory.md` is expected to be in the context, and so do the watch list and feature status. If not yet, read it.

## After Goal Creation

Tell the user:

> "Goal document created. Start a fresh session and run `/porting-start-milestone` to begin the first milestone."

Do NOT start any implementation work. Goal planning is planning only.

---
name: porting-discover
description: Analyze a codebase before starting a Metal 4 port. Produces a discovery report with platform readiness, graphics backend analysis, feature coverage matrix, and trace-grounded findings. Use before any porting work begins.
disable-model-invocation: false
context: fork
agent: general-purpose
---

You are preparing to port a game or engine to Apple platforms with Metal 4. Before writing any porting code, you must understand the target codebase thoroughly and gather any available reference artifacts.

## Pre-flight Check

Locate the agent's **artifact directory** at `<project-root>/.porting/` (defined in `porting-methodology`). All artifacts live there.

**Check if a discovery report already exists** (`discovery-report.md` in the artifact directory).
- If it exists, tell the user: "A discovery report already exists. Do you want to re-run discovery (this will overwrite the existing report) or use the existing report and proceed to `/porting-plan-goal`?"
- Wait for the user's response before continuing.
- If the user chooses to use the existing report, stop here.

**Announce:** "Running codebase discovery for Apple platform porting."

## Before You Begin — Load Skills

**Read these skill files NOW before doing any discovery work:**
1. **porting-methodology** — Read `skills/porting-methodology/SKILL.md`. Understand the porting goal system, milestone lifecycle, and what discovery feeds into.
2. **translating-to-metal4-api** — Read `skills/translating-to-metal4-api/SKILL.md`. Know what Metal 4 API changes to look for and cross-check findings against Metal 4 domain knowledge.

Do not skip skill loading. These inform what to look for during discovery.

## Step 1: Ask the Developer

Before analyzing the codebase, ask these questions and **WAIT for responses** before continuing:

1. **Metal API style** — Objective-C, Swift, or metal-cpp? This affects file organization, bridging patterns, and which pitfalls to plan for.
2. **Renderer abstraction strategy** — If no abstraction exists, what's the preference? (Options will be discussed during goal planning, but knowing the preference early helps focus analysis.)
3. **RenderDoc traces** — Do they have a RenderDoc capture from the source platform? (XML + ZIP export is most useful.)
4. **Evaluation environment traces** — Has the game been run under Game Porting Toolkit (commonly referred to as GPTK)? Are any of these available?
   - **GPU frame capture** (`.gputrace`) — rendering ground truth, most valuable for validation
   - **Metal System Trace** (`.trace`) — CPU/GPU timing, useful for performance planning
   - **Memgraph** — memory snapshot, useful for resource planning
5. **Off-limits subsystems** — Any files or directories the agent should NOT modify?
6. **Known blockers or constraints** — Anything the agent should be aware of?

Metal 4 is the target API — all domain skills are Metal 4.

**STOP.** Do not proceed until the developer has answered. Do not assume answers.

## Step 2: Game Porting Toolkit Evaluation and Trace Analysis

**Read `reference/gptk-and-traces.md` now.** Follow the procedures for:
- Game Porting Toolkit evaluation (if not already done)
- GPU frame capture collection (if available or capturable)
- Trace collection and analysis (Instruments, memgraph)
- RenderDoc XML parsing (if provided)

Record all artifact paths in a table — these will be included in the discovery report and used during validation.

If no traces are available and none can be captured now, note this in the report and recommend the developer collect them when possible.

## Step 3: Codebase Analysis

**Read `reference/codebase-analysis.md` now.** Work through all checklists:
- Platform readiness (build, windowing, content pipeline, libraries)
- Graphics backend analysis (12-point investigation)
- Feature coverage matrix
- Platform gap analysis
- Practical porting advice applicability
- Risk assessment
- Dependency graph

For graphics-specific details, load domain skills rather than guessing. If you encounter something that a domain skill covers (synchronization model, shader pipeline, resource binding), consult that skill.

## Step 4: Scope Discussion

After completing Steps 2-3 but BEFORE writing the report, confirm decisions with the user:

1. **Language choice confirmation** — ObjC with ARC or metal-cpp? (Your analysis should inform a recommendation, but the user decides.)
2. **Abstraction strategy** — If discovery found "no abstraction" (single-API codebase with raw API calls throughout), flag this. The detailed options (abstraction layer first, thin shim, direct replacement, hybrid) will be resolved during `/porting-plan-goal`, but the finding must be in the report.
3. **Reference availability** — Is there a reference implementation or documentation the agent can consult for undiscoverable conventions?
4. **Review preliminary findings** — Share key findings and risks. Let the user correct any misunderstandings before the report is finalized.

**STOP.** Wait for the user's responses before writing the report.

## Output Format

Produce a **Codebase Discovery Report**. Save to the artifact directory as `discovery-report.md`:

```markdown
# Codebase Discovery Report: [Engine/Project Name]

## Summary
[2-3 sentence overview of porting readiness and key findings]

## Skills Loaded
[List which skills were read and how they informed the analysis]

## Game Porting Toolkit Evaluation Findings
[What works, what breaks, what's slow under the evaluation environment for Windows games. If not evaluated: "Not evaluated — recommend running under Game Porting Toolkit's evaluation environment."]

## Trace Analysis
[Findings from each trace type. If none available: "No traces available — recommend collecting."]

## Reference Artifacts

| Artifact Type | Path | Scene/State | Notes |
|---|---|---|---|
| GPU frame capture (.gputrace) | ... | ... | ... |
| RenderDoc XML | ... | ... | ... |
| Metal System Trace (.trace) | ... | ... | ... |
| Memgraph (.memgraph) | ... | ... | ... |

[Remove rows for artifacts not available. If none: "No reference artifacts collected."]

## Platform Readiness

| Area | Status | Notes |
|------|--------|-------|
| macOS build | Ready / Blocked / Partial | ... |
| Platform layer (windowing) | Ready / Blocked / Partial | ... |
| Content pipeline | Ready / Blocked / Partial | ... |
| Required libraries | Ready / Blocked / Partial | ... |
| Deployment target | Compatible / Needs update | ... |

## Graphics Backend Analysis

| # | Category | Finding | Metal 4 Impact |
|---|----------|---------|----------------|
| 1 | Existing backends | ... | ... |
| 2 | API abstraction | ... | ... |
| 3 | Shader language | ... | ... |
| 4 | Shader pipeline | ... | ... |
| 5 | Existing Metal backend | ... | ... |
| 6 | Binding model | ... | ... |
| 7 | Render graph | ... | ... |
| 8 | Synchronization | ... | ... |
| 9 | Threading | ... | ... |
| 10 | Memory management | ... | ... |
| 11 | Language conventions | ... | ... |
| 12 | ObjC/ARC | ... | ... |

## Platform Gap Analysis
[Source → Apple platform mapping for each subsystem. Point to domain skills where they exist (windowing → setting-up-macos-window, input → using-game-controller, graphics → Metal 4 domain skills). Inline for domains without skills (audio, threading, file system, dynamic libraries, entry point).]

## Feature Coverage Matrix

| Feature Domain | Function Count | Essential | Notes |
|----------------|---------------|-----------|-------|
| Device / Init | ... | Yes | ... |
| Buffers | ... | Yes | ... |
| Textures | ... | Yes | ... |
| Render Targets | ... | Yes | ... |
| Samplers | ... | Yes | ... |
| Pipeline State | ... | Yes | ... |
| Descriptor Binding | ... | Yes | ... |
| Command Encoding (Draw) | ... | Yes | ... |
| Command Encoding (Dispatch) | ... | Depends | ... |
| Resource Copy (Blit) | ... | Yes | ... |
| Synchronization | ... | Yes | ... |
| Presentation / Swap Chain | ... | Yes | ... |
| Queries (Timestamp/Occlusion) | ... | Optional | ... |
| Debug Markers / Labels | ... | Yes (early) | ... |
| Compute | ... | Depends | ... |
| Raytracing | ... | Optional | ... |
| Indirect Draw/Dispatch | ... | Optional | ... |

## Practical Porting Advice
[Tailored subset from codebase-analysis.md — only items relevant to this specific codebase]

## Stub Candidates
[Every subsystem that can be stubbed for initial milestones, with recommended preprocessor define names. For each: what it does, why it can be stubbed, and whether it blocks startup if removed. Do not stub input — at least one input method must be functional. This list feeds directly into the Build foundation milestone in porting-plan-goal.]

## Quick Wins
[Subsystems or code paths that are already portable or nearly so — minimal effort to get working on Apple platforms. Examples: cross-platform libraries already available on macOS, code behind a clean abstraction, subsystems with existing POSIX paths.]

## Parallel Work Opportunities
[Work that can proceed on the source platform (Windows/Game Porting Toolkit) in parallel with native porting. Examples: shader optimization (heaviest shaders from GPU timing data), CPU-GPU synchronization fixes, precision/correctness bugs, asset pipeline issues. If GPU timing data is available, identify the heaviest passes to optimize in HLSL.]

## Risk Assessment
[Middleware blockers, shader complexity, inline assembly, custom allocators, threading assumptions, file I/O, anti-cheat/DRM]

## Dependency Graph
[What blocks what, minimum subsystems for main loop, init-order dependencies]

## Key Files
[Most important files for modification or creation]

## Scope Decisions (from user)
- **Language:** [ObjC/ARC or metal-cpp]
- **Off-limits:** [Files/subsystems not to modify]
- **Abstraction strategy:** [Existing abstraction / No abstraction — flagged for goal planning]
- **Reference available:** [Yes/No — what the user can help with]
```

## After Discovery

After the discovery report is saved and reviewed by the user, prompt:

> "Discovery complete. Run `/porting-plan-goal` to define the first porting goal based on this report."

Do NOT proceed to any porting work. Discovery is analysis only.

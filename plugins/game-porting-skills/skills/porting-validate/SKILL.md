---
name: porting-validate
description: Run the validation checklist before the milestone's final commit. Checks runtime verification, visual correctness, reference artifact comparison, Metal validation, memory leaks, skill-driven code review, and data flow verification. Can also be run mid-milestone.
disable-model-invocation: false
---

You are entering Phase 3: Validate for the current milestone. The milestone's work is functionally complete. Mid-milestone commits for stable checkpoints are fine, but this full validation pass should happen before closing out the milestone.

## Reload Skills

Validation often runs in a fresh session after the execute phase. Skills loaded during execution are no longer in context. **You MUST reload the skills you need before proceeding:**

1. **Always reload** `porting-methodology` (for anti-patterns checklist and debugging escalation).
2. **For rendering milestones**, reload `using-gpucapture` and `using-gpudebug` — you will need these for GPU frame capture and ground truth comparison. Do NOT attempt GPU capture workflows from memory.
3. **Reload domain skills** for this milestone. Read the goal document's milestone plan to find which skills are associated with the current milestone. Also check porting-memory.md for any additional context. You need these for the skill-driven code review (checklist item 7).
4. **If visual bugs are found**, reload `debugging-rendering-issues` for structured diagnostic workflows.

## Validation Checklist

Work through each item and report findings:

### 1. Runtime Verification

**The app must run.** From M1 onward, do not declare a milestone complete based on code review alone — verify at runtime.

- Build and launch the app. Confirm the milestone's success criterion is met.
- If the app crashes or the success criterion isn't met, fix the issue before continuing validation.
- Run with a debugger attached (lldb) to catch issues that don't surface from terminal launches. If you cannot attach a debugger, ask the user to run from Xcode.
- Report: did the app launch, did it meet the success criterion, were there crashes.

### 2. Visual Correctness

**Verify rendering output.** Metal validation does not catch wrong-but-valid states (wrong format, wrong color space, wrong blend mode, darker/brighter rendering).

- Take a screenshot (`screencapture` on macOS) and analyze it visually — check that the scene is visible, geometry is present, and there are no obvious artifacts (black screen, missing objects, color issues).
- If a GPU frame capture is available, inspect the final output texture for correctness.
- After self-analysis, ask the user to confirm the visual result matches expectations — the agent may miss subtle issues (color accuracy, lighting differences, platform-specific rendering).
- Report: self-analysis findings, user-confirmed visual correctness, or issues identified.

### 3. GPU Frame Capture

**YOU MUST capture and analyze a GPU frame for any milestone that touches rendering. Do NOT skip this step.** This catches issues invisible to both visual inspection and validation layers — wrong textures bound, empty buffers, missing descriptor entries, non-resident resources, stale reads from missing barriers.

Before capturing, ensure `using-gpucapture` is loaded. Before analyzing, ensure `using-gpudebug` is loaded. Do NOT attempt these workflows from memory — the skills contain required environment variables, API calls, and analysis procedures.

- Capture a GPU frame and analyze it autonomously. Check bound resources per draw/dispatch, output texture contents, pass structure.
- If debug markers and resource labels are implemented, reference them by name so the capture can be navigated quickly.
- If GPU capture tools (`gpucapture`, `gpudebug`) are unavailable, ask the user to capture a frame via Xcode and share the `.gputrace` file for analysis. Do NOT silently skip GPU frame validation — either do it yourself or get the user's help.
- Skip this step **only** for milestones that exclusively change non-rendering code (build setup, stubs, device init with no rendering).
- Report: bindings, output contents, pass structure, residency, and barriers checked — confirmed correct, or issues identified.

### 4. Ground Truth Comparison

**Cross-reference available ground truths against the current milestone's output.** Determine which ground truths are relevant based on what the milestone touches — the agent should select the appropriate comparisons, not run all of them mechanically. Only compare features that are expected to work at this milestone — do not flag missing functionality that belongs to future milestones.

Check the discovery report's Reference Artifacts table. Available ground truths and when they're relevant:

- **GPTK evaluation environment GPU frame capture** — relevant when validating rendering. Capture a frame of the native port and compare against the GPTK evaluation environment reference: render pass structure, draw/dispatch counts, output texture contents. Use `using-gpudebug` for autonomous comparison.
- **RenderDoc XML** — relevant when validating rendering. Compare render pass structure and draw/dispatch counts against the native port.
- **Instruments trace** — relevant when validating performance or encoder overhead. Native port should have comparable or less overhead than the GPTK evaluation environment.
- **Memgraph** — relevant when validating memory usage. Native port should use comparable or less memory than the GPTK evaluation environment.

If no reference artifacts are available, skip this step.

Report: which ground truths were compared, discrepancies found, whether they're expected (incomplete milestone) or need investigation.

### 5. Metal Validation Layers

Run the app with Metal validation enabled. Load `using-metal-validation` for env-var setup, launch rule, and gotchas.

- Capture stderr: `./App 2>&1 | grep -i error` or `./App 2>metal_errors.log`.
- If you also need system log access (e.g., without the stderr redirect), use `log show --predicate 'subsystem == "com.apple.Metal"' --last 5m` — but this may be sandboxed. Prefer stderr redirection. 
- Fix errors caused by this milestone's changes.
- Errors from features not yet implemented can be noted and deferred.
- Before the final milestone of a goal, all validation errors must be resolved.
- Report: which errors found, which fixed, which deferred and why.

### 6. Memory and Safety

Check for memory issues using available tools:
- **AddressSanitizer (ASan)** — build with `-fsanitize=address` or enable ASan in the Xcode scheme. Catches use-after-free, buffer overflows, stack corruption, and other memory errors that leak checkers miss. Run at least once per milestone.
- **Engine's own memory tracker** — if the engine reports leaks on exit, check for any new ones. Note: clean exit typically requires user collaboration (e.g., Cmd-Q on macOS) since SIGINT/SIGTERM bypass most engines' teardown paths.
- **ObjC/ARC leaks** — verify every teardown function nils all `id<...>` members before freeing C-allocated structs.
- **GPU memory leaks** — check Metal HUD (`MTL_HUD_ENABLED=1`) memory counter. If it grows continuously, resources are leaking.
- Report: any issues found, whether fixed or deferred.

### 7. Skill-Driven Code Review

For each domain skill loaded during this milestone, re-read its guidance sections — look for any of: **Anti-Patterns, Common Mistakes, Common Pitfalls, Troubleshooting, Best Practices, Good Practices**. Not all skills use the same headings. Some skills have reference subdirectories with additional anti-patterns — check any reference files relevant to the milestone's scope. Review your code against each item found.

- Check each anti-pattern or pitfall — does your code violate any?
- Check each good practice or best practice — does your code follow them?
- Report: violations found, whether fixed or accepted with justification.

### 8. Trace the Data

**CPU-side data flow:** For every struct member you wrote to during this milestone:
- Grep for all read sites and verify the value is consumed correctly.
- For every struct member you read, verify it was written somewhere.
- This catches the storage/consumption mismatch pattern — storing a value but forgetting to read it in the corresponding code path.

**GPU resource binding chain:** For resources introduced or modified this milestone, trace the full path:
- Resource creation (format, type, storage mode) → descriptor binding (correct entry type, address, metadata) → shader binding slot → shader consumption (how the shader reads it).
- A break at any point in this chain produces silent corruption with no error.

- Report: any mismatches found and fixed.

### 9. Code Review

Walk through every function changed during this milestone. Look for:
- Missing nil-before-free on ObjC members
- Wrong enum mappings (source engine enums vs Metal enums — don't assume 1:1)
- Silent fallback defaults that mask bugs (e.g., `default: return MTLVertexFormatFloat4`)
- Hardcoded values without comments
- Missing assertions for preconditions
- **Code dropped during full-file rewrites** — for any file rewritten in full rather than via targeted edits, diff against the previous commit and verify no existing code was accidentally removed, truncated, or replaced with placeholder text like "omitted for brevity."
- **Deprecated API calls** — if you used deprecated platform APIs and a one-line modern replacement exists, fix it now. Do not defer trivial modernizations.
- Report: issues found and fixed.

### 10. Refactor Pressure Hacks

If you introduced any shortcuts, hacks, or temporary code during debugging in Phase 2, clean them up now:
- Remove ALL temporary debug logging statements (NSLog, printf, LOGF, or any engine-specific logging added for debugging)
- Remove any diagnostic code, test values, or hardcoded overrides used during development
- Replace hardcoded workarounds with proper implementations
- Clean up any commented-out code
- Report: what was cleaned up.

### 11. Deferred Work Markers

Review all deferred work:
- Any known gaps get `STUB(Mx)` or `TODO` comments with clear descriptions.
- Report: list of deferred items with their markers.

## Output: Validation Report

Present the validation results to the user:

```
## Validation Report: [milestone name]

### Runtime Verification
[Did the app run? Success criterion met? Crashes?]

### Visual Correctness
[Screenshot analysis, user-confirmed visual result, or issues identified]

### GPU Frame Capture
[Resource binding correctness confirmed, or issues identified. "N/A — non-rendering milestone" if skipped.]

### Ground Truth Comparison
[Which ground truths compared, discrepancies found, whether expected or needing investigation. "No reference artifacts available" if none.]

### Metal Validation
[Results — errors found/fixed/deferred]

### Memory and Safety
[Results — leaks found/fixed]

### Skill-Driven Review
[Guidance sections checked, violations found/fixed]

### Data Flow Verification
[Struct members traced, mismatches found/fixed. Resource binding chains verified.]

### Code Review
[Issues found/fixed]

### Pressure Hacks Cleaned
[What was refactored]

### Deferred Work
[STUB/TODO items remaining]

### Overall Status
[Clean / Issues remaining — recommendation to proceed or fix first]
```

## Request User Review

After presenting the validation report, ask the user to review the changes and provide feedback. Incorporate any feedback before closing out the milestone.

**Gate: STOP after presenting validation results.** Wait for the user to review. The user will invoke `/porting-handoff` when satisfied.

> "Validation complete. Run `/porting-handoff` to write the handoff note and close out this milestone."

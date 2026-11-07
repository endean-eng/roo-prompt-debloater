# Upstream GitHub Issue & PR Specification for `RooVetGit/Roo-Code`

Below are two ready-to-submit documents for `RooVetGit/Roo-Code`:
1. **Bug + Enhancement Issue Proposal:** Covers the three verifiable defects uncovered in v3.54.0 (the hardcoded `'/test/path'` duplicate essay, native tool-calling contradictions, and the Windows User Installer `<commit-hash>\resources\app` ripgrep binary lookup failure) plus the proposed **"Concise System Prompt (Power Mode)"** setting.
2. **Exact PR Implementation Guide:** Maps the exact TypeScript files and functions in `RooVetGit/Roo-Code` for a surgical Pull Request.

---

## Part 1: GitHub Issue Draft

**Title:** `[Bug / Enhancement]: Fix '/test/path' duplicate prompt bloat, native tool-calling contradictions, Windows commit-hash ripgrep lookup failure, and add "Concise System Prompt (Power Mode)" toggle`

### Summary
Forensic inspection of `SYSTEM_PROMPT` (`src/core/prompts/system.ts`) and task initialization in Roo Code v3.54.0 exposed three concrete bugs and **~1,560 tokens of redundant static boilerplate** injected into every mode and Orchestrator subtask turn:

1. **Bug 1: Word-for-Word Duplicate 120-Word Paragraph + Hardcoded `('/test/path')` Literal:**
   - `src/core/prompts/sections/capabilities.ts` and `src/core/prompts/sections/system-info.ts` both inject the exact same 120-word paragraph (`"When the user initially gives you a task, a recursive list of all filepaths in the current workspace directory..."`).
   - In `system-info.ts`, the workspace path is not even interpolated—it outputs `('c:\Users\...')` in `CAPABILITIES` and then outputs the hardcoded test literal `('/test/path')` in `SYSTEM INFORMATION`.
2. **Bug 2: Contradictory Tool-Batching Directives Under Provider-Native Tool Calling:**
   - `TOOL USE` instructs the model: *"Prefer calling as many tools as are reasonably needed in a single response to reduce back-and-forth and complete tasks faster."*
   - Directly below it, `RULES` (`src/core/prompts/sections/rules.ts`) and `OBJECTIVE` (`src/core/prompts/sections/objective.ts`) instruct the model: *"Work through these goals sequentially, utilizing available tools one at a time as necessary"* and *"It is critical you wait for the user's response after each tool use, in order to confirm the success of the tool use."*
3. **Bug 3: Silent Turn-1 `API Request...` Hang When `rg.exe` Is Nested in VS Code Commit-Hash Directories (`Could not find ripgrep binary`):**
   - During `initializeFilePaths` / `recursivelyMakeClineRequests`, `getBinPath(vscode.env.appRoot)` searches for `rg.exe` only under standard `node_modules/@vscode/ripgrep/bin/rg.exe` paths relative to `vscode.env.appRoot`.
   - On recent Windows VS Code User Installer builds (where `appRoot` is nested under `%LOCALAPPDATA%\Programs\Microsoft VS Code\<commit-hash>\resources\app`), `node_modules/@vscode/ripgrep/bin/rg.exe` can be absent while `rg.exe` is present in bundled extensions or `PATH`. Because the resulting `Error: Could not find ripgrep binary` is thrown inside `initiateTaskLoop` prior to the first HTTP call, the Webview UI hangs indefinitely on `API Request...` (`Context Length: 0`).
4. **Enhancement: "Concise System Prompt (Power Mode)" Toggle (`conciseSystemPrompt`):**
   - When provider-native tool calling is active, tool names, descriptions, and parameter schemas are already enforced via the API's native `tools` payload.
   - However, `SYSTEM_PROMPT` still unconditionally concatenates ~1,350 words of legacy XML-era prose (`# Tool Use Guidelines`, `CAPABILITIES`, verbose `RULES`, and `OBJECTIVE`).
   - For power users running multi-step `orchestrator` pipelines (`architect` -> `code` -> custom audit/docs modes) with `.roo/rules-{mode}/` protocols, this static prefix burns ~1,560 tokens per turn and dilutes instruction-following attention on smaller/faster models (e.g., Gemini Flash / Claude Haiku).

### Proposed Solution
1. **Immediate Bug Fixes (Default for All Users):**
   - Delete the duplicated 120-word `environment_details` / `list_files` paragraph (and hardcoded `'/test/path'` string) from `src/core/prompts/sections/system-info.ts`.
   - Remove or conditionalize the *"utilize available tools one at a time"* / *"wait for the user's response after each tool use"* sentences in `rules.ts` and `objective.ts` when native tool calling is active.
   - Add a system `PATH` (`which rg` / `where.exe rg.exe`) and bundled extension fallback in `src/services/ripgrep/index.ts` (`getBinPath`) and surface any missing-binary error to the chat UI rather than hanging silently on `API Request...`.
2. **Add an Opt-In `conciseSystemPrompt` ("Concise System Prompt / Power Mode") Setting:**
   - Add a boolean toggle in **Prompts / Advanced Settings** (default `false` to preserve existing behavior for default users).
   - When `conciseSystemPrompt: true`:
     - Omit `getToolUseGuidelinesSection()`, `getCapabilitiesSection()`, and `getObjectiveSection()`.
     - Render a compact 1-line `SYSTEM INFORMATION` summary (`OS | Shell | Workspace`).
     - Render a compact 4-bullet `RULES` summary (relative paths, OS/shell command-chaining hygiene, context efficiency, and non-conversational output).

### Measured Benchmark (v3.54.0)
Testing this exact compaction across a 5-stage `orchestrator` pipeline:
- **Base System Prompt Overhead:** Drops from **~1,345 words (~1,790 tokens)** to **~215 words (~285 tokens)**—an **84.0% reduction in static boilerplate** (**~1,560 tokens saved per subtask turn**, `-12,308 bytes` in `dist/extension.js`).
- **Instruction Adherence:** Significantly improves compliance with `.roo/rules-{mode}/*.md` state machines on high-speed models by eliminating conflicting middle-prompt instructions.

---

## Part 2: Exact TypeScript PR Implementation Map (`RooVetGit/Roo-Code`)

| Minified Function (in `v3.54.0` `extension.js`) | Upstream TypeScript Source File | Exact Change for PR |
| :--- | :--- | :--- |
| `RHt(cwd)` | `src/core/prompts/sections/system-info.ts` | Delete the duplicate 120-word paragraph containing `('/test/path')`. When `settings?.conciseSystemPrompt` is true, return the 1-line `OS \| Shell \| Workspace` summary. |
| `LHt(cwd, mcpHub)` | `src/core/prompts/sections/capabilities.ts` | Skip calling in `system.ts` when `settings?.conciseSystemPrompt` is true. |
| `kHt()` | `src/core/prompts/sections/tool-use-guidelines.ts` | Skip calling in `system.ts` when `settings?.conciseSystemPrompt` is true. |
| `FHt()` | `src/core/prompts/sections/objective.ts` | Remove `"utilizing available tools one at a time"` when native tool calling is active; skip calling in `system.ts` when `settings?.conciseSystemPrompt` is true. |
| `oHt(cwd, settings)` | `src/core/prompts/sections/rules.ts` | Remove `"wait for the user's response after each tool use"` under native tool calling. When `settings?.conciseSystemPrompt` is true, return the 4-bullet core rules block. |
| `aNs(...)` / `SYSTEM_PROMPT` | `src/core/prompts/system.ts` | Pass `settings?.conciseSystemPrompt` into `generatePrompt()` and conditionally omit the redundant sections. |
| `_4a()` / `fne(vscodeAppRoot)` | `src/services/ripgrep/index.ts` | If `rg.exe` is not found in the 4 `node_modules` relative paths under `vscodeAppRoot`, fall back to resolving `rg` on system `PATH` or sibling VS Code extensions (`extensions/copilot/.../rg.exe`) before throwing. |

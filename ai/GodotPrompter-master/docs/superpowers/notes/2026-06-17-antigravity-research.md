# Antigravity — Platform Research Digest (for v1.10.0 platform support)

> Gathered 2026-06-17 from official Google Codelabs, Google Cloud Community (Medium), agentpedia.codes,
> and Dazbo/Deven Goratela's MCP+Skills guide, to pin the skill-loading facts needed before Task 13
> (tool-mapping file) can be written.
>
> **Official docs caveat:** `https://antigravity.google/docs/skills` and
> `https://antigravity.google/docs/sdk-overview` both return empty pages (client-side rendering).
> All findings are triangulated from the sources cited inline. Confidence levels are stated explicitly.
>
> **Local install check (2026-06-17):** No Antigravity install found on this Windows machine.
> `~/.gemini/` does not exist; no `agy` binary present.

## 1. What is Antigravity?

Google Antigravity (announced at Google I/O 2026) is an agent-first coding platform that ships as four
components:

- **Antigravity 2.0** — the flagship desktop app (agent-first, VS Code-based)
- **Antigravity IDE** — VS Code fork with deep agent integration
- **Antigravity CLI** (`agy`) — a Go-based terminal-first agent (successor to Gemini CLI)
- **Antigravity SDK** — Python library for programmatic agent construction

All four share the same skill format (`SKILL.md`) and global config directory. Sources:
[TechCrunch I/O 2026 announcement](https://techcrunch.com/2026/05/19/google-launches-antigravity-2-0-with-an-updated-desktop-app-and-cli-tool-at-io-2026/),
[MarkTechPost](https://www.marktechpost.com/2026/05/19/google-launches-antigravity-2-0-at-i-o-2026-a-standalone-agent-first-platform-with-cli-sdk-managed-execution-and-enterprise-support/).

## 2. Workspace (project-scoped) skills directory — RESOLVED

**Recommended path: `.agents/skills/<skill-name>/SKILL.md`**

This is the current standard as of 2026. It is confirmed by three independent sources:

| Source | Claimed path | Authority |
|--------|-------------|-----------|
| [Google Codelabs "Getting Started"](https://codelabs.developers.google.com/getting-started-google-antigravity) | `.agents/skills/` | Official |
| [Google Codelabs "Autonomous Dev Pipelines"](https://codelabs.developers.google.com/autonomous-ai-developer-pipelines-antigravity) | `.agents/skills/` | Official |
| [agentpedia.codes CLI Deep Dive](https://agentpedia.codes/blog/antigravity-cli-deep-dive) | `.agents/skills/` | Community |
| [agentpedia.codes Skills Setup Guide](https://agentpedia.codes/blog/antigravity-skills-setup-guide) | `.agent/skills/` | Community |
| [agensi.io Skills Guide](https://www.agensi.io/learn/antigravity-ide-skills-guide) | `.antigravity/skills/` | Community |
| [George Mao, Medium](https://medium.com/google-cloud/tutorial-getting-started-with-antigravity-skills-864041811e0d) | `.agent/skills/` (CLI) / `.agents/skills/` (IDE) | Google Cloud Community |

**Resolution:**

- `.agents/skills/` (plural) is the **current standard** for all Antigravity products (IDE, 2.0, CLI).
  Confirmed by two official Google Codelabs.
- `.agent/skills/` (singular) is an **older convention** from the Gemini CLI era / early Antigravity CLI,
  maintained for backward compatibility. George Mao's article (Google Cloud Community, June 2026) treats
  `.agent/skills/` as CLI-specific and `.agents/skills/` as IDE-standard. agentpedia.codes Skills Setup
  Guide uses `.agent/skills/` but its CLI Deep Dive article (a later piece) uses `.agents/skills/`.
- `.antigravity/skills/` is mentioned only by agensi.io and is not corroborated by any official source or
  other community guide. **Treat as incorrect or product-specific variant — not recommended.**

**Confidence: HIGH** that `.agents/skills/` is the correct current workspace path for Antigravity 2.0 and
IDE. **MEDIUM** that `.agent/skills/` still works for the CLI (backward compat). `.antigravity/skills/`
should not be used.

## 3. Global skills directory — PARTIALLY RESOLVED

Three paths appear in the literature. Dazbo's guide (the most technically detailed community source)
explicitly tested all of them:

| Source | Claimed global path | Status |
|--------|-------------------|--------|
| Brief / initial search summary | `~/.gemini/antigravity/skills/` | **Incorrect per Dazbo** |
| [Dazbo / Deven Goratela](https://devengoratela.com/2026/05/configuring-mcp-servers-and-skills-for-antigravity-cli-and-ide/) | `~/.gemini/skills/` | Verified working (shared across all tools) |
| [Dazbo / Deven Goratela](https://devengoratela.com/2026/05/configuring-mcp-servers-and-skills-for-antigravity-cli-and-ide/) | `~/.gemini/antigravity-cli/skills/` | Working for CLI only |
| [Google Codelabs "Getting Started"](https://codelabs.developers.google.com/getting-started-google-antigravity) | `~/.gemini/config/skills/` | Official codelab |
| [George Mao, Medium](https://medium.com/google-cloud/deep-dive-antigravity-agent-skills-b303bf05085b) | `~/.gemini/skills/` | Google Cloud Community |

**Resolution:**

- `~/.gemini/config/skills/` is the **official-documented global path**, specified explicitly in the
  Google Codelabs "Getting Started with Google Antigravity" codelab: "Global Scope
  (`~/.gemini/config/skills/`): Available across all Antigravity products (Antigravity, Antigravity IDE,
  Antigravity CLI) and projects."
- `~/.gemini/skills/` is a **community-verified alias** — confirmed working by both George Mao (Google
  Cloud Community) and Dazbo's live test. Reported to work in practice, but not the path the official
  codelab names.
- `~/.gemini/antigravity-cli/skills/` is CLI-specific only.
- `~/.gemini/antigravity/skills/` is **confirmed incorrect** by Dazbo's live testing — skills placed
  there are not picked up.

**Confidence: HIGH** that `~/.gemini/config/skills/` is the correct shared global path (official Codelab source).
**Confidence: MEDIUM** that `~/.gemini/skills/` works as an alias (community-verified, Dazbo live test).

## 4. SKILL.md frontmatter fields

Three fields are documented across sources:

```yaml
---
name: my-skill-name        # required — skill identifier; defaults to directory name if omitted
description: Use when ...  # required — semantic trigger for skill activation (most important field)
tools: mcp_server_name_*   # optional — filters which MCP servers the skill can access
---
```

Details:

- **`name`**: Required identifier. Lowercase with hyphens. Defaults to the directory name if omitted
  (per official Codelabs). Sources:
  [Google Codelabs](https://codelabs.developers.google.com/getting-started-google-antigravity),
  [George Mao (Medium)](https://medium.com/google-cloud/tutorial-getting-started-with-antigravity-skills-864041811e0d).
- **`description`**: The most important field; functions as the semantic trigger for skill activation.
  Mandatory. Sources: same as above.
- **`tools`**: Optional. Specifies which MCP server(s) the skill can access, using wildcard syntax (e.g.,
  `mcp_google-developer-knowledge_*`). This filters available MCP tools when the skill runs, reducing
  context noise. Source: [George Mao (Medium)](https://medium.com/google-cloud/deep-dive-antigravity-agent-skills-b303bf05085b).
- One source ([mcpdirectory.app](https://mcpdirectory.app/blog/how-to-use-antigravity-skills-2026)) also
  lists `version` — but this is not corroborated by any official source. Treat as unofficial/optional.

**GodotPrompter implication:** GodotPrompter's existing `name:` and `description:` frontmatter is already
compatible. No `tools:` override is needed for the base skill install (users can add it themselves if they
want to scope skills to specific MCP servers). No format changes required for the existing skill files.

## 5. `references/` subdirectory handling

Behavior is **not automatically indexed** — Antigravity does not scan `references/` at load time and
inject the contents into context. The body of `SKILL.md` must explicitly instruct the agent to read a
specific file from the `references/` folder when it is needed.

This is consistent with how GodotPrompter already uses Pattern X: the skill body contains "if you need
detail on X, read `references/X.md`." That instruction works the same way in Antigravity.

Sources:
[Google Codelabs "Getting Started"](https://codelabs.developers.google.com/getting-started-google-antigravity)
(confirms `references/` holds on-demand content, not auto-loaded);
[agentpedia.codes Skills Setup Guide](https://agentpedia.codes/blog/antigravity-skills-setup-guide)
("large schemas, templates, and documentation should go in references/ — not in the SKILL.md body").

**Confidence: HIGH.** Both official codelab and community sources agree that `references/` is read on
explicit instruction, not auto-indexed. This is the same behavior as Claude Code.

## 6. AGENTS.md / rules file

Mixed picture across sources:

- The `AGENTS.md` at the GodotPrompter repo root is a re-export that delegates to the
  `using-godot-prompter` skill. Antigravity does not natively read `AGENTS.md` in the same way Codex
  does (it is not a recognised Antigravity config file).
- However, the Autonomous Dev Pipelines codelab uses `.agents/agents.md` (lowercase `a`, inside the
  `.agents/` folder) as an agent-persona definition file distinct from skills. This is different from
  the root `AGENTS.md` Codex reads.
- Dazbo's guide references `~/.gemini/GEMINI.md` as a config file (user preferences / system instructions),
  analogous to Claude Code's `CLAUDE.md`.

**Conclusion:** GodotPrompter's root `AGENTS.md` will NOT be auto-read by Antigravity as project
instructions. For Antigravity users who want project-level system instructions, the equivalent would be
placing instructions in a `.gemini/GEMINI.md` file at the project root. This is a gap to note in the
`using-godot-prompter` skill when Antigravity support is added (Task 13).

Sources:
[Codelabs Autonomous Pipelines](https://codelabs.developers.google.com/autonomous-ai-developer-pipelines-antigravity),
[Dazbo / Deven Goratela](https://devengoratela.com/2026/05/configuring-mcp-servers-and-skills-for-antigravity-cli-and-ide/).

## 7. Antigravity built-in tool names

The Antigravity CLI hands-on codelab and related sources reveal these tool function names:

| Claude Code tool (canonical) | Antigravity CLI equivalent | Source |
|-----------------------------|---------------------------|--------|
| `Read` (file reading) | `Read()` | [Codelabs Hands-On](https://codelabs.developers.google.com/antigravity-cli-hands-on) |
| `Write` (file creation) | `Create()` | [Codelabs Hands-On](https://codelabs.developers.google.com/antigravity-cli-hands-on) |
| `Edit` (file editing) | `Edit()` / `Replace()` (unconfirmed exact name) | Inferred from "multi-file editing" capability docs |
| `Bash` (run commands) | `Bash()` | [WebSearch result](https://beginnersinai.org/google-antigravity/) |
| `Glob` (search files by name) | `ListDir()` | [Codelabs Hands-On](https://codelabs.developers.google.com/antigravity-cli-hands-on) |
| `Grep` (search file content) | Likely `grep`-like via `Bash()` | No explicit tool found |
| `WebSearch` (web search) | `WebSearch()` | [Codelabs Hands-On](https://codelabs.developers.google.com/antigravity-cli-hands-on) |
| `WebFetch` (fetch a URL) | `ReadURL()` | [Codelabs Hands-On](https://codelabs.developers.google.com/antigravity-cli-hands-on) |
| `Task` (dispatch subagent) | `Subagent()` / delegate via natural language | Inferred from subagent capability docs |
| `Skill` (invoke a skill) | No equivalent tool call — skills activate via description matching | Multiple sources |

**Confidence notes:**
- `Read()`, `Create()`, `ListDir()`, `ReadURL()`, `WebSearch()` — **HIGH** (verbatim from official codelab).
- `Bash()` — **HIGH** (multiple sources confirm shell execution tool).
- `Edit()` / `Replace()` — **LOW** (name not confirmed; multi-file editing is documented as a capability
  but the exact tool function name is not exposed in public docs). The Codelabs source mentions
  `replace_file_content` as a generic descriptor, not a confirmed tool name.
- Subagent tool name — **LOW** (capability confirmed, exact API name unconfirmed in public docs).
- No dedicated grep/content-search tool found; likely falls through to `Bash()` with `grep`.

These tool names will be the basis for `skills/using-godot-prompter/references/antigravity-tools.md`
in Task 13. Flag `Edit` and subagent names as "verify against official docs when available" in that file.

## 8. Skill discovery — how Antigravity picks a skill

Skills are loaded **progressively** (source:
[agentpedia.codes Skills Setup Guide](https://agentpedia.codes/blog/antigravity-skills-setup-guide)):

1. At startup, Antigravity **indexes only the frontmatter** of all skills in the workspace and global
   directories. The body and `references/` files are not loaded into context.
2. When the user's prompt semantically matches a skill's `description`, that skill is selected.
3. The full SKILL.md body (and any explicitly referenced `references/` files) is loaded into context.

**Priority:** workspace skills (`.agents/skills/`) override global skills with the same name.

This matches Claude Code's behaviour exactly. GodotPrompter's 16 KB SKILL.md size budget (v1.7.0
token-budget rule) applies equally to Antigravity — body is loaded on demand, not upfront.

## 9. Recommended install path for GodotPrompter users

**Recommendation: workspace symlink into `.agents/skills/`**

```
# From your Godot project root (Linux/macOS):
mkdir -p .agents
ln -s /path/to/GodotPrompter/skills .agents/skills

# Windows (PowerShell, run as admin or with developer mode):
New-Item -ItemType Junction -Path .agents\skills -Target D:\Godot\GodotPrompter\skills
```

Or global install:

```
# Symlink individual skill folders so each is a direct child of the skills dir (recommended):
ln -s /path/to/GodotPrompter/skills/* ~/.gemini/config/skills/
# Each skill folder becomes:  ~/.gemini/config/skills/player-controller/SKILL.md

# Alternative — clone the whole repo (but see nesting caveat below):
git clone https://github.com/jame581/GodotPrompter ~/.gemini/config/skills/godot-prompter
# Each skill folder becomes:  ~/.gemini/config/skills/godot-prompter/player-controller/SKILL.md
```

> **Nesting caveat (open verify-item):** If Antigravity discovers skills as immediate subdirectories of
> the skills dir (`<skills-dir>/<skill-name>/SKILL.md`), the clone approach nests skills one level too
> deep and they may not be picked up. Prefer the `ln -s skills/*` form so each skill is a direct child,
> or confirm that nested discovery (`<skills-dir>/<repo>/skills/<skill>/SKILL.md`) actually works before
> recommending the clone path.

**No loader/manifest directory is needed.** Skills load directly from the skills directory by
subdirectory-name + SKILL.md discovery. There is no `plugin.json` or index file required.

**GodotPrompter layout is already compatible:** each skill lives in `skills/<skill-name>/SKILL.md`
with the required `name:` and `description:` frontmatter. The only delta from the current Claude Code
install path is the target directory name (`.agents/skills/` vs the user's own setup).

The workspace symlink approach is preferred for active Godot development (skills stay up to date with
git pull). The global clone is better for users who want GodotPrompter available across all projects.

## 10. Unresolved items / gaps for Task 13

1. **Edit tool exact name**: `Edit()` vs `Replace()` vs `replace_file_content`. Mark as "verify" in the
   tool-mapping file.
2. **Subagent tool name**: capability confirmed, API name not found in public docs.
3. **Grep equivalent**: no dedicated tool found — likely `Bash("grep ...")`. Mark as such.
4. **`~/.gemini/config/skills/` vs `~/.gemini/skills/`**: codelab names `~/.gemini/config/skills/` as
   official; `~/.gemini/skills/` is a community-verified alias. Document `~/.gemini/config/skills/` as
   primary in Task 13 tool-mapping file.
5. **GEMINI.md / project instructions**: GodotPrompter's `AGENTS.md` is not read by Antigravity. A note
   for Antigravity users should be added to the `using-godot-prompter` skill (or a `.gemini/GEMINI.md`
   should be added to the repo that re-exports the skill). Not blocking for Task 13 but worth flagging.
6. **`tools:` frontmatter field**: GodotPrompter skills don't currently use it. No change needed, but
   advanced users may want to scope Godot skills to specific MCP servers.

## Sources

- [Google Codelabs: Authoring Google Antigravity Skills](https://codelabs.developers.google.com/getting-started-with-antigravity-skills)
- [Google Codelabs: Getting Started with Google Antigravity](https://codelabs.developers.google.com/getting-started-google-antigravity)
- [Google Codelabs: Hands-on with Antigravity CLI](https://codelabs.developers.google.com/antigravity-cli-hands-on)
- [Google Codelabs: Autonomous Dev Pipelines with Antigravity](https://codelabs.developers.google.com/autonomous-ai-developer-pipelines-antigravity)
- [George Mao (Google Cloud Community): Deep Dive: Antigravity Agent Skills](https://medium.com/google-cloud/deep-dive-antigravity-agent-skills-b303bf05085b)
- [George Mao (Google Cloud Community): How to Build Custom Skills in Google Antigravity](https://medium.com/google-cloud/tutorial-getting-started-with-antigravity-skills-864041811e0d)
- [Dazbo / Deven Goratela: Configuring MCP Servers and Skills for Antigravity CLI and IDE](https://devengoratela.com/2026/05/configuring-mcp-servers-and-skills-for-antigravity-cli-and-ide/) — mirror of [Medium original](https://medium.com/google-cloud/configuring-mcp-servers-and-skills-for-antigravity-cli-and-ide-a938c7eebb78)
- [agentpedia.codes: Antigravity Skills Setup Guide](https://agentpedia.codes/blog/antigravity-skills-setup-guide)
- [agentpedia.codes: Antigravity CLI Deep Dive](https://agentpedia.codes/blog/antigravity-cli-deep-dive)
- [TechCrunch: Google launches Antigravity 2.0 at IO 2026](https://techcrunch.com/2026/05/19/google-launches-antigravity-2-0-with-an-updated-desktop-app-and-cli-tool-at-io-2026/)
- [MCP Directory: How to Use Antigravity Skills](https://mcpdirectory.app/blog/how-to-use-antigravity-skills-2026)

## Verification result (2026-06-17) — Task 16

**Status: FORMAT-VERIFIED, RUNTIME-PENDING.**

- **Format verification (done):** Antigravity's documented Agent Skill format — a `SKILL.md` with `name` + `description` frontmatter plus a `references/` subfolder for load-on-demand material — is identical to GodotPrompter's existing skill structure. GodotPrompter skills therefore require no structural change to load in Antigravity. The tool-name mapping (`skills/using-godot-prompter/references/antigravity-tools.md`) and install paths are grounded in the sources above.
- **Runtime verification (NOT done):** No Antigravity install exists on the v1.10.0 dev machine. Checked `~/.gemini` (absent), `%LOCALAPPDATA%\Programs\Antigravity`, `%LOCALAPPDATA%\Antigravity`, `C:\Program Files\Antigravity`, and `antigravity` on PATH — none present. Discovery + invocation in a live Antigravity install was therefore NOT exercised.
- **Carried-forward open items for a future release** (do not claim as verified): (1) the exact file-edit / subagent-dispatch / content-search tool names (marked unconfirmed in `antigravity-tools.md`); (2) whether global skill discovery accepts nested clones or requires flat per-skill subdirectories (the clone-nesting caveat); (3) confirmation that `references/` subfolders resolve identically at runtime. Install docs (`antigravity-tools.md`, `using-godot-prompter/SKILL.md`) are labeled with these caveats rather than overclaiming.

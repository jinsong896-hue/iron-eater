# C# Parity Debt — v1.5.0 baseline

The validator (added in v1.5.0) flags these GDScript-only sections. They are intentional gaps for now — adding correct C# requires per-section authorship that exceeded v1.5.0 scope. Future minor releases should pick this up.

## v1.6.0 progress (2026-05-02)

10 short / trivial sections closed by `godot-csharp-engineer` in parity mode. Validator warning count dropped from 42 → 32. Remaining 23 sections continue to be picked up in v1.6.x point releases.

Also: section names in the camera-system and save-load entries were aligned with the validator's reported headings (was descriptive labels, now matches `## ` heading text), and a missing camera-system entry ("7. Split Screen") was added to bring the deferred list to true parity with the validator output.

---

## v1.7.0 progress (2026-05-06)

4 medium-complexity sections closed by `godot-tools-engineer` in dogfood mode — all four `addon-development` deferred sections (Custom Inspector Plugin, Custom Resource Editors, Gizmos, Testing Plugins). With this, **`addon-development` becomes the first skill in the repo with fully closed C# parity.** Three of the four landed in `references/` (post-restructure) and one (Testing Plugins) stayed in core SKILL.md.

Validator deferred-parity warning count: 23 → 19. Token-budget warning count: 35 → 24 (the top-10 plus `addon-development` were restructured this release; remaining 24 over-budget skills tracked in the new `2026-05-06-token-budget-debt.md`).

---

## v1.8.0 progress (2026-05-17)

**C# parity initiative complete.** All 19 remaining deferred sections closed in this release:

| Skill | Section(s) closed | Location |
|---|---|---|
| `camera-system` | 5 Camera3D Patterns, 6 Camera Transitions, 7 Split Screen | references/ |
| `dedicated-server` | 6 Deployment | references/ |
| `dependency-injection` | 7 Testing with DI, 9 Anti-patterns | references/ + SKILL.md |
| `dialogue-system` | 5 Branching, 6 Dialogue UI, 7 External Formats | references/ |
| `event-bus` | 6 Typed Signal Parameters, 8 Testing | SKILL.md + references/ |
| `localization` | 6 Locale-Aware Formatting | SKILL.md |
| `player-controller` | 5 Common Movement Recipes (Dash, WallJump) | SKILL.md |
| `resource-pattern` | 10 Anti-patterns | SKILL.md |
| `save-load` | 4 Save Architecture, 6 Version Migration | references/ |
| `scene-organization` | 4 Node Communication Patterns | SKILL.md |
| `shader-basics` | 7 Compositor Effects | references/ |
| `state-machine` | 4 Resource-Based Approach | SKILL.md |

Validator visible `csharp-parity-missing` count: 7 → **0**. Overall validator: 22 → 10 warnings (7 csharp-parity-missing closed; the remaining 10 are all `csharp-parity-accepted` intentional GDScript-only; 0 `token-budget-exceeded`).

**The v1.5.0 C# parity initiative spanning v1.6.0–v1.8.0 is complete after this release** (33 → 0 deferred sections). Every skill in the repo now has matching C# code for every GDScript example, except the intentional `csharp-parity-accepted` category (the `gdscript-patterns` and `gdscript-advanced` skills, which are GDScript-by-design).

Carry-over notes for follow-up polish:
- 5 skills still trigger `token-budget-exceeded`: `3d-essentials`, `ai-navigation`, `animation-system`, `multiplayer-basics`, `physics-system`. All sit at 16.1–16.3 KB. Candidate for a future token-budget point release.

Pre-tag code review surfaced four correctness issues (inverted null-check semantics in dependency-injection, broken `.Connect(methodGroup)` in dialogue-system, missing gravity + horizontal movement in player-controller Wall Jump C#, fictitious gdUnit4 APIs in test examples). All four were fixed before re-tagging; the player-controller fix used Pattern X to move Section 5 into `references/common-movement-recipes.md`, where proper C# could be written without budget pressure.

---

## Deferred (count: 0 — initiative complete in v1.8.0; originally 33; 10 closed in v1.6.0; 4 closed in v1.7.0; 19 closed in v1.8.0; 1 missing entry added during v1.6.0 cleanup)

These sections have GDScript code but no C# block. Each entry notes what kind of C# would belong so a future author can pick up any single item in isolation.

- ~~`skills/2d-essentials/SKILL.md` — Section "8. 2D Antialiasing" — short GDScript `draw_line()` call; C# equivalent is a `DrawLine()` call in a `_Draw()` override, plus a note that `Line2D.Antialiased` is a property set in the Inspector (no code needed)~~ **(closed in v1.6.0)**
- ~~`skills/addon-development/SKILL.md` — Section "4. Custom Inspector Plugin" — medium complexity; needs `EditorInspectorPlugin` subclass in C# with `#if TOOLS` guard, `_CanHandle`, `_ParseBegin`, `_ParseProperty` overrides, and the registration boilerplate in the `EditorPlugin` subclass~~ **(closed in v1.7.0)** — section moved to `references/inspector-plugins.md` during restructure
- ~~`skills/addon-development/SKILL.md` — Section "6. Custom Resource Editors" — needs C# for `EditorResourcePicker` embedded in a dock tool control, and a `EditorResourcePreviewGenerator` subclass with `_Handles` and `_Generate` overrides; `#if TOOLS` guards throughout~~ **(closed in v1.7.0)** — section moved to `references/inspector-plugins.md` during restructure
- ~~`skills/addon-development/SKILL.md` — Section "7. Gizmos" — needs C# `EditorNode3DGizmoPlugin` subclass with `_Init`, `_GetGizmoName`, `_HasGizmo`, `_Redraw`, `_GetHandleValue`, `_SetHandle`, `_CommitHandle`; complex undo/redo wiring; all under `#if TOOLS`~~ **(closed in v1.7.0)** — section moved to `references/gizmos-deep-dive.md` during restructure
- ~~`skills/addon-development/SKILL.md` — Section "8. Testing Plugins" — needs C# equivalent of the plugin reload snippet and `print()` → `GD.Print()` logging guidance; the lifecycle gotcha table should note C# compilation failures specifically~~ **(closed in v1.7.0)**
- ~~`skills/audio-system/SKILL.md` — Section "4. Spatial Audio (2D & 3D)" — short C# note: `AudioStreamPlayer2D` / `AudioStreamPlayer3D` properties are identical in C#; `AudioListener2D`/`AudioListener3D.MakeCurrent()` pattern; medium length~~ **(closed in v1.6.0)**
- ~~`skills/camera-system/SKILL.md` — Section "5. Camera3D Patterns" — substantial: C# `SpringArm3D` subclass with `_UnhandledInput` and `_Process`, mouse delta accumulation, `TopLevel = true`; plus Orbit Camera variant~~ **(closed in v1.8.0)** — section in `references/camera3d-patterns.md`
- ~~`skills/camera-system/SKILL.md` — Section "6. Camera Transitions" — medium: C# `CameraTransitionManager` class with async `Transition2D` / `Transition3D` methods using `Tween` and `await ToSignal`~~ **(closed in v1.8.0)** — section in `references/transitions.md`
- ~~`skills/camera-system/SKILL.md` — Section "7. Split Screen (Local Multiplayer)" — short to medium: C# `SubViewport` setup with multiple `Camera3D` nodes assigned to `Custom Viewport`; UI side is straightforward `SubViewportContainer` placement~~ **(closed in v1.8.0)** — section in `references/split-screen.md`
- ~~`skills/component-system/SKILL.md` — Section "7. Wiring Components" — short: C# `[Export]` property wiring, `[Export] public HealthComponent HealthComponent`, `GetNode<HealthComponent>()` patterns; straightforward translation~~ **(closed in v1.6.0)**
- ~~`skills/dedicated-server/SKILL.md` — Section "1. Headless Export" — short: C# `OS.HasFeature("dedicated_server")` boot check, `RenderingServer.SetRenderLoopEnabled(false)`; export preset guidance is language-agnostic~~ **(closed in v1.6.0)**
- ~~`skills/dedicated-server/SKILL.md` — Section "6. Deployment" — Dockerfile and shell commands are language-agnostic; the only C# addition needed is a note that `.NET` runtime must be bundled in the server export and the C# `DisplayServer.GetName()` equivalent of the headless detection~~ **(closed in v1.8.0)** — section in `references/deployment.md`
- ~~`skills/dependency-injection/SKILL.md` — Section "1. The Problem" — anti-pattern GDScript blocks showing tight coupling; C# equivalents are direct translations (`GetNode<>()` calls, field assignments) — short~~ **(closed in v1.6.0)**
- ~~`skills/dependency-injection/SKILL.md` — Section "7. Testing with Dependency Injection" — needs C# GdUnit4 or similar test class with mock injection; medium complexity requiring knowledge of the test framework conventions used in the project~~ **(closed in v1.8.0)** — section in `references/testing-with-di.md`
- ~~`skills/dependency-injection/SKILL.md` — Section "9. Anti-patterns" — comment-only GDScript (no executable code); C# equivalents would be equivalent inline comments, not real code blocks — arguably acceptable without C#, but validator fires because the section contains `gdscript` fenced blocks~~ **(closed in v1.8.0)**
- ~~`skills/dialogue-system/SKILL.md` — Section "5. Branching and Conditions" — needs C# for condition evaluation logic (dictionary key checks, callable branching); medium~~ **(closed in v1.8.0)** — section in `references/branching-and-conditions.md`
- ~~`skills/dialogue-system/SKILL.md` — Section "6. Dialogue UI" — needs C# `RichTextLabel` + `Label` control wiring in a `Control` subclass; medium~~ **(closed in v1.8.0)** — section in `references/ui-presentation.md`
- ~~`skills/dialogue-system/SKILL.md` — Section "7. External Formats" — needs C# JSON parsing with `System.Text.Json` or `Godot.Collections.Dictionary` from `Json.ParseString`; medium~~ **(closed in v1.8.0)** — section in `references/external-formats.md`
- ~~`skills/event-bus/SKILL.md` — Section "6. Typed Signal Parameters" — needs C# `[Signal]` delegate with a `Resource`-based payload class and the emit/connect patterns; medium; the Dictionary option is also translatable~~ **(closed in v1.8.0)**
- ~~`skills/event-bus/SKILL.md` — Section "8. Testing" — needs C# GdUnit4 signal assertion patterns; short, but requires knowledge of how gdUnit4 C# bindings expose signal tracking~~ **(closed in v1.8.0)** — section in `references/testing.md`
- ~~`skills/localization/SKILL.md` — Section "5. Right-to-Left (RTL) Support" — needs C# `RichTextLabel` with `IsRtl()` check, `LayoutDirection` enum assignment, and `TextServer.IsLocaleRtl()`; short to medium~~ **(closed in v1.6.0)**
- ~~`skills/localization/SKILL.md` — Section "6. Locale-Aware Formatting" — needs C# `string.Format` / `CultureInfo` patterns plus `Time.GetDatetimeDictFromSystem()` → `System.DateTime` equivalents; medium~~ **(closed in v1.8.0)**
- ~~`skills/particles-vfx/SKILL.md` — Section "6. Subemitters" — `SubEmitter2D`/`SubEmitter3D` node properties; C# equivalent is setting `SubEmitterMode` and `SubEmitterMaterial` as Inspector properties; no runtime code needed beyond a short note~~ **(closed in v1.6.0)**
- ~~`skills/particles-vfx/SKILL.md` — Section "9. Flipbook Animation (2D)" — `AnimatedTexture` and `GPUParticles2D` process material properties; C# equivalent is direct property assignment on `ParticleProcessMaterial`; short~~ **(closed in v1.6.0)**
- ~~`skills/player-controller/SKILL.md` — Section "5. Common Movement Recipes" — Dash and WallJump examples labeled "(GDScript)" in subsection headings; C# translation is direct (`CharacterBody2D` subclass, `_PhysicsProcess`, `IsOnFloor()`, `GetWallNormal()`); medium~~ **(closed in v1.8.0)** — moved to `references/common-movement-recipes.md` via Pattern X after pre-tag review
- ~~`skills/resource-pattern/SKILL.md` — Section "6. Resource Collections" — typed array of `Resource` subclasses; C# `[Export] public Godot.Collections.Array<MyResource>` pattern; short~~ **(closed in v1.6.0)**
- ~~`skills/resource-pattern/SKILL.md` — Section "8. Sharing vs Unique" — `.Duplicate()` and resource instancing concepts; C# `.Duplicate()` call is identical API; short~~ **(closed in v1.6.0)**
- ~~`skills/resource-pattern/SKILL.md` — Section "10. Anti-patterns" — comment-only GDScript blocks showing bad patterns; C# equivalents are structural translations of the anti-pattern comments; short but low value~~ **(closed in v1.8.0)**
- ~~`skills/save-load/SKILL.md` — Section "4. Save Architecture Pattern" — `SaveableComponent` with `Callable` fields; C# equivalent uses `Callable.From()` or a delegate approach; medium — the `Callable` API differs meaningfully between GDScript and C#~~ **(closed in v1.8.0)** — section in `references/save-architecture.md`
- ~~`skills/save-load/SKILL.md` — Section "6. Version Migration" — incremental migration function; C# translation is a direct `switch` on `version` integer; short to medium~~ **(closed in v1.8.0)** — section in `references/version-migration.md`
- ~~`skills/scene-organization/SKILL.md` — Section "4. Node Communication Patterns" — signal bus and direct reference patterns; C# equivalents are `[Signal]` delegates and `GetNode<>()` calls; medium~~ **(closed in v1.8.0)**
- ~~`skills/shader-basics/SKILL.md` — Section "7. Compositor Effects (Godot 4.3+)" — `CompositorEffect` subclass with `@tool`; C# equivalent is a `[Tool]` class extending `CompositorEffect` with `_RenderCallback` override and `RenderingDevice` access; medium complexity, render pipeline knowledge required~~ **(closed in v1.8.0)** — section in `references/compositor-effects.md`
- ~~`skills/state-machine/SKILL.md` — Section "4. Approach 3: Resource-Based (Data-Driven)" — `Resource`-based state data pattern; C# uses `[Export]` on a `Resource` subclass with `GodotObject` method dispatch; medium~~ **(closed in v1.8.0)**

---

## Accepted (intentional GDScript-only — not debt)

- `skills/gdscript-patterns/SKILL.md` — all sections (9 warnings, sections 1-6, 8, 12, 13) — this skill is GDScript-by-design and explicitly documents GDScript-specific language features (`@export`, `await`, `match`, `class_name`, lambdas, annotations, `...args` variadic, `@abstract`). Adding C# to this skill would undermine its purpose. Documented in the skill itself with an intent note added in v1.5.0.

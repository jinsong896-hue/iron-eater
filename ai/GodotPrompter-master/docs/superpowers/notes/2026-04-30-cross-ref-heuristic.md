# Cross-Reference Heuristic — v1.5.0 Audit

Cross-reference audit (Task 5 of v1.5.0) treats these skills as "foundation/utility" — they may be referenced by many skills but do not need to enumerate consumers in their own "Related skills" line.

## From the plan's heuristic

- resource-pattern, event-bus, gdscript-patterns, csharp-godot, csharp-signals, math-essentials, godot-debugging, godot-testing, godot-optimization, godot-code-review, assets-pipeline, dependency-injection, scene-organization, component-system

## Added during the audit (with justification)

- **save-load** — consumed by audio-system, dialogue-system, input-handling, localization for persisting state. Each consumer's reason is specific to that subsystem; save-load itself is a generic persistence pattern.
- **godot-ui** — consumed by addon-development (custom inspectors), input-handling (UI input handling), localization (translated UI). UI is a target subsystem; consumers are domain-specific.
- **2d-essentials**, **3d-essentials** — rendering subsystem foundations; many gameplay skills reference one or the other for canvas-layer/spatial setup, but the rendering skills don't need to enumerate gameplay consumers.

## Process / Bootstrap (one-way intentional)

- godot-project-setup, godot-brainstorming — process skills; content skills mention them, they don't list back
- using-godot-prompter — bootstrap; links via the index table, not via Related skills lines

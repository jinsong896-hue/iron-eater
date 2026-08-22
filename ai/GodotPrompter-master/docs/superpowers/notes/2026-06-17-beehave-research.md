# Beehave — Godot 4.x Research Digest (for the `beehave` skill)

> Gathered 2026-06-17 from the local clone at `D:/Godot/_addon-src/beehave` pinned to **v2.9.2**.
> Primary source: GDScript under `addons/beehave/` — `blackboard.gd`, `nodes/**/*.gd`,
> `debug/`, `metrics/`, `plugin.cfg`, `plugin.gd`. Cross-checked with the repo README.
> **Beehave is GDScript-only. No official C# API exists.** (Confirmed: zero `.cs` files in
> `addons/beehave/`; the one `.cs` file in the repo belongs to the gdUnit4 test addon, not Beehave.)

---

## 1. Release metadata

| Field | Value |
|---|---|
| Version | **2.9.2** (tag `v2.9.2`) |
| Godot compatibility | 4.1.x for v2.9.x; 4.0.x for v2.7.x (from README table) |
| Minimum Godot | Godot 4 (`config_version=5` in project.godot; `config/features=PackedStringArray("4.5")` in demo project) |
| License | MIT (`addons/beehave/LICENSE`) |
| Author | bitbrain |
| Plugin name | `Beehave` (`plugin.cfg`) |
| Autoloads added | `BeehaveGlobalMetrics`, `BeehaveGlobalDebugger` |

Install path: clone or copy `addons/beehave/` into the project's `addons/` folder.
Enable via **Project > Project Settings > Plugins**. Copy `script_templates/` into the project root.
Also available on the Godot Asset Library.

---

## 2. Return codes (enum on `BeehaveNode`)

Defined verbatim in `beehave_node.gd` (and mirrored in `beehave_tree.gd`):

```
enum { SUCCESS, FAILURE, RUNNING }
# SUCCESS = 0, FAILURE = 1, RUNNING = 2  (int enum, untyped)
```

Every node that overrides `tick()` must return one of these three int values.

---

## 3. `BeehaveNode` — base class

File: `nodes/beehave_node.gd`

```
class_name BeehaveNode extends Node

# Core overridable lifecycle methods:
func tick(actor: Node, blackboard: Blackboard) -> int       # override; returns SUCCESS/FAILURE/RUNNING
func interrupt(actor: Node, blackboard: Blackboard) -> void # called when tree interrupts this node
func before_run(actor: Node, blackboard: Blackboard) -> void  # called before first tick of a run
func after_run(actor: Node, blackboard: Blackboard) -> void   # called after tick returns SUCCESS or FAILURE

# Internal:
func _safe_tick(actor: Node, blackboard: Blackboard) -> int  # validates tick() return type; returns FAILURE on bad type
func can_send_message(blackboard: Blackboard) -> bool        # true when debugger tab is visible; blackboard value set per-tick by BeehaveTree
func get_class_name() -> Array[StringName]                   # returns [&"BeehaveNode"]
```

All nodes are `@tool` — they run in the Godot editor for configuration warnings.

---

## 4. `BeehaveTree` — tree root

**Important:** `BeehaveTree extends Node`, NOT `BeehaveNode`. An `is BeehaveNode` check on a tree instance returns `false`.

File: `nodes/beehave_tree.gd`

```
class_name BeehaveTree extends Node

enum ProcessThread { IDLE, PHYSICS, MANUAL }

# Exported properties:
@export var enabled: bool = true          # enables/disables ticking; emits tree_enabled / tree_disabled
@export var tick_rate: int = 1            # tick every N frames (1 = every frame)
@export_node_path var actor_node_path: NodePath  # target actor; defaults to get_parent()
@export var process_thread: ProcessThread = ProcessThread.PHYSICS  # IDLE, PHYSICS, or MANUAL
@export var blackboard: Blackboard        # optional external Blackboard; auto-creates internal if not set
@export var custom_monitor: bool = false  # registers tree in Performance monitor
@export var actor: Node                   # the actor node (set from actor_node_path or parent)

# Signals:
signal tree_enabled
signal tree_disabled

# Methods:
func tick() -> int                        # manually tick if process_thread == MANUAL; returns status int
func enable() -> void                     # sets enabled = true
func disable() -> void                    # sets enabled = false
func interrupt() -> void                  # interrupts tree if something is running
func get_running_action() -> ActionLeaf   # returns currently running ActionLeaf or null
func get_last_condition() -> ConditionLeaf          # returns last evaluated ConditionLeaf or null
func get_last_condition_status() -> String          # returns "SUCCESS", "FAILURE", or "RUNNING"

# State:
var status: int = -1      # last returned status code
var last_tick: int = -1   # internal frame counter for tick_rate throttle
```

`BeehaveTree` must have **exactly one** BeehaveNode child (the root composite or decorator).
It auto-creates an internal `Blackboard` if none is exported.

---

## 5. `Blackboard`

File: `blackboard.gd`

```
class_name Blackboard extends Node

const DEFAULT = "default"

@export var blackboard: Dictionary = {}   # pre-populated key-value pairs (exported for inspector)

# Methods:
func set_value(key: Variant, value: Variant, blackboard_name: String = DEFAULT) -> void
func get_value(key: Variant, default_value: Variant = null, blackboard_name: String = DEFAULT) -> Variant
func has_value(key: Variant, blackboard_name: String = DEFAULT) -> bool
func erase_value(key: Variant, blackboard_name: String = DEFAULT) -> void
func keys() -> Array[String]
func get_debug_data() -> Dictionary   # sanitized dict safe to send over EngineDebugger
```

The `blackboard_name` param (default `"default"`) allows multiple named namespaces on the same
Blackboard node. Actor-scoped internal state uses `str(actor.get_instance_id())` as the name.

`erase_value` sets the key to `null` (does not delete the key from the dict). `has_value` returns
`false` if the value is `null`, so erasing correctly hides a key from `has_value`.

---

## 6. Composites

### Base class: `Composite extends BeehaveNode`

File: `nodes/composites/composite.gd`

```
class_name Composite extends BeehaveNode
var running_child: BeehaveNode = null   # tracks which child is currently RUNNING
```

Has `interrupt()`, `after_run()`, and internal helpers `_cleanup_running()` / `_interrupt_children()`.

---

### `SequenceComposite` (AND logic)

File: `nodes/composites/sequence.gd`

```
class_name SequenceComposite extends Composite
```

Ticks children left-to-right. Returns `SUCCESS` only if **all** children return `SUCCESS`.
Returns `FAILURE` on the first child `FAILURE` (resets successful_index to 0).
Returns `RUNNING` if a child is `RUNNING` (resumes at that child next tick, skips already-succeeded children).

---

### `SequenceReactiveComposite` (reactive AND)

File: `nodes/composites/sequence_reactive.gd`

```
class_name SequenceReactiveComposite extends Composite
```

Like `SequenceComposite` but re-evaluates from the **first child every tick**, even while RUNNING.
Suitable for conditions that can change mid-action.

---

### `SequenceStarComposite` (memory AND)

File: `nodes/composites/sequence_star.gd`

```
class_name SequenceStarComposite extends Composite
```

Like `SequenceComposite` but does NOT reset `successful_index` on FAILURE — resumes from where
it left off on FAILURE as well as RUNNING.

---

### `SelectorComposite` (OR logic)

File: `nodes/composites/selector.gd`

```
class_name SelectorComposite extends Composite
```

Ticks children left-to-right. Returns `SUCCESS` on the first child that returns `SUCCESS`.
Returns `FAILURE` only if **all** children return `FAILURE`. Returns `RUNNING` if a child is `RUNNING`.
Skips already-failed children across ticks (`last_execution_index`).

---

### `SelectorReactiveComposite` (reactive OR)

File: `nodes/composites/selector_reactive.gd`

```
class_name SelectorReactiveComposite extends Composite
```

Like `SelectorComposite` but re-evaluates from the **first child every tick** while RUNNING.

---

### `SimpleParallelComposite`

File: `nodes/composites/simple_parallel.gd`

```
class_name SimpleParallelComposite extends Composite

@export var secondary_node_repeat_count: int = 0   # 0 = loop secondary forever
@export var delay_mode: bool = false               # wait for secondary to finish after primary ends
```

Requires **exactly two** children: child 0 = primary, child 1 = secondary.
Always reports the primary child's status. Secondary runs alongside primary regardless of primary's result.
If `delay_mode = true`, waits for secondary's current tick to complete after primary finishes.

---

### `SequenceRandomComposite`

File: `nodes/composites/sequence_random.gd`

```
class_name SequenceRandomComposite extends RandomizedComposite

signal reset(new_order: Array[Node])   # emitted when children are reshuffled

@export var resume_on_failure: bool = false    # if true, keeps current shuffle on failure
@export var resume_on_interrupt: bool = false  # if true, keeps current shuffle on interrupt
```

Executes children in a random shuffled order. Inherits `RandomizedComposite` weight support.

---

### `SelectorRandomComposite`

File: `nodes/composites/selector_random.gd`

```
class_name SelectorRandomComposite extends RandomizedComposite
```

Tries children in random shuffled order; returns `SUCCESS` on first success, `FAILURE` if all fail.

---

### `RandomizedComposite` (shared base for random composites)

File: `nodes/composites/randomized_composite.gd`

```
class_name RandomizedComposite extends Composite

@export var random_seed: int = 0       # 0 = randomize(); nonzero = seed(random_seed)
@export var use_weights: bool          # if true, exposes per-child "Weights/<name>" int (1-100) properties

func get_shuffled_children() -> Array[Node]   # returns shuffled children array (weighted or uniform)
```

---

## 7. Decorators

### Base class: `Decorator extends BeehaveNode`

File: `nodes/decorators/decorator.gd`

```
class_name Decorator extends BeehaveNode
var running_child: BeehaveNode = null
```

Must have **exactly one** child node.

---

### `InverterDecorator`

File: `nodes/decorators/inverter.gd`

```
class_name InverterDecorator extends Decorator
```

Flips `SUCCESS` ↔ `FAILURE`. Passes `RUNNING` through unchanged.

---

### `AlwaysFailDecorator`

File: `nodes/decorators/failer.gd`

```
class_name AlwaysFailDecorator extends Decorator
```

**Note:** The brief calls this `FailerDecorator` but the actual class_name is `AlwaysFailDecorator`.
Always returns `FAILURE` (passes `RUNNING` through).

---

### `AlwaysSucceedDecorator`

File: `nodes/decorators/succeeder.gd`

```
class_name AlwaysSucceedDecorator extends Decorator
```

**Note:** The brief calls this `SucceederDecorator` but the actual class_name is `AlwaysSucceedDecorator`.
Always returns `SUCCESS` (passes `RUNNING` through).

---

### `LimiterDecorator`

File: `nodes/decorators/limiter.gd`

```
class_name LimiterDecorator extends Decorator

@export var max_count: int = 0   # max number of RUNNING ticks before returning FAILURE
```

Allows its child to be ticked at most `max_count` times while `RUNNING`. After that returns `FAILURE`.
Counter resets when child finishes (not RUNNING) or when interrupted.

---

### `CooldownDecorator`

File: `nodes/decorators/cooldown.gd`

```
class_name CooldownDecorator extends Decorator

@export var wait_time := 0.0   # cooldown duration in seconds
```

After child executes (non-RUNNING result), blocks re-execution for `wait_time` seconds by returning
`FAILURE` during cooldown. Uses `Time.get_ticks_msec()` internally. Resets on interrupt.

---

### `TimeLimiterDecorator`

File: `nodes/decorators/time_limiter.gd`

```
class_name TimeLimiterDecorator extends Decorator

@export var wait_time := 0.0   # time budget in seconds
```

Gives child `wait_time` seconds to finish. If still `RUNNING` after that, interrupts and returns `FAILURE`.
Timer tracked via `get_physics_process_delta_time()` accumulated in the Blackboard. Resets on `before_run`
or interrupt.

---

### `DelayDecorator`

File: `nodes/decorators/delayer.gd`

```
class_name DelayDecorator extends Decorator

@export var wait_time := 0.0   # delay in seconds before executing child
```

Returns `RUNNING` for `wait_time` seconds before first executing the child. Timer resets when
child is no longer RUNNING or on interrupt.

---

### `RepeaterDecorator`

File: `nodes/decorators/repeater.gd`

```
class_name RepeaterDecorator extends Decorator

@export var repetitions: int = 1   # number of times child must return SUCCESS before this returns SUCCESS
```

Executes child until it succeeds `repetitions` times. Returns `FAILURE` immediately if child fails.
Returns `RUNNING` while looping. Counter resets on `before_run` and interrupt.
**Note:** `get_class_name()` in this file returns `&"LimiterDecorator"` — this is a bug in the source
(a copy-paste error). The actual GDScript class is `RepeaterDecorator`.

---

### `UntilFailDecorator`

File: `nodes/decorators/until_fail.gd`

```
class_name UntilFailDecorator extends Decorator
```

Returns `RUNNING` as long as child returns `SUCCESS` or `RUNNING`. Returns `SUCCESS` when child
finally returns `FAILURE`. (Loop until the child fails.)

---

## 8. Leaves

### Base class chain: `Leaf extends BeehaveNode` → `ActionLeaf extends Leaf` / `ConditionLeaf extends Leaf`

Files: `nodes/leaves/leaf.gd`, `action.gd`, `condition.gd`

```
class_name Leaf extends BeehaveNode
# leaf nodes must not have BeehaveNode children (editor warning if they do)

class_name ActionLeaf extends Leaf
# long-running tasks; may return RUNNING across multiple frames

class_name ConditionLeaf extends Leaf
# single-frame checks; should never return RUNNING
```

**The leaf contract** — override `tick(actor: Node, blackboard: Blackboard) -> int`:
- Return `SUCCESS` when the action/condition is satisfied or complete.
- Return `FAILURE` when the action/condition is not satisfied or failed.
- Return `RUNNING` (ActionLeaf only) when the task needs more frames to complete.

Leaf files declare `EXPRESSION_PLACEHOLDER: String = "Insert an expression..."` — used by built-in
expression leaves (see section 9).

---

## 9. Built-in expression leaves

These are ready-to-use nodes (no GDScript required) that evaluate GDScript expressions against the Blackboard.

### `BlackboardSetAction extends ActionLeaf`

File: `nodes/leaves/blackboard_set.gd`

```
class_name BlackboardSetAction extends ActionLeaf

@export_placeholder(...) var key: String = ""     # GDScript expression for the key
@export_placeholder(...) var value: String = ""   # GDScript expression for the value
# Returns SUCCESS; FAILURE if expression fails
```

### `BlackboardEraseAction extends ActionLeaf`

File: `nodes/leaves/blackboard_erase.gd`

```
class_name BlackboardEraseAction extends ActionLeaf

@export_placeholder(...) var key: String = ""   # expression for the key to erase
# Returns SUCCESS; FAILURE if expression fails
```

### `BlackboardHasCondition extends ConditionLeaf`

File: `nodes/leaves/blackboard_has.gd`

```
class_name BlackboardHasCondition extends ConditionLeaf

@export_placeholder(...) var key: String = ""   # expression for the key to check
# Returns SUCCESS if key exists and is non-null; FAILURE otherwise
```

### `BlackboardCompareCondition extends ConditionLeaf`

File: `nodes/leaves/blackboard_compare.gd`

```
class_name BlackboardCompareCondition extends ConditionLeaf

enum Operators { EQUAL, NOT_EQUAL, GREATER, LESS, GREATER_EQUAL, LESS_EQUAL }

@export_placeholder(...) var left_operand: String = ""   # GDScript expression
@export_enum("==", "!=", ">", "<", ">=", "<=") var operator: int = 0
@export_placeholder(...) var right_operand: String = ""  # GDScript expression
# Returns SUCCESS if comparison is true; FAILURE on expression error or false comparison
```

Expression strings run via Godot's `Expression.execute([], blackboard)` — the blackboard itself
is the base instance, so expressions can call `get_value("key")` directly.

---

## 10. Visual debugger

Files: `debug/debugger.gd`, `debug/global_debugger.gd`, `debug/debugger_messages.gd`

The debugger is an `EditorDebuggerPlugin` registered by `plugin.gd` on `_enter_tree`.
Two autoloads handle runtime state:
- `BeehaveGlobalDebugger` (`global_debugger.gd`) — singleton on the running game side; listens for
  `"beehave:activate_tree"` and `"beehave:visibility_changed"` from the editor via `EngineDebugger`.
- `BeehaveGlobalMetrics` (`metrics/beehave_global_metrics.gd`) — exposes two Performance monitors:
  `"beehave/total_trees"` and `"beehave/total_enabled_trees"`.

**Enabling the debugger tab:**
- Plugin adds a `"🐝 Beehave"` tab in the bottom editor panel (Debugger section).
- Select a running tree in the tab to activate it; only one tree is active at a time.
- Optional floating window: click the detach button in the tab (or set project setting
  `beehave/debugger/start_detached = true` to start detached by default).

**Per-tree custom Performance monitor:**
- Set `custom_monitor = true` on a `BeehaveTree` to register
  `"beehave [microseconds]/process_time_<actor_name>-<id>"` in the Performance panel.

**How it works at runtime:**
- Each `BeehaveTree` calls `BeehaveDebuggerMessages.process_begin/tick/end/interrupt()` via
  `EngineDebugger.send_message("beehave:...", [...])` — only when the debugger tab is visible
  and the tree is the active tree (`_can_send_message == true`).
- The editor-side `BeehaveEditorDebugger._capture()` handles `beehave:*` prefixed messages and
  updates the graph UI.

---

## 11. GDScript-only confirmation

**Beehave is GDScript-only.** There are zero `.cs` files in `addons/beehave/`.

The only `.cs` file in the entire repository (`addons/gdUnit4/src/dotnet/GdUnit4CSharpApi.cs`) belongs
to the gdUnit4 testing framework bundled in the demo project, not to Beehave itself.

There is no official C# wrapper or C# port of Beehave. Users wishing to use Beehave from C#
can call the GDScript API via Godot's cross-language interop (e.g. `GetNode<BeehaveTree>().Call("tick")`),
but Beehave provides no typed C# classes or interfaces.

**Skill author implication:** the validator allowlist for the `beehave` skill must mark C# examples
as skill-authored, not doc-sourced. The skill itself should be GDScript-only with a note that
no official C# API exists (pattern identical to how we handle addon-specific content).

---

## 12. Class-name discrepancies (source vs. common names)

The brief uses some names that differ from actual `class_name` declarations:

| Common name | Actual `class_name` in source |
|---|---|
| `FailerDecorator` | `AlwaysFailDecorator` |
| `SucceederDecorator` | `AlwaysSucceedDecorator` |
| `RepeaterDecorator` | `RepeaterDecorator` (correct) — but `get_class_name()` erroneously returns `&"LimiterDecorator"` (copy-paste bug in v2.9.2 source) |

The skill must use the actual `class_name` values since that is what Godot's autocomplete and `is`
checks will see: `AlwaysFailDecorator`, `AlwaysSucceedDecorator`.

---

## 13. Node hierarchy diagram

```
BeehaveNode (base)
  ├── Composite
  │     ├── SequenceComposite
  │     ├── SequenceReactiveComposite
  │     ├── SequenceStarComposite
  │     ├── SelectorComposite
  │     ├── SelectorReactiveComposite
  │     ├── SimpleParallelComposite
  │     └── RandomizedComposite
  │           ├── SequenceRandomComposite
  │           └── SelectorRandomComposite
  ├── Decorator
  │     ├── InverterDecorator
  │     ├── AlwaysFailDecorator
  │     ├── AlwaysSucceedDecorator
  │     ├── LimiterDecorator
  │     ├── CooldownDecorator
  │     ├── TimeLimiterDecorator
  │     ├── DelayDecorator
  │     ├── RepeaterDecorator
  │     └── UntilFailDecorator
  └── Leaf
        ├── ActionLeaf
        │     ├── BlackboardSetAction
        │     └── BlackboardEraseAction
        └── ConditionLeaf
              ├── BlackboardHasCondition
              └── BlackboardCompareCondition

BeehaveTree (tree root; extends Node NOT BeehaveNode; not ticked by parent)
```

---

## Doc-coverage flags for skill author

1. **C# parity** — does not exist; Beehave is GDScript-only. The skill must not include C# examples
   and should include a "C# note" explaining the limitation (cross-language call via `Call()` only).
   This is a validator allowlist decision: the `beehave` skill should be listed in the validator's
   GDScript-only exception list (alongside gdextension).

2. **`MANUAL` process thread** — `tick()` is exposed publicly for manual invocation, but the README
   and wiki do not document a worked example. The skill should author a short example for
   `process_thread = MANUAL` + calling `tree.tick()` from a parent script.

3. **Sharing a single `Blackboard` across multiple trees** — a common pattern (one Blackboard node
   exported to multiple BeehaveTrees on the same actor). Not explicitly documented in README/wiki;
   the skill should author this pattern from the `@export var blackboard: Blackboard` API.

4. **Weight-based random composites** — `RandomizedComposite.use_weights` and the `Weights/<name>`
   per-child properties are configured via the inspector (dynamic property list); not easily
   represented in code. Skill should note this is inspector-only configuration.

5. **`RepeaterDecorator` `get_class_name()` bug** — returns `&"LimiterDecorator"` in v2.9.2 source.
   This means `node.get_class_name()` checks will return the wrong value for `RepeaterDecorator`.
   Flag as a known bug; do not paper over it in the skill.

6. **Process thread default is PHYSICS** — `tick()` runs in `_physics_process`. If the game uses
   `_process` for the actor, set `process_thread = IDLE`. The skill should call this out.

7. **`tick_rate` throttling** — `tick_rate = 1` means every frame; `tick_rate = 3` = every 3 frames.
   Useful for optimizing AI-heavy scenes. Author a short note with an example value.

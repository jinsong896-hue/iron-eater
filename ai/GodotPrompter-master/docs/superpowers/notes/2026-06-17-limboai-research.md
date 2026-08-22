# LimboAI — Godot 4.x Research Digest (for the `limboai` skill)

> Gathered 2026-06-17 from the local clone at `D:/Godot/_addon-src/limboai` pinned to tag **v1.7.1**.
> Primary sources: `doc_classes/*.xml` (verbatim class reference), `doc/source/**/*.rst` (tutorial docs),
> `demo/demo/**/*.gd` (example tasks and states), `gdextension/limboai.gdextension` (install config).
> Cross-checked with https://limboai.readthedocs.io/en/v1.7.1/.

## 1. Release metadata

| Field              | Value                                            |
|--------------------|--------------------------------------------------|
| **Version**        | 1.7.1 (`limboai_version.py`: major=1, minor=7, patch=1) |
| **Min Godot (GDExtension)** | 4.6 (v1.7.x per README compatibility table; `gdextension/limboai.gdextension` sets `compatibility_minimum = "4.2"` but the README explicitly states Godot 4.6 for v1.7.x) |
| **Min Godot (module)** | 4.6                                         |
| **License**        | MIT — "Copyright (c) 2023-2025 Serhii Snitsaruk and the LimboAI contributors" |
| **Repo**           | https://github.com/limbonaut/limboai            |

## 2. Install paths

### GDExtension (recommended — no custom engine required)

1. Godot AssetLib → search "LimboAI" → Download. Reload project.
2. Or download from GitHub Releases, place the `addons/limboai/` folder in `res://addons/limboai/`.
3. The `.gdextension` file ships at `res://addons/limboai/bin/` with platform entries:

```ini
[configuration]
entry_symbol = "limboai_init"
compatibility_minimum = "4.2"

[libraries]
macos.debug    = "res://addons/limboai/bin/liblimboai.macos.editor.framework"
macos.release  = "res://addons/limboai/bin/liblimboai.macos.template_release.framework"
windows.debug.x86_64   = "res://addons/limboai/bin/liblimboai.windows.editor.x86_64.dll"
windows.release.x86_64 = "res://addons/limboai/bin/liblimboai.windows.template_release.x86_64.dll"
linux.debug.x86_64     = "res://addons/limboai/bin/liblimboai.linux.editor.x86_64.so"
linux.release.x86_64   = "res://addons/limboai/bin/liblimboai.linux.template_release.x86_64.so"
# ... also: linux arm64/rv64, android arm32/arm64/x86_32/x86_64, iOS, web
```

**GDExtension limitations:** no in-editor documentation tooltips; `BBParam` property editor not available.

### Module version (custom engine build)

Download pre-compiled editor + export templates from GitHub Releases. Requires custom engine for export.
Module version has full editor integration and slightly better performance.

## 3. Core classes

### 3.1 `BT` (base `Resource`) — status constants

```gdscript
# BT.Status enum (defined in BT.xml):
BT.FRESH   = 0  # Task wasn't executed yet or was aborted/reset
BT.RUNNING = 1  # Task is being performed and hasn't finished yet
BT.FAILURE = 2  # Task has finished with failure
BT.SUCCESS = 3  # Task has finished with success
```

In task scripts, use the shorthand constants `SUCCESS`, `FAILURE`, `RUNNING` (available without prefix inside a BTTask subclass).

### 3.2 `BehaviorTree` (`Resource`)

`BehaviorTree` is a **saved `.tres` / `.res` resource** edited in the LimboAI editor panel.

| Member | Type | Notes |
|---|---|---|
| `blackboard_plan` | `BlackboardPlan` | Variable schema for new Blackboard instances |
| `description` | `String` | User-provided description (default `""`) |

| Method | Signature | Notes |
|---|---|---|
| `get_root_task()` | `-> BTTask` | Returns root task of the resource |
| `set_root_task(task)` | `(BTTask)` | Assigns a new root task |
| `instantiate(agent, blackboard, instance_owner, custom_scene_root=null)` | `-> BTInstance` | Creates a runtime BTInstance; `instance_owner` is typically the BTPlayer/BTState node; if `custom_scene_root` is non-null it is used as the scene root, otherwise the scene root defaults to `instance_owner.owner` |
| `clone()` | `-> BehaviorTree` | Makes a copy of the resource |
| `copy_other(other)` | `(BehaviorTree)` | Become a copy of another BT |

Signals: `branch_changed(branch: BTTask)` (editor only), `plan_changed`.

### 3.3 `BTPlayer` (`Node`)

`BTPlayer` executes a `BehaviorTree` resource at runtime. Add it as a child of the agent node.

| Property | Type | Default | Notes |
|---|---|---|---|
| `behavior_tree` | `BehaviorTree` | — | The BT resource to execute |
| `blackboard` | `Blackboard` | — | Shared data for tasks; set after init |
| `blackboard_plan` | `BlackboardPlan` | — | Variable overrides per-scene |
| `active` | `bool` | `true` | When `false`, BT is not executed; init is deferred until activation |
| `agent_node` | `NodePath` | `NodePath("..")` | Path to the agent (defaults to parent) |
| `update_mode` | `BTPlayer.UpdateMode` | `PHYSICS` (1) | See enum below |
| `monitor_performance` | `bool` | `false` | Adds Debugger→Monitors entry |

`BTPlayer.UpdateMode` enum:
```gdscript
BTPlayer.IDLE    = 0  # Execute during _process
BTPlayer.PHYSICS = 1  # Execute during _physics_process
BTPlayer.MANUAL  = 2  # Call update(delta) manually
```

| Method | Signature | Notes |
|---|---|---|
| `update(delta)` | `(float)` | Manual tick — only call when `update_mode == MANUAL` |
| `restart()` | `-> void` | Resets execution; does NOT reset Blackboard |
| `get_bt_instance()` | `-> BTInstance` | Returns the live BTInstance |
| `set_bt_instance(bt_instance)` | `(BTInstance)` | Swap to a different BT instance at runtime |
| `set_scene_root_hint(scene_root)` | `(Node)` | Call before adding to scene tree when creating BTPlayer dynamically |

Signals:
- `updated(status: int)` — emitted after each BT update tick
- `behavior_tree_finished(status: int)` — **deprecated**, use `updated`

### 3.4 `BTTask` (`BT` → `Resource`)

Base class for all BT tasks. **Do not extend directly** — use `BTAction`, `BTCondition`, `BTDecorator`, or `BTComposite`.

**Virtual methods to override:**

| Method | Signature | Called when |
|---|---|---|
| `_setup()` | `-> void` | Once before first tick; initialize state/config here |
| `_enter()` | `-> void` | When task is entered (status was not RUNNING in previous tick) |
| `_tick(delta)` | `(float) -> Status` | Each time task is executed; **main logic** |
| `_exit()` | `-> void` | After `_tick` returns `SUCCESS` or `FAILURE` |
| `_generate_name()` | `-> String` (const) | Editor display name (requires `@tool`) |
| `_get_configuration_warnings()` | `-> PackedStringArray` (const) | Editor warnings (requires `@tool`) |

**Properties accessible inside a task:**

| Property | Type | Notes |
|---|---|---|
| `agent` | `Node` | The agent node (usually BTPlayer's parent) |
| `blackboard` | `Blackboard` | The shared data store |
| `scene_root` | `Node` | Root of the scene the BT is used in; use for `get_node(node_path)` |
| `status` | `BT.Status` | Last status returned by `_tick` |
| `elapsed_time` | `float` | Seconds since task was entered; 0 when not RUNNING |
| `custom_name` | `String` | User-set name override (default `""`) |

**Execution flow for `execute(delta)` (called by BTPlayer, not by user code):**
1. If `status != RUNNING` → call `_enter()`
2. Call `_tick(delta)`
3. If result is `SUCCESS` or `FAILURE` → call `_exit()`

Key non-virtual methods: `abort()`, `add_child(task)`, `add_child_at_index(task, idx)`,
`remove_child(task)`, `get_child(idx)`, `get_child_count()`, `get_enabled_child_count()`,
`get_parent()`, `get_root()`, `is_root()`, `is_descendant_of(task)`, `initialize(agent, blackboard, scene_root)`.

### 3.5 `BTAction` and `BTCondition`

- **`BTAction`** (`BTTask`): Leaf tasks that perform work. May span multiple ticks (return `RUNNING`). No children.
- **`BTCondition`** (`BTTask`): Leaf tasks that check a condition. Typically return `SUCCESS` or `FAILURE` immediately (no `RUNNING`). No children.

Custom task pattern (GDScript):

```gdscript
@tool
extends BTAction
## Moves agent toward a blackboard position.

@export var target_pos_var: StringName = &"target_pos"
@export var speed: float = 200.0

func _generate_name() -> String:
    return "MoveToward  %s" % LimboUtility.decorate_var(target_pos_var)

func _setup() -> void:
    pass  # one-time init

func _enter() -> void:
    pass  # called when entering from non-RUNNING state

func _tick(delta: float) -> Status:
    var target: Vector2 = blackboard.get_var(target_pos_var, Vector2.ZERO)
    var dist := agent.global_position.distance_to(target)
    if dist < 5.0:
        return SUCCESS
    agent.velocity = agent.global_position.direction_to(target) * speed
    agent.move_and_slide()
    return RUNNING

func _exit() -> void:
    pass  # cleanup after SUCCESS or FAILURE
```

Custom condition pattern:

```gdscript
@tool
extends BTCondition
## Returns SUCCESS if agent is within range of target.

@export var distance_max: float = 150.0
@export var target_var: StringName = &"target"

var _max_sq: float

func _setup() -> void:
    _max_sq = distance_max * distance_max

func _tick(_delta: float) -> Status:
    var target: Node2D = blackboard.get_var(target_var, null)
    if not is_instance_valid(target):
        return FAILURE
    return SUCCESS if agent.global_position.distance_squared_to(
        target.global_position) <= _max_sq else FAILURE
```

## 4. Composite tasks

Composites control execution flow and can have multiple children.

| Class | Behaviour |
|---|---|
| `BTSequence` | AND logic — runs children left-to-right while they return `SUCCESS`; resumes from last `RUNNING` child next tick |
| `BTSelector` | OR logic — runs children left-to-right until first `SUCCESS`; resumes from last `RUNNING` child |
| `BTParallel` | Runs all children each tick (no multithreading); `num_successes_required`/`num_failures_required` control result; optional `repeat` |
| `BTDynamicSequence` | Like `BTSequence` but re-evaluates preceding children each tick (aborts `RUNNING` child if a preceding child changes result) |
| `BTDynamicSelector` | Like `BTSelector` but re-evaluates from the start each tick (allows higher-priority fallback to preempt) |
| `BTRandomSequence` | `BTSequence` with shuffled child order |
| `BTRandomSelector` | `BTSelector` with shuffled child order |
| `BTProbabilitySelector` | Weighted random selector using `BTProbability` child weights |

`BTParallel` properties:
```
num_failures_required: int  # default 1
num_successes_required: int  # default 1
repeat: bool                 # default false — re-execute SUCCESS/FAILURE children each tick
```

## 5. Decorator tasks

Decorators wrap a single child and modify its behaviour.

| Class | Behaviour / Key properties |
|---|---|
| `BTInvert` | Flips `SUCCESS`↔`FAILURE`; passes `RUNNING` through |
| `BTRepeat` | Repeats child N times (`times: int`) or forever (`forever: bool`); `abort_on_failure: bool` |
| `BTRepeatUntilSuccess` | Keeps retrying until child returns `SUCCESS` |
| `BTRepeatUntilFailure` | Keeps retrying until child returns `FAILURE` |
| `BTAlwaysSucceed` | Returns `SUCCESS` regardless of child result |
| `BTAlwaysFail` | Returns `FAILURE` regardless of child result |
| `BTCooldown` | Runs child only if `duration` seconds have passed; `start_cooled`, `trigger_on_failure`, `cooldown_state_var` |
| `BTTimeLimit` | Aborts child and returns `FAILURE` if `time_limit` exceeded |
| `BTDelay` | Delays child execution by N seconds |
| `BTRunLimit` | Restricts child to `run_limit` executions; `count_policy` (COUNT_SUCCESSFUL=0, COUNT_FAILED=1, COUNT_ALL=2) |
| `BTNewScope` | Creates a new Blackboard scope; `blackboard_plan` property |
| `BTSubtree` | Loads and runs another `BehaviorTree` resource as a child; creates new scope; `subtree: BehaviorTree` |
| `BTForEach` | Iterates over a Blackboard array variable |
| `BTProbability` | Child of `BTProbabilitySelector`; assigns a probability weight |

`BTCooldown` properties:
```
duration: float            # default 10.0
start_cooled: bool         # default false
trigger_on_failure: bool   # default false
cooldown_state_var: StringName  # optional BB var to store cooldown state
process_pause: bool        # default false
```

`BTRepeat` properties:
```
times: int           # default 1
forever: bool        # default false
abort_on_failure: bool  # default false
```

## 6. Built-in leaf tasks (actions and conditions)

### Actions
| Class | Purpose |
|---|---|
| `BTSetVar` | Assigns `value` (BBVariant) to `variable` on blackboard; optional `operation` (LimboUtility.Operation) |
| `BTCallMethod` | Calls a method on a node |
| `BTSetAgentProperty` | Sets a property on the agent |
| `BTPlayAnimation` | Plays an animation |
| `BTStopAnimation` | Stops an animation |
| `BTPauseAnimation` | Pauses an animation |
| `BTAwaitAnimation` | Waits for animation to finish |
| `BTWait` | Waits N seconds |
| `BTWaitTicks` | Waits N physics ticks |
| `BTConsolePrint` | Debug print to console |
| `BTFail` | Always returns `FAILURE` |
| `BTEvaluateExpression` | Evaluates a GDScript expression |

### Conditions
| Class | Purpose |
|---|---|
| `BTCheckVar` | Checks `variable` against `value` using `check_type` (LimboUtility.CheckType) |
| `BTCheckTrigger` | Returns `SUCCESS` and clears a boolean BB variable (one-shot gate) |
| `BTCheckAgentProperty` | Checks a property on the agent |
| `BTComment` | No-op; editor annotation; always returns `FAILURE`; `is_enabled()` always false |

`BTCheckVar.check_type` enum values (LimboUtility.CheckType):
```
CHECK_EQUAL = 0, CHECK_LESS_THAN = 1, CHECK_LESS_THAN_OR_EQUAL = 2
CHECK_GREATER_THAN = 3, CHECK_GREATER_THAN_OR_EQUAL = 4, CHECK_NOT_EQUAL = 5
```

## 7. Blackboard system

### `Blackboard` (`RefCounted`)

Key methods:

```gdscript
blackboard.get_var(var_name: StringName, default = null, complain: bool = true) -> Variant
blackboard.set_var(var_name: StringName, value: Variant) -> void
blackboard.has_var(var_name: StringName) -> bool
blackboard.erase_var(var_name: StringName) -> void
blackboard.list_vars() -> StringName[]          # current scope only
blackboard.get_vars_as_dict() -> Dictionary     # current scope only
blackboard.clear() -> void                      # current scope only
blackboard.get_parent() -> Blackboard           # parent scope
blackboard.set_parent(blackboard: Blackboard)   # assign parent scope
blackboard.top() -> Blackboard                  # topmost scope in chain
blackboard.populate_from_dict(dict: Dictionary) -> void
blackboard.print_state() -> void                # debug: print all scopes
blackboard.bind_var_to_property(var_name, object, property, create=false)
blackboard.link_var(var_name, target_blackboard, target_var, create=false)
blackboard.unbind_var(var_name: StringName)
```

Usage in tasks:

```gdscript
# Recommended: suffix exported var names with "_var" for inspector hints
@export var speed_var: StringName = &"speed"
@export var target_var: StringName = &"target"

func _tick(delta: float) -> Status:
    var speed: float = blackboard.get_var(speed_var, 100.0)
    blackboard.set_var(speed_var, 200.0)
    if blackboard.has_var(target_var):
        var obj = blackboard.get_var(target_var)  # no type annotation to avoid freed-instance errors
        if is_instance_valid(obj):
            pass
    return SUCCESS
```

### `BlackboardPlan` (`Resource`)

Stores the variable schema (types, defaults, hints) for constructing new `Blackboard` instances.

Key methods:
```gdscript
blackboard_plan.create_blackboard(prefetch_root: Node, parent_scope: Blackboard = null) -> Blackboard
blackboard_plan.populate_blackboard(blackboard, overwrite: bool, prefetch_root: Node) -> void
blackboard_plan.is_derived() -> bool
blackboard_plan.get_base_plan() -> BlackboardPlan
blackboard_plan.set_base_plan(plan: BlackboardPlan) -> void
blackboard_plan.sync_with_base_plan() -> void
```

Property: `prefetch_nodepath_vars: bool` (default `true`) — automatically resolves `NodePath` variables to node instances on blackboard creation.

### `BBParam` typed parameters

`BBParam` subclasses allow task properties to be either a literal value or a Blackboard variable reference:

```gdscript
# In an exported property, the inspector shows a BB param editor
@export var speed: BBFloat
@export var target_node: BBNode

func _tick(delta: float) -> Status:
    var s: float = speed.get_value(scene_root, blackboard, 0.0)
    var node: Node = target_node.get_value(scene_root, blackboard, null)
    return SUCCESS
```

Available subtypes: `BBBool`, `BBInt`, `BBFloat`, `BBString`, `BBStringName`, `BBVector2`, `BBVector2i`,
`BBVector3`, `BBVector3i`, `BBVector4`, `BBVector4i`, `BBColor`, `BBRect2`, `BBRect2i`, `BBArray`,
`BBDictionary`, `BBNode`, `BBBasis`, `BBTransform2D`, `BBTransform3D`, `BBQuaternion`, `BBPlane`,
`BBProjection`, `BBVariant`, and packed array variants.

`BBParam.ValueSource` enum:
```
SAVED_VALUE = 0    # literal value stored in resource
BLACKBOARD_VAR = 1 # reference to a named BB variable
```

Scope rules (new scopes are created automatically):
- Within `BTNewScope` and `BTSubtree` decorators.
- For any `LimboState` with non-empty `blackboard_plan`.
- At root-level `LimboHSM` nodes and each `BTState` child.

## 8. HSM system

### `LimboState` (`Node`)

Base class for states. Extend this for state implementations.

**Virtual methods:**

| Method | When called |
|---|---|
| `_setup() -> void` | Once during `hsm.initialize()` |
| `_enter() -> void` | When state becomes active |
| `_exit() -> void` | When state becomes inactive (also on `queue_free`; NOT on `free()`) |
| `_update(delta: float) -> void` | Each update tick while active |

**Properties:**

```gdscript
agent: Node                  # agent assigned during initialize()
blackboard: Blackboard       # shared data store for the HSM
blackboard_plan: BlackboardPlan
EVENT_FINISHED: StringName   # per-state event name indicating state is done
```

**Methods:**

```gdscript
dispatch(event: StringName, cargo: Variant = null) -> bool
# Propagates event from leaf to root; returns true if consumed.

get_root() -> LimboState     # root state (typically LimboHSM)
is_active() -> bool
restart() -> void            # exit and re-enter if active

# Chained builder methods (return self for fluent API):
named(name: String) -> LimboState
call_on_enter(callable: Callable) -> LimboState
call_on_exit(callable: Callable) -> LimboState
call_on_update(callable: Callable) -> LimboState

# Event handlers:
add_event_handler(event: StringName, handler: Callable) -> void
# handler signature: func my_handler(cargo = null) -> bool (return true to consume event)
remove_event_handler(event: StringName) -> void

# State-wide guard (checked before any transition to this state):
set_guard(guard_callable: Callable) -> void  # callable -> bool
clear_guard() -> void

get_cargo() -> Variant   # available only during _enter(); cargo passed to dispatch()
```

Signals: `entered`, `exited`, `setup`, `updated(delta: float)`.

### `LimboHSM` (`LimboState`)

Hierarchical State Machine node; itself a `LimboState` so it can nest.

**Properties:**

```gdscript
initial_state: LimboState    # first active state; defaults to first child
update_mode: LimboHSM.UpdateMode  # IDLE=0, PHYSICS=1, MANUAL=2 (default PHYSICS)
ANYSTATE: LimboState         # use as from_state for any-state transitions
```

**Key methods:**

```gdscript
initialize(agent: Node, parent_scope: Blackboard = null) -> void
set_active(active: bool) -> void   # activates initial_state when true
update(delta: float) -> void       # manual tick (when update_mode == MANUAL)

add_transition(from_state, to_state, event: StringName, guard: Callable = Callable()) -> void
remove_transition(from_state, event: StringName) -> void
has_transition(from_state, event: StringName) -> bool

get_active_state() -> LimboState
get_previous_active_state() -> LimboState
get_leaf_state() -> LimboState
change_active_state(state: LimboState) -> void  # direct state change (skips event system)
```

Signal: `active_state_changed(current: LimboState, previous: LimboState)`.

**Complete HSM setup example:**

```gdscript
# Scene tree: CharacterBody2D -> LimboHSM -> IdleState, MoveState (both LimboState nodes)
@onready var hsm: LimboHSM = $LimboHSM
@onready var idle_state: LimboState = $LimboHSM/IdleState
@onready var move_state: LimboState = $LimboHSM/MoveState

func _ready() -> void:
    hsm.add_transition(idle_state, move_state, idle_state.EVENT_FINISHED)
    hsm.add_transition(move_state, idle_state, move_state.EVENT_FINISHED)
    hsm.initialize(self)
    hsm.set_active(true)
```

**Single-file (delegation/fluent) pattern:**

```gdscript
func _init_state_machine() -> void:
    var hsm := LimboHSM.new()
    add_child(hsm)

    var idle_state := LimboState.new().named("Idle") \
        .call_on_enter(func(): $AnimationPlayer.play("idle")) \
        .call_on_update(_idle_update)
    var move_state := LimboState.new().named("Move") \
        .call_on_enter(func(): $AnimationPlayer.play("walk")) \
        .call_on_update(_move_update)

    hsm.add_child(idle_state)
    hsm.add_child(move_state)

    hsm.add_transition(idle_state, move_state, &"movement_started")
    hsm.add_transition(move_state, idle_state, &"movement_ended")
    # Any-state transition:
    hsm.add_transition(hsm.ANYSTATE, idle_state, &"stunned")

    hsm.initialize(self)
    hsm.set_active(true)

func _idle_update(delta: float) -> void:
    if not Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down").is_zero_approx():
        hsm.dispatch(&"movement_started")
```

**State anatomy:**

```gdscript
extends LimboState

func _setup() -> void:
    pass  # runs once; agent/blackboard available

func _enter() -> void:
    pass  # state became active

func _exit() -> void:
    pass  # state became inactive

func _update(delta: float) -> void:
    # dispatch an event to trigger a transition:
    dispatch(EVENT_FINISHED)
    # or:
    get_root().dispatch(&"some_event", optional_cargo)
```

### `BTState` (`LimboState`)

A `LimboState` that runs a `BehaviorTree`. Bridges the HSM and BT systems.

```gdscript
behavior_tree: BehaviorTree   # the BT resource to execute
success_event: StringName     # dispatched when BT returns SUCCESS (default: &"success")
failure_event: StringName     # dispatched when BT returns FAILURE (default: &"failure")
monitor_performance: bool     # default false
```

```gdscript
get_bt_instance() -> BTInstance
set_scene_root_hint(scene_root: Node) -> void  # call before HSM initialize() for dynamic setup
```

**HSM + BT integration example:**

```gdscript
extends CharacterBody2D

func _ready():
    var hsm := LimboHSM.new()
    add_child(hsm)

    var bt_state := BTState.new().named("Patrol")
    bt_state.behavior_tree = preload("res://ai/trees/patrol.tres")
    bt_state.set_scene_root_hint(self)
    hsm.add_child(bt_state)
    hsm.initial_state = bt_state

    hsm.initialize(self)
    hsm.set_active(true)
```

## 9. `BTInstance` (`RefCounted`)

Runtime instance of a `BehaviorTree`. Created by `BehaviorTree.instantiate()`.

```gdscript
get_agent() -> Node
get_blackboard() -> Blackboard
get_root_task() -> BTTask
get_last_status() -> BT.Status
get_owner_node() -> Node
get_source_bt_path() -> String
is_instance_valid() -> bool                 # instance method (distinct from GDScript's global is_instance_valid())
update(delta: float) -> BT.Status   # manually tick the instance
register_with_debugger() -> void
monitor_performance: bool
```

Signals: `updated(status: int)`, `freed`.

## 10. `LimboUtility` (singleton `Object`)

Helper singleton for task display and operations.

```gdscript
LimboUtility.decorate_var(variable: String) -> String
LimboUtility.decorate_output_var(variable: String) -> String
LimboUtility.get_status_name(status: int) -> String
LimboUtility.get_task_icon(class_or_script_path: String) -> Texture2D
LimboUtility.perform_check(check: CheckType, a, b) -> bool
LimboUtility.perform_operation(operation: Operation, a, b) -> Variant
LimboUtility.get_check_operator_string(check: CheckType) -> String
LimboUtility.get_operation_string(operation: Operation) -> String
```

## 11. C# usage

C# is supported via the **module version only** (not GDExtension in v1.7.1). Install the NuGet package from the LimboAI build's `GodotSharp/Tools/nupkgs/` folder:

```shell
dotnet nuget add source path/to/limboai/nupkgs --name LimboNugetSource
```

**Key naming differences from GDScript:**
- Virtual method names use PascalCase with leading underscore: `_Setup()`, `_Enter()`, `_Exit()`, `_Tick()`, `_GenerateName()`, `_Update()`
- `_Tick` takes `double delta` (not `float`)
- Status is `Status.Success`, `Status.Failure`, `Status.Running` (not `SUCCESS` etc.)
- Class names are identical to GDScript: `BTAction`, `BTCondition`, `LimboState`, `LimboHSM`, etc.

**C# custom task template** (verbatim from `doc/source/behavior-trees/custom-tasks.rst`):

```csharp
using Godot;
using System;

[Tool]
public partial class _CLASS_ : _BASE_
{
    public override string _GenerateName()
    {
        return "_CLASS_";
    }

    public override void _Setup()
    {
    }

    public override void _Enter()
    {
    }

    public override void _Exit()
    {
    }

    public override Status _Tick(double delta)
    {
        return Status.Success;
    }

    public override string[] _GetConfigurationWarnings()
    {
        return Array.Empty<string>();
    }
}
```

**C# HSM state template:**

```csharp
public partial class IdleState : LimboState
{
    public override void _Setup() { }

    public override void _Enter() { }

    public override void _Exit() { }

    public override void _Update(double delta)
    {
        Dispatch(EventFinished);
    }
}
```

**Note:** There are no C# example files in the `demo/` folder in v1.7.1 (all demos are GDScript). The official docs confirm GDExtension + C# was unresolved as of this version.

## 12. Custom task location and tooling

- Default search path: `res://ai/tasks/` (configurable in Project Settings → LimboAI with Advanced Settings enabled).
- Subdirectories under `res://ai/tasks/` become task categories in the editor.
- Script template: use "Misc → Create script template" in the LimboAI menu.
- `@tool` annotation required for `_generate_name()` and `_get_configuration_warnings()` to work in editor.
- `StringName` properties ending with `_var` get a special inspector widget for picking Blackboard variables.

## 13. Gaps / author ourselves

1. **C# examples for Blackboard access** — the docs only show GDScript snippets; C# has no generic overload for `GetVar`, so must cast the Variant result: `(float)blackboard.GetVar(varName, 0f)`. The official docs do not show this pattern; need to author C# Blackboard examples ourselves.

2. **C# HSM initialization** — the `_init_state_machine()` HSM setup in GDScript uses fluent `.named().call_on_enter()` chaining. The C# equivalents require property assignment (`.Name = "Idle"`) and `Connect(LimboState.SignalName.Entered, ...)` — this is unexampled in the official docs and should be authored.

3. **GDExtension + C# status** — the docs note GDExtension + C# was "unresolved" as of the module docs; the readthedocs C# page explicitly says "I can only confirm success with the module version." The skill should clearly flag that C# requires the module version.

4. **`BBParam` property editor gap in GDExtension** — the inspector-based `BBParam` typed parameter editor (binding a task property to a BB var via UI) is not available in the GDExtension build. No workaround is documented. The skill should note this limitation.

5. **`BTForEach` / `BTEvaluateExpression` / `BTRandomWait`** — these XMLs exist in the repo but lack example code in the official docs. Need to author examples from the XML descriptions alone.

6. **`BTProbabilitySelector` / `BTProbability`** — the weighted random selector works via child `BTProbability` decorators with probability weights, but no example exists in the docs. Need to author.

7. **`BlackboardPlan` mapping (BTState ↔ HSM)** — the `using-blackboard.rst` covers the concept but the programmatic `link_var` approach and its limitations vs. inspector mapping need clearer examples for the skill.

8. **API version drift** — the README compatibility table shows GDExtension minimum was Godot 4.2 in the `.gdextension` file but v1.7.x requires 4.6 at runtime (the file's `compatibility_minimum = "4.2"` is a legacy lower bound; 4.6 is the actual tested minimum per the README matrix). The skill should use 4.6 as the minimum.

9. **`BTPlayer.updated` vs `behavior_tree_finished`** — `behavior_tree_finished` is marked `deprecated` in the XML; always use `updated`.

## Skill-authoring implications

- **Target class hierarchy for coverage:** BehaviorTree (resource) → BTPlayer → BTTask → BTAction/BTCondition → Blackboard; LimboHSM → LimboState → BTState.
- **C# parity**: All GDScript examples need C# pairs. The C# method-name table (§11) is authoritative.
- **Cross-refs to plan:** `state-machine` (LimboHSM is a state machine), `event-bus` (dispatch pattern), `ai-navigation` (common BT use case), `gdscript-advanced` (coroutine tasks), `addon-development` (distribution), `csharp-godot` (C# parity gap).
- **Pattern X candidate:** `BTInstance` low-level API + multi-agent shared Blackboard + `BTSubtree` + `BTProbabilitySelector` examples are good `references/` material (keep core SKILL.md ≤ 16 KB).

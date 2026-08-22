# Multithreading — Godot 4.x Research Digest (for the `multithreading` skill)

> Gathered 2026-05-29 from official Godot docs to ground the v1.9.0 `multithreading` skill.
> Sources (github.com/godotengine/godot-docs/master): `tutorials/performance/using_multiple_threads.rst`,
> `tutorials/performance/thread_safe_apis.rst`, `tutorials/io/background_loading.rst`, plus class refs
> for `WorkerThreadPool`, `Thread`, `Mutex`, `Semaphore`, `ResourceLoader`.

## 1. Threading model & safety rules (from `thread_safe_apis.rst`)

- **Global singletons / servers** are mostly thread-safe. RenderingServer & PhysicsServer require enabling
  thread-safe operation in **project settings** first. Servers are ideal for thousands of thread-driven instances.
- **Scene tree interaction is NOT thread-safe.** Use mutexes to pass data; use `call_deferred` / `set_deferred`
  to call functions / set properties from a thread.
- **Building scenes off-tree is fine** — instantiate in a thread, then `add_child.call_deferred()` on main thread.
  Only safe with ONE loader thread (multiple threads risk tweaking the same cached resource → crashes).
- **Rendering:** instancing render nodes (Sprite2D, MeshInstance3D) not thread-safe by default; set
  `Rendering > Driver > Thread Model = Separate` (has KNOWN BUGS). Avoid GPU work off-main-thread (texture
  creation, image read/modify) → RenderingServer sync stalls.
- **Physics:** not thread-safe by default; enable `Physics > {2D,3D} > Run on Separate Thread`.
- **Navigation:** NavigationServer2D/3D thread-safe AND thread-friendly (true parallel queries); tune
  `Navigation > Pathfinding > Max Threads`. Nav resources thread-safe but NOT thread-friendly.
- **AStar2D/3D/Grid2D:** NOT thread-safe. One dedicated thread per object OK; sharing one object across
  threads corrupts data.
- **GDScript Array/Dictionary:** reading/writing existing elements across threads OK; **resizing/adding/
  removing requires a mutex.**
- **Resources:** modifying a unique resource from multiple threads unsupported; handling refs across threads OK.

## 2. WorkerThreadPool (PREFERRED high-level API)

Global singleton, threads allocated at startup. Regular task → one worker; **group task** → distributed
across workers, Callable called repeatedly (great for iterating many elements).

Real signatures:
```
int   add_task(action: Callable, high_priority := false, description := "")
int   add_group_task(action: Callable, elements: int, tasks_needed := -1, high_priority := false, description := "")
int   get_caller_task_id() const          # -1 for group tasks / main thread
int   get_caller_group_id() const
int   get_group_processed_element_count(group_id: int) const
bool  is_task_completed(task_id: int) const
bool  is_group_task_completed(group_id: int) const
void  wait_for_group_task_completion(group_id: int)
Error wait_for_task_completion(task_id: int)   # OK / ERR_INVALID_PARAMETER / ERR_BUSY
```
- `add_group_task`: Callable receives `0..elements-1`; `tasks_needed = -1` → all workers.
- **WARNING: tasks are NOT fire-and-forget.** Must call `wait_for_*_completion` so allocated resources are freed.
- `ERR_BUSY`: waiting from inside another running task with deadlock potential.
- Note: distributing cheap tasks can HURT performance — only use for genuinely expensive work.

Verbatim example (both langs from class ref):
```gdscript
var enemies = []
func process_enemy_ai(enemy_index):
    var processed_enemy = enemies[enemy_index]
    # Expensive logic...
func _process(delta):
    var task_id = WorkerThreadPool.add_group_task(process_enemy_ai, enemies.size())
    WorkerThreadPool.wait_for_group_task_completion(task_id)
```
```csharp
private List<Node> _enemies = new();
private void ProcessEnemyAI(int enemyIndex) { var e = _enemies[enemyIndex]; /* expensive */ }
public override void _Process(double delta)
{
    long taskId = WorkerThreadPool.AddGroupTask(Callable.From<int>(ProcessEnemyAI), _enemies.Count);
    WorkerThreadPool.WaitForGroupTaskCompletion(taskId);
}
```
Caveat: relies on element count staying constant during the multithreaded part. C# wraps the method via
`Callable.From<int>(...)` and stores the id in a `long`.

## 3. Thread / Mutex / Semaphore (low-level)

```
# Thread
Error   start(callable: Callable, priority := PRIORITY_NORMAL)   # PRIORITY_LOW=0, NORMAL=1, HIGH=2
Variant wait_to_finish()    # joins, returns the Callable's return value; BLOCKS
bool    is_alive() const
bool    is_started() const
String  get_id() const
# Mutex (REENTRANT/recursive): lock(), unlock(), try_lock() -> bool
# Semaphore: wait(), post(count := 1), try_wait() -> bool
```

Basic thread (verbatim):
```gdscript
var thread: Thread
func _ready():
    thread = Thread.new()
    thread.start(_thread_function.bind("Wafflecopter"))   # bind args
func _thread_function(userdata):
    print("I'm a thread! Userdata is: ", userdata)
func _exit_tree():
    thread.wait_to_finish()   # must join before free
```

Semaphore producer/consumer + clean shutdown idiom (verbatim — canonical "work on demand"):
```gdscript
var counter := 0
var mutex: Mutex
var semaphore: Semaphore
var thread: Thread
var exit_thread := false

func _ready():
    mutex = Mutex.new(); semaphore = Semaphore.new()
    exit_thread = false
    thread = Thread.new(); thread.start(_thread_function)

func _thread_function():
    while true:
        semaphore.wait()                 # wait until posted
        mutex.lock(); var should_exit = exit_thread; mutex.unlock()
        if should_exit: break
        mutex.lock(); counter += 1; mutex.unlock()

func increment_counter():
    semaphore.post()

func _exit_tree():
    mutex.lock(); exit_thread = true; mutex.unlock()
    semaphore.post()           # unblock
    thread.wait_to_finish()    # join
```

Perf warnings: thread creation is SLOW (esp. Windows) — pre-create before heavy processing, not just-in-time.
Over-locking mutexes is expensive too.

## 4. call_deferred / set_deferred (hand results to main thread)

```gdscript
node.add_child(child_node)              # UNSAFE from a thread
node.add_child.call_deferred(child_node)  # SAFE
```
```csharp
node.AddChild(childNode);                                  // UNSAFE
node.CallDeferred(Node.MethodName.AddChild, childNode);    // SAFE
```
**C# gotcha:** `CallDeferred`/`Call`/`Connect`/`Get`/`Set` use Godot's snake_case names — `CallDeferred("AddChild")`
does NOT work; use `add_child` or, better, the `Node.MethodName.AddChild` StringName constant (avoids the
pitfall + extra allocation).

## 5. Threaded resource loading (ResourceLoader)

```
Error            load_threaded_request(path, type_hint := "", use_sub_threads := false, cache_mode := CACHE_MODE_REUSE)
ThreadLoadStatus load_threaded_get_status(path, progress: Array = [])   # progress[0] = ratio 0..1
Resource         load_threaded_get(path)   # blocks like load() if not yet finished
```
`ThreadLoadStatus`: `THREAD_LOAD_INVALID_RESOURCE=0`, `THREAD_LOAD_IN_PROGRESS=1`, `THREAD_LOAD_FAILED=2`,
`THREAD_LOAD_LOADED=3`.

**Docs do NOT ship a polling loop** — author it: request → each frame poll `load_threaded_get_status(path, progress)`,
update bar from `progress[0]`, on `THREAD_LOAD_LOADED` call `load_threaded_get`. Minimal request/get example
exists verbatim in both GDScript and C# (`LoadThreadedRequest`/`LoadThreadedGet`).

## 6. C# specifics

- Godot exposes `Godot.Thread`, `Godot.Mutex`, `Godot.Semaphore`, `WorkerThreadPool` (PascalCase: `AddTask`,
  `AddGroupTask`, `WaitForTaskCompletion`...), `ResourceLoader.LoadThreadedRequest/Get/GetStatus`.
- `CallDeferred(Node.MethodName.AddChild, ...)` is the documented thread→main bridge.
- **NOT in official docs (author ourselves):** `System.Threading.Tasks` / `Task.Run`, async/await interplay,
  `GodotTaskScheduler`/`SynchronizationContext`, and the rule that awaiting Godot signals (`ToSignal`) / touching
  Godot objects must happen on the main thread. **Flag C# `System.Threading` examples as skill-authored, not doc-sourced.**

## 7. Gotchas (doc-sourced)

- Tasks must be awaited (resource leak otherwise). `ERR_BUSY` deadlock case on nested waits.
- Never mutate live scene tree from threads — always defer.
- Don't load the same resource from multiple threads (cache corruption); one loader thread.
- Don't resize Array/Dictionary across threads without a mutex.
- No GPU work off main thread. AStar/nav: one thread per object. `wait_to_finish()` blocks (check `is_alive()`).
- Thread creation expensive; threading only helps for genuinely CPU-expensive work.

## 8. Version notes

All APIs present in Godot 4.x (since 4.0); the `Thread.start(Callable, Priority)` form is the 4.x form (pre-4.0
target+method-name string is gone). Stable across 4.3–4.6. Repo min is 4.3+ → all available.

## Doc-coverage flags for skill author

1. C# parity for Thread/Mutex/Semaphore producer-consumer — **author ourselves** (docs give GDScript + C++).
2. C# `System.Threading.Tasks` / async-await / main-thread marshaling — **author ourselves** (no doc page).
3. Threaded ResourceLoader polling loop with progress — **assemble ourselves** from enum + "blocks like load()" caveat.

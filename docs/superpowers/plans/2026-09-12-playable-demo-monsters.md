# 可游玩 Demo 与普通怪物系统实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不生成玩家和 Boss 模型的前提下，完成一场可从主菜单进入、探索房间、战斗、获得资源、击败普通怪物并进入结算的 Demo，并优先把第一层普通怪物做成可读、可战斗、可复现的内容。

**Architecture:** 保留现有 Core/Data/Gameplay/Entities/World/UI 分层。普通怪物使用数据表驱动的共享 EnemyBase 行为，视觉使用程序化占位材质和简单几何，不依赖玩家或 Boss 模型；GameRoot 负责把地牢、房间、刷怪、资源和结算串起来，RoomController 负责单房间生命周期。

**Tech Stack:** Godot 4.7 Mono、GDScript、现有自研 SceneTree 测试框架、JSON 房间蓝图、Resource/Dictionary 数据。

**Spec:** 本次对话中已批准的“可玩 Demo 大框架”范围及“玩家模型由用户导入、Boss 模型延后、普通怪物优先”约束。

## Global Constraints

- 不生成或替换玩家模型；玩家节点保留现有占位/用户后续导入接口。
- 不实现 Boss 模型和 Boss 专属内容；Boss 只保留现有流程所需的最小占位逻辑。
- 第一层普通怪物必须覆盖策划规定的 10 种：监牢僵尸、毒瘴僵尸、骷髅弓手、墓穴哨兵、狂暴囚犯、狱卒猎犬、石翼蝙蝠、鬼火灵体、巨型变异老鼠、迷雾幽灵。
- 普通怪物数据必须可由固定种子复现，且攻击间隔不小于 2.5 秒。
- 所有新增函数带简短注释；不引入无关重构或新依赖。
- 每个行为先写失败测试并确认失败，再写最小实现。
- 每个完成条目必须有自动测试或实际运行证据，并记录到进度文档。

---

### Task 1: 修复 Demo 测试入口并建立普通怪物验收基线

**Files:**
- Modify: `tests/test_framework.gd`
- Create: `tests/test_demo_acceptance.gd`
- Modify: `docs/progress/PROGRESS_20260831.md`

**Interfaces:**
- Produces `test_demo_acceptance.gd` with checks for main scene readiness, first-layer monster database count, room combat loop, resource acquisition, and settlement signal.
- Keeps the existing self-contained `SceneTree` test convention and counts script-load failures as failures.

- [ ] **Step 1: Write the failing acceptance tests**

Add tests that load the existing main scene and assert:

```gdscript
func test_floor_one_has_ten_monsters() -> void:
    var db = load("res://data/monsters/monster_db.gd").new()
    db.init_layer1()
    assert(db.all_monsters().size() == 10)

func test_normal_room_can_clear_and_unlock() -> void:
    # Build the existing RoomController test tree, activate it, kill living enemies,
    # then assert is_cleared and all DoorTrigger nodes are unlocked.
    pass

func test_settlement_has_run_result() -> void:
    # Start one run, call GameManager.finish_run("defeated"), and assert result fields.
    pass
```

Use the repository's `_check` helper rather than introducing a second assertion framework. Add the suite call to `test_framework.gd` only after the function exists.

- [ ] **Step 2: Run the test and verify the expected failure**

Run the project test through the connected Godot editor test runner or the documented headless command after `--import`. Expected result: the new acceptance test fails because the current test discovery/scene fixture cannot yet provide the complete Demo flow, not because of a typo.

- [ ] **Step 3: Make the smallest test-harness correction**

Correct only the broken test entry point or fixture assumptions revealed by the failure. Do not weaken assertions or mark a broken script as passed. If the editor test runner cannot instantiate the legacy `SceneTree` scripts, preserve the direct test script path and record the runner limitation in the progress document.

- [ ] **Step 4: Re-run the baseline tests**

Run all current framework and scene regression suites. Expected: the baseline is either green or has a precisely recorded pre-existing failure list; no new silent load failures are allowed.

- [ ] **Step 5: Commit the isolated test baseline**

```bash
git add tests/test_framework.gd tests/test_demo_acceptance.gd docs/progress/PROGRESS_20260831.md
git commit -m "test: establish playable demo acceptance baseline"
```

---

### Task 2: Make first-layer ordinary monsters visually readable without external models

**Files:**
- Read/Modify: `entities/enemies/enemy_base.gd`
- Read/Modify: `data/monsters/monster_db.gd`
- Test: `tests/test_demo_acceptance.gd`

**Interfaces:**
- `MonsterDB.init_layer1()` remains the source of the ten monster dictionaries.
- `EnemyBase.apply_monster_config(config: Dictionary)` remains the configuration entry point.
- Add a single internal visual builder in `EnemyBase` that creates a simple mesh and material from the configured monster role/color; it must not affect combat stats.

- [ ] **Step 1: Add failing visual-role tests**

For each monster dictionary, instantiate `EnemyBase`, call `apply_monster_config`, and assert the node has one visual child with a role marker matching the configuration (for example `monster_role`, `ranged`, `sentry`, `flying`, or `rusher`). Assert that visual setup does not change `max_hp`, `atk`, `attack_range`, or `behavior`.

- [ ] **Step 2: Run the focused tests and confirm failure**

Expected: at least one configured monster has no readable visual child or role marker.

- [ ] **Step 3: Implement minimal procedural visuals**

Create only simple Godot meshes already available in the engine:

- melee: box/capsule-like mesh with red-orange material;
- ranged: smaller sphere/cylinder with blue material;
- sentry: short cylinder/turret with cyan material;
- rusher: elongated capsule/box with orange material;
- flying: sphere/diamond-like mesh elevated slightly with violet material;
- giant: scaled box/capsule with dark red material;
- phantom: translucent sphere with pale blue material.

Store the role on the root node metadata so tests and future imported models can replace the child without changing gameplay code. Do not add player or Boss meshes.

- [ ] **Step 4: Re-run focused and full tests**

Verify all ten monster roles, stats, AI mappings, and existing room/combat tests remain green.

- [ ] **Step 5: Commit the ordinary-monster presentation slice**

```bash
git add entities/enemies/enemy_base.gd data/monsters/monster_db.gd tests/test_demo_acceptance.gd
git commit -m "feat: add readable procedural ordinary monster visuals"
```

---

### Task 3: Finish the ordinary-monster combat roster and deterministic room spawning

**Files:**
- Modify: `data/monsters/monster_db.gd`
- Modify: `gameplay/dungeon/room_controller.gd`
- Modify: `gameplay/enemies/enemy_spawner.gd`
- Modify: `tests/test_framework.gd`
- Test: `tests/test_demo_acceptance.gd`

**Interfaces:**
- `MonsterDB.random_monster(rng)` and `random_elite(rng)` return dictionaries from the configured layer pool.
- `RoomController.activate()` spawns from `MonsterDB` and tracks `_living_enemies`/`enemies_alive`.
- `EnemyBase.died(world_position)` remains the room-clear signal path.

- [ ] **Step 1: Add failing deterministic roster tests**

Use two `RandomNumberGenerator` instances with the same seed and assert that the selected normal-monster ID sequence is identical. Build a room with explicit `monster_id` markers for all ten IDs and assert each spawned enemy receives the intended config and role. Assert that a high-damage monster has a longer windup and that ranged/flying constraints remain valid.

- [ ] **Step 2: Run focused tests and verify failure**

Expected: explicit marker IDs are currently not all represented in the spawned runtime or same-seed selection is not stable because the room controller mixes global `randf()` with the injected RNG.

- [ ] **Step 3: Implement deterministic spawning and role behavior**

Use the room's injected/GameManager RNG for every spawn decision. Keep explicit `monster_id` markers authoritative. Ensure the ten configurations expose the minimum fields needed by runtime: `id`, display name, role/AI, hp, atk, speed percentage, attack interval, range, and special flags. Do not add later-floor monsters.

- [ ] **Step 4: Re-run ordinary-monster and room-combat tests**

Verify repeated seeds produce the same roster, all ten explicit IDs spawn correctly, rooms lock while enemies live, and unlock after every enemy dies.

- [ ] **Step 5: Commit the deterministic combat roster**

```bash
git add data/monsters/monster_db.gd gameplay/dungeon/room_controller.gd gameplay/enemies/enemy_spawner.gd tests/test_framework.gd tests/test_demo_acceptance.gd
git commit -m "feat: stabilize deterministic first-layer monster combat"
```

---

### Task 4: Connect the complete one-run Demo flow

**Files:**
- Modify: `scenes/game_root.gd`
- Modify: `gameplay/dungeon/room_controller.gd`
- Modify: `entities/player/player.gd`
- Modify: `ui/hud/hud.gd`
- Modify: `ui/menu/settlement_panel.gd`
- Test: `tests/test_demo_acceptance.gd`

**Interfaces:**
- `GameRoot._init_dungeon()`, `load_current_room()`, `_transition_to_room()`, and `next_floor()` remain the scene orchestration API.
- `RoomController.room_cleared`/`EventBus.room_cleared` and `GameManager.finish_run(reason)` remain the flow events.
- `Player` retains existing movement/attack/input actions and only gains missing Demo feedback, not a new control scheme.

- [ ] **Step 1: Add failing end-to-end flow tests**

Test this exact sequence:

```gdscript
main menu -> start new run -> current room loads -> enter normal room
-> enemies spawn -> room doors lock -> kill enemies
-> doors unlock -> collect gold/equipment or use existing chest
-> reach Boss-room placeholder -> finish the run
-> settlement result contains reason, floor, kills, gold, devoured, fusions
```

The test must assert actual state transitions/signals, not only that methods exist.

- [ ] **Step 2: Run and confirm the flow failure**

Expected: one or more links are currently disconnected, such as main-menu start state, room selection, pickup persistence, Boss-room placeholder transition, or settlement display.

- [ ] **Step 3: Implement only the missing orchestration links**

Keep existing systems intact. Fix signal connections, room selection, current-room state, transition ordering, and settlement handoff. Do not implement Boss skills, Boss models, full special-room UI, or a second save system. Ensure a failed run also reaches settlement rather than leaving the player in a frozen gameplay scene.

- [ ] **Step 4: Run end-to-end scene tests**

Run the full suite and verify no duplicate signals, stale room nodes, orphaned enemies, or missing settlement result. Record test counts and any known headless rendering noise.

- [ ] **Step 5: Commit the playable one-run flow**

```bash
git add scenes/game_root.gd gameplay/dungeon/room_controller.gd entities/player/player.gd ui/hud/hud.gd ui/menu/settlement_panel.gd tests/test_demo_acceptance.gd
git commit -m "feat: connect playable one-run demo flow"
```

---

### Task 5: Add simple procedural environment polish and real-play verification

**Files:**
- Modify: `scenes/game_root.gd`
- Modify: `world/rooms/room_builder.gd` or the existing room visual builder selected after inspection
- Modify: `docs/progress/PROGRESS_20260831.md`
- Test: `tests/test_demo_acceptance.gd`

**Interfaces:**
- Existing room geometry builders remain authoritative for floors, walls, doors, and collisions.
- New polish must be additive: lighting, role-color readability, damage feedback, and basic interaction prompts.

- [ ] **Step 1: Add failing smoke assertions**

Assert that a loaded gameplay scene has a player node, current room controller, at least one ordinary enemy visual, and a visible HUD/settlement path. Assert that a room transition does not leave the previous room controller in the current-room group.

- [ ] **Step 2: Run smoke assertions and verify failure**

Expected: the test exposes any stale current-room group, missing visual, or HUD/scene readiness issue remaining after Task 4.

- [ ] **Step 3: Add minimal polish**

Use generated materials only where needed: distinct monster role colors, simple point lights or emission, clear room/door state feedback, and existing damage popup/message systems. Do not generate player or Boss model assets.

- [ ] **Step 4: Start the project and perform the actual golden-path run**

Use the Godot editor/game runner to:

1. start the main scene;
2. start a new run from the menu;
3. move into a normal room;
4. attack and defeat ordinary monsters;
5. verify doors unlock and loot can be collected/devoured;
6. transition through the available room path;
7. reach the existing Boss/settlement placeholder and finish the run;
8. capture a screenshot or runtime log plus the final settlement state.

- [ ] **Step 5: Update progress and commit the verified Demo**

Record exact test counts, actual play path, known limitations, and the fact that player/Boss models are intentionally deferred.

```bash
git add scenes/game_root.gd world/rooms/room_builder.gd docs/progress/PROGRESS_20260831.md tests/test_demo_acceptance.gd
git commit -m "chore: verify playable demo presentation"
```

---

## Self-review

- **Spec coverage:** The plan covers the approved playable path, ordinary-monster priority, procedural visuals, deterministic spawning, room combat, resources, settlement, and real-play verification. Player and Boss models are explicitly excluded.
- **Placeholder scan:** No implementation step depends on an unspecified file or vague “appropriate” behavior; each task names concrete APIs, assertions, and commands.
- **Type consistency:** MonsterDB dictionaries feed `EnemyBase.apply_monster_config`; RoomController owns spawn/clear state; GameRoot owns scene transitions; GameManager owns settlement results.
- **Scope:** Full 9-floor content, 53 Bosses, complete rarity system, full special-room UI, controller navigation, and external forging remain outside this Demo plan.

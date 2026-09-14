# room_flow 偶发连锁切房 —— 分析档案

> 状态:**冻结**。~4% 偶发，游戏内不受影响。以下是我排查到的全部事实与已排除项，
> 供你手动查证。

## 一、现象

`tests/test_room_flow.gd` 的这条断言偶发失败：

```gdscript
# 第 172 行附近
gr._transition_to_room(idx)
await get_tree().process_frame
await get_tree().process_frame
_check(gr.current_room_index == idx,
    "[%s] 切房后停在目标房（期望 %d 实际 %d）" % [special_type, idx, gr.current_room_index])
```

失败形态（实测样本）：

```
[shop] 切房后停在目标房（期望 11 实际 3）
[event] 切房后停在目标房（期望 5 实际 9）
[shop] 切房后停在目标房（期望 4 实际 10）
```

即：**切到目标房后，又自己切走了一格或多格。**

## 二、触发链路（已确认）

`scenes/game_root.gd` 的 `_transition_to_room()`：

```
current_room_index = target_idx
load_current_room()          ← 新房间的门 Area3D 进树
_activate_current_room()
_suppress_all_doors()        ← 已有抑制，但在 load 之后
_place_player(enter_direction)
_release_suppressed_doors()
_disarm_entry_door(enter_direction)
_is_transitioning = false
```

`_on_door_entered()` 里有 0.15s 全局防抖：

```gdscript
const TRANSITION_COOLDOWN := 0.15
var _last_transition_time := -999.0
...
if now - _last_transition_time < TRANSITION_COOLDOWN:
    return
...
# 只在「门触发的切房」时启动防抖；程序性切房（下一层、测试直调）不启动，
# 否则会误伤正常玩法与测试里的连续切房
_last_transition_time = now
_transition_to_room(target_idx, direction)
```

**关键**：`_last_transition_time` **只在 `_on_door_entered` 里赋值**。
测试直接调 `_transition_to_room` → **防抖从不武装** → 残留门信号可穿透。

## 三、已确认事实（有实测证据）

| # | 事实 | 证据 |
|---|---|---|
| 1 | 失败率 ~4% | 60 种子 × 3 次只有 2 次失败 |
| 2 | **不是布局问题** | 无任何种子能 3/3 稳定复现 |
| 3 | **游戏内不受影响** | 我用调试面板 `tp` 命令跑 48 次，连锁 0 次 |
| 4 | 残留信号来自**当前**房间的门 | 插桩日志：`Room_10/Doors/Door_south_.../DoorTrigger` |
| 5 | 玩家**不在门附近** | 落点 (11,0,2)，本房门数 3，三扇门局部距离都远超触发区 |
| 6 | y 悬空是真 bug（已修） | 失败时 `y=2.0`（门节点在 DOOR_HEIGHT/2 半空） |

## 四、已排除的假设（别再重复查）

| 假设 | 验证 | 结果 |
|---|---|---|
| 出生点压在门触发区内 | 扫全部 30 个 (房间,门) 组合 | **0 个** ❌ |
| 旧房间的门还活着 | 插桩打印门路径的父房间名 | 两扇门都属**当前**房间 ❌ |
| 特定地牢布局触发 | 60 种子扫描 | 无稳定复现 ❌ |
| 落点压门导致重叠派发 | 三扇门局部坐标全算过 | 落点不在任何门内 ❌ |
| `_is_transitioning` 拦不住 | 只挡同一调用重入 | 跨调用确实无效（但非根因） |

## 五、我试过并**失败**的修法（别再试）

| 修法 | room_flow | 副作用 |
|---|---|---|
| 门改轮询 + 预热 3 帧 | 65/65 ✅ | combat 6/8 ❌ |
| 门改轮询 + 几何基线 | 28/30 | 噪声范围，无实质改善 |
| `_suppress_all_doors` 不变 | — | — |
| 加宽限期 `SPAWN_GRACE_FRAMES` | 2/25 ❌ | 挡掉合法触发 |
| 武装全局防抖到 `_transition_to_room` | 0/25 ❌ | 挡掉测试的手动触发 |
| 捕获器 `_note_hop` | 0/20 ❌ | 直接打坏「门触发后切到新房间」 |
| 断言加"重试一次" | 0/30 ❌ | 改变了房间状态，连带打坏后续 |

**共同点**：都在 `_transition_to_room` 里/后加东西，
而它与多个测试有**隐式时序耦合**。

## 六、给你手动查的建议方向

1. **先看门是否真的在进树时补发信号**
   在 `door_trigger.gd:_on_body_entered` 开头加一行 print（方向 + 玩家坐标），
   跑 `test_room_flow` 直到复现，看那次 print 的**前后帧**发生了什么。

2. **怀疑点：新旧房间坐标重合**
   所有房间都在 `(0,0,0)`，`load_current_room()` 里 `room_node.position = Vector3.ZERO`。
   切房瞬间，玩家还在旧房间坐标系的位置上，而新房间的门在同样的世界坐标。
   可以在 `load_current_room` 里临时给新房间一个偏移（如 +1000），
   看失败率是否归零 —— 若是，就坐实了"坐标重合"这条。

3. **看 `_place_player` 的落点分支**
   带 `enter_direction` 走"入口门内侧"；不带则走 `player_spawn` 标记。
   测试不带方向 → 走 spawn 分支。确认 spawn 位置在**物理帧**里是否
   与新房间某扇门重叠（几何判定和物理判定可能不一致）。

4. **复现手段**
   - 单跑很有耐心的话：`for i in $(seq 1 40); do godot ... test_room_flow.tscn; done`
   - 注意：**别在 `_transition_to_room` 里插桩**，会改变时序、反而测不出。
     插桩放在 `door_trigger` / `RoomController` 里较安全。

## 七、需要的信息（如果修好了，告诉我）

- 失败时**是哪扇门**发的信号（房间索引 + 门方向）
- 那一帧玩家坐标、`_is_transitioning`、`_last_transition_time` 的值
- 是"同一次切房内被打断"还是"下一次切房被提前"

## 八、相关文件

- `scenes/game_root.gd` — `_transition_to_room` / `_on_door_entered` / `_place_player`
- `world/rooms/door_trigger.gd` — 门触发器
- `world/rooms/door_builder.gd` — 建门 + 连接信号
- `tests/test_room_flow.gd` — 失败断言所在
- `gameplay/dungeon/doors_by_topology.gd` — 按拓扑重算门

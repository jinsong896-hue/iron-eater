# room_flow 偶发连锁切房 —— 已修复（2026-09-15）

> 状态:**已根治**。修复前失败率 ~50%（预加载后加剧），修复后 50/50 全绿。
> 此前的「冻结」由用户主动解除后修复。以下保留完整根因链供后人参考。

## 一、根因链（完整证据链）

### 1. 现象
`_transition_to_room(idx)` 后玩家又「自己」切走一格。插桩显示误触发的门
距玩家 **2.5~10 米**（如 `Door_west_0_6` 被玩家在 (9,0,10) 触发）——
远超物理包络（门盒半厚 0.75 + 胶囊半径 0.5 = 1.25m）。

### 2. 根因：teleport 后的 stale broadphase pair 迟发派发
- `_place_player` 用 `player.global_position = spawn` **teleport** 玩家
- 物理服务器（PhysicsServer3D）的 broadphase 重叠对不会立即刷新
- 期间 `Area3D.get_overlapping_bodies()` 报告 **stale 重叠**（探针实测：
  `Door_south_8_11, local=(0.00, -1.50)`——物理包络外 0.25m 仍报重叠）
- Area3D 据此**补发** `body_entered`，且**可迟至切房后十几物理帧**
  （实测 frame 13 切房 → frame 27 幽灵派发第二跳连锁）
- 旧版 `_release_suppressed_doors` 用几何判定（容差 x≤1.3/z≤1.05）释放门
  → 门复活 → 幽灵派发得逞 → 连锁切房

### 3. 为何「档案时期 4%」变成「修复前 ~50%」
房间预加载（commit 210ebcca，9-15 15:14）之后失败率暴增。档案（dd42b86d，
9-15 01:05）的 4% 基线测于预加载之前。预建房间的门 Area3D **构建时即创建
碰撞体**、入树时机更密集，放大了 stale pair 的暴露面。

## 二、修复方案（最终采用：几何复核防御纵深）

`door_trigger.gd:_on_body_entered` 在发信号前做**几何复核**：
玩家在触发器局部空间的坐标若超出 `|x|>1.5 or |z|>1.25`（物理包络）→ 判为
幽灵派发，丢弃。真实穿门的玩家必然在触发区内，复核无感知。

配套修正测试失真（两处，均为「玩家不在门边直调 `_on_body_entered`」）：
- `tests/test_room_flow.gd` `_test_door_transition`：直调前把玩家移进触发区
- `tests/test_gameplay_fixes.gd` 门重入保护测试：同上

### 途中证伪/放弃的方案（勿重试）
| 方案 | 结果 |
|---|---|
| `_release` 全部 `disarm_until_clear` | 挡掉测试直调，20/20 红 |
| 释放延迟 1 物理帧（`_reset_after_phys`） | 幽灵可迟发十几帧，1 帧不够，6/15 仍连锁 |
| `cut_monitoring` + 2 物理帧后 rearm | headless 下物理帧稀疏，process 驱动的测试看不到恢复，15/15 红 |
| `create_physics_frame_timer` | **API 不存在**（Godot 4.7 无此方法），调用抛错致门永久哑掉 |
| 新旧房间坐标重合（+1000 偏移实验） | 失败依旧——**证伪**，非坐标串扰 |

### 死结的本质（为什么时序方案全败）
测试直调 `_on_body_entered`（玩家在任意位置）与幽灵派发（玩家不在门边）
**在信号处理端不可区分**——两者都是「玩家几何上不在触发区」。任何在
`door_trigger`/`game_root` 侧按时序拦截的方案必然同时挡掉测试合法路径。
唯一出路：几何复核拦幽灵 + 修正测试让直调时玩家真实站在门边。

## 三、验证
- `test_room_flow.tscn` 单跑 50/50 全绿（修复前 ~50% 失败率）
- 全量门禁 15 套全绿

## 四、遗留观察
- `_suppress_all_doors` / `_release_suppressed_doors` 的几何释放路径
  （原始设计）保留——几何复核在信号端兜底，双层防御
- 探针脚本（`tests/probe_ghost_overlap.*`）已删除；如需复现调查，
  参考 `.gdd_build/` 时期的插桩方式：在 `door_trigger._on_body_entered`
  print 门路径+玩家坐标+物理帧号（勿在 `_transition_to_room` 插桩）

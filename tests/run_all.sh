#!/usr/bin/env bash
# 《噬铁者》全量测试门禁 —— 一条命令跑完所有套件，任一失败即非 0 退出
# 用法：bash tests/run_all.sh
#
# 背景：此前"文档写全绿、实际已断链"的假绿灯，根因是场景测试从未被批量执行。
# 收工前必须跑本脚本并以输出为证据（见 AGENTS.md 收工流程）。

set -uo pipefail

GODOT="${GODOT:-F:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -f "$GODOT" ]; then
	echo "找不到 Godot：$GODOT"
	echo "请设置环境变量 GODOT 指向 Godot 可执行文件"
	exit 1
fi

cd "$PROJECT_DIR" || exit 1

FAILED_SUITES=()
PASSED_SUITES=()

# --script 模式套件（SceneTree 脚本，无 autoload）
run_script_suite() {
	local name="$1" path="$2"
	echo "── $name ──────────────────────────────"
	local out rc
	out=$(timeout 300 "$GODOT" --headless --path . --script "$path" 2>&1)
	rc=$?
	echo "$out" | grep -E "ALL .*PASSED|FAILED:|\.\.\. FAIL|ALL [0-9]+ TESTS" || true
	_judge "$name" "$out" "$rc"
}

# 场景模式套件（.tscn，带 autoload，真实节点树）
run_scene_suite() {
	local name="$1" path="$2"
	echo "── $name ──────────────────────────────"
	local out rc
	out=$(timeout 300 "$GODOT" --headless --path . "$path" 2>&1)
	rc=$?
	echo "$out" | grep -E "ALL .*PASSED|FAILED:|\[FAIL\]" || true
	_judge "$name" "$out" "$rc"
}

# 判定单套结果。
#
# **必须同时看退出码**：套件跑完会调 `get_tree().quit(0)`，进程随即退出，
# stdout 管道里尚未冲刷的缓冲会被丢掉——`$(...)` 抓到的流是**被截断**的，
# 截断位置每次不同（表现为"每轮红的套件不一样"，而单独跑同样的套件却通过）。
# 只查文本就会把已通过的套件判成失败。退出码不受缓冲影响，是权威信号；
# 文本标记仍保留，用于兜住"退出码 0 但实际有断言失败"的情况。
_judge() {
	local name="$1" out="$2" rc="$3"
	if echo "$out" | grep -qE "FAILED:|\.\.\. FAIL|\[FAIL\]"; then
		FAILED_SUITES+=("$name")
	elif echo "$out" | grep -qE "PASSED" || [ "$rc" -eq 0 ]; then
		PASSED_SUITES+=("$name")
	else
		echo "  (退出码 $rc，且未出现 PASSED 标记——脚本可能加载失败或挂起)"
		FAILED_SUITES+=("$name")
	fi
}

echo "=============================================="
echo "《噬铁者》全量测试门禁"
echo "引擎：$GODOT"
echo "=============================================="
echo

run_script_suite "framework    (核心逻辑)" "res://tests/test_framework.gd"
run_script_suite "iron_studio  (编辑器数据类)" "res://tests/test_iron_studio.gd"
run_scene_suite  "menu         (主菜单交互)" "res://tests/test_menu_interaction_scene.tscn"
run_scene_suite  "settings     (设置面板)" "res://tests/test_settings_panel.tscn"
run_scene_suite  "backpack     (背包 UI)" "res://tests/test_backpack_ui.tscn"
run_scene_suite  "class_mech   (职业/形态机制)" "res://tests/test_class_mechanics.tscn"
# CrowdSim 有双后端：有 C++ 扩展时测真扩展，无编译产物时自动改测
# GDScript fallback（见 addons/crowd_sim/crowd_sim_loader.gd）。
# 故本套件在 CI / 新克隆的机器上**照样跑逻辑断言**，不是整片 SKIP。
run_scene_suite  "crowd_sim    (海量单位模拟)" "res://tests/test_crowd_sim.tscn"
run_scene_suite  "crowd_affix  (群体单位词缀)" "res://tests/test_crowd_affix.tscn"
run_scene_suite  "pickup_field (掉落物规模化)" "res://tests/test_pickup_field.tscn"
run_scene_suite  "mass_text    (海量文本渲染)" "res://tests/test_mass_text.tscn"
run_scene_suite  "projectile   (投射物模拟核)" "res://tests/test_projectile_sim.tscn"
run_scene_suite  "proj_mgr     (投射物接线)" "res://tests/test_projectile_manager.tscn"
run_scene_suite  "effect_field (特效池)" "res://tests/test_effect_field.tscn"
run_scene_suite  "player_state (玩家状态机)" "res://tests/test_player_states.tscn"
run_scene_suite  "room_flow    (房间流程+特殊房)" "res://tests/test_room_flow.tscn"
run_scene_suite  "special_room (特殊房交互 UI)" "res://tests/test_special_room_ui.tscn"
run_scene_suite  "debug_mode   (调试模式)" "res://tests/test_debug_mode.tscn"
run_scene_suite  "element_buff (元素/词条框架)" "res://tests/test_element_buff.tscn"
run_scene_suite  "door_physics (穿门物理信号)" "res://tests/test_door_physics.tscn"
run_scene_suite  "floor_flow   (楼层递进)" "res://tests/test_floor_flow.tscn"
run_scene_suite  "death_flow   (死亡结算)" "res://tests/test_death_flow.tscn"
run_scene_suite  "gameplay     (运行时行为回归)" "res://tests/test_gameplay_fixes.tscn"
run_scene_suite  "fixes2       (连锁切房/伤害数字)" "res://tests/test_gameplay_fixes2.tscn"
run_scene_suite  "skill_mech   (技能机制落地)" "res://tests/test_skill_mechanics.tscn"
run_scene_suite  "ranged_atk   (远程普攻)" "res://tests/test_ranged_attack.tscn"
run_scene_suite  "equip_elem   (装备元素词条)" "res://tests/test_equip_element.tscn"

echo
echo "=============================================="
echo "通过：${#PASSED_SUITES[@]} 套"
for s in "${PASSED_SUITES[@]}"; do echo "  [OK]   $s"; done
if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
	echo "失败：${#FAILED_SUITES[@]} 套"
	for s in "${FAILED_SUITES[@]}"; do echo "  [FAIL] $s"; done
	echo "=============================================="
	exit 1
fi
echo "全部套件通过"
echo "=============================================="
exit 0

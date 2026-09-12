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
	local out
	out=$(timeout 300 "$GODOT" --headless --path . --script "$path" 2>&1)
	echo "$out" | grep -E "ALL .*PASSED|FAILED:|\.\.\. FAIL|ALL [0-9]+ TESTS" || true
	if echo "$out" | grep -qE "FAILED:|\.\.\. FAIL"; then
		FAILED_SUITES+=("$name")
	else
		PASSED_SUITES+=("$name")
	fi
}

# 场景模式套件（.tscn，带 autoload，真实节点树）
run_scene_suite() {
	local name="$1" path="$2"
	echo "── $name ──────────────────────────────"
	local out
	out=$(timeout 300 "$GODOT" --headless --path . "$path" 2>&1)
	echo "$out" | grep -E "ALL .*PASSED|FAILED:|\[FAIL\]" || true
	if echo "$out" | grep -qE "FAILED:|\[FAIL\]"; then
		FAILED_SUITES+=("$name")
	else
		PASSED_SUITES+=("$name")
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
run_scene_suite  "backpack     (背包 UI)" "res://tests/test_backpack_ui.tscn"
run_scene_suite  "combat       (战斗系统)" "res://tests/test_combat_system.tscn"
run_scene_suite  "room_flow    (房间流程+特殊房)" "res://tests/test_room_flow.tscn"
run_scene_suite  "door_physics (穿门物理信号)" "res://tests/test_door_physics.tscn"
run_scene_suite  "floor_flow   (楼层递进)" "res://tests/test_floor_flow.tscn"
run_scene_suite  "death_flow   (死亡结算)" "res://tests/test_death_flow.tscn"

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

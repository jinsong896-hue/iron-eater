extends SceneTree
## 生成默认美术配置 `data/art/default_profile.tres`
##
## ## 为什么用生成器而不是手写 .tres
##
## `.tres` 里 Dictionary 的序列化格式（嵌套 Variant 字面量）手写容易出错，
## 且 Godot 写入时会带上 `script_class` / `uid` 等元数据。用
## `ResourceSaver.save()` 生成保证格式一定正确。
##
## ## 初始映射的选择
##
## `decoration_builder.PROP_PATHS` 有 4 个用途，其中：
##   · `chest`  —— `scenes/props/chest.tscn` **存在**，不需要配置
##   · `torch` / `barrel` / `pillar` —— 指向的 .tscn **都不存在**，
##     每次加载失败后静默回退到方块占位
##
## 故只配这 3 个，从 castle-kit 里挑语义最接近的：
##   · `pillar` → `wall-pillar`   柱状，语义直接对应
##   · `torch`  → `flag-pennant`  细杆 + 顶部小旗，视觉上像火把
##   · `barrel` → `rocks-small`   矮小圆润的物件
##
## **变换参数先给中性值**（scale=1.0 / offset=0 / rotation=0）——
## castle-kit 的 AABB 是 1.00 单位宽，与项目 `CELL_SIZE = 1.0` 匹配，
## 大概率不需要缩放。实际观感需在编辑器界面里逐个调，调完覆盖此文件。
##
## ## 用法
##
## ```bash
## "$GODOT" --headless --path . --script res://tools/gen_default_art_profile.gd
## ```

const OUT_PATH := "res://data/art/default_profile.tres"
const MODEL_DIR := "res://assets/castle-kit/Models/GLB format/"

## 用途 → castle-kit 模型名
const INITIAL_PROPS := {
	"pillar": "wall-pillar",
	"torch": "flag-pennant",
	"barrel": "rocks-small",
}


func _init() -> void:
	var p := ArtProfile.new()
	var missing: Array = []
	for prop_type in INITIAL_PROPS:
		var model: String = MODEL_DIR + str(INITIAL_PROPS[prop_type]) + ".glb"
		# **用 load() 校验**——castle-kit 有 30 个模型的 .import 是坏的
		#（exists() 返 true 但 load() 返 null），不校验就会配上一个用不了的路径
		if load(model) == null:
			missing.append(model)
			continue
		p.set_prop(str(prop_type), model)
		print("  %-8s → %s" % [prop_type, model])

	if not missing.is_empty():
		push_error("[gen] 以下模型加载失败，未写入配置：\n  " + "\n  ".join(missing))
		quit(1)
		return

	# 确保目录存在（新克隆时 data/art/ 可能不存在）
	DirAccess.make_dir_recursive_absolute("res://data/art")

	var err := ResourceSaver.save(p, OUT_PATH)
	if err != OK:
		push_error("[gen] 保存失败：%s（错误码 %d）" % [OUT_PATH, err])
		quit(1)
		return

	print("\n已写入 %s" % OUT_PATH)
	print("配置了 %d 个用途：%s" % [p.configured_props().size(), str(p.configured_props())])
	quit(0)

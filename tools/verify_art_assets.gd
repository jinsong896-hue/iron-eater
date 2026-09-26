extends SceneTree
## 美术资源可用性校验 —— **必须用 `load()`，不能用 `exists()`**
##
## ## 为什么不能用 `exists()`
##
## 项目已知陷阱（见 CLAUDE.md 与项目记忆）：`.import` 里
## `valid=false` 的资源，`ResourceLoader.exists()` **仍然返回 true**，
## 但 `load()` 返回 null。于是：
##
##   · 校验脚本报「全部正常」——假绿灯
##   · 运行时 `ResourceLoader.exists()` 通过、`load()` 拿到 null，
##     静默回退到占位体，玩家看到方块而不是模型
##
## 实测 castle-kit 76 个模型里 **30 个**如此（全部 `siege-*` / 大部分
## `tower-*` / 全部 `tree-*`）。源文件本身是好的（GLB 头 magic
## `676c5446`、version 2、声明长度与实际字节数一致），是**导入失败**。
##
## ## 用法
##
## ```bash
## "$GODOT" --headless --path . --script res://tools/verify_art_assets.gd
## ```
##
## 退出码：0 = 全部可加载，1 = 有失败项（可进门禁）

## 扫描范围
const SCAN_DIRS := [
	"res://assets",
]

## 视为「美术资源」的扩展名
##
## **不含 FBX/OBJ**：castle-kit 提供同一批模型的 3 套格式（GLB/FBX/OBJ），
## 项目**只用 GLB**。实测 FBX 9 个 + OBJ 76 个导入失败，但那是**冗余格式**，
## 修它们没有意义——只会让校验报告被噪声淹没（85 条失败里 85 条是它们）。
##
## 若将来真的要换格式，再单独处理。
const ART_EXTS := ["glb", "gltf", "tscn", "tres", "res"]

## 需要跳过的大目录（UI 素材数量巨大且不走 3D 加载，单独统计）
const SKIP_DIRS := ["ui-pack", "game-icons", "fantasy-ui-borders", "rpg-audio"]


func _init() -> void:
	var ok: Array[String] = []
	var bad: Array[String] = []
	var skipped := 0

	for d in SCAN_DIRS:
		_walk(d, ok, bad)

	print("=== 美术资源可用性校验（用 load()）===")
	print("可加载 : %d" % ok.size())
	print("失败   : %d" % bad.size())
	print("跳过   : %d（UI/音频素材，不走 3D 加载）" % skipped)

	if not bad.is_empty():
		print("\n--- 失败清单 ---")
		for p in bad:
			# 附上 .import 的 valid 状态，便于判断是导入失败还是文件缺失
			var imp := p + ".import"
			var why := "无 .import"
			if FileAccess.file_exists(imp):
				var f := FileAccess.open(imp, FileAccess.READ)
				if f != null:
					var txt := f.get_as_text()
					f.close()
					why = "valid=false（导入失败）" if txt.contains("valid=false") \
						else "有 .import 但 load 失败"
			print("  %s  ← %s" % [p, why])

	print("\n%s" % ("全部可加载" if bad.is_empty() else "存在失败项"))
	quit(0 if bad.is_empty() else 1)


## 递归扫描目录
func _walk(dir_path: String, ok: Array[String], bad: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if not f.begins_with("."):
				var full := dir_path + "/" + f
				# 跳过 UI/音频大类（数量巨大，且不参与 3D 加载校验）
				var skip := false
				for s in SKIP_DIRS:
					if f == s:
						skip = true
				if not skip:
					_walk(full, ok, bad)
		else:
			var ext := f.get_extension().to_lower()
			if ext in ART_EXTS:
				var full := dir_path + "/" + f
				# **判据是 load() 而不是 exists()**——见文件头说明
				var res = load(full)
				if res != null:
					ok.append(full)
				else:
					bad.append(full)
		f = d.get_next()
	d.list_dir_end()

class_name UITheme
extends RefCounted
## 游戏 UI 主题：《AGENTS.md 素材规则》——使用已下载的 Kenney 免费素材
## 按钮皮肤：ui-pack；面板边框：fantasy-ui-borders；背景：roguelike-rpg-pack

const BUTTON_TEX := "res://assets/ui-pack/PNG/Blue/Default/button_round_depth_gradient.png"
const PANEL_TEX := "res://assets/fantasy-ui-borders/PNG/Default/Border/panel-border-000.png"
const MENU_BG := "res://assets/roguelike-rpg-pack/Sample2.png"

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = _build()
	return _theme


static func get_menu_background() -> Texture2D:
	return load(MENU_BG)


static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_color("font_color", "Button", Color(0.94, 0.92, 0.88))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color(0.7, 0.6, 0.5))
	theme.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.48))
	theme.set_constant("outline_size", "Button", 0)

	var btn_tex := load(BUTTON_TEX) as Texture2D
	for style_name in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxTexture.new()
		sb.texture = btn_tex
		sb.texture_margin_left = 26.0
		sb.texture_margin_right = 26.0
		sb.texture_margin_top = 14.0
		sb.texture_margin_bottom = 16.0
		sb.content_margin_left = 26.0
		sb.content_margin_right = 26.0
		sb.content_margin_top = 10.0
		sb.content_margin_bottom = 10.0
		match style_name:
			"hover":
				sb.modulate_color = Color(1.25, 1.25, 1.25)
			"pressed":
				sb.modulate_color = Color(0.75, 0.75, 0.8)
				sb.content_margin_top = 12.0
				sb.content_margin_bottom = 8.0
			"disabled":
				sb.modulate_color = Color(0.5, 0.5, 0.55)
		theme.set_stylebox(style_name, "Button", sb)

	var panel_tex := load(PANEL_TEX) as Texture2D
	var panel_sb := StyleBoxTexture.new()
	panel_sb.texture = panel_tex
	panel_sb.texture_margin_left = 48.0
	panel_sb.texture_margin_right = 48.0
	panel_sb.texture_margin_top = 48.0
	panel_sb.texture_margin_bottom = 48.0
	panel_sb.content_margin_left = 30.0
	panel_sb.content_margin_right = 30.0
	panel_sb.content_margin_top = 24.0
	panel_sb.content_margin_bottom = 24.0
	theme.set_stylebox("panel", "PanelContainer", panel_sb)

	theme.set_color("font_color", "Label", Color(0.93, 0.92, 0.9))
	theme.set_color("font_color", "RichTextLabel", Color(0.93, 0.92, 0.9))
	return theme

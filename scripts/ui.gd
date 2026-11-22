extends CanvasLayer
## HUD, menus, inventory and crafting screens (all built in code).

const SLOT := 58
const CHEST0 := 100  # UI slot index of the first chest slot (inventory slots are 0..40)
const FURN_IN := 200  # UI slot indexes of the open furnace's input, fuel and output
const FURN_FUEL := 201
const FURN_OUT := 202
const FURN_KEYS := ["in", "fuel", "out"]
const FLAME := ["....#......", "....##.....", "...###.....", "...####....", "..#####.#..", "..#######..",
	".#########.", ".#########.", "###########", "###########", ".#########.", "..#######.."]
const ACCENT := Color(1.0, 0.62, 0.2)
const ACCENT_DARK := Color(0.72, 0.38, 0.08)
const TEAL := Color(0.38, 0.9, 0.95)
const INK := Color(0.07, 0.08, 0.11, 0.93)
const MUTED := Color(0.72, 0.76, 0.86)
const GOOD := Color(0.55, 0.95, 0.55)
const BAD := Color(1.0, 0.45, 0.4)
const VERSION := "v1.0"
const SPLASHES := [
	"Now with 6 sides!", "Gravity is a suggestion!", "Mind the edges!", "100% cube!", "Don't dig straight down!",
	"Also try: escaping!", "Torches keep the dark away!", "The core is warm!", "Jump the shockwave!", "Pixel perfect!",
]
const TIPS := [
	"Walk off any edge - gravity rotates onto the next face.",
	"Torches stop monsters from spawning nearby.",
	"Hit monsters while falling for a critical hit.",
	"Zombies burn in daylight. Boomers do not.",
	"Hold Right Mouse with food to eat it.",
	"Double-tap W to sprint.",
	"Diamonds hide deep inside the planet.",
	"Stand near a Crafting Table to unlock more recipes.",
	"Hover an item and press 1-9 to move it to your hotbar.",
	"Shift-click a recipe to craft as many as you can.",
]

var main
var root: Control
var font_r: SystemFont
var font_b: SystemFont
var font_x: SystemFont

var hud: Control
var hotbar: HBoxContainer
var hot_slots: Array[Control] = []
var hearts: HBoxContainer
var heart_rects: Array[TextureRect] = []
var armor_row: HBoxContainer
var armor_rects: Array[TextureRect] = []
var hot_panel: PanelContainer
var off_slot: Panel
var heart_flash := 0.0
var heal_t := 0.0
var last_health := 20.0
var air_label: Label
var obj_panel: PanelContainer
var obj_title: Label
var obj_text: Label
var obj_hint: Label
var obj_bar: ProgressBar
var toast_box: PanelContainer
var toast_label: Label
var toast_t := 0.0
var held_label: Label
var held_t := 0.0
var info_label: Label
var info_sub: Label
var info_icon: Label
var day_bar: ProgressBar
var fps_label: Label
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_trail: ProgressBar
var boss_tag: Label
var vignette: ColorRect
var water_overlay: ColorRect
var crosshair: Control
var flash_rect: ColorRect
var fade_rect: ColorRect
var banner_box: VBoxContainer
var banner_kicker: Label
var banner_title: Label
var banner_sub: Label
var banner_t := 0.0
var banner_len := 0.0
var feed: VBoxContainer
var feed_items := {}
var heartbeat_t := 0.0

var title_screen: Control
var continue_btn: Button
var splash: Label
var loading_screen: Control
var loading_bar: ProgressBar
var loading_label: Label
var loading_tip: Label
var loading_icon: TextureRect
var tip_t := 0.0
var pause_screen: Control
var pause_stats: Label
var death_screen: Control
var death_label: Label
var death_stats: Label
var respawn_btn: Button
var death_t := 0.0
var end_screen: Control
var end_stats: Label
var confirm_screen: Control
var confirm_label: Label
var confirm_cb: Callable
var help_screen: Control
var settings_screen: Control
var worlds_screen: Control
var world_list: VBoxContainer
var create_screen: Control
var create_name: LineEdit
var create_seed: LineEdit
var create_mode := "survival"
var create_mode_btns := {}
var create_mode_desc: Label
var settings_back := "title"
var screen_name := ""
var t := 0.0

var inv_screen: Control
var inv_panel: PanelContainer
var inv_slots: Array[Control] = []
var chest_slots: Array[Control] = []
var chest_box: VBoxContainer
var inv_right: VBoxContainer
var chest_idx := -1
var furnace_idx := -1
var furnace_box: VBoxContainer
var furn_slots: Array[Control] = []
var furn_flame: Control
var furn_arrow: Control
var hover_slot := -1
var craft_list: VBoxContainer
var craft_status: HBoxContainer
var craftable_only: CheckBox
var creative_grid: GridContainer
var craft_scroll: ScrollContainer
var creative_scroll: ScrollContainer
var craft_title: Label
var tip_panel: PanelContainer
var tip_name: Label
var tip_desc: Label
var cursor_icon: TextureRect
var cursor_label: Label
var cursor_stack = null


func setup(m) -> void:
	main = m
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_hud()
	_build_title()
	_build_loading()
	_build_pause()
	_build_settings()
	_build_worlds()
	_build_create()
	_build_death()
	_build_end()
	_build_confirm()
	_build_help()
	_build_inventory()
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade_rect)
	show_screen("")


# ---------------- theme helpers ----------------

func _font(weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Avenir Next", "Segoe UI", "Helvetica Neue", "Arial"])
	f.font_weight = weight
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


func _sb(bg: Color, radius := 10, border := Color(1, 1, 1, 0.1), bw := 2, margin := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.anti_aliasing = true
	return s


func _img_tex(w: int, h: int, painter: Callable) -> ImageTexture:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			im.set_pixel(x, y, painter.call(x, y))
	return ImageTexture.create_from_image(im)


func _circle(r: int, col: Color, ring := Color(0, 0, 0, 0)) -> ImageTexture:
	var s := r * 2
	return _img_tex(s, s, func(x, y):
		var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
		var a := clampf(r - d, 0.0, 1.0)
		var c: Color = col
		if ring.a > 0.0 and d > r - 3.0:
			c = ring
		return Color(c.r, c.g, c.b, c.a * a))


func _check_tex(on: bool) -> ImageTexture:
	return _img_tex(24, 24, func(x, y):
		var inside: bool = x >= 1 and y >= 1 and x <= 22 and y <= 22
		if not inside:
			return Color(0, 0, 0, 0)
		var edge: bool = x <= 2 or y <= 2 or x >= 21 or y >= 21
		if on:
			var mark: bool = (absi((x - 5) - (y - 11)) <= 1 and x >= 5 and x <= 10) or (absi((x - 10) + (y - 16)) <= 1 and x >= 10 and x <= 18)
			if mark:
				return Color(0.1, 0.06, 0.02)
			return ACCENT if not edge else ACCENT_DARK
		return Color(1, 1, 1, 0.35) if edge else Color(0, 0, 0, 0.35))


func _make_theme() -> Theme:
	font_r = _font(500)
	font_b = _font(700)
	font_x = _font(900)
	var th := Theme.new()
	th.default_font = font_r
	th.default_font_size = 18
	var panel := _sb(INK, 14, Color(1, 1, 1, 0.09), 1, 18)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 18
	panel.shadow_offset = Vector2(0, 6)
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("panel", "Panel", panel)
	# Buttons: chunky keycaps with a darker bottom lip that compresses when pressed.
	var bn := _sb(Color(0.17, 0.19, 0.26, 0.96), 10, Color(0.07, 0.08, 0.11, 1.0), 0, 12)
	bn.border_width_bottom = 5
	bn.content_margin_bottom = 14
	var bh := bn.duplicate()
	bh.bg_color = ACCENT
	bh.border_color = ACCENT_DARK
	var bp := bh.duplicate()
	bp.bg_color = Color(0.92, 0.52, 0.14)
	bp.border_width_bottom = 1
	bp.content_margin_top = 16
	bp.content_margin_bottom = 10
	var bd := bn.duplicate()
	bd.bg_color = Color(0.13, 0.14, 0.18, 0.8)
	var bf := _sb(Color(0, 0, 0, 0), 11, Color(1, 1, 1, 0.85), 3, 0)
	bf.draw_center = false
	bf.expand_margin_left = 3
	bf.expand_margin_right = 3
	bf.expand_margin_top = 3
	bf.expand_margin_bottom = 3
	th.set_stylebox("normal", "Button", bn)
	th.set_stylebox("hover", "Button", bh)
	th.set_stylebox("pressed", "Button", bp)
	th.set_stylebox("hover_pressed", "Button", bp)
	th.set_stylebox("focus", "Button", bf)
	th.set_stylebox("disabled", "Button", bd)
	th.set_font("font", "Button", font_b)
	th.set_font_size("font_size", "Button", 21)
	th.set_color("font_color", "Button", Color(0.95, 0.96, 1.0))
	th.set_color("font_hover_color", "Button", Color(0.12, 0.06, 0.0))
	th.set_color("font_pressed_color", "Button", Color(0.12, 0.06, 0.0))
	th.set_color("font_hover_pressed_color", "Button", Color(0.12, 0.06, 0.0))
	th.set_color("font_focus_color", "Button", Color(1, 1, 1))
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	var pb_bg := _sb(Color(0, 0, 0, 0.55), 6, Color(1, 1, 1, 0.08), 1, 0)
	var pb_fg := _sb(ACCENT, 6, Color(1, 1, 1, 0.0), 0, 0)
	th.set_stylebox("background", "ProgressBar", pb_bg)
	th.set_stylebox("fill", "ProgressBar", pb_fg)
	th.set_constant("outline_size", "Label", 0)
	# Sliders
	var track := _sb(Color(0, 0, 0, 0.5), 4, Color(1, 1, 1, 0.08), 1, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := _sb(ACCENT, 4, ACCENT, 0, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_icon("grabber", "HSlider", _circle(11, Color(1, 1, 1), ACCENT))
	th.set_icon("grabber_highlight", "HSlider", _circle(12, Color(1, 0.95, 0.85), ACCENT))
	th.set_stylebox("focus", "HSlider", StyleBoxEmpty.new())
	# Check boxes
	th.set_icon("checked", "CheckBox", _check_tex(true))
	th.set_icon("unchecked", "CheckBox", _check_tex(false))
	var cb := _sb(Color(1, 1, 1, 0.0), 8, Color(1, 1, 1, 0), 0, 8)
	var cbh := _sb(Color(1, 1, 1, 0.06), 8, Color(1, 1, 1, 0), 0, 8)
	for st in ["normal", "pressed", "focus"]:
		th.set_stylebox(st, "CheckBox", cb)
	th.set_stylebox("hover", "CheckBox", cbh)
	th.set_stylebox("hover_pressed", "CheckBox", cbh)
	th.set_constant("h_separation", "CheckBox", 10)
	for c in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		th.set_color(c, "CheckBox", Color(0.95, 0.96, 1.0))
	# Scroll bars
	var sc_bg := _sb(Color(0, 0, 0, 0.25), 5, Color(0, 0, 0, 0), 0, 0)
	sc_bg.content_margin_left = 5
	sc_bg.content_margin_right = 5
	var sc_g := _sb(Color(1, 1, 1, 0.22), 5, Color(0, 0, 0, 0), 0, 0)
	var sc_gh := _sb(Color(1, 1, 1, 0.38), 5, Color(0, 0, 0, 0), 0, 0)
	th.set_stylebox("scroll", "VScrollBar", sc_bg)
	th.set_stylebox("grabber", "VScrollBar", sc_g)
	th.set_stylebox("grabber_highlight", "VScrollBar", sc_gh)
	th.set_stylebox("grabber_pressed", "VScrollBar", _sb(ACCENT, 5, Color(0, 0, 0, 0), 0, 0))
	return th


func _label(text: String, size := 18, col := Color.WHITE, outline := 0, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 3)
		l.add_theme_constant_override("shadow_outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable, w := 340) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 58)
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	b.mouse_entered.connect(func():
		if not b.disabled:
			Sfx.play("hover", -14.0, randf_range(0.95, 1.05))
			b.create_tween().tween_property(b, "scale", Vector2(1.04, 1.04), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))
	b.focus_entered.connect(func(): Sfx.play("hover", -16.0))
	b.pressed.connect(func():
		Sfx.play("click", -6.0)
		cb.call())
	return b


func _screen(dim := 0.55, blur := false) -> ColorRect:
	var s := ColorRect.new()
	s.color = Color(0.02, 0.02, 0.05, dim)
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_STOP
	if blur:
		var sh := Shader.new()
		sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float dim = 0.55;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 3.2).rgb;
	float v = 1.0 - smoothstep(0.35, 0.95, distance(UV, vec2(0.5)));
	COLOR = vec4(mix(c * (1.0 - dim), vec3(0.02, 0.02, 0.05), 0.15) * mix(0.75, 1.0, v), 1.0);
}"""
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("dim", dim)
		s.material = mat
	root.add_child(s)
	return s


func _center_box(parent: Control, sep := 14) -> VBoxContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)
	return v


func _card(parent: Control, sep := 12) -> VBoxContainer:
	var pc := PanelContainer.new()
	parent.add_child(pc)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", sep)
	pc.add_child(inner)
	return inner


func _heading(text: String, size := 40) -> Label:
	var l := _label(text, size, Color.WHITE, 0, font_x)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _slot_style(selected := false, hover := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.18, 0.24, 0.92) if (selected or hover) else Color(0.11, 0.12, 0.16, 0.85)
	sb.border_color = ACCENT if selected else (Color(1, 1, 1, 0.35) if hover else Color(1, 1, 1, 0.08))
	sb.set_border_width_all(3 if selected else 2)
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	sb.shadow_color = Color(1.0, 0.6, 0.15, 0.35) if selected else Color(0, 0, 0, 0)
	sb.shadow_size = 8 if selected else 0
	return sb


func _slot_panel(selected := false, key := "") -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT, SLOT)
	p.add_theme_stylebox_override("panel", _slot_style(selected))
	p.resized.connect(func(): p.pivot_offset = p.size / 2.0)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 9
	icon.offset_top = 9
	icon.offset_right = -9
	icon.offset_bottom = -9
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(icon)
	if key != "":
		var k := _label(key, 11, Color(1, 1, 1, 0.4), 0, font_b)
		k.position = Vector2(6, 2)
		p.add_child(k)
	var cnt := _label("", 16, Color.WHITE, 4, font_b)
	cnt.name = "Count"
	cnt.set_anchors_preset(Control.PRESET_FULL_RECT)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	cnt.offset_right = -5
	cnt.offset_bottom = 0
	p.add_child(cnt)
	return p


## `ghost` = item drawn as a faint silhouette while the slot is empty (armor / offhand placeholders).
func _set_slot(p: Control, s, ghost := 0) -> void:
	var icon: TextureRect = p.get_node("Icon")
	var cnt: Label = p.get_node("Count")
	icon.modulate = Color.WHITE
	if s:
		icon.texture = T.icon(s["id"])
		cnt.text = str(s["n"]) if s["n"] > 1 else ""
	else:
		icon.texture = T.icon(ghost) if ghost > 0 else null
		icon.modulate = Color(0, 0, 0, 0.4)
		cnt.text = ""


func _set_slot_selected(p: Panel, selected: bool, hover := false) -> void:
	p.add_theme_stylebox_override("panel", _slot_style(selected, hover))


func rarity_color(id: int) -> Color:
	if id == B.STARCORE or id == B.STARCORE_ORE or id in [B.ROCKET, B.ROCKET_HULL, B.ROCKET_ENGINE, B.FUEL_CELL, B.NAV_CORE]:
		return Color(0.95, 0.55, 1.0)
	if id == B.DIAMOND or id == B.DIAMOND_ORE or (id >= B.WOOD_PICK and id <= B.DIAMOND_SWORD and (id - B.WOOD_PICK) % 4 == 3) or (id >= B.DIAMOND_HELMET and id <= B.DIAMOND_BOOTS):
		return TEAL
	if id == B.GOLD_INGOT or id == B.GOLD_ORE:
		return Color(1.0, 0.85, 0.3)
	return Color.WHITE


# ---------------- HUD ----------------

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	water_overlay = ColorRect.new()
	water_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	water_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ws := Shader.new()
	ws.code = """shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.1, 0.3, 0.65, 0.4);
void fragment() {
	float w = sin(UV.y * 18.0 + TIME * 2.0) * 0.5 + sin(UV.x * 11.0 - TIME * 1.3) * 0.5;
	float edge = smoothstep(0.25, 0.9, distance(UV, vec2(0.5)));
	COLOR = vec4(tint.rgb * (1.0 + w * 0.06), tint.a * (0.8 + edge * 0.5));
}"""
	var wm := ShaderMaterial.new()
	wm.shader = ws
	water_overlay.material = wm
	water_overlay.visible = false
	hud.add_child(water_overlay)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = """shader_type canvas_item;
uniform float amount = 0.0;
uniform float base = 0.28;
void fragment() {
	vec2 q = UV - 0.5;
	q.x *= 1.4;
	float d = length(q);
	float dark = smoothstep(0.45, 1.05, d) * base;
	float red = smoothstep(0.3, 0.85, d) * amount;
	COLOR = vec4(mix(vec3(0.0), vec3(0.75, 0.0, 0.02), red / max(red + dark, 0.001)), clamp(dark + red, 0.0, 1.0));
}"""
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vignette.material = vm
	hud.add_child(vignette)
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(flash_rect)
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	hud.add_child(crosshair)
	_build_bottom()
	_build_objective()
	_build_info()
	_build_boss()
	_build_banner()
	feed = VBoxContainer.new()
	feed.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	feed.offset_right = -24
	feed.offset_bottom = -26
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.add_theme_constant_override("separation", 6)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(feed)


func _build_bottom() -> void:
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -14
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bottom)
	toast_box = PanelContainer.new()
	toast_box.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.06, 0.09, 0.82), 20, Color(1, 1, 1, 0.1), 1, 0))
	toast_box.get_theme_stylebox("panel").content_margin_left = 20
	toast_box.get_theme_stylebox("panel").content_margin_right = 20
	toast_box.get_theme_stylebox("panel").content_margin_top = 7
	toast_box.get_theme_stylebox("panel").content_margin_bottom = 7
	toast_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.modulate.a = 0.0
	bottom.add_child(toast_box)
	toast_label = _label("", 20, Color(1, 0.96, 0.88), 0, font_b)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_box.add_child(toast_label)
	held_label = _label("", 19, Color.WHITE, 4, font_b)
	held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(held_label)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(col)
	armor_row = HBoxContainer.new()
	armor_row.add_theme_constant_override("separation", 3)
	armor_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	armor_row.visible = false
	col.add_child(armor_row)
	var apad := Control.new()
	apad.custom_minimum_size = Vector2(8, 0)
	armor_row.add_child(apad)
	for i in 10:
		var a := TextureRect.new()
		a.texture = T.armor_full
		a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		a.custom_minimum_size = Vector2(27, 21)
		armor_row.add_child(a)
		armor_rects.append(a)
	hearts = HBoxContainer.new()
	hearts.add_theme_constant_override("separation", 1)
	hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hearts)
	var hpad := Control.new()
	hpad.custom_minimum_size = Vector2(6, 0)
	hearts.add_child(hpad)
	for i in 10:
		var h := TextureRect.new()
		h.texture = T.heart_full
		h.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.custom_minimum_size = Vector2(33, 27)
		h.pivot_offset = Vector2(16.5, 13.5)
		hearts.add_child(h)
		heart_rects.append(h)
	hot_panel = PanelContainer.new()
	var bar := hot_panel
	var bs := _sb(Color(0.04, 0.05, 0.07, 0.7), 14, Color(1, 1, 1, 0.08), 1, 6)
	bs.shadow_color = Color(0, 0, 0, 0.35)
	bs.shadow_size = 10
	bar.add_theme_stylebox_override("panel", bs)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bar)
	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 5)
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(hotbar)
	for i in 9:
		var p := _slot_panel(i == 0, str(i + 1))
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hotbar.add_child(p)
		hot_slots.append(p)
	off_slot = _slot_panel()
	off_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(off_slot)


func _build_objective() -> void:
	obj_panel = PanelContainer.new()
	obj_panel.position = Vector2(22, 22)
	obj_panel.custom_minimum_size = Vector2(390, 0)
	obj_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := _sb(Color(0.05, 0.06, 0.09, 0.8), 14, Color(1, 1, 1, 0.08), 1, 16)
	ps.set_border_width_all(0)
	ps.border_width_left = 4
	ps.border_color = ACCENT
	ps.shadow_color = Color(0, 0, 0, 0.3)
	ps.shadow_size = 12
	obj_panel.add_theme_stylebox_override("panel", ps)
	hud.add_child(obj_panel)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 4)
	obj_panel.add_child(ov)
	obj_title = _label("MISSION", 13, ACCENT, 0, font_x)
	ov.add_child(obj_title)
	obj_text = _label("", 23, Color.WHITE, 0, font_b)
	obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_text.custom_minimum_size = Vector2(350, 0)
	ov.add_child(obj_text)
	obj_hint = _label("", 15, MUTED)
	obj_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_hint.custom_minimum_size = Vector2(350, 0)
	ov.add_child(obj_hint)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 4)
	ov.add_child(sp)
	obj_bar = ProgressBar.new()
	obj_bar.custom_minimum_size = Vector2(0, 6)
	obj_bar.show_percentage = false
	ov.add_child(obj_bar)


func _build_info() -> void:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pc.offset_right = -22
	pc.offset_top = 22
	pc.custom_minimum_size = Vector2(240, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.06, 0.09, 0.75), 14, Color(1, 1, 1, 0.08), 1, 14))
	hud.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	pc.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	info_icon = _label("☀", 20, Color(1.0, 0.85, 0.4), 0, font_b)
	row.add_child(info_icon)
	info_label = _label("", 19, Color.WHITE, 0, font_b)
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_label)
	day_bar = ProgressBar.new()
	day_bar.custom_minimum_size = Vector2(0, 5)
	day_bar.show_percentage = false
	day_bar.add_theme_stylebox_override("fill", _sb(Color(1.0, 0.85, 0.4), 3, Color(0, 0, 0, 0), 0, 0))
	v.add_child(day_bar)
	info_sub = _label("", 14, MUTED)
	v.add_child(info_sub)
	fps_label = _label("", 13, Color(0.6, 1.0, 0.6))
	v.add_child(fps_label)


func _build_boss() -> void:
	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_box.offset_top = 24
	boss_box.offset_left = -330
	boss_box.offset_right = 330
	boss_box.add_theme_constant_override("separation", 6)
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(boss_box)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	boss_box.add_child(hb)
	hb.add_child(_label("THE CORE SENTINEL", 22, Color(1, 0.72, 0.55), 5, font_x))
	boss_tag = _label("ENRAGED", 14, Color(1, 0.3, 0.2), 4, font_x)
	boss_tag.visible = false
	hb.add_child(boss_tag)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(660, 20)
	boss_box.add_child(stack)
	boss_trail = ProgressBar.new()
	boss_trail.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_trail.show_percentage = false
	boss_trail.add_theme_stylebox_override("fill", _sb(Color(1, 0.92, 0.8), 6, Color(0, 0, 0, 0), 0, 0))
	stack.add_child(boss_trail)
	boss_bar = ProgressBar.new()
	boss_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_bar.show_percentage = false
	boss_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	boss_bar.add_theme_stylebox_override("fill", _sb(Color(0.9, 0.2, 0.15), 6, Color(1, 0.5, 0.4, 0.6), 1, 0))
	stack.add_child(boss_bar)
	boss_box.visible = false


func _build_banner() -> void:
	banner_box = VBoxContainer.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_box.offset_top = 150
	banner_box.offset_left = -500
	banner_box.offset_right = 500
	banner_box.add_theme_constant_override("separation", 2)
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.modulate.a = 0.0
	hud.add_child(banner_box)
	banner_kicker = _label("", 16, ACCENT, 4, font_x)
	banner_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_kicker)
	banner_title = _label("", 52, Color.WHITE, 8, font_x)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_title)
	banner_sub = _label("", 20, Color(0.92, 0.94, 1.0), 5, font_b)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.add_child(banner_sub)


func _draw_crosshair() -> void:
	var p = main.player
	var c := crosshair
	var ent: bool = p.target_ent != null
	var col := Color(1.0, 0.42, 0.35) if ent else Color(1, 1, 1, 0.95)
	var spread: float = 0.0
	if p.vm.is_swinging():
		spread = sin(p.vm.swing_t * PI) * 4.0
	if p.sprinting:
		spread += 2.0
	var gap := 4.0 + spread
	var ln := 7.0
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		c.draw_line(d * (gap - 1.0), d * (gap + ln + 1.0), Color(0, 0, 0, 0.45), 4.0)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		c.draw_line(d * gap, d * (gap + ln), col, 2.0)
	c.draw_circle(Vector2.ZERO, 1.6, col)
	var prog: float = p.break_prog
	if prog > 0.02:
		c.draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 40, Color(0, 0, 0, 0.4), 4.0, true)
		c.draw_arc(Vector2.ZERO, 19.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(prog, 0.0, 1.0), 40, ACCENT, 3.0, true)
	if p.eat_prog > 0.0:
		c.draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 40, Color(0, 0, 0, 0.4), 4.0, true)
		c.draw_arc(Vector2.ZERO, 19.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(p.eat_prog / p.EAT_TIME, 0.0, 1.0), 40, GOOD, 3.0, true)
	var hm: float = p.hit_marker
	if hm > 0.0:
		var hc := Color(1, 1, 1, hm)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var n: Vector2 = d.normalized()
			c.draw_line(n * 8.0, n * 15.0, Color(0, 0, 0, hm * 0.5), 4.0)
			c.draw_line(n * 8.0, n * 15.0, hc, 2.0)
	if p.attack_cd > 0.0 and ent:
		var w := 28.0
		var k: float = clampf(1.0 - p.attack_cd / 0.42, 0.0, 1.0)
		c.draw_rect(Rect2(-w / 2.0, 24.0, w, 4.0), Color(0, 0, 0, 0.5))
		c.draw_rect(Rect2(-w / 2.0, 24.0, w * k, 4.0), Color(1, 1, 1, 0.9))


func refresh_hotbar() -> void:
	var p = main.player
	for i in 9:
		_set_slot(hot_slots[i], p.inv[i])
		_set_slot_selected(hot_slots[i], i == p.sel)
		hot_slots[i].scale = Vector2(1.08, 1.08) if i == p.sel else Vector2.ONE
	_set_slot(off_slot, p.inv[p.OFFHAND], B.SHIELD)
	var id: int = p.held_id()
	var nm := B.item_name(id) if id > 0 else ""
	if nm != held_label.text:
		held_label.text = nm
		held_label.add_theme_color_override("font_color", rarity_color(id))
		held_t = 2.2


func pop_slot(i: int) -> void:
	var s: Control = hot_slots[i]
	s.scale = Vector2(1.22, 1.22)
	s.create_tween().tween_property(s, "scale", Vector2(1.08, 1.08), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func toast(text: String, secs := 3.0) -> void:
	toast_label.text = text
	if toast_t <= 0.0:
		toast_box.scale = Vector2(0.9, 0.9)
	toast_t = secs


func banner(title: String, sub: String, secs := 3.0, kicker := "") -> void:
	banner_kicker.text = kicker
	banner_kicker.visible = kicker != ""
	banner_title.text = title
	banner_sub.text = sub
	banner_t = secs
	banner_len = secs
	banner_box.pivot_offset = Vector2(500, 40)


func mission_complete(done: String, next: String) -> void:
	banner(done, ("Next: " + next) if next != "" else "", 3.6, "✦  MISSION COMPLETE  ✦")
	banner_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	obj_panel.modulate = Color(1.6, 1.4, 1.0)
	obj_panel.create_tween().tween_property(obj_panel, "modulate", Color.WHITE, 0.8)
	white_flash(0.12)


func pickup(id: int, n: int, first := false) -> void:
	if feed_items.has(id) and is_instance_valid(feed_items[id]["node"]):
		var e: Dictionary = feed_items[id]
		e["n"] += n
		e["t"] = 3.0
		e["label"].text = "+%d  %s" % [e["n"], B.item_name(id)]
		var node: Control = e["node"]
		node.scale = Vector2(1.08, 1.08)
		node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.15)
		return
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.06, 0.09, 0.8), 10, Color(1, 1, 1, 0.08) if not first else ACCENT, 1, 6))
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size_flags_horizontal = Control.SIZE_SHRINK_END
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	pc.add_child(hb)
	var ic := TextureRect.new()
	ic.texture = T.icon(id)
	ic.custom_minimum_size = Vector2(28, 28)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hb.add_child(ic)
	var l := _label("+%d  %s" % [n, B.item_name(id)], 16, rarity_color(id), 0, font_b)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	if first:
		var nw := _label("NEW", 11, Color(0.12, 0.06, 0.0), 0, font_x)
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", _sb(ACCENT, 5, ACCENT, 0, 3))
		tag.add_child(nw)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(tag)
	feed.add_child(pc)
	pc.modulate.a = 0.0
	pc.create_tween().tween_property(pc, "modulate:a", 1.0, 0.15)
	feed_items[id] = {"node": pc, "label": l, "n": n, "t": 3.0 if not first else 4.5}
	if feed.get_child_count() > 6:
		var old := feed.get_child(0)
		feed.remove_child(old)
		old.queue_free()


func set_objective(idx: int, total: int, text: String, hint: String) -> void:
	obj_title.text = "MISSION  %d / %d" % [mini(idx + 1, total), total]
	obj_text.text = text
	obj_hint.text = hint
	obj_bar.max_value = total
	var tw := obj_bar.create_tween()
	tw.tween_property(obj_bar, "value", float(mini(idx, total)), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func set_info(place: String, tod: String, day: float, depth: String, creative: bool) -> void:
	info_label.text = place
	info_icon.text = "☀" if day > 0.5 else "☾"
	info_icon.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if day > 0.5 else Color(0.7, 0.8, 1.0))
	day_bar.value = day * 100.0
	var fs := day_bar.get_theme_stylebox("fill") as StyleBoxFlat
	fs.bg_color = Color(1.0, 0.85, 0.4).lerp(Color(0.5, 0.6, 1.0), 1.0 - day)
	info_sub.text = tod + "  ·  " + depth + ("  ·  CREATIVE" if creative else "")


func on_player_hurt() -> void:
	heart_flash = 1.0


func heal_pulse() -> void:
	heal_t = 1.0


func update_hud(dt: float) -> void:
	var p = main.player
	t += dt
	toast_t -= dt
	toast_box.modulate.a = clampf(toast_t * 2.0, 0.0, 1.0)
	toast_box.scale = toast_box.scale.lerp(Vector2.ONE, 1.0 - exp(-14.0 * dt))
	toast_box.pivot_offset = toast_box.size / 2.0
	held_t -= dt
	held_label.modulate.a = clampf(held_t, 0.0, 1.0)
	hearts.visible = not p.creative
	var armor: int = p.armor_points()
	armor_row.visible = armor > 0 and not p.creative
	if armor_row.visible:
		for i in 10:
			var a: int = armor - i * 2
			armor_rects[i].texture = T.armor_full if a >= 2 else (T.armor_half if a >= 1 else T.armor_empty)
	var hr := hot_panel.get_global_rect()
	off_slot.global_position = Vector2(hr.position.x - SLOT - 12, hr.position.y + (hr.size.y - SLOT) * 0.5)
	heart_flash = maxf(0.0, heart_flash - dt * 3.0)
	heal_t = maxf(0.0, heal_t - dt * 2.0)
	var low: bool = p.health <= 6.0 and not p.creative
	for i in 10:
		var hp: float = p.health - i * 2.0
		var h := heart_rects[i]
		h.texture = T.heart_full if hp >= 2.0 else (T.heart_half if hp >= 1.0 else T.heart_empty)
		var off := 0.0
		if low:
			off = sin(t * 30.0 + i * 1.7) * 2.0
		if heal_t > 0.0:
			off -= sin(clampf(heal_t * 3.0 - i * 0.15, 0.0, 1.0) * PI) * 6.0
		h.position.y = off
		var s := 1.0 + heart_flash * 0.15
		h.scale = Vector2(s, s)
		h.modulate = Color(1, 1, 1).lerp(Color(2.2, 2.2, 2.2), heart_flash) if heart_flash > 0.0 else Color.WHITE
	if low and not p.dead:
		heartbeat_t -= dt
		if heartbeat_t <= 0.0:
			heartbeat_t = 0.75 + p.health * 0.08
			Sfx.play("heartbeat", -4.0)
	var vm: ShaderMaterial = vignette.material
	var pulse := (0.3 + 0.12 * sin(t * 7.0)) if low else 0.0
	vm.set_shader_parameter("amount", p.hurt_flash * 0.85 + pulse)
	var eye_b: int = main.world.block_at(p.eye_pos())
	water_overlay.visible = eye_b == B.WATER or eye_b == B.LAVA
	if air_label == null:
		air_label = Label.new()
		air_label.add_theme_font_size_override("font_size", 20)
		air_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		air_label.add_theme_constant_override("outline_size", 6)
		air_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		add_child(air_label)
	air_label.visible = p.air < p.MAX_AIR and not p.creative and hearts.visible
	if air_label.visible:
		var bubbles := ceili(p.air)
		air_label.text = "Air  " + "●".repeat(bubbles) + "○".repeat(int(p.MAX_AIR) - bubbles)
		var hr2: Rect2 = hearts.get_global_rect()
		air_label.global_position = Vector2(hr2.position.x, hr2.position.y - 30)
	var wm: ShaderMaterial = water_overlay.material
	wm.set_shader_parameter("tint", Color(1.0, 0.35, 0.05, 0.65) if eye_b == B.LAVA else Color(0.1, 0.3, 0.65, 0.38))
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - dt * 0.8)
	var boss = main.boss
	boss_box.visible = boss != null and is_instance_valid(boss) and not boss.dead
	if boss_box.visible:
		var v: float = boss.hp / boss.MAX_HP * 100.0
		boss_bar.value = v
		boss_trail.value = move_toward(boss_trail.value, v, dt * 25.0) if boss_trail.value > v else v
		boss_tag.visible = boss.enraged
		boss_tag.modulate.a = 0.6 + 0.4 * sin(t * 8.0)
	crosshair.visible = screen_name == ""
	crosshair.queue_redraw()
	for id in feed_items.keys():
		var e: Dictionary = feed_items[id]
		e["t"] -= dt
		if not is_instance_valid(e["node"]):
			feed_items.erase(id)
			continue
		var node: Control = e["node"]
		if e["t"] < 0.4:
			node.modulate.a = maxf(0.0, e["t"] / 0.4)
		if e["t"] <= 0.0:
			node.queue_free()
			feed_items.erase(id)
	if inv_screen.visible:
		if furnace_idx >= 0:
			refresh_furnace()
		var mp := root.get_local_mouse_position()
		cursor_icon.position = mp - Vector2(24, 24)
		cursor_label.position = mp + Vector2(2, 4)
		var vs := root.size
		var ts := tip_panel.size
		tip_panel.position = Vector2(minf(mp.x + 20, vs.x - ts.x - 8), minf(mp.y + 20, vs.y - ts.y - 8))


## Runs every frame in every state (menus, loading, play).
func update_always(dt: float) -> void:
	if banner_t > 0.0:
		banner_t -= dt
		var age := banner_len - banner_t
		var a := clampf(age * 4.0, 0.0, 1.0) * clampf(banner_t * 2.0, 0.0, 1.0)
		banner_box.modulate.a = a
		var s := 1.0 + 0.12 * (1.0 - ease(clampf(age * 3.0, 0.0, 1.0), 0.3))
		banner_box.scale = Vector2(s, s)
	else:
		banner_box.modulate.a = 0.0
		banner_title.remove_theme_color_override("font_color")
		banner_title.add_theme_color_override("font_color", Color.WHITE)
	if title_screen.visible:
		var ss := 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.006)
		splash.scale = Vector2(ss, ss)
	if loading_screen.visible:
		loading_icon.rotation += dt * 2.2
		tip_t -= dt
		if tip_t <= 0.0:
			tip_t = 4.0
			loading_tip.text = "TIP:  " + TIPS[randi() % TIPS.size()]
	if death_screen.visible and death_t > 0.0:
		death_t -= dt
		respawn_btn.disabled = death_t > 0.0
		if death_t <= 0.0:
			respawn_btn.grab_focus()
		respawn_btn.text = "Respawn" if death_t <= 0.0 else "Respawn (%d)" % ceili(death_t)
	fps_label.visible = Cfg.get_v("show_fps")
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func white_flash(a := 1.0) -> void:
	flash_rect.color = Color(1, 1, 1, a)


func fade_in(secs := 0.6) -> void:
	fade_rect.color.a = 1.0
	fade_rect.create_tween().tween_property(fade_rect, "color:a", 0.0, secs).set_trans(Tween.TRANS_SINE)


# ---------------- screens ----------------

func show_screen(name: String) -> void:
	var prev := screen_name
	screen_name = name
	for s in [title_screen, loading_screen, pause_screen, death_screen, end_screen, confirm_screen, inv_screen, help_screen, settings_screen, worlds_screen, create_screen]:
		s.visible = false
	hud.visible = name == "" or name == "inventory" or name == "confirm"
	var shown: Control = null
	match name:
		"title":
			shown = title_screen
			var worlds: Array = main.list_worlds()
			continue_btn.visible = not worlds.is_empty()
			if not worlds.is_empty():
				continue_btn.text = "Continue:  " + str(worlds[0]["name"])
			splash.text = SPLASHES[randi() % SPLASHES.size()]
		"loading":
			shown = loading_screen
		"pause":
			shown = pause_screen
			var s: Dictionary = main.player.stats
			pause_stats.text = "Played %d min  ·  %d blocks mined  ·  %d placed  ·  %d monsters" % [int(s["time"]) / 60, s["mined"], s["placed"], s["kills"]]
		"death":
			shown = death_screen
		"end":
			shown = end_screen
		"confirm":
			shown = confirm_screen
		"inventory":
			shown = inv_screen
		"help":
			shown = help_screen
		"settings":
			shown = settings_screen
		"worlds":
			shown = worlds_screen
			_refresh_worlds()
		"create":
			shown = create_screen
			create_name.text = "World %d" % (main.list_worlds().size() + 1)
			create_seed.text = ""
			_set_create_mode("survival")
	if shown:
		shown.visible = true
		if prev != name and name != "loading":
			shown.modulate.a = 0.0
			shown.create_tween().tween_property(shown, "modulate:a", 1.0, 0.18)
		_focus_first(shown)


func _focus_first(c: Control) -> void:
	for ch in c.find_children("*", "Button", true, false):
		var b := ch as Button
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
			b.call_deferred("grab_focus")
			return


func _build_title() -> void:
	title_screen = Control.new()
	title_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_screen)
	var grad := ColorRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	var gs := Shader.new()
	gs.code = """shader_type canvas_item;
void fragment() {
	float l = 1.0 - smoothstep(0.0, 0.62, UV.x);
	float v = smoothstep(0.55, 1.2, distance(UV, vec2(0.5)));
	COLOR = vec4(0.01, 0.01, 0.04, clamp(l * 0.8 + v * 0.5, 0.0, 0.92));
}"""
	var gm := ShaderMaterial.new()
	gm.shader = gs
	grad.material = gm
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(grad)
	var v := VBoxContainer.new()
	v.position = Vector2(96, 120)
	v.add_theme_constant_override("separation", 12)
	title_screen.add_child(v)
	var t1 := _label("PLANET", 92, Color(1.0, 0.66, 0.22), 18, font_x)
	var t2 := _label("CUBE", 132, Color(1, 1, 1), 20, font_x)
	t1.add_theme_constant_override("line_spacing", -30)
	v.add_child(t1)
	var t2wrap := Control.new()
	t2wrap.custom_minimum_size = Vector2(0, 120)
	v.add_child(t2wrap)
	t2.position = Vector2(-4, -44)
	t2wrap.add_child(t2)
	v.add_child(_label("Mine it.  Build it.  Escape it.", 26, Color(0.82, 0.87, 1.0), 6, font_b))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 24)
	v.add_child(sp)
	continue_btn = _button("Continue", func(): main.start_game("continue"))
	v.add_child(continue_btn)
	v.add_child(_button("Worlds", func(): show_screen("worlds")))
	v.add_child(_button("New World", func(): show_screen("create")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(_button("How to Play", func(): show_screen("help"), 165))
	row.add_child(_button("Settings", func(): open_settings("title"), 165))
	v.add_child(_button("Quit", func(): main.quit_game()))
	splash = _label("", 24, Color(1.0, 0.95, 0.35), 6, font_x)
	splash.position = Vector2(470, 300)
	splash.rotation = -0.3
	splash.pivot_offset = Vector2(60, 14)
	title_screen.add_child(splash)
	var ver := _label("Planet Cube " + VERSION + "   ·   Made with Godot", 14, Color(1, 1, 1, 0.45), 3)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.offset_left = 22
	ver.offset_top = -36
	title_screen.add_child(ver)
	var keys := _label("F2  Screenshot", 14, Color(1, 1, 1, 0.45), 3)
	keys.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	keys.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	keys.offset_right = -22
	keys.offset_top = -36
	title_screen.add_child(keys)


func _key_chip(text: String) -> PanelContainer:
	var pc := PanelContainer.new()
	var s := _sb(Color(0.2, 0.22, 0.3), 6, Color(0.05, 0.05, 0.08), 0, 6)
	s.border_width_bottom = 3
	s.content_margin_left = 10
	s.content_margin_right = 10
	pc.add_theme_stylebox_override("panel", s)
	pc.add_child(_label(text, 15, Color.WHITE, 0, font_b))
	return pc


func _build_help() -> void:
	help_screen = _screen(0.75)
	var v := _center_box(help_screen)
	var inner := _card(v, 10)
	inner.add_child(_heading("HOW TO PLAY", 36))
	var intro := _label("You crash-landed on a tiny cube-shaped planet. Walk off any edge and gravity follows you onto\nthe next face. Every face is a different biome. Build a rocket and escape!", 17, MUTED)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	inner.add_child(grid)
	var binds := [
		["W A S D", "Move"], ["Space", "Jump  (double-tap: fly in Creative)"],
		["Shift / W W", "Sprint"], ["Ctrl", "Fly down"],
		["Hold LMB", "Mine / attack"], ["RMB", "Place / use"],
		["Hold RMB", "Eat food"], ["E", "Inventory & crafting"],
		["1 - 9 / Wheel", "Hotbar"], ["Q", "Drop item"],
		["V", "Third-person camera"], ["Hold M", "Planet map"],
	]
	for b in binds:
		var chip := _key_chip(b[0])
		chip.size_flags_horizontal = Control.SIZE_SHRINK_END
		grid.add_child(chip)
		grid.add_child(_label(b[1], 17, Color.WHITE))
	var path := _label("Trees  →  wooden tools  →  stone  →  coal & torches  →  furnace & iron  →  diamonds\n→  Starcore at the core  →  build the Rocket  →  defeat the Core Sentinel  →  ESCAPE", 16, Color(1.0, 0.85, 0.6))
	path.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(path)
	var boss_tip := _label("Boss tip: dodge its magma, JUMP over its shockwave, strike the glowing eye while it is stunned.", 15, MUTED)
	boss_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(boss_tip)
	var back := _button("Back", func(): show_screen("title" if main.state == "title" else "pause"), 220)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(back)


func _build_loading() -> void:
	loading_screen = _screen(1.0)
	loading_screen.color = Color(0.03, 0.035, 0.06)
	var v := _center_box(loading_screen, 18)
	loading_icon = TextureRect.new()
	loading_icon.texture = T.icon(B.GRASS)
	loading_icon.custom_minimum_size = Vector2(72, 72)
	loading_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	loading_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	loading_icon.pivot_offset = Vector2(36, 36)
	loading_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(loading_icon)
	var t := _label("PLANET CUBE", 54, ACCENT, 8, font_x)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	loading_label = _label("Forming planet...", 20, Color(0.85, 0.88, 1.0), 0, font_b)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loading_label)
	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size = Vector2(560, 14)
	loading_bar.show_percentage = false
	v.add_child(loading_bar)
	loading_tip = _label("", 16, MUTED)
	loading_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loading_tip)


func set_loading(f: float, text: String) -> void:
	loading_bar.value = f * 100.0
	loading_label.text = text


func _build_pause() -> void:
	pause_screen = _screen(0.45, true)
	var v := _center_box(pause_screen, 12)
	var t := _heading("PAUSED", 64)
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.4))
	v.add_child(t)
	pause_stats = _label("", 16, MUTED)
	pause_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pause_stats)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	v.add_child(sp)
	for b in [
		_button("Resume", func(): main.resume(), 360),
		_button("Settings", func(): open_settings("pause"), 360),
		_button("How to Play", func(): show_screen("help"), 360),
		_button("Save & Quit to Title", func(): main.save_and_title(), 360),
		_button("Quit Game", func(): main.quit_game(), 360),
	]:
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(b)


func open_settings(from: String) -> void:
	settings_back = from
	show_screen("settings")


func _slider_row(grid: GridContainer, text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	grid.add_child(_label(text, 18, Color.WHITE, 0, font_b))
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(Cfg.get_v(key))
	sl.custom_minimum_size = Vector2(300, 32)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(sl)
	var val := _label(fmt.call(sl.value), 17, MUTED)
	val.custom_minimum_size = Vector2(70, 0)
	grid.add_child(val)
	sl.value_changed.connect(func(x):
		val.text = fmt.call(x)
		Cfg.set_v(key, x)
		if key == "sfx" or key == "master":
			Sfx.play("tick", -8.0))


func _check_row(grid: GridContainer, text: String, key: String) -> void:
	grid.add_child(_label(text, 18, Color.WHITE, 0, font_b))
	var cb := CheckBox.new()
	cb.button_pressed = bool(Cfg.get_v(key))
	cb.text = "On" if cb.button_pressed else "Off"
	cb.toggled.connect(func(on):
		cb.text = "On" if on else "Off"
		Sfx.play("click", -8.0)
		Cfg.set_v(key, on))
	grid.add_child(cb)
	grid.add_child(Control.new())


# ---------------- worlds ----------------

func _line_edit(placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.custom_minimum_size = Vector2(420, 46)
	le.add_theme_font_size_override("font_size", 19)
	le.add_theme_stylebox_override("normal", _sb(Color(0, 0, 0, 0.45), 8, Color(1, 1, 1, 0.15), 1, 10))
	le.add_theme_stylebox_override("focus", _sb(Color(0, 0, 0, 0.55), 8, ACCENT, 2, 10))
	le.add_theme_color_override("caret_color", ACCENT)
	return le


func _ago(unix: float) -> String:
	var s := Time.get_unix_time_from_system() - unix
	if unix <= 0:
		return "never"
	if s < 90:
		return "just now"
	if s < 3600:
		return "%d min ago" % int(s / 60)
	if s < 86400:
		return "%d h ago" % int(s / 3600)
	return "%d days ago" % int(s / 86400)


func _build_worlds() -> void:
	worlds_screen = _screen(0.6)
	var v := _center_box(worlds_screen)
	var inner := _card(v, 12)
	inner.add_child(_heading("WORLDS", 36))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(680, 400)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(sc)
	world_list = VBoxContainer.new()
	world_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_list.add_theme_constant_override("separation", 8)
	sc.add_child(world_list)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	inner.add_child(row)
	row.add_child(_button("New World", func(): show_screen("create"), 240))
	row.add_child(_button("Back", func(): show_screen("title"), 200))


func _refresh_worlds() -> void:
	for ch in world_list.get_children():
		ch.queue_free()
	var worlds: Array = main.list_worlds()
	if worlds.is_empty():
		var l := _label("No worlds yet - make your first planet!", 18, MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		world_list.add_child(l)
		return
	for w in worlds:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _sb(Color(0.15, 0.17, 0.23, 0.95), 10, Color(1, 1, 1, 0.08), 1, 12))
		world_list.add_child(pc)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		pc.add_child(hb)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		hb.add_child(info)
		info.add_child(_label(str(w["name"]), 21, Color.WHITE, 0, font_b))
		var mode := "Creative" if w["mode"] == "creative" else "Survival"
		var sub := "%s  ·  %d min played  ·  last played %s" % [mode, int(w["time"]) / 60, _ago(w["played"])]
		if w.get("escaped", false):
			sub += "  ·  ✦ Escaped"
		info.add_child(_label(sub, 14, MUTED))
		var path: String = w["path"]
		var play := _button("Play", func(): main.play_world(path), 120)
		play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(play)
		var del := _button("Delete", func(): pass, 120)
		del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Two-step delete: the first click arms it, the second removes the world.
		del.pressed.connect(func():
			if del.text == "Delete":
				del.text = "Sure?"
				del.add_theme_color_override("font_color", BAD)
			else:
				main.delete_world(path)
				_refresh_worlds())
		hb.add_child(del)


func _set_create_mode(mode: String) -> void:
	create_mode = mode
	for m in create_mode_btns:
		var b: Button = create_mode_btns[m]
		b.add_theme_stylebox_override("normal", _sb(ACCENT if m == mode else Color(0.17, 0.19, 0.26, 0.96), 10, Color(0, 0, 0, 0), 0, 12))
		b.add_theme_color_override("font_color", Color(0.12, 0.06, 0.0) if m == mode else Color(0.95, 0.96, 1.0))
	create_mode_desc.text = "Gather, craft, survive the night and escape the planet." if mode == "survival" else "Unlimited blocks, flying, no damage. Build anything."


func _build_create() -> void:
	create_screen = _screen(0.6)
	var v := _center_box(create_screen)
	var inner := _card(v, 10)
	inner.add_child(_heading("NEW WORLD", 36))
	inner.add_child(_label("World name", 16, MUTED, 0, font_b))
	create_name = _line_edit("My Planet")
	inner.add_child(create_name)
	inner.add_child(_label("Game mode", 16, MUTED, 0, font_b))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	inner.add_child(modes)
	for m in ["survival", "creative"]:
		var b := _button(m.capitalize(), func(): _set_create_mode(m), 205)
		modes.add_child(b)
		create_mode_btns[m] = b
	create_mode_desc = _label("", 15, MUTED)
	inner.add_child(create_mode_desc)
	inner.add_child(_label("Seed (optional)", 16, MUTED, 0, font_b))
	create_seed = _line_edit("Leave blank for a random planet")
	inner.add_child(create_seed)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 6)
	inner.add_child(sp)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	inner.add_child(row)
	row.add_child(_button("Create World", func(): main.create_world(create_name.text, create_mode, create_seed.text), 240))
	row.add_child(_button("Back", func(): show_screen("title"), 200))


func _build_settings() -> void:
	settings_screen = _screen(0.45, true)
	var v := _center_box(settings_screen)
	var inner := _card(v, 14)
	inner.add_child(_heading("SETTINGS", 36))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 10)
	inner.add_child(grid)
	var pct := func(x): return "%d%%" % roundi(x * 100.0)
	_slider_row(grid, "Master volume", "master", 0.0, 1.0, 0.05, pct)
	_slider_row(grid, "Music", "music", 0.0, 1.0, 0.05, pct)
	_slider_row(grid, "Sound effects", "sfx", 0.0, 1.0, 0.05, pct)
	_slider_row(grid, "Mouse sensitivity", "sens", 0.25, 3.0, 0.05, func(x): return "%.2fx" % x)
	_slider_row(grid, "Field of view", "fov", 60.0, 100.0, 1.0, func(x): return "%d°" % roundi(x))
	_check_row(grid, "Invert mouse Y", "invert_y")
	_check_row(grid, "View bobbing", "view_bob")
	_check_row(grid, "Fullscreen", "fullscreen")
	_check_row(grid, "Show FPS", "show_fps")
	var back := _button("Done", func(): show_screen(settings_back), 220)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	inner.add_child(back)


func _build_death() -> void:
	death_screen = _screen(0.0)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 1.5).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	float v = smoothstep(0.2, 0.9, distance(UV, vec2(0.5)));
	COLOR = vec4(mix(vec3(g * 0.9, g * 0.25, g * 0.22), vec3(0.25, 0.0, 0.0), 0.35 + v * 0.4), 1.0);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	death_screen.material = mat
	var v := _center_box(death_screen, 14)
	var t := _heading("YOU DIED", 84)
	t.add_theme_color_override("font_color", Color(1, 0.88, 0.86))
	t.add_theme_constant_override("outline_size", 12)
	t.add_theme_color_override("font_outline_color", Color(0.3, 0, 0, 0.6))
	v.add_child(t)
	death_label = _label("", 24, Color(1, 0.9, 0.9), 5, font_b)
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(death_label)
	death_stats = _label("", 16, Color(1, 0.85, 0.85, 0.75))
	death_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(death_stats)
	var keep := _label("You keep your inventory.", 16, Color(1, 1, 1, 0.6))
	keep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(keep)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 12)
	v.add_child(sp)
	respawn_btn = _button("Respawn", func(): main.respawn(), 320)
	respawn_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(respawn_btn)
	var tb := _button("Save & Quit to Title", func(): main.save_and_title(), 320)
	tb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(tb)


func show_death(stats: Dictionary) -> void:
	death_stats.text = "Deaths: %d   ·   Blocks mined: %d   ·   Monsters defeated: %d" % [stats["deaths"], stats["mined"], stats["kills"]]
	death_t = 1.2
	respawn_btn.disabled = true
	show_screen("death")


func _build_end() -> void:
	end_screen = _screen(0.35)
	var v := _center_box(end_screen, 18)
	var t := _heading("YOU ESCAPED PLANET CUBE!", 60)
	t.add_theme_color_override("font_color", Color(1.0, 0.8, 0.32))
	t.add_theme_constant_override("outline_size", 12)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	v.add_child(t)
	end_stats = _label("", 22, Color.WHITE, 5, font_b)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_stats)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	hb.add_child(_button("Keep Exploring", func(): main.continue_after_end()))
	hb.add_child(_button("Title Screen", func(): main.save_and_title()))
	v.add_child(hb)


func _build_confirm() -> void:
	confirm_screen = _screen(0.5)
	var v := _center_box(confirm_screen, 18)
	var inner := _card(v, 18)
	confirm_label = _label("", 23, Color.WHITE, 0, font_b)
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(confirm_label)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	hb.add_child(_button("YES", func():
		main.close_confirm()
		confirm_cb.call(), 220))
	hb.add_child(_button("Not yet", func(): main.close_confirm(), 220))
	inner.add_child(hb)


func ask(text: String, cb: Callable) -> void:
	confirm_label.text = text
	confirm_cb = cb


# ---------------- inventory & crafting ----------------

func _build_inventory() -> void:
	inv_screen = _screen(0.5)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_screen.add_child(c)
	inv_panel = PanelContainer.new()
	inv_panel.resized.connect(func(): inv_panel.pivot_offset = inv_panel.size / 2.0)
	c.add_child(inv_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	inv_panel.add_child(hb)
	var gear := VBoxContainer.new()
	gear.add_theme_constant_override("separation", 5)
	hb.add_child(gear)
	gear.add_child(_label("GEAR", 13, MUTED, 0, font_x))
	inv_slots.resize(41)
	for k in 4:
		gear.add_child(_inv_slot(36 + k, ""))
	var gsp := Control.new()
	gsp.custom_minimum_size = Vector2(0, 10)
	gear.add_child(gsp)
	gear.add_child(_label("OFFHAND", 13, MUTED, 0, font_x))
	gear.add_child(_inv_slot(40, "F"))
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)
	chest_box = VBoxContainer.new()
	chest_box.add_theme_constant_override("separation", 8)
	left.add_child(chest_box)
	chest_box.add_child(_label("CHEST", 24, ACCENT, 0, font_x))
	var cgrid := GridContainer.new()
	cgrid.columns = 9
	cgrid.add_theme_constant_override("h_separation", 5)
	cgrid.add_theme_constant_override("v_separation", 5)
	chest_box.add_child(cgrid)
	chest_slots.resize(27)
	for k in 27:
		cgrid.add_child(_inv_slot(CHEST0 + k, ""))
	furnace_box = VBoxContainer.new()
	furnace_box.add_theme_constant_override("separation", 8)
	left.add_child(furnace_box)
	furnace_box.add_child(_label("FURNACE", 24, ACCENT, 0, font_x))
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 18)
	frow.alignment = BoxContainer.ALIGNMENT_CENTER
	furnace_box.add_child(frow)
	var fcol := VBoxContainer.new()
	fcol.add_theme_constant_override("separation", 4)
	frow.add_child(fcol)
	furn_slots.resize(3)
	fcol.add_child(_inv_slot(FURN_IN, ""))
	furn_flame = Control.new()
	furn_flame.custom_minimum_size = Vector2(SLOT, 42)
	furn_flame.draw.connect(_draw_flame)
	fcol.add_child(furn_flame)
	fcol.add_child(_inv_slot(FURN_FUEL, ""))
	furn_arrow = Control.new()
	furn_arrow.custom_minimum_size = Vector2(72, 48)
	furn_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	furn_arrow.draw.connect(_draw_arrow)
	frow.add_child(furn_arrow)
	var fout := _inv_slot(FURN_OUT, "")
	fout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frow.add_child(fout)
	left.add_child(_label("INVENTORY", 24, ACCENT, 0, font_x))
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	left.add_child(grid)
	for i in range(9, 36):
		grid.add_child(_inv_slot(i, ""))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	left.add_child(sp)
	left.add_child(_label("HOTBAR", 13, MUTED, 0, font_x))
	var hgrid := GridContainer.new()
	hgrid.columns = 9
	hgrid.add_theme_constant_override("h_separation", 5)
	left.add_child(hgrid)
	for i in 9:
		hgrid.add_child(_inv_slot(i, str(i + 1)))
	var help := HBoxContainer.new()
	help.add_theme_constant_override("separation", 6)
	left.add_child(help)
	for pair in [["LMB", "pick up / place"], ["RMB", "split / one"], ["Shift", "quick move"], ["1-9", "to hotbar"]]:
		help.add_child(_key_chip(pair[0]))
		help.add_child(_label(pair[1] + "  ", 13, MUTED))
	inv_right = VBoxContainer.new()
	var right := inv_right
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(500, 540)
	hb.add_child(right)
	var title_row := HBoxContainer.new()
	right.add_child(title_row)
	craft_title = _label("CRAFTING", 24, ACCENT, 0, font_x)
	title_row.add_child(craft_title)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(fill)
	craftable_only = CheckBox.new()
	craftable_only.text = "Only craftable"
	craftable_only.focus_mode = Control.FOCUS_NONE
	craftable_only.toggled.connect(func(_on):
		Sfx.play("click", -8.0)
		refresh_crafting())
	title_row.add_child(craftable_only)
	craft_status = HBoxContainer.new()
	craft_status.add_theme_constant_override("separation", 8)
	right.add_child(craft_status)
	craft_scroll = ScrollContainer.new()
	craft_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	craft_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(craft_scroll)
	craft_list = VBoxContainer.new()
	craft_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	craft_list.add_theme_constant_override("separation", 6)
	craft_scroll.add_child(craft_list)
	creative_scroll = ScrollContainer.new()
	creative_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(creative_scroll)
	creative_grid = GridContainer.new()
	creative_grid.columns = 7
	creative_grid.add_theme_constant_override("h_separation", 5)
	creative_grid.add_theme_constant_override("v_separation", 5)
	creative_scroll.add_child(creative_grid)
	var all_ids: Array[int] = []
	all_ids.append_array(B.block_list)
	all_ids.append(B.WATER)
	all_ids.append(B.LAVA)
	all_ids.append_array(B.item_list)
	for id in all_ids:
		var p := _slot_panel()
		_set_slot(p, {"id": id, "n": 1})
		p.gui_input.connect(_palette_input.bind(id))
		p.mouse_entered.connect(func():
			_show_tip(id)
			_set_slot_selected(p, false, true))
		p.mouse_exited.connect(func():
			_hide_tip()
			_set_slot_selected(p, false, false))
		creative_grid.add_child(p)
	tip_panel = PanelContainer.new()
	tip_panel.add_theme_stylebox_override("panel", _sb(Color(0.04, 0.05, 0.08, 0.97), 8, Color(1, 1, 1, 0.18), 1, 10))
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.visible = false
	inv_screen.add_child(tip_panel)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tip_panel.add_child(tv)
	tip_name = _label("", 18, Color.WHITE, 0, font_b)
	tv.add_child(tip_name)
	tip_desc = _label("", 14, MUTED)
	tv.add_child(tip_desc)
	cursor_icon = TextureRect.new()
	cursor_icon.custom_minimum_size = Vector2(48, 48)
	cursor_icon.size = Vector2(48, 48)
	cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_screen.add_child(cursor_icon)
	cursor_label = _label("", 17, Color.WHITE, 4, font_b)
	inv_screen.add_child(cursor_label)


func _inv_slot(i: int, key: String) -> Panel:
	var p := _slot_panel(false, key)
	p.gui_input.connect(_slot_input.bind(i))
	p.mouse_entered.connect(func():
		hover_slot = i
		Sfx.play("hover", -20.0, 1.2)
		_slot_hover(i)
		refresh_inventory())
	p.mouse_exited.connect(func():
		if hover_slot == i:
			hover_slot = -1
		_hide_tip()
		refresh_inventory())
	if i >= FURN_IN:
		furn_slots[i - FURN_IN] = p
	elif i >= CHEST0:
		chest_slots[i - CHEST0] = p
	else:
		inv_slots[i] = p
	return p


func _item_desc(id: int) -> String:
	var info: Dictionary = B.info.get(id, {})
	if info.is_empty():
		return ""
	var lines: Array[String] = []
	if info["block"]:
		if info.get("tier", 0) > 0:
			lines.append("Needs a %s pickaxe" % B.TIER_NAMES[info["tier"]])
		lines.append("Block  ·  Right-click to place")
	else:
		var tool := B.tool_of(id)
		if not tool.is_empty():
			if tool["tool"] == "sword":
				lines.append("%.1f attack damage" % tool["dmg"])
			else:
				lines.append("%s tier  ·  %.0fx mining speed" % [B.TIER_NAMES[tool["tier"]], tool["speed"]])
				lines.append("%.1f attack damage" % tool["dmg"])
		if info["food"] > 0:
			lines.append("Restores %d health  ·  Hold Right Mouse to eat" % info["food"])
		if info["armor"] > 0:
			lines.append("+%d armor  ·  Right-click to wear" % info["armor"])
		elif info["desc"] != "":
			lines.append(info["desc"])
	return "\n".join(lines)


func _show_tip(id: int) -> void:
	tip_name.text = B.item_name(id)
	tip_name.add_theme_color_override("font_color", rarity_color(id))
	tip_desc.text = _item_desc(id)
	tip_desc.visible = tip_desc.text != ""
	tip_panel.visible = true
	tip_panel.reset_size()


func _hide_tip() -> void:
	tip_panel.visible = false


func open_inventory() -> void:
	var cr: bool = main.player.creative
	var chest := chest_idx >= 0
	chest_box.visible = chest
	furnace_box.visible = furnace_idx >= 0
	inv_right.visible = not chest and furnace_idx < 0
	craft_scroll.visible = not cr
	craftable_only.visible = not cr
	craft_status.visible = not cr
	creative_scroll.visible = cr
	craft_title.text = "ALL BLOCKS & ITEMS" if cr else "CRAFTING"
	hover_slot = -1
	_hide_tip()
	refresh_inventory()
	refresh_crafting()
	inv_panel.scale = Vector2(0.96, 0.96)
	inv_panel.create_tween().tween_property(inv_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close_inventory() -> void:
	if cursor_stack:
		main.player.add_item(cursor_stack["id"], cursor_stack["n"], false)
		cursor_stack = null
	chest_idx = -1
	furnace_idx = -1
	_hide_tip()
	_update_cursor()


## Contents of UI slot `i`: player inventory (0..40), the open chest (CHEST0..CHEST0+26) or the open
## furnace (FURN_IN, FURN_FUEL, FURN_OUT).
func _get_slot(i: int):
	if i >= FURN_IN:
		return main.world.furnace_at(furnace_idx)[FURN_KEYS[i - FURN_IN]]
	if i >= CHEST0:
		return main.world.chest_inv(chest_idx)[i - CHEST0]
	return main.player.inv[i]


func _put_slot(i: int, s) -> void:
	if i >= FURN_IN:
		main.world.furnace_at(furnace_idx)[FURN_KEYS[i - FURN_IN]] = s
	elif i >= CHEST0:
		main.world.chest_inv(chest_idx)[i - CHEST0] = s
	else:
		main.player.inv[i] = s


func refresh_inventory() -> void:
	var p = main.player
	for i in p.INV_SIZE:
		var ghost := 0
		if i >= p.ARMOR0 and i < p.OFFHAND:
			ghost = B.IRON_HELMET + i - p.ARMOR0
		elif i == p.OFFHAND:
			ghost = B.SHIELD
		_set_slot(inv_slots[i], p.inv[i], ghost)
		_set_slot_selected(inv_slots[i], i == p.sel, i == hover_slot)
	if chest_idx >= 0:
		for k in 27:
			_set_slot(chest_slots[k], _get_slot(CHEST0 + k))
			_set_slot_selected(chest_slots[k], false, CHEST0 + k == hover_slot)
	if furnace_idx >= 0:
		refresh_furnace()
	_update_cursor()


## Furnace slots, flame and arrow; also refreshed every frame while open since it keeps smelting.
func refresh_furnace() -> void:
	for k in 3:
		_set_slot(furn_slots[k], _get_slot(FURN_IN + k))
		_set_slot_selected(furn_slots[k], false, FURN_IN + k == hover_slot)
	furn_flame.queue_redraw()
	furn_arrow.queue_redraw()


func _update_cursor() -> void:
	if cursor_stack:
		cursor_icon.texture = T.icon(cursor_stack["id"])
		cursor_label.text = str(cursor_stack["n"]) if cursor_stack["n"] > 1 else ""
	else:
		cursor_icon.texture = null
		cursor_label.text = ""


func _slot_hover(i: int) -> void:
	var s = _get_slot(i)
	if s and cursor_stack == null:
		_show_tip(s["id"])
	else:
		_hide_tip()


func _input(event: InputEvent) -> void:
	if not inv_screen.visible or hover_slot < 0:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var k: int = event.keycode - KEY_1
		var p = main.player
		if k != hover_slot:
			var tmp = p.inv[k]
			if tmp and not _accepts(hover_slot, tmp["id"]):
				Sfx.play("deny", -10.0)
			else:
				p.inv[k] = _get_slot(hover_slot)
				_put_slot(hover_slot, tmp)
				if hover_slot == FURN_OUT and p.inv[k]:
					p.note_obtained(p.inv[k]["id"])
				Sfx.play("click", -10.0, 1.2)
				main.on_inventory_changed()
				_slot_hover(hover_slot)
		get_viewport().set_input_as_handled()


## Where shift-click sends the stack in slot `i`: chest/furnace <-> inventory while one is open
## (smeltables to the furnace input, fuels below), armor straight onto its empty slot, gear back to
## the inventory, otherwise hotbar <-> main grid.
func _shift_dest(i: int, id: int) -> Array:
	var p = main.player
	if i >= CHEST0:
		return range(0, p.SLOTS)
	if chest_idx >= 0 and i < p.SLOTS:
		return range(CHEST0, CHEST0 + 27)
	if furnace_idx >= 0 and i < p.SLOTS:
		if B.smelts.has(id):
			return [FURN_IN]
		if B.fuels.has(id):
			return [FURN_FUEL]
	var k := B.armor_slot(id)
	if i < p.SLOTS and k >= 0 and p.inv[p.ARMOR0 + k] == null:
		return [p.ARMOR0 + k]
	if i >= p.SLOTS:
		return range(9, p.SLOTS) + range(0, 9)
	return range(9, p.SLOTS) if i < 9 else range(0, 9)


## Whether `id` may be put in UI slot `i`: armor slots take their piece, the furnace fuel slot takes
## fuel and its output takes nothing.
func _accepts(i: int, id: int) -> bool:
	if i == FURN_FUEL:
		return B.fuels.has(id)
	if i == FURN_OUT:
		return false
	return main.player.slot_accepts(i, id)


func _slot_input(event: InputEvent, i: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var p = main.player
	var s = _get_slot(i)
	# Clicking the furnace output with a matching stack in hand scoops the output onto it.
	if i == FURN_OUT and cursor_stack and s and event.button_index == MOUSE_BUTTON_LEFT and not event.shift_pressed:
		if s["id"] != cursor_stack["id"] or cursor_stack["n"] + s["n"] > B.stack_max(s["id"]):
			Sfx.play("deny", -10.0)
			return
		cursor_stack["n"] += s["n"]
		_put_slot(i, null)
		_slot_changed(i, s)
		return
	if cursor_stack and not _accepts(i, cursor_stack["id"]) and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		Sfx.play("deny", -10.0)
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed and s:
		var dest_range := _shift_dest(i, s["id"])
		var moved := false
		for j in dest_range:
			var d = _get_slot(j)
			if d and d["id"] == s["id"] and d["n"] < B.stack_max(s["id"]):
				var k := mini(B.stack_max(s["id"]) - d["n"], s["n"])
				d["n"] += k
				s["n"] -= k
				moved = true
				if s["n"] <= 0:
					_put_slot(i, null)
					break
		if _get_slot(i) != null:
			for j in dest_range:
				if _get_slot(j) == null:
					_put_slot(j, s)
					_put_slot(i, null)
					moved = true
					break
		if not moved:
			Sfx.play("deny", -10.0)
			return
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if cursor_stack == null:
			_put_slot(i, null)
			cursor_stack = s
		elif s == null:
			_put_slot(i, cursor_stack)
			cursor_stack = null
		elif s["id"] == cursor_stack["id"]:
			var mx := B.stack_max(s["id"])
			var k := mini(mx - s["n"], cursor_stack["n"])
			s["n"] += k
			cursor_stack["n"] -= k
			if cursor_stack["n"] <= 0:
				cursor_stack = null
		else:
			_put_slot(i, cursor_stack)
			cursor_stack = s
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if cursor_stack == null and s:
			var half := ceili(s["n"] / 2.0)
			cursor_stack = {"id": s["id"], "n": half}
			s["n"] -= half
			if s["n"] <= 0:
				_put_slot(i, null)
		elif cursor_stack:
			if s == null:
				_put_slot(i, {"id": cursor_stack["id"], "n": 1})
				cursor_stack["n"] -= 1
			elif s["id"] == cursor_stack["id"] and s["n"] < B.stack_max(s["id"]):
				s["n"] += 1
				cursor_stack["n"] -= 1
			if cursor_stack["n"] <= 0:
				cursor_stack = null
	else:
		return
	_slot_changed(i, s)


## After a click changed slot `i` (which held `s`): taking a furnace's output counts as obtaining it.
func _slot_changed(i: int, s) -> void:
	if i == FURN_OUT and s:
		main.player.note_obtained(s["id"])
	Sfx.play("click", -10.0, randf_range(0.95, 1.1))
	main.on_inventory_changed()
	_slot_hover(i)


## Remaining burn of the open furnace: the flame lights up from the bottom.
func _draw_flame() -> void:
	if furnace_idx < 0:
		return
	var fz: Dictionary = main.world.furnace_at(furnace_idx)
	var frac: float = fz["burn"] / fz["burn_max"] if fz["burn_max"] > 0.0 else 0.0
	var px := 3.0
	var o := (furn_flame.size - Vector2(11, 12) * px) * 0.5
	for y in 12:
		for x in 11:
			if FLAME[y][x] != "#":
				continue
			var c := Color(0.22, 0.23, 0.28)
			if frac > 0.0 and 11 - y < frac * 12.0:
				c = Color(1.0, 0.9, 0.35).lerp(Color(1.0, 0.35, 0.08), y / 11.0)
			furn_flame.draw_rect(Rect2(o + Vector2(x, y) * px, Vector2(px, px)), c)


## Smelting progress of the open furnace: the arrow fills left to right.
func _draw_arrow() -> void:
	if furnace_idx < 0:
		return
	var frac: float = main.world.furnace_at(furnace_idx)["prog"] / B.SMELT_TIME
	var px := 4.0
	var o := (furn_arrow.size - Vector2(16, 11) * px) * 0.5
	for r in 11:
		for x in 16:
			if not ((x < 10 and r >= 4 and r <= 6) or (x >= 10 and x - 10 <= 5 - absi(r - 5))):
				continue
			var c := Color(1, 1, 1, 0.95) if x < frac * 16.0 else Color(0.22, 0.23, 0.28)
			furn_arrow.draw_rect(Rect2(o + Vector2(x, r) * px, Vector2(px, px)), c)


func _palette_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		cursor_stack = {"id": id, "n": B.stack_max(id)}
		Sfx.play("click", -10.0)
		_update_cursor()


func _chip(text: String, ok: bool) -> PanelContainer:
	var pc := PanelContainer.new()
	var col := GOOD if ok else Color(1, 1, 1, 0.35)
	var s := _sb(Color(col.r, col.g, col.b, 0.12), 12, Color(col.r, col.g, col.b, 0.5), 1, 4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	pc.add_theme_stylebox_override("panel", s)
	pc.add_child(_label(("✓ " if ok else "✗ ") + text, 14, col if ok else Color(1, 1, 1, 0.55), 0, font_b))
	return pc


func refresh_crafting() -> void:
	if main.player.creative:
		return
	for ch in craft_list.get_children():
		ch.queue_free()
	for ch in craft_status.get_children():
		ch.queue_free()
	var st: Dictionary = main.station_status()
	craft_status.add_child(_chip("Crafting Table", st["table"]))
	var only: bool = craftable_only.button_pressed
	var ready: Array = []
	var locked: Array = []
	for r in B.recipes:
		if r["st"] == "furnace":
			continue
		var ok: bool = main.can_craft(r, st)
		if ok:
			ready.append(r)
		elif not only:
			locked.append(r)
	for r in ready:
		craft_list.add_child(_recipe_row(r, true))
	for r in locked:
		craft_list.add_child(_recipe_row(r, false))
	if ready.is_empty() and only:
		var l := _label("Nothing craftable yet - gather more materials.", 16, MUTED)
		craft_list.add_child(l)


func _recipe_row(r: Dictionary, ok: bool) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(470, 64)
	btn.focus_mode = Control.FOCUS_NONE
	var rs := _sb(Color(0.15, 0.17, 0.23, 0.95) if ok else Color(0.1, 0.11, 0.14, 0.7), 10, Color(1, 1, 1, 0.08), 1, 0)
	var rh := rs.duplicate()
	rh.bg_color = Color(0.22, 0.24, 0.31, 1.0) if ok else rs.bg_color
	rh.border_color = ACCENT if ok else Color(1, 1, 1, 0.12)
	var rp := rh.duplicate()
	rp.bg_color = Color(0.3, 0.22, 0.12)
	btn.add_theme_stylebox_override("normal", rs)
	btn.add_theme_stylebox_override("hover", rh)
	btn.add_theme_stylebox_override("pressed", rp)
	btn.add_theme_stylebox_override("hover_pressed", rp)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 10
	hb.offset_right = -10
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hb)
	var ibox := PanelContainer.new()
	ibox.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0.3), 8, Color(1, 1, 1, 0.06), 1, 4))
	ibox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ibox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ibox)
	var icon := TextureRect.new()
	icon.texture = T.icon(r["out"])
	icon.custom_minimum_size = Vector2(42, 42)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not ok:
		icon.modulate = Color(0.6, 0.6, 0.65, 0.8)
	ibox.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(v)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_row)
	var nm := B.item_name(r["out"]) + ("  ×%d" % r["n"] if r["n"] > 1 else "")
	var ncol := rarity_color(r["out"]) if ok else Color(1, 1, 1, 0.5)
	name_row.add_child(_label(nm, 18, ncol, 0, font_b))
	if r["st"] != "":
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", _sb(Color(1, 1, 1, 0.08), 5, Color(0, 0, 0, 0), 0, 2))
		tag.get_theme_stylebox("panel").content_margin_left = 6
		tag.get_theme_stylebox("panel").content_margin_right = 6
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(_label("TABLE", 11, MUTED, 0, font_x))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(tag)
	var ing := HBoxContainer.new()
	ing.add_theme_constant_override("separation", 4)
	ing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ing)
	var p = main.player
	for id in r["in"]:
		var need: int = r["in"][id]
		var have: int = p.count(id)
		var ic := TextureRect.new()
		ic.texture = T.icon(B.group_members(id)[0])
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ing.add_child(ic)
		var col := GOOD if have >= need else BAD
		ing.add_child(_label("%d/%d %s   " % [mini(have, need), need, B.item_name(id)], 13, col))
	if ok:
		var go := _label("CRAFT ›", 13, ACCENT, 0, font_x)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(go)
	btn.mouse_entered.connect(func(): Sfx.play("hover", -20.0))
	btn.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var times := 16 if e.shift_pressed else 1
			var made := 0
			for k in times:
				if not main.craft(r):
					break
				made += 1
				if not main.can_craft(r):
					break
			if made > 0:
				refresh_crafting()
			btn.accept_event())
	return btn

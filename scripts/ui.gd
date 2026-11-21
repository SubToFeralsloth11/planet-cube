extends CanvasLayer
## HUD, menus, inventory and crafting screens (all built in code).

const SLOT := 62
const ACCENT := Color(1.0, 0.62, 0.2)

var main
var root: Control
var hud: Control
var hotbar: HBoxContainer
var hot_slots: Array[Control] = []
var hearts: HBoxContainer
var heart_rects: Array[TextureRect] = []
var obj_title: Label
var obj_text: Label
var obj_hint: Label
var toast_label: Label
var toast_t := 0.0
var held_label: Label
var held_t := 0.0
var info_label: Label
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var vignette: ColorRect
var water_overlay: ColorRect
var crosshair: Control
var flash_rect: ColorRect

var title_screen: Control
var continue_btn: Button
var loading_screen: Control
var loading_bar: ProgressBar
var loading_label: Label
var pause_screen: Control
var music_btn: Button
var death_screen: Control
var death_label: Label
var end_screen: Control
var end_stats: Label
var confirm_screen: Control
var confirm_label: Label
var confirm_cb: Callable
var help_screen: Control

var inv_screen: Control
var inv_slots: Array[Control] = []
var craft_list: VBoxContainer
var craft_status: Label
var craftable_only: CheckBox
var creative_grid: GridContainer
var craft_scroll: ScrollContainer
var creative_scroll: ScrollContainer
var tooltip: Label
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
	_build_death()
	_build_end()
	_build_confirm()
	_build_help()
	_build_inventory()
	show_screen("")


# ---------------- theme helpers ----------------

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.07, 0.1, 0.88)
	panel.border_color = Color(1, 1, 1, 0.12)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(16)
	panel.shadow_color = Color(0, 0, 0, 0.4)
	panel.shadow_size = 10
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("panel", "Panel", panel)
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(0.16, 0.18, 0.24, 0.95)
	bn.border_color = Color(1, 1, 1, 0.15)
	bn.set_border_width_all(2)
	bn.set_corner_radius_all(8)
	bn.set_content_margin_all(10)
	var bh := bn.duplicate()
	bh.bg_color = Color(0.95, 0.55, 0.18, 0.95)
	bh.border_color = Color(1, 0.85, 0.6, 0.8)
	var bp := bh.duplicate()
	bp.bg_color = Color(0.8, 0.42, 0.1, 1.0)
	th.set_stylebox("normal", "Button", bn)
	th.set_stylebox("hover", "Button", bh)
	th.set_stylebox("pressed", "Button", bp)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_stylebox("disabled", "Button", bn)
	th.set_font_size("font_size", "Button", 22)
	th.set_color("font_hover_color", "Button", Color(0.1, 0.06, 0.02))
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.3))
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0, 0, 0, 0.6)
	pb_bg.set_corner_radius_all(6)
	var pb_fg := StyleBoxFlat.new()
	pb_fg.bg_color = ACCENT
	pb_fg.set_corner_radius_all(6)
	th.set_stylebox("background", "ProgressBar", pb_bg)
	th.set_stylebox("fill", "ProgressBar", pb_fg)
	th.set_constant("outline_size", "Label", 0)
	return th


func _label(text: String, size := 18, col := Color.WHITE, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable, w := 340) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 54)
	b.pressed.connect(func():
		Sfx.play("click", -6.0)
		cb.call())
	return b


func _screen(dim := 0.55) -> Control:
	var s := ColorRect.new()
	s.color = Color(0.02, 0.02, 0.05, dim)
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_STOP
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


func _slot_panel(selected := false) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT, SLOT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.15, 0.82)
	sb.border_color = ACCENT if selected else Color(1, 1, 1, 0.18)
	sb.set_border_width_all(4 if selected else 2)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
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
	var cnt := _label("", 17, Color.WHITE, 5)
	cnt.name = "Count"
	cnt.set_anchors_preset(Control.PRESET_FULL_RECT)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	cnt.offset_right = -5
	cnt.offset_bottom = -1
	p.add_child(cnt)
	return p


func _set_slot(p: Control, s) -> void:
	var icon: TextureRect = p.get_node("Icon")
	var cnt: Label = p.get_node("Count")
	if s:
		icon.texture = T.icon(s["id"])
		cnt.text = str(s["n"]) if s["n"] > 1 else ""
	else:
		icon.texture = null
		cnt.text = ""


func _set_slot_selected(p: Panel, selected: bool) -> void:
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.border_color = ACCENT if selected else Color(1, 1, 1, 0.18)
	sb.set_border_width_all(4 if selected else 2)


# ---------------- HUD ----------------

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	water_overlay = ColorRect.new()
	water_overlay.color = Color(0.1, 0.25, 0.6, 0.35)
	water_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	water_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	water_overlay.visible = false
	hud.add_child(water_overlay)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = "shader_type canvas_item;\nuniform float amount = 0.0;\nuniform vec3 col = vec3(0.8, 0.0, 0.0);\nvoid fragment(){ float d = distance(UV, vec2(0.5)); COLOR = vec4(col, smoothstep(0.35, 0.85, d) * amount); }"
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
	hud.add_child(crosshair)
	for r in [Rect2(-11, -1.5, 22, 3), Rect2(-1.5, -11, 3, 22)]:
		var c := ColorRect.new()
		c.color = Color(1, 1, 1, 0.85)
		c.position = r.position
		c.size = r.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair.add_child(c)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -16
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bottom)
	toast_label = _label("", 24, Color(1, 0.95, 0.8), 7)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(toast_label)
	held_label = _label("", 20, Color.WHITE, 6)
	held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(held_label)
	hearts = HBoxContainer.new()
	hearts.add_theme_constant_override("separation", 2)
	hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(hearts)
	for i in 10:
		var h := TextureRect.new()
		h.texture = T.heart_full
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hearts.add_child(h)
		heart_rects.append(h)
	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 4)
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(hotbar)
	for i in 9:
		var p := _slot_panel(i == 0)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hotbar.add_child(p)
		hot_slots.append(p)
	var obj := PanelContainer.new()
	obj.position = Vector2(20, 20)
	obj.custom_minimum_size = Vector2(380, 0)
	obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(obj)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 4)
	obj.add_child(ov)
	obj_title = _label("MISSION", 15, ACCENT)
	ov.add_child(obj_title)
	obj_text = _label("", 22, Color.WHITE)
	obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_text.custom_minimum_size = Vector2(350, 0)
	ov.add_child(obj_text)
	obj_hint = _label("", 15, Color(0.75, 0.78, 0.85))
	obj_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_hint.custom_minimum_size = Vector2(350, 0)
	ov.add_child(obj_hint)
	info_label = _label("", 17, Color(1, 1, 1, 0.9), 5)
	info_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_label.offset_left = -520
	info_label.offset_right = -20
	info_label.offset_top = 18
	hud.add_child(info_label)
	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_box.offset_top = 24
	boss_box.custom_minimum_size = Vector2(620, 0)
	boss_box.offset_left = -310
	boss_box.offset_right = 310
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(boss_box)
	var bl := _label("THE CORE SENTINEL", 22, Color(1, 0.5, 0.35), 7)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(bl)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(620, 22)
	boss_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.2, 0.15)
	fill.set_corner_radius_all(6)
	boss_bar.add_theme_stylebox_override("fill", fill)
	boss_box.add_child(boss_bar)
	boss_box.visible = false


func refresh_hotbar() -> void:
	var p = main.player
	for i in 9:
		_set_slot(hot_slots[i], p.inv[i])
		_set_slot_selected(hot_slots[i], i == p.sel)
	var id: int = p.held_id()
	var nm := B.item_name(id) if id > 0 else ""
	if nm != held_label.text:
		held_label.text = nm
		held_t = 2.0


func toast(text: String, secs := 3.0) -> void:
	toast_label.text = text
	toast_t = secs


func set_objective(idx: int, total: int, text: String, hint: String) -> void:
	obj_title.text = "MISSION  %d / %d" % [mini(idx + 1, total), total]
	obj_text.text = text
	obj_hint.text = hint


func update_hud(dt: float) -> void:
	var p = main.player
	toast_t -= dt
	toast_label.modulate.a = clampf(toast_t, 0.0, 1.0)
	held_t -= dt
	held_label.modulate.a = clampf(held_t, 0.0, 1.0)
	hearts.visible = not p.creative
	for i in 10:
		var hp: float = p.health - i * 2.0
		heart_rects[i].texture = T.heart_full if hp >= 2.0 else (T.heart_half if hp >= 1.0 else T.heart_empty)
	if p.health <= 6.0 and not p.creative:
		var wob := sin(Time.get_ticks_msec() * 0.02) * 2.0
		hearts.position.y = wob
	var vm: ShaderMaterial = vignette.material
	vm.set_shader_parameter("amount", p.hurt_flash * 0.9 + (0.35 if (p.health <= 6.0 and not p.creative) else 0.0))
	water_overlay.visible = main.world.block_at(p.eye_pos()) == B.WATER
	if main.world.block_at(p.eye_pos()) == B.LAVA:
		water_overlay.visible = true
		water_overlay.color = Color(1.0, 0.35, 0.05, 0.6)
	else:
		water_overlay.color = Color(0.1, 0.25, 0.6, 0.35)
	flash_rect.color.a = maxf(0.0, flash_rect.color.a - dt * 0.8)
	var boss = main.boss
	boss_box.visible = boss != null and is_instance_valid(boss) and not boss.dead
	if boss_box.visible:
		boss_bar.value = boss.hp / boss.MAX_HP * 100.0
	if inv_screen.visible:
		var mp := root.get_local_mouse_position()
		cursor_icon.position = mp - Vector2(22, 22)
		cursor_label.position = mp + Vector2(4, 6)
		tooltip.position = mp + Vector2(18, 18)


func white_flash(a := 1.0) -> void:
	flash_rect.color = Color(1, 1, 1, a)


# ---------------- screens ----------------

func show_screen(name: String) -> void:
	for s in [title_screen, loading_screen, pause_screen, death_screen, end_screen, confirm_screen, inv_screen, help_screen]:
		s.visible = false
	hud.visible = name == "" or name == "inventory" or name == "confirm"
	match name:
		"title":
			title_screen.visible = true
			continue_btn.visible = main.has_save()
		"loading":
			loading_screen.visible = true
		"pause":
			pause_screen.visible = true
		"death":
			death_screen.visible = true
		"end":
			end_screen.visible = true
		"confirm":
			confirm_screen.visible = true
		"inventory":
			inv_screen.visible = true
		"help":
			help_screen.visible = true


func _build_title() -> void:
	title_screen = Control.new()
	title_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_screen)
	var grad := ColorRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	var gs := Shader.new()
	gs.code = "shader_type canvas_item;\nvoid fragment(){ COLOR = vec4(0.0, 0.0, 0.03, smoothstep(0.25, 0.0, UV.x) * 0.0 + (1.0 - smoothstep(0.0, 0.55, UV.x)) * 0.75); }"
	var gm := ShaderMaterial.new()
	gm.shader = gs
	grad.material = gm
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_screen.add_child(grad)
	var v := VBoxContainer.new()
	v.position = Vector2(90, 150)
	v.add_theme_constant_override("separation", 14)
	title_screen.add_child(v)
	var t1 := _label("PLANET", 96, Color(1.0, 0.68, 0.25), 14)
	var t2 := _label("CUBE", 120, Color(1, 1, 1), 16)
	t1.add_theme_constant_override("line_spacing", -30)
	v.add_child(t1)
	v.add_child(t2)
	v.add_child(_label("Mine it.  Build it.  Escape it.", 26, Color(0.8, 0.85, 1.0), 6))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 26)
	v.add_child(sp)
	continue_btn = _button("Continue", func(): main.start_game("continue"))
	v.add_child(continue_btn)
	v.add_child(_button("New Survival World", func(): main.start_game("survival")))
	v.add_child(_button("New Creative World", func(): main.start_game("creative")))
	v.add_child(_button("How to Play", func(): show_screen("help")))
	v.add_child(_button("Quit", func(): main.quit_game()))


func _build_help() -> void:
	help_screen = _screen(0.75)
	var v := _center_box(help_screen)
	var pc := PanelContainer.new()
	v.add_child(pc)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	pc.add_child(inner)
	inner.add_child(_label("HOW TO PLAY", 34, ACCENT))
	var txt := """You crash-landed on a tiny cube-shaped planet. Walk off any edge and gravity
follows you onto the next face. Every face is a different biome.

WASD move · Space jump (double-tap in Creative to fly) · Shift sprint · Ctrl fly down
Hold Left Mouse: mine / attack · Right Mouse: place / use / eat
E: inventory & crafting · 1-9 / Mouse wheel: hotbar · Q: drop item
V: third-person camera · M (hold): planet map · Esc: pause

Progress: punch trees → wooden tools → stone → coal & torches → furnace & iron
→ diamonds deep underground → Starcore crystals at the planet's core → build
the Rocket, place it on open ground and right-click it to launch.
The planet's guardian will try to stop you: dodge its magma, JUMP over its
shockwave, and hit its glowing eye while it is stunned."""
	inner.add_child(_label(txt, 19, Color(0.9, 0.92, 1.0)))
	inner.add_child(_button("Back", func(): show_screen("title" if main.state == "title" else "pause")))


func _build_loading() -> void:
	loading_screen = _screen(0.92)
	var v := _center_box(loading_screen, 18)
	var t := _label("PLANET CUBE", 54, ACCENT, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	loading_label = _label("Forming planet...", 22, Color(0.85, 0.88, 1.0))
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loading_label)
	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size = Vector2(560, 22)
	loading_bar.show_percentage = false
	v.add_child(loading_bar)


func set_loading(f: float, text: String) -> void:
	loading_bar.value = f * 100.0
	loading_label.text = text


func _build_pause() -> void:
	pause_screen = _screen(0.6)
	var v := _center_box(pause_screen)
	var t := _label("PAUSED", 56, Color.WHITE, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(_button("Resume", func(): main.resume()))
	music_btn = _button("Music: ON", func():
		var on: bool = Sfx.toggle_music()
		music_btn.text = "Music: " + ("ON" if on else "OFF"))
	v.add_child(music_btn)
	var sl_box := HBoxContainer.new()
	sl_box.add_child(_label("Mouse sensitivity ", 18))
	var sl := HSlider.new()
	sl.min_value = 0.5
	sl.max_value = 3.0
	sl.step = 0.1
	sl.value = 1.0
	sl.custom_minimum_size = Vector2(170, 30)
	sl.value_changed.connect(func(val): main.player.sens = 0.0025 * val)
	sl_box.add_child(sl)
	v.add_child(sl_box)
	v.add_child(_button("How to Play", func(): show_screen("help")))
	v.add_child(_button("Save & Quit to Title", func(): main.save_and_title()))
	v.add_child(_button("Quit Game", func(): main.quit_game()))


func _build_death() -> void:
	death_screen = _screen(0.0)
	death_screen.color = Color(0.4, 0.0, 0.0, 0.55)
	var v := _center_box(death_screen, 20)
	var t := _label("YOU DIED", 72, Color(1, 0.85, 0.85), 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	death_label = _label("", 24, Color(1, 0.9, 0.9), 5)
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(death_label)
	v.add_child(_label("You keep your inventory.", 18, Color(1, 1, 1, 0.7)))
	v.add_child(_button("Respawn", func(): main.respawn()))


func _build_end() -> void:
	end_screen = _screen(0.35)
	var v := _center_box(end_screen, 18)
	var t := _label("YOU ESCAPED PLANET CUBE!", 60, Color(1.0, 0.78, 0.3), 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	end_stats = _label("", 24, Color.WHITE, 5)
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
	var pc := PanelContainer.new()
	v.add_child(pc)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)
	pc.add_child(inner)
	confirm_label = _label("", 24, Color.WHITE)
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
	var pc := PanelContainer.new()
	c.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 26)
	pc.add_child(hb)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)
	left.add_child(_label("INVENTORY", 26, ACCENT))
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	left.add_child(grid)
	inv_slots.resize(36)
	for i in range(9, 36):
		var p := _slot_panel()
		p.gui_input.connect(_slot_input.bind(i))
		p.mouse_entered.connect(_slot_hover.bind(i))
		p.mouse_exited.connect(func(): tooltip.text = "")
		grid.add_child(p)
		inv_slots[i] = p
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 10)
	left.add_child(sp)
	var hgrid := GridContainer.new()
	hgrid.columns = 9
	hgrid.add_theme_constant_override("h_separation", 4)
	left.add_child(hgrid)
	for i in 9:
		var p := _slot_panel()
		p.gui_input.connect(_slot_input.bind(i))
		p.mouse_entered.connect(_slot_hover.bind(i))
		p.mouse_exited.connect(func(): tooltip.text = "")
		hgrid.add_child(p)
		inv_slots[i] = p
	left.add_child(_label("Click to pick up / place · Right-click: half / one · Shift-click: quick move", 14, Color(1, 1, 1, 0.55)))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(500, 560)
	hb.add_child(right)
	var title_row := HBoxContainer.new()
	right.add_child(title_row)
	title_row.add_child(_label("CRAFTING", 26, ACCENT))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(fill)
	craftable_only = CheckBox.new()
	craftable_only.text = "Only craftable"
	craftable_only.toggled.connect(func(_on): refresh_crafting())
	title_row.add_child(craftable_only)
	craft_status = _label("", 16, Color(0.8, 0.85, 0.95))
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
	creative_grid.add_theme_constant_override("h_separation", 4)
	creative_grid.add_theme_constant_override("v_separation", 4)
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
		p.mouse_entered.connect(func(): tooltip.text = B.item_name(id))
		p.mouse_exited.connect(func(): tooltip.text = "")
		creative_grid.add_child(p)
	tooltip = _label("", 18, Color.WHITE, 6)
	inv_screen.add_child(tooltip)
	cursor_icon = TextureRect.new()
	cursor_icon.custom_minimum_size = Vector2(44, 44)
	cursor_icon.size = Vector2(44, 44)
	cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inv_screen.add_child(cursor_icon)
	cursor_label = _label("", 17, Color.WHITE, 5)
	inv_screen.add_child(cursor_label)


func open_inventory() -> void:
	var cr: bool = main.player.creative
	craft_scroll.visible = not cr
	craftable_only.visible = not cr
	creative_scroll.visible = cr
	refresh_inventory()
	refresh_crafting()


func close_inventory() -> void:
	if cursor_stack:
		main.player.add_item(cursor_stack["id"], cursor_stack["n"])
		cursor_stack = null
	tooltip.text = ""
	_update_cursor()


func refresh_inventory() -> void:
	var p = main.player
	for i in 36:
		_set_slot(inv_slots[i], p.inv[i])
		_set_slot_selected(inv_slots[i], i == p.sel)
	_update_cursor()


func _update_cursor() -> void:
	if cursor_stack:
		cursor_icon.texture = T.icon(cursor_stack["id"])
		cursor_label.text = str(cursor_stack["n"]) if cursor_stack["n"] > 1 else ""
	else:
		cursor_icon.texture = null
		cursor_label.text = ""


func _slot_hover(i: int) -> void:
	var s = main.player.inv[i]
	tooltip.text = B.item_name(s["id"]) if s else ""


func _slot_input(event: InputEvent, i: int) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var p = main.player
	var s = p.inv[i]
	if event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed and s:
		var dest_range := range(9, 36) if i < 9 else range(0, 9)
		var moved := false
		for j in dest_range:
			if p.inv[j] == null:
				p.inv[j] = s
				p.inv[i] = null
				moved = true
				break
		if not moved:
			return
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if cursor_stack == null:
			p.inv[i] = null
			cursor_stack = s
		elif s == null:
			p.inv[i] = cursor_stack
			cursor_stack = null
		elif s["id"] == cursor_stack["id"]:
			var mx := B.stack_max(s["id"])
			var k := mini(mx - s["n"], cursor_stack["n"])
			s["n"] += k
			cursor_stack["n"] -= k
			if cursor_stack["n"] <= 0:
				cursor_stack = null
		else:
			p.inv[i] = cursor_stack
			cursor_stack = s
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if cursor_stack == null and s:
			var half := ceili(s["n"] / 2.0)
			cursor_stack = {"id": s["id"], "n": half}
			s["n"] -= half
			if s["n"] <= 0:
				p.inv[i] = null
		elif cursor_stack:
			if s == null:
				p.inv[i] = {"id": cursor_stack["id"], "n": 1}
				cursor_stack["n"] -= 1
			elif s["id"] == cursor_stack["id"] and s["n"] < B.stack_max(s["id"]):
				s["n"] += 1
				cursor_stack["n"] -= 1
			if cursor_stack["n"] <= 0:
				cursor_stack = null
	else:
		return
	Sfx.play("click", -10.0)
	main.on_inventory_changed()
	_slot_hover(i)


func _palette_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		cursor_stack = {"id": id, "n": B.stack_max(id)}
		Sfx.play("click", -10.0)
		_update_cursor()


func refresh_crafting() -> void:
	if main.player.creative:
		return
	for ch in craft_list.get_children():
		ch.queue_free()
	var st: Dictionary = main.station_status()
	var parts := []
	parts.append("Crafting Table: " + ("[nearby]" if st["table"] else "[none nearby]"))
	parts.append("Furnace: " + ("[nearby]" if st["furnace"] else "[none nearby]"))
	parts.append("Fuel: %d smelts" % main.player.fuel)
	craft_status.text = "   ".join(parts)
	var only: bool = craftable_only.button_pressed
	for r in B.recipes:
		var ok: bool = main.can_craft(r)
		if only and not ok:
			continue
		craft_list.add_child(_recipe_row(r, ok, st))


func _recipe_row(r: Dictionary, ok: bool, st: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(470, 62)
	btn.disabled = false
	btn.focus_mode = Control.FOCUS_NONE
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 8
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hb)
	var icon := TextureRect.new()
	icon.texture = T.icon(r["out"])
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(v)
	var nm := B.item_name(r["out"]) + ("  x%d" % r["n"] if r["n"] > 1 else "")
	var st_name := ""
	if r["st"] == "table":
		st_name = "  [Table]"
	elif r["st"] == "furnace":
		st_name = "  [Furnace]"
	v.add_child(_label(nm + st_name, 18, Color.WHITE if ok else Color(1, 1, 1, 0.5)))
	var ing := HBoxContainer.new()
	ing.add_theme_constant_override("separation", 4)
	ing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ing)
	var p = main.player
	for id in r["in"]:
		var need: int = r["in"][id]
		var have: int = p.count(id)
		var ic := TextureRect.new()
		var shown_id: int = B.group_members(id)[0]
		ic.texture = T.icon(shown_id)
		ic.custom_minimum_size = Vector2(22, 22)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ing.add_child(ic)
		var col := Color(0.6, 1.0, 0.6) if have >= need else Color(1.0, 0.45, 0.4)
		ing.add_child(_label("%d/%d %s   " % [mini(have, need), need, B.item_name(id)], 13, col))
	if not ok:
		btn.modulate = Color(1, 1, 1, 0.7)
	btn.pressed.connect(func():
		if main.craft(r):
			refresh_crafting())
	return btn

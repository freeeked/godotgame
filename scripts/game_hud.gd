extends CanvasLayer
class_name GameHUD

signal level_selected(index: int)
signal next_level_requested()
signal restart_requested()
signal mute_toggled(is_muted: bool)
signal gameplay_resumed()

const PB_SAVE_PATH := "user://stackroll_course_pbs.cfg"

const COURSES := [
	{"id": 1, "name": "1 · Classic Parkour", "blurb": "Classic gaps & ledge leaps"},
	{"id": 2, "name": "2 · Wall-Slip Alley", "blurb": "Tight corridors & wall-slips"},
	{"id": 3, "name": "3 · Vault & Gates", "blurb": "Power-ups, gates & high vaults"},
	{"id": 4, "name": "4 · Trick-Shot Table", "blurb": "Pool table trick-shots & pockets"},
]

# Palette matching style.css
const COL_INK := Color("0f172a")
const COL_PANEL_BG := Color("0f172a", 0.92)
const COL_PANEL_SURFACE := Color("1e293b")
const COL_SLATE := Color("334155")
const COL_CREAM := Color("f8fafc")
const COL_GOLD := Color("facc15")
const COL_GOLD_LIP := Color("ca8a04")
const COL_BLUE := Color("2563eb")
const COL_BLUE_LIP := Color("1d4ed8")
const COL_ORANGE := Color("f97316")
const COL_ORANGE_LIP := Color("c2410c")
const COL_RED := Color("ef4444")
const COL_RED_LIP := Color("b91c1c")
const COL_GREEN := Color("22c55e")
const COL_GREEN_LIP := Color("15803d")
const COL_SKY := Color("38bdf8")

# Custom drawn orb icon control for Stack Dock pills
class StackOrbIcon extends Control:
	var orb_color: Color = Color("2563eb")
	var is_dead: bool = false

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		# Drop lip + main circle + ink outline
		draw_circle(c + Vector2(0, 2), r, Color("0f172a"))
		var fill: Color = Color.from_hsv(orb_color.h, orb_color.s * 0.15, orb_color.v, orb_color.a) if is_dead else orb_color
		draw_circle(c, r, fill)
		draw_arc(c, r, 0.0, TAU, 28, Color("0f172a"), 2.5, true)

		if is_dead:
			var d := r * 0.42
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), Color.WHITE, 2.4, true)
			draw_line(c + Vector2(d, -d), c + Vector2(-d, d), Color.WHITE, 2.4, true)
		else:
			draw_rect(Rect2(c.x - 5.5, c.y - 3.0, 3.0, 4.5), Color("0f172a"))
			draw_rect(Rect2(c.x + 2.5, c.y - 3.0, 3.0, 4.5), Color("0f172a"))

# Physics Ball-Pit Pause Menu Body
class PauseBall:
	var id: String
	var label: String
	var color: Color
	var base_weight: float
	var radius: float = 80.0
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var home_x: float = 0.0
	var anchor_norm_x: float = 0.0
	var drop_rank: int = 0
	var angle: float = 0.0
	var v_angle: float = 0.0
	var scale_val: float = 1.0
	var target_scale: float = 1.0
	var is_action: bool = false
	var icon_type: String = ""
	var on_select: Callable

class PausePitCanvas extends Control:
	var balls: Array[PauseBall] = []
	var hovered_id: String = ""
	var pointer_pos: Vector2 = Vector2.ZERO
	var is_muted: bool = false
	var font_ref: Font

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			pointer_pos = event.position
			var found := ""
			for i in range(balls.size() - 1, -1, -1):
				var b := balls[i]
				if b.pos.distance_to(pointer_pos) <= b.radius * b.scale_val:
					if b.is_action:
						found = b.id
					else:
						b.vel.y -= 90.0
						b.vel.x += randf_range(-80.0, 80.0)
					break
			hovered_id = found
			for b in balls:
				b.target_scale = 1.1 if (b.is_action and b.id == hovered_id) else 1.0
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pointer_pos = event.position
			for i in range(balls.size() - 1, -1, -1):
				var b := balls[i]
				if b.pos.distance_to(pointer_pos) <= b.radius * b.scale_val:
					if b.is_action and b.on_select.is_valid():
						b.on_select.call()
					else:
						b.vel.y -= 420.0
						b.vel.x += randf_range(-360.0, 360.0)
					accept_event()
					break

	func _draw() -> void:
		# Draw filler balls behind action balls
		for pass_idx in range(2):
			for b in balls:
				if (pass_idx == 0 and b.is_action) or (pass_idx == 1 and not b.is_action):
					continue
				var is_hov := b.is_action and b.id == hovered_id
				var r := b.radius * b.scale_val
				var max_tilt := 0.16 if b.is_action else 0.42
				var rot := clampf(b.angle, -max_tilt, max_tilt)

				draw_set_transform(b.pos, rot, Vector2.ONE)

				# Drop lip shadow
				draw_circle(Vector2(0, 9), r, Color("0f172a"))
				if is_hov:
					draw_circle(Vector2.ZERO, r + 5.0, Color("facc15"))

				# Main body + top-left glossy highlight
				draw_circle(Vector2.ZERO, r, b.color)
				draw_circle(Vector2(-r * 0.28, -r * 0.30), r * 0.34, Color(1, 1, 1, 0.22))
				draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color.WHITE if is_hov else Color("0f172a"), 5.0, true)

				# Cursor-tracking blob eyes
				var look := pointer_pos - b.pos
				var look_len := look.length()
				var eye_shift := (look / maxf(1.0, look_len)) * minf(4.0, look_len * 0.02)
				var eye_y := -r * 0.34
				var eye_dx := r * 0.22
				for side in [-1.0, 1.0]:
					var ep := Vector2(side * eye_dx, eye_y) + eye_shift
					draw_circle(ep, maxf(4.5, r * 0.075), Color("0f172a"))

				# Action icon + pill badge
				if b.is_action:
					_draw_action_icon(b.icon_type, r * 0.34)
					var lbl_text := ("UNMUTE" if is_muted else "SFX ON") if b.id == "sound" else b.label
					var f_size := 13
					var txt_size := font_ref.get_string_size(lbl_text, HORIZONTAL_ALIGNMENT_CENTER, -1, f_size)
					var pill_w := txt_size.x + 24.0
					var pill_h := 26.0
					var pill_rect := Rect2(-pill_w * 0.5, r - 12.0, pill_w, pill_h)
					draw_rect(Rect2(pill_rect.position + Vector2(0, 3), pill_rect.size), Color("0f172a"))
					draw_rect(pill_rect, Color("facc15") if is_hov else Color("0f172a"))
					draw_rect(pill_rect, Color("0f172a") if is_hov else Color.WHITE, false, 2.5)
					draw_string(
						font_ref,
						Vector2(-txt_size.x * 0.5, r + 5.0),
						lbl_text,
						HORIZONTAL_ALIGNMENT_LEFT,
						-1,
						f_size,
						Color("0f172a") if is_hov else Color("f8fafc")
					)

				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_action_icon(icon_type: String, s: float) -> void:
		var ink := Color("0f172a")
		var w := 3.4
		match icon_type:
			"play":
				var pts := PackedVector2Array([Vector2(-s * 0.45, -s * 0.65), Vector2(s * 0.72, 0.0), Vector2(-s * 0.45, s * 0.65)])
				draw_colored_polygon(pts, Color.WHITE)
				pts.append(pts[0])
				draw_polyline(pts, ink, w, true)
			"next":
				var pts := PackedVector2Array([Vector2(-s * 0.65, -s * 0.6), Vector2(s * 0.35, 0.0), Vector2(-s * 0.65, s * 0.6)])
				draw_colored_polygon(pts, Color.WHITE)
				pts.append(pts[0])
				draw_polyline(pts, ink, w, true)
				draw_line(Vector2(s * 0.55, -s * 0.6), Vector2(s * 0.55, s * 0.6), ink, w, true)
			"restart":
				draw_arc(Vector2.ZERO, s * 0.62, -PI * 0.75, PI * 0.85, 24, ink, w, true)
				draw_line(Vector2(-s * 0.65, -s * 0.55), Vector2(-s * 0.65, -s * 0.1), ink, w, true)
				draw_line(Vector2(-s * 0.65, -s * 0.1), Vector2(-s * 0.2, -s * 0.1), ink, w, true)
			"home":
				draw_polyline(PackedVector2Array([Vector2(-s * 0.7, -s * 0.05), Vector2(0, -s * 0.72), Vector2(s * 0.7, -s * 0.05)]), ink, w, true)
				draw_rect(Rect2(-s * 0.48, -s * 0.05, s * 0.96, s * 0.72), ink, false, w)
			"courses":
				var gap := s * 0.14
				var box := s * 0.46
				for gx in [-1.0, 1.0]:
					for gy in [-1.0, 1.0]:
						var pos := Vector2(gx * (gap + box * 0.5) - box * 0.5, gy * (gap + box * 0.5) - box * 0.5)
						draw_rect(Rect2(pos, Vector2(box, box)), ink, false, w * 0.85)
			"controls":
				draw_rect(Rect2(-s * 0.75, -s * 0.42, s * 1.5, s * 0.84), ink, false, w)
				draw_line(Vector2(-s * 0.35, -s * 0.2), Vector2(-s * 0.35, s * 0.2), ink, w * 0.85)
				draw_line(Vector2(-s * 0.55, 0.0), Vector2(-s * 0.15, 0.0), ink, w * 0.85)
				draw_circle(Vector2(s * 0.3, -s * 0.1), 2.5, ink)
				draw_circle(Vector2(s * 0.48, s * 0.12), 2.5, ink)
			"sound":
				var spk := PackedVector2Array([
					Vector2(-s * 0.6, -s * 0.28),
					Vector2(-s * 0.25, -s * 0.28),
					Vector2(s * 0.18, -s * 0.62),
					Vector2(s * 0.18, s * 0.62),
					Vector2(-s * 0.25, s * 0.28),
					Vector2(-s * 0.6, s * 0.28),
				])
				draw_colored_polygon(spk, Color.WHITE)
				spk.append(spk[0])
				draw_polyline(spk, ink, w * 0.85, true)
				if is_muted:
					draw_line(Vector2(s * 0.38, -s * 0.25), Vector2(s * 0.75, s * 0.25), ink, w)
					draw_line(Vector2(s * 0.75, -s * 0.25), Vector2(s * 0.38, s * 0.25), ink, w)
				else:
					draw_arc(Vector2(s * 0.22, 0.0), s * 0.38, -0.7, 0.7, 12, ink, w * 0.85, true)

class DynamicReticle extends Control:
	var is_locked: bool = false
	var anim_t: float = 0.0

	func _process(delta: float) -> void:
		var target := 1.0 if is_locked else 0.0
		anim_t = lerpf(anim_t, target, 1.0 - exp(-18.0 * delta))
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var ring_r := lerpf(9.0, 15.0, anim_t)
		var ring_col := Color(1.0, 1.0, 1.0, 0.45).lerp(Color("facc15", 0.95), anim_t)
		var dot_col := Color(1.0, 1.0, 1.0, 0.85).lerp(Color("38bdf8", 1.0), anim_t)

		# Subtle dark backing ring for contrast against bright sky/walls
		draw_arc(c, ring_r, 0.0, TAU, 32, Color(0.06, 0.09, 0.16, 0.55), 3.5, true)
		draw_arc(c, ring_r, 0.0, TAU, 32, ring_col, 2.0, true)
		draw_circle(c, lerpf(2.2, 3.2, anim_t), dot_col)

		if anim_t > 0.15:
			var tick := lerpf(4.0, 7.0, anim_t)
			var gap := ring_r + 3.0
			for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + dir * gap, c + dir * (gap + tick), ring_col, 2.2, true)

var _font: Font
var _hud_root: Control
var _stack_dock: PanelContainer
var _stack_pills: Dictionary = {} # id -> {panel, style, orb, name_lbl, role_lbl, badge_lbl, badge_style, target_pos, target_scale}
var _course_lbl: Label
var _pb_lbl: Label
var _timer_lbl: Label
var _mute_btn: Button
var _reticle: DynamicReticle

var _title_overlay: ColorRect
var _course_modal: ColorRect
var _controls_modal: ColorRect
var _pause_overlay: ColorRect
var _pause_canvas: PausePitCanvas
var _win_banner: ColorRect
var _win_time_lbl: Label
var _course_cards: Array[Dictionary] = []

var _elapsed_seconds: float = 0.0
var _elapsed_anim: float = 0.0
var _is_paused: bool = false
var _pause_guard_until_ms: int = 0
var _on_title_screen: bool = true
var _is_win_visible: bool = false
var _is_muted: bool = false
var _selected_level_idx: int = 0
var _pbs: Dictionary = {}

func _ready() -> void:
	layer = 20
	_font = _load_ui_font()
	_pbs = _load_pbs()

	_build_gameplay_hud()
	_build_title_screen()
	_build_course_modal()
	_build_controls_modal()
	_build_pause_menu()
	_build_win_banner()

	set_selected_level(0)
	_sync_visibility()

func _load_ui_font() -> Font:
	for path in ["res://assets/fonts/Fredoka-Bold.ttf", "res://fonts/Fredoka-Bold.ttf"]:
		if ResourceLoader.exists(path):
			var f := load(path) as Font
			if f != null:
				return f
	return ThemeDB.fallback_font

# --- Style Helpers (Balatro Tactile Cards & Buttons) ---

func _make_box_style(
	bg: Color,
	border_col: Color = COL_INK,
	radius: int = 14,
	border_w: int = 3,
	shadow_size: int = 6,
	shadow_col: Color = COL_INK
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = shadow_col
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(0, shadow_size)
	return sb

func _make_balatro_button(text_str: String, fill: Color, lip: Color, small: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text_str
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 13 if small else 16)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_outline_color", Color(0.06, 0.09, 0.16, 0.7))
	btn.add_theme_constant_override("outline_size", 3)

	var r := 11 if small else 14
	var pad_x := 14 if small else 22
	var pad_y := 8 if small else 12

	var normal := _make_box_style(fill, COL_INK, r, 3, 5 if small else 6, COL_INK)
	normal.content_margin_left = pad_x
	normal.content_margin_right = pad_x
	normal.content_margin_top = pad_y
	normal.content_margin_bottom = pad_y

	var hover := _make_box_style(fill.lightened(0.10), Color.WHITE, r, 3, 7 if small else 8, COL_INK)
	hover.content_margin_left = pad_x
	hover.content_margin_right = pad_x
	hover.content_margin_top = pad_y
	hover.content_margin_bottom = pad_y

	var pressed := _make_box_style(lip, COL_INK, r, 3, 2, COL_INK)
	pressed.content_margin_left = pad_x
	pressed.content_margin_right = pad_x
	pressed.content_margin_top = pad_y + 2
	pressed.content_margin_bottom = pad_y - 2

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	return btn

func _make_keycap(key_text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	var sb := _make_box_style(COL_SLATE, COL_INK, 6, 2, 2, COL_INK)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	cap.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = key_text
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", COL_CREAM)
	cap.add_child(lbl)
	return cap

# --- 1. Gameplay HUD (Stack Order Dock, Top Course/Timer Bar, Quick Actions, Controls Ribbon, Reticle) ---

func _build_gameplay_hud() -> void:
	_hud_root = Control.new()
	_hud_root.name = "GameplayHUD"
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_root)

	_reticle = DynamicReticle.new()
	_reticle.name = "Reticle"
	_reticle.set_anchors_preset(Control.PRESET_CENTER)
	_reticle.offset_left = -28
	_reticle.offset_top = -28
	_reticle.offset_right = 28
	_reticle.offset_bottom = 28
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_reticle)

	# Upper-Left Dynamic Stack Tracker
	_stack_dock = PanelContainer.new()
	_stack_dock.name = "StackDock"
	_stack_dock.position = Vector2(18, 18)
	_stack_dock.custom_minimum_size = Vector2(214, 206)
	_stack_dock.pivot_offset = Vector2(107, 103)
	_stack_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dock_sb := _make_box_style(COL_PANEL_BG, COL_INK, 18, 3, 7, COL_INK)
	dock_sb.content_margin_left = 12
	dock_sb.content_margin_right = 12
	dock_sb.content_margin_top = 12
	dock_sb.content_margin_bottom = 14
	_stack_dock.add_theme_stylebox_override("panel", dock_sb)
	_hud_root.add_child(_stack_dock)

	var dock_vbox := VBoxContainer.new()
	dock_vbox.add_theme_constant_override("separation", 10)
	dock_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack_dock.add_child(dock_vbox)

	var header_hbox := HBoxContainer.new()
	header_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock_vbox.add_child(header_hbox)

	var h_left := Label.new()
	h_left.text = "STACK ORDER"
	h_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_left.add_theme_font_override("font", _font)
	h_left.add_theme_font_size_override("font_size", 11)
	h_left.add_theme_color_override("font_color", Color("94a3b8"))
	header_hbox.add_child(h_left)

	var h_right := Label.new()
	h_right.text = "TOP ↑"
	h_right.add_theme_font_override("font", _font)
	h_right.add_theme_font_size_override("font_size", 11)
	h_right.add_theme_color_override("font_color", Color("94a3b8"))
	header_hbox.add_child(h_right)

	var stage := Control.new()
	stage.custom_minimum_size = Vector2(184, 158)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock_vbox.add_child(stage)

	var initial := [
		{"id": 0, "name": "Blue", "color": Color("2563eb"), "is_stacked": true, "stack_pos": 0, "is_dead": false},
		{"id": 1, "name": "Green", "color": Color("22c55e"), "is_stacked": true, "stack_pos": 1, "is_dead": false},
		{"id": 2, "name": "Pink", "color": Color("d946ef"), "is_stacked": true, "stack_pos": 2, "is_dead": false},
	]

	for m in initial:
		var pill := PanelContainer.new()
		pill.custom_minimum_size = Vector2(184, 46)
		pill.size = Vector2(184, 46)
		pill.pivot_offset = Vector2(92, 23)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var p_sb := _make_box_style(COL_PANEL_SURFACE, COL_INK, 13, 3, 4, COL_INK)
		p_sb.content_margin_left = 10
		p_sb.content_margin_right = 10
		p_sb.content_margin_top = 4
		p_sb.content_margin_bottom = 4
		pill.add_theme_stylebox_override("panel", p_sb)
		stage.add_child(pill)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(row)

		var orb := StackOrbIcon.new()
		orb.orb_color = m["color"]
		orb.custom_minimum_size = Vector2(24, 24)
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(orb)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", -2)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)

		var name_lbl := Label.new()
		name_lbl.text = m["name"]
		name_lbl.add_theme_font_override("font", _font)
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", COL_CREAM)
		info.add_child(name_lbl)

		var role_lbl := Label.new()
		role_lbl.text = "STACKED"
		role_lbl.add_theme_font_override("font", _font)
		role_lbl.add_theme_font_size_override("font_size", 10)
		role_lbl.add_theme_color_override("font_color", Color("94a3b8"))
		info.add_child(role_lbl)

		var badge_panel := PanelContainer.new()
		badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b_sb := _make_box_style(Color(0.06, 0.09, 0.16, 0.85), COL_INK, 7, 2, 0, COL_INK)
		b_sb.content_margin_left = 7
		b_sb.content_margin_right = 7
		b_sb.content_margin_top = 2
		b_sb.content_margin_bottom = 2
		badge_panel.add_theme_stylebox_override("panel", b_sb)
		row.add_child(badge_panel)

		var badge_lbl := Label.new()
		badge_lbl.text = "#1"
		badge_lbl.add_theme_font_override("font", _font)
		badge_lbl.add_theme_font_size_override("font_size", 10)
		badge_lbl.add_theme_color_override("font_color", Color("cbd5e1"))
		badge_panel.add_child(badge_lbl)

		_stack_pills[m["id"]] = {
			"panel": pill,
			"style": p_sb,
			"orb": orb,
			"name_lbl": name_lbl,
			"role_lbl": role_lbl,
			"badge_lbl": badge_lbl,
			"badge_style": b_sb,
			"target_pos": Vector2.ZERO,
			"target_scale": Vector2.ONE,
		}

	update_stack_status(initial)

	# Top-Center Course & Timer Pill
	var top_center := CenterContainer.new()
	top_center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_center.offset_top = 18
	top_center.offset_bottom = 82
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(top_center)

	var top_bar := PanelContainer.new()
	var tb_sb := _make_box_style(COL_PANEL_BG, COL_INK, 16, 3, 6, COL_INK)
	tb_sb.content_margin_left = 14
	tb_sb.content_margin_right = 14
	tb_sb.content_margin_top = 8
	tb_sb.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", tb_sb)
	top_center.add_child(top_bar)

	var tb_hbox := HBoxContainer.new()
	tb_hbox.add_theme_constant_override("separation", 10)
	top_bar.add_child(tb_hbox)

	var course_vbox := VBoxContainer.new()
	course_vbox.add_theme_constant_override("separation", 2)
	tb_hbox.add_child(course_vbox)

	var course_pill := PanelContainer.new()
	var cp_sb := _make_box_style(COL_PANEL_SURFACE, COL_INK, 10, 2, 0, COL_INK)
	cp_sb.content_margin_left = 12
	cp_sb.content_margin_right = 12
	cp_sb.content_margin_top = 4
	cp_sb.content_margin_bottom = 4
	course_pill.add_theme_stylebox_override("panel", cp_sb)
	course_vbox.add_child(course_pill)

	_course_lbl = Label.new()
	_course_lbl.text = COURSES[0]["name"]
	_course_lbl.add_theme_font_override("font", _font)
	_course_lbl.add_theme_font_size_override("font_size", 14)
	_course_lbl.add_theme_color_override("font_color", COL_GOLD)
	course_pill.add_child(_course_lbl)

	_pb_lbl = Label.new()
	_pb_lbl.text = "PB: --:--.-"
	_pb_lbl.add_theme_font_override("font", _font)
	_pb_lbl.add_theme_font_size_override("font_size", 10)
	_pb_lbl.add_theme_color_override("font_color", Color("64748b"))
	course_vbox.add_child(_pb_lbl)

	var timer_pill := PanelContainer.new()
	var tp_sb := _make_box_style(COL_INK, COL_SLATE, 10, 2, 0, COL_INK)
	tp_sb.content_margin_left = 12
	tp_sb.content_margin_right = 12
	tp_sb.content_margin_top = 6
	tp_sb.content_margin_bottom = 6
	timer_pill.add_theme_stylebox_override("panel", tp_sb)
	tb_hbox.add_child(timer_pill)

	_timer_lbl = Label.new()
	_timer_lbl.text = "00:00.0"
	_timer_lbl.add_theme_font_override("font", _font)
	_timer_lbl.add_theme_font_size_override("font_size", 16)
	_timer_lbl.add_theme_color_override("font_color", COL_SKY)
	timer_pill.add_child(_timer_lbl)

	# Top-Right Quick Actions
	var top_right := HBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.offset_top = 18
	top_right.offset_right = -18
	top_right.add_theme_constant_override("separation", 10)
	_hud_root.add_child(top_right)

	_mute_btn = _make_balatro_button("SFX ON", COL_SLATE, COL_PANEL_SURFACE, true)
	_mute_btn.pressed.connect(func() -> void:
		_is_muted = not _is_muted
		_sync_mute_ui()
		mute_toggled.emit(_is_muted)
	)
	top_right.add_child(_mute_btn)

	var pause_btn := _make_balatro_button("PAUSE [ESC]", COL_ORANGE, COL_ORANGE_LIP, true)
	pause_btn.pressed.connect(open_pause_menu)
	top_right.add_child(pause_btn)

	# Bottom Controls Ribbon
	var bottom_center := CenterContainer.new()
	bottom_center.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_center.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_center.offset_bottom = -16
	bottom_center.offset_top = -62
	bottom_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(bottom_center)

	var ribbon := PanelContainer.new()
	var rb_sb := _make_box_style(Color(0.06, 0.09, 0.16, 0.86), COL_INK, 15, 3, 5, COL_INK)
	rb_sb.content_margin_left = 14
	rb_sb.content_margin_right = 14
	rb_sb.content_margin_top = 7
	rb_sb.content_margin_bottom = 7
	ribbon.add_theme_stylebox_override("panel", rb_sb)
	bottom_center.add_child(ribbon)

	var rb_hbox := HBoxContainer.new()
	rb_hbox.add_theme_constant_override("separation", 12)
	ribbon.add_child(rb_hbox)

	var hints := [
		["WASD", "Move"],
		["SPACE", "Jump"],
		["SHIFT", "Sprint-Roll"],
		["E", "Throw Top"],
		["C", "Bowl Bottom"],
		["R", "Recall"],
		["F", "Swap Swoop"],
		["ESC", "Pause"],
	]
	for h in hints:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		item.add_child(_make_keycap(h[0]))
		var lbl := Label.new()
		lbl.text = h[1]
		lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color("cbd5e1"))
		item.add_child(lbl)
		rb_hbox.add_child(item)

# --- 2. Title Screen Overlay ---

func _build_title_screen() -> void:
	_title_overlay = ColorRect.new()
	_title_overlay.name = "TitleOverlay"
	_title_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_overlay.color = Color(0.01, 0.02, 0.09, 0.62)
	add_child(_title_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_overlay.add_child(center)

	var hero := VBoxContainer.new()
	hero.add_theme_constant_override("separation", 22)
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(hero)

	# Title Emblem Card
	var emblem := PanelContainer.new()
	var em_sb := _make_box_style(COL_INK, COL_INK, 26, 4, 10, COL_INK)
	em_sb.content_margin_left = 40
	em_sb.content_margin_right = 40
	em_sb.content_margin_top = 24
	em_sb.content_margin_bottom = 24
	emblem.add_theme_stylebox_override("panel", em_sb)
	hero.add_child(emblem)

	var em_vbox := VBoxContainer.new()
	em_vbox.add_theme_constant_override("separation", 8)
	em_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	emblem.add_child(em_vbox)

	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 10)
	em_vbox.add_child(chips)

	for c in [Color("2563eb"), Color("22c55e"), Color("d946ef")]:
		var orb := StackOrbIcon.new()
		orb.orb_color = c
		orb.custom_minimum_size = Vector2(30, 30)
		chips.add_child(orb)

	var wordmark := Label.new()
	wordmark.text = "STACK ROLL"
	wordmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wordmark.add_theme_font_override("font", _font)
	wordmark.add_theme_font_size_override("font_size", 58)
	wordmark.add_theme_color_override("font_color", COL_GOLD)
	wordmark.add_theme_color_override("font_outline_color", COL_INK)
	wordmark.add_theme_constant_override("outline_size", 8)
	em_vbox.add_child(wordmark)

	var sub := Label.new()
	sub.text = "3D TRIO PARKOUR & TRICK-SHOT SANDBOX"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", _font)
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", COL_SKY)
	em_vbox.add_child(sub)

	# Menu Bar
	var menu_panel := PanelContainer.new()
	var mp_sb := _make_box_style(Color(0.06, 0.09, 0.16, 0.92), COL_INK, 20, 3, 8, COL_INK)
	mp_sb.content_margin_left = 18
	mp_sb.content_margin_right = 18
	mp_sb.content_margin_top = 14
	mp_sb.content_margin_bottom = 14
	menu_panel.add_theme_stylebox_override("panel", mp_sb)
	hero.add_child(menu_panel)

	var menu_row := HBoxContainer.new()
	menu_row.add_theme_constant_override("separation", 14)
	menu_panel.add_child(menu_row)

	var play_btn := _make_balatro_button("▶ PLAY", COL_BLUE, COL_BLUE_LIP, false)
	play_btn.add_theme_font_size_override("font_size", 20)
	play_btn.pressed.connect(func() -> void: start_from_title(_selected_level_idx))
	menu_row.add_child(play_btn)

	var courses_btn := _make_balatro_button("COURSES", COL_ORANGE, COL_ORANGE_LIP, false)
	courses_btn.pressed.connect(func() -> void: _course_modal.visible = true)
	menu_row.add_child(courses_btn)

	var how_btn := _make_balatro_button("CONTROLS", COL_GREEN, COL_GREEN_LIP, false)
	how_btn.pressed.connect(func() -> void: _controls_modal.visible = true)
	menu_row.add_child(how_btn)

# --- 3. Course Select Modal ---

func _build_course_modal() -> void:
	_course_modal = ColorRect.new()
	_course_modal.name = "CourseModal"
	_course_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_course_modal.color = Color(0.01, 0.02, 0.09, 0.78)
	_course_modal.visible = false
	add_child(_course_modal)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_course_modal.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	var p_sb := _make_box_style(COL_PANEL_SURFACE, COL_INK, 22, 4, 10, COL_INK)
	p_sb.content_margin_left = 28
	p_sb.content_margin_right = 28
	p_sb.content_margin_top = 24
	p_sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", p_sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var head := HBoxContainer.new()
	vbox.add_child(head)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)

	var eye := Label.new()
	eye.text = "SELECT STAGE"
	eye.add_theme_font_override("font", _font)
	eye.add_theme_font_size_override("font_size", 12)
	eye.add_theme_color_override("font_color", COL_GOLD)
	titles.add_child(eye)

	var h2 := Label.new()
	h2.text = "CHOOSE A COURSE"
	h2.add_theme_font_override("font", _font)
	h2.add_theme_font_size_override("font_size", 26)
	h2.add_theme_color_override("font_color", COL_CREAM)
	titles.add_child(h2)

	var back_btn := _make_balatro_button("← BACK", COL_RED, COL_RED_LIP, true)
	back_btn.pressed.connect(func() -> void: _course_modal.visible = false)
	head.add_child(back_btn)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	vbox.add_child(grid)

	_course_cards.clear()
	for idx in range(COURSES.size()):
		var c_data: Dictionary = COURSES[idx]
		var card := Button.new()
		card.custom_minimum_size = Vector2(320, 128)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var normal_sb := _make_box_style(COL_SLATE, COL_INK, 16, 3, 6, COL_INK)
		normal_sb.content_margin_left = 14
		normal_sb.content_margin_right = 14
		normal_sb.content_margin_top = 12
		normal_sb.content_margin_bottom = 12

		var active_sb := _make_box_style(COL_BLUE_LIP, COL_GOLD, 16, 3, 6, COL_INK)
		active_sb.content_margin_left = 14
		active_sb.content_margin_right = 14
		active_sb.content_margin_top = 12
		active_sb.content_margin_bottom = 12

		card.add_theme_stylebox_override("normal", normal_sb)
		card.add_theme_stylebox_override("hover", active_sb)
		card.add_theme_stylebox_override("pressed", active_sb)

		var c_vbox := VBoxContainer.new()
		c_vbox.add_theme_constant_override("separation", 6)
		c_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(c_vbox)

		var num_lbl := Label.new()
		num_lbl.text = "COURSE 0%d" % c_data["id"]
		num_lbl.add_theme_font_override("font", _font)
		num_lbl.add_theme_font_size_override("font_size", 11)
		num_lbl.add_theme_color_override("font_color", COL_GOLD)
		c_vbox.add_child(num_lbl)

		var title_lbl := Label.new()
		title_lbl.text = c_data["name"].substr(4)
		title_lbl.add_theme_font_override("font", _font)
		title_lbl.add_theme_font_size_override("font_size", 17)
		title_lbl.add_theme_color_override("font_color", COL_CREAM)
		c_vbox.add_child(title_lbl)

		var tag_lbl := Label.new()
		tag_lbl.text = c_data["blurb"]
		tag_lbl.add_theme_font_override("font", _font)
		tag_lbl.add_theme_font_size_override("font_size", 12)
		tag_lbl.add_theme_color_override("font_color", Color("cbd5e1"))
		c_vbox.add_child(tag_lbl)

		var pb_card_lbl := Label.new()
		var pb_val: Variant = _pbs.get(c_data["id"], null)
		pb_card_lbl.text = ("PB: " + _format_time(float(pb_val))) if pb_val != null else "NO RECORD"
		pb_card_lbl.add_theme_font_override("font", _font)
		pb_card_lbl.add_theme_font_size_override("font_size", 11)
		pb_card_lbl.add_theme_color_override("font_color", COL_GREEN if pb_val != null else Color("94a3b8"))
		c_vbox.add_child(pb_card_lbl)

		var captured_idx := idx
		card.pressed.connect(func() -> void:
			_course_modal.visible = false
			start_from_title(captured_idx)
		)

		grid.add_child(card)
		_course_cards.append({
			"btn": card,
			"normal_sb": normal_sb,
			"active_sb": active_sb,
			"pb_lbl": pb_card_lbl,
		})

# --- 4. Controls Modal ---

func _build_controls_modal() -> void:
	_controls_modal = ColorRect.new()
	_controls_modal.name = "ControlsModal"
	_controls_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_controls_modal.color = Color(0.01, 0.02, 0.09, 0.78)
	_controls_modal.visible = false
	add_child(_controls_modal)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_controls_modal.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	var p_sb := _make_box_style(COL_PANEL_SURFACE, COL_INK, 22, 4, 10, COL_INK)
	p_sb.content_margin_left = 28
	p_sb.content_margin_right = 28
	p_sb.content_margin_top = 24
	p_sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", p_sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var eye := Label.new()
	eye.text = "MOVESET"
	eye.add_theme_font_override("font", _font)
	eye.add_theme_font_size_override("font_size", 12)
	eye.add_theme_color_override("font_color", COL_SKY)
	vbox.add_child(eye)

	var h2 := Label.new()
	h2.text = "HOW TO PLAY"
	h2.add_theme_font_override("font", _font)
	h2.add_theme_font_size_override("font_size", 24)
	h2.add_theme_color_override("font_color", COL_CREAM)
	vbox.add_child(h2)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	var rows := [
		["Move Trio", "WASD / Arrows"],
		["Jump / Coyote", "SPACE"],
		["Snake Sprint-Roll", "SHIFT"],
		["Throw Top Blob", "E"],
		["Bowl Bottom Blob", "C / CTRL"],
		["Recall All Blobs", "R"],
		["Stack Swap Swoop", "F"],
		["Orbit / Reset Cam", "MOUSE / Q"],
	]
	for r in rows:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c_sb := _make_box_style(Color(0.06, 0.09, 0.16, 0.78), COL_INK, 12, 2, 0, COL_INK)
		c_sb.content_margin_left = 12
		c_sb.content_margin_right = 12
		c_sb.content_margin_top = 8
		c_sb.content_margin_bottom = 8
		cell.add_theme_stylebox_override("panel", c_sb)

		var hbox := HBoxContainer.new()
		cell.add_child(hbox)

		var lbl := Label.new()
		lbl.text = r[0]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_override("font", _font)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", COL_CREAM)
		hbox.add_child(lbl)
		hbox.add_child(_make_keycap(r[1]))
		grid.add_child(cell)

	var got_it := _make_balatro_button("GOT IT", COL_BLUE, COL_BLUE_LIP, false)
	got_it.pressed.connect(func() -> void: _controls_modal.visible = false)
	vbox.add_child(got_it)

# --- 5. Falling Ball-Pit Pause Menu ---

func _build_pause_menu() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.name = "PausePitOverlay"
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.color = Color(0.01, 0.02, 0.09, 0.76)
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	_pause_canvas = PausePitCanvas.new()
	_pause_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_canvas.font_ref = _font
	_pause_overlay.add_child(_pause_canvas)

	# Top Banner
	var top_center := CenterContainer.new()
	top_center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_center.offset_top = 22
	top_center.offset_bottom = 70
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(top_center)

	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b_sb := _make_box_style(COL_PANEL_BG, COL_INK, 18, 3, 6, COL_INK)
	b_sb.content_margin_left = 20
	b_sb.content_margin_right = 20
	b_sb.content_margin_top = 10
	b_sb.content_margin_bottom = 10
	banner.add_theme_stylebox_override("panel", b_sb)
	top_center.add_child(banner)

	var b_hbox := HBoxContainer.new()
	b_hbox.add_theme_constant_override("separation", 10)
	banner.add_child(b_hbox)

	var p_title := Label.new()
	p_title.text = "PAUSED"
	p_title.add_theme_font_override("font", _font)
	p_title.add_theme_font_size_override("font_size", 16)
	p_title.add_theme_color_override("font_color", COL_GOLD)
	b_hbox.add_child(p_title)

	var p_hint := Label.new()
	p_hint.text = "Click a blob or press ESC to resume"
	p_hint.add_theme_font_override("font", _font)
	p_hint.add_theme_font_size_override("font_size", 13)
	p_hint.add_theme_color_override("font_color", Color("cbd5e1"))
	b_hbox.add_child(p_hint)

	var specs := [
		{"id": "title", "label": "TITLE", "color": Color("ef4444"), "w": 0.94, "act": true, "nx": -0.78, "rank": 0, "icon": "home"},
		{"id": "sound", "label": "SFX ON", "color": Color("db2777"), "w": 0.95, "act": true, "nx": 0.78, "rank": 0, "icon": "sound"},
		{"id": "controls", "label": "CONTROLS", "color": Color("bef264"), "w": 1.00, "act": true, "nx": -0.36, "rank": 1, "icon": "controls"},
		{"id": "courses", "label": "LEVELS", "color": Color("4338ca"), "w": 1.04, "act": true, "nx": 0.36, "rank": 1, "icon": "courses"},
		{"id": "restart", "label": "RESTART", "color": Color("d97706"), "w": 1.14, "act": true, "nx": -0.22, "rank": 2, "icon": "restart"},
		{"id": "next", "label": "NEXT LEVEL", "color": Color("0284c7"), "w": 1.08, "act": true, "nx": 0.22, "rank": 2, "icon": "next"},
		{"id": "resume", "label": "RESUME", "color": Color("10b981"), "w": 1.24, "act": true, "nx": 0.0, "rank": 3, "icon": "play"},
		{"id": "d1", "label": "", "color": Color("10b981"), "w": 0.96, "act": false},
		{"id": "d2", "label": "", "color": Color("0284c7"), "w": 0.92, "act": false},
		{"id": "d3", "label": "", "color": Color("4338ca"), "w": 0.94, "act": false},
		{"id": "d4", "label": "", "color": Color("db2777"), "w": 0.90, "act": false},
		{"id": "d5", "label": "", "color": Color("bef264"), "w": 0.84, "act": false},
		{"id": "d6", "label": "", "color": Color("3b82f6"), "w": 0.88, "act": false},
		{"id": "d7", "label": "", "color": Color("10b981"), "w": 0.86, "act": false},
		{"id": "d8", "label": "", "color": Color("d97706"), "w": 0.82, "act": false},
		{"id": "d9", "label": "", "color": Color("db2777"), "w": 0.85, "act": false},
		{"id": "d10", "label": "", "color": Color("4338ca"), "w": 0.80, "act": false},
		{"id": "d11", "label": "", "color": Color("0284c7"), "w": 0.78, "act": false},
		{"id": "d12", "label": "", "color": Color("bef264"), "w": 0.76, "act": false},
		{"id": "d13", "label": "", "color": Color("ef4444"), "w": 0.75, "act": false},
		{"id": "d14", "label": "", "color": Color("10b981"), "w": 0.82, "act": false},
	]

	_pause_canvas.balls.clear()
	for s in specs:
		var b := PauseBall.new()
		b.id = s["id"]
		b.label = s["label"]
		b.color = s["color"]
		b.base_weight = s["w"]
		b.is_action = s["act"]
		b.anchor_norm_x = s.get("nx", 0.0)
		b.drop_rank = s.get("rank", 0)
		b.icon_type = s.get("icon", "")

		match b.id:
			"resume":
				b.on_select = func() -> void: resume_gameplay()
			"restart":
				b.on_select = func() -> void:
					_is_paused = false
					_pause_guard_until_ms = Time.get_ticks_msec() + 350
					_sync_visibility()
					reset_timer()
					restart_requested.emit()
					gameplay_resumed.emit()
			"next":
				b.on_select = func() -> void:
					_is_paused = false
					_pause_guard_until_ms = Time.get_ticks_msec() + 350
					_sync_visibility()
					reset_timer()
					next_level_requested.emit()
					gameplay_resumed.emit()
			"courses":
				b.on_select = func() -> void: _course_modal.visible = true
			"controls":
				b.on_select = func() -> void: _controls_modal.visible = true
			"sound":
				b.on_select = func() -> void:
					_is_muted = not _is_muted
					_sync_mute_ui()
					mute_toggled.emit(_is_muted)
			"title":
				b.on_select = func() -> void: open_title_screen()

		_pause_canvas.balls.append(b)

func _spawn_pause_balls_from_top() -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := vp.x
	var h := vp.y
	var target_fill_area := w * h * 0.50
	var total_weight_sq := 0.0
	for b in _pause_canvas.balls:
		total_weight_sq += b.base_weight * b.base_weight

	var unit_radius := clampf(sqrt(target_fill_area / (PI * total_weight_sq)), 52.0, 114.0)
	var center_x := w * 0.5
	var action_span := minf(w * 0.36, 440.0)
	var filler_spread := maxf(260.0, w - unit_radius * 2.2)

	var fillers: Array[PauseBall] = []
	for b in _pause_canvas.balls:
		if not b.is_action:
			fillers.append(b)
	fillers.shuffle()

	var filler_idx := 0
	for b in _pause_canvas.balls:
		b.radius = roundf(unit_radius * b.base_weight)
		b.scale_val = 1.0
		b.target_scale = 1.0
		if b.is_action:
			var target_x := center_x + b.anchor_norm_x * action_span
			b.home_x = target_x
			b.pos = Vector2(target_x, -b.radius - 40.0 - float(b.drop_rank) * (unit_radius * 2.15))
			b.vel = Vector2(0.0, 280.0)
			b.angle = 0.0
			b.v_angle = 0.0
		else:
			var slot := fillers.find(b)
			var norm := (float(slot) / float(max(1, fillers.size() - 1)) - 0.5) if fillers.size() > 1 else 0.0
			var flank := pow(norm * 2.0, 0.75) * 0.5 if norm >= 0.0 else -pow(-norm * 2.0, 0.75) * 0.5
			b.home_x = center_x + flank * filler_spread
			b.pos = Vector2(
				b.home_x + randf_range(-30.0, 30.0),
				-b.radius - 50.0 - float(filler_idx) * (unit_radius * 0.85) - randf_range(0.0, 45.0)
			)
			b.vel = Vector2(randf_range(-115.0, 115.0), randf_range(200.0, 350.0))
			b.angle = randf_range(-0.18, 0.18)
			b.v_angle = randf_range(-0.7, 0.7)
			filler_idx += 1

	_pause_canvas.hovered_id = ""
	_pause_canvas.pointer_pos = get_viewport().get_mouse_position()

func _step_pause_physics(delta: float) -> void:
	var dt := minf(0.033, delta)
	var vp := get_viewport().get_visible_rect().size
	var w := vp.x
	var h := vp.y
	var pad := 10.0
	var gravity := 2450.0
	var substeps := 5
	var sub_dt := dt / float(substeps)

	for _s in range(substeps):
		for b in _pause_canvas.balls:
			b.vel.y += gravity * sub_dt
			if b.is_action:
				var dx_home := b.home_x - b.pos.x
				b.vel.x += dx_home * 16.0 * sub_dt
				b.vel.x *= pow(0.18, sub_dt)

			b.pos += b.vel * sub_dt
			b.angle += b.v_angle * sub_dt

			if b.pos.x - b.radius < pad:
				b.pos.x = pad + b.radius
				b.vel.x = absf(b.vel.x) * 0.35
				b.v_angle = b.vel.y * 0.002
			elif b.pos.x + b.radius > w - pad:
				b.pos.x = w - pad - b.radius
				b.vel.x = -absf(b.vel.x) * 0.35
				b.v_angle = -b.vel.y * 0.002

			if b.pos.y + b.radius > h - pad:
				b.pos.y = h - pad - b.radius
				b.vel.y = -b.vel.y * (0.22 if b.is_action else 0.30)
				if absf(b.vel.y) < 30.0:
					b.vel.y = 0.0
				b.vel.x *= 0.78 if b.is_action else 0.87
				b.v_angle = b.vel.x / maxf(24.0, b.radius)

			b.v_angle += -b.angle * (14.0 if b.is_action else 9.5) * sub_dt
			b.v_angle *= 0.92

		var n := _pause_canvas.balls.size()
		for i in range(n):
			for j in range(i + 1, n):
				var a := _pause_canvas.balls[i]
				var b := _pause_canvas.balls[j]
				var diff := b.pos - a.pos
				var min_dist := a.radius + b.radius
				var dist_sq := diff.length_squared()
				if dist_sq < min_dist * min_dist:
					var dist := sqrt(dist_sq) if dist_sq > 0.0001 else 0.001
					var normal := diff / dist
					var overlap := min_dist - dist

					var mass_a := a.radius * a.radius * (1.85 if a.is_action else 1.0)
					var mass_b := b.radius * b.radius * (1.85 if b.is_action else 1.0)
					var inv_a := 1.0 / mass_a
					var inv_b := 1.0 / mass_b
					var inv_sum := inv_a + inv_b

					var corr := (maxf(0.0, overlap - 0.35) / inv_sum) * 0.84
					a.pos -= normal * corr * inv_a
					b.pos += normal * corr * inv_b

					var rel_vel := b.vel - a.vel
					var vn := rel_vel.dot(normal)
					if vn < 0.0:
						var rest := 0.2 if (a.is_action and b.is_action) else 0.3
						var imp := (-(1.0 + rest) * vn) / inv_sum
						a.vel -= normal * imp * inv_a
						b.vel += normal * imp * inv_b

						var tang := Vector2(-normal.y, normal.x)
						var vt := rel_vel.dot(tang)
						var f_imp := (-vt * 0.32) / inv_sum
						a.vel -= tang * f_imp * inv_a
						b.vel += tang * f_imp * inv_b

	for b in _pause_canvas.balls:
		b.scale_val = lerpf(b.scale_val, b.target_scale, minf(1.0, 18.0 * dt))
	_pause_canvas.queue_redraw()

# --- 6. Win Banner ---

func _build_win_banner() -> void:
	_win_banner = ColorRect.new()
	_win_banner.name = "WinBanner"
	_win_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_banner.color = Color(0.01, 0.02, 0.09, 0.78)
	_win_banner.visible = false
	add_child(_win_banner)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_banner.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var p_sb := _make_box_style(COL_PANEL_SURFACE, COL_INK, 22, 4, 10, COL_INK)
	p_sb.content_margin_left = 28
	p_sb.content_margin_right = 28
	p_sb.content_margin_top = 26
	p_sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", p_sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var eye := Label.new()
	eye.text = "COURSE CLEARED!"
	eye.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eye.add_theme_font_override("font", _font)
	eye.add_theme_font_size_override("font_size", 12)
	eye.add_theme_color_override("font_color", COL_GREEN)
	vbox.add_child(eye)

	var title := Label.new()
	title.text = "★ GOAL REACHED ★"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", COL_GOLD)
	vbox.add_child(title)

	_win_time_lbl = Label.new()
	_win_time_lbl.text = "Finish Time: 00:00.0"
	_win_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win_time_lbl.add_theme_font_override("font", _font)
	_win_time_lbl.add_theme_font_size_override("font_size", 16)
	_win_time_lbl.add_theme_color_override("font_color", Color("e2e8f0"))
	vbox.add_child(_win_time_lbl)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)

	var next_btn := _make_balatro_button("NEXT COURSE ▶", COL_GREEN, COL_GREEN_LIP, false)
	next_btn.pressed.connect(func() -> void:
		hide_win_banner()
		reset_timer()
		next_level_requested.emit()
		gameplay_resumed.emit()
	)
	row.add_child(next_btn)

	var replay_btn := _make_balatro_button("↻ REPLAY", COL_ORANGE, COL_ORANGE_LIP, false)
	replay_btn.pressed.connect(func() -> void:
		hide_win_banner()
		reset_timer()
		restart_requested.emit()
		gameplay_resumed.emit()
	)
	row.add_child(replay_btn)

	var title_btn := _make_balatro_button("⌂ TITLE", COL_SLATE, COL_PANEL_SURFACE, false)
	title_btn.pressed.connect(open_title_screen)
	row.add_child(title_btn)

# --- Process Loop (Timer, Stack Pill Spring Tweening, Dock Idle Wobble, Pause Physics) ---

func _process(delta: float) -> void:
	_elapsed_anim += delta

	# Gentle Balatro idle card wobble on the stack dock
	if _stack_dock != null and _hud_root.visible:
		_stack_dock.rotation = sin(_elapsed_anim * 1.15) * 0.007

	# Smooth spring-like interpolation for Stack Order pills
	var t := 1.0 - exp(-16.0 * delta)
	for id in _stack_pills:
		var entry: Dictionary = _stack_pills[id]
		var pill: PanelContainer = entry["panel"]
		pill.position = pill.position.lerp(entry["target_pos"], t)
		pill.scale = pill.scale.lerp(entry["target_scale"], t)

	if _is_paused and _pause_overlay.visible:
		_step_pause_physics(delta)
	elif not is_gameplay_blocked():
		_elapsed_seconds += delta
		_timer_lbl.text = _format_time(_elapsed_seconds)

# --- Public API ---

func set_reticle_locked(is_locked: bool) -> void:
	if _reticle == null:
		return
	_reticle.is_locked = is_locked
	
func update_stack_status(statuses: Array) -> void:
	var stacked_count := 0
	var ejected_ids: Array[int] = []
	var dead_ids: Array[int] = []

	for s in statuses:
		if s.get("is_dead", false):
			dead_ids.append(s["id"])
		elif s.get("is_stacked", true):
			stacked_count += 1
		else:
			ejected_ids.append(s["id"])

	const ROW_STEP := 54.0

	for s in statuses:
		var id: int = s["id"]
		if not _stack_pills.has(id):
			continue
		var entry: Dictionary = _stack_pills[id]
		var pill: PanelContainer = entry["panel"]
		var sb: StyleBoxFlat = entry["style"]
		var orb: StackOrbIcon = entry["orb"]
		var name_lbl: Label = entry["name_lbl"]
		var role_lbl: Label = entry["role_lbl"]
		var badge_lbl: Label = entry["badge_lbl"]
		var badge_sb: StyleBoxFlat = entry["badge_style"]

		var is_dead: bool = s.get("is_dead", false)
		var is_stacked: bool = s.get("is_stacked", true)
		var pos_idx: int = s.get("stack_pos", 0)

		orb.is_dead = is_dead
		orb.queue_redraw()

		if is_dead:
			var d_idx := dead_ids.find(id)
			var row_from_top := stacked_count + ejected_ids.size() + maxi(0, d_idx)
			entry["target_pos"] = Vector2(10.0, float(row_from_top) * ROW_STEP)
			entry["target_scale"] = Vector2(0.93, 0.93)
			pill.modulate = Color(1, 1, 1, 0.55)
			sb.bg_color = Color("090d16")
			sb.border_color = Color("475569")
			name_lbl.add_theme_color_override("font_color", Color("94a3b8"))
			role_lbl.text = "LOST IN VOID"
			role_lbl.add_theme_color_override("font_color", Color("f87171"))
			badge_lbl.text = "✕"
			badge_lbl.add_theme_color_override("font_color", Color("fca5a5"))
			badge_sb.bg_color = Color(0.50, 0.11, 0.11, 0.35)
		elif is_stacked:
			var row_from_top := stacked_count - 1 - pos_idx
			entry["target_pos"] = Vector2(0.0, float(row_from_top) * ROW_STEP)
			entry["target_scale"] = Vector2.ONE
			pill.modulate = Color.WHITE
			name_lbl.add_theme_color_override("font_color", COL_CREAM)
			badge_lbl.add_theme_color_override("font_color", Color("cbd5e1"))
			badge_sb.bg_color = Color(0.06, 0.09, 0.16, 0.85)

			if pos_idx == 0:
				sb.bg_color = Color("2d2a1e")
				sb.border_color = COL_GOLD
				role_lbl.text = "★ BASE DRIVER"
				role_lbl.add_theme_color_override("font_color", COL_GOLD)
				badge_lbl.text = "BOT"
			elif pos_idx == stacked_count - 1:
				sb.bg_color = COL_PANEL_SURFACE
				sb.border_color = COL_INK
				role_lbl.text = "TOP [E]"
				role_lbl.add_theme_color_override("font_color", Color("94a3b8"))
				badge_lbl.text = "TOP"
			else:
				sb.bg_color = COL_PANEL_SURFACE
				sb.border_color = COL_INK
				role_lbl.text = "MIDDLE"
				role_lbl.add_theme_color_override("font_color", Color("94a3b8"))
				badge_lbl.text = "MID"
		else:
			var e_idx := ejected_ids.find(id)
			var row_from_top := stacked_count + maxi(0, e_idx)
			entry["target_pos"] = Vector2(10.0, float(row_from_top) * ROW_STEP)
			entry["target_scale"] = Vector2(0.95, 0.95)
			pill.modulate = Color(1, 1, 1, 0.80)
			sb.bg_color = COL_INK
			sb.border_color = Color("64748b")
			name_lbl.add_theme_color_override("font_color", COL_CREAM)
			role_lbl.text = "OUT [R / F]"
			role_lbl.add_theme_color_override("font_color", COL_SKY)
			badge_lbl.text = "OUT"
			badge_lbl.add_theme_color_override("font_color", Color("cbd5e1"))
			badge_sb.bg_color = Color(0.06, 0.09, 0.16, 0.85)

func start_from_title(level_idx: int) -> void:
	_on_title_screen = false
	_is_paused = false
	_is_win_visible = false
	_pause_guard_until_ms = Time.get_ticks_msec() + 350
	_course_modal.visible = false
	_controls_modal.visible = false
	reset_timer()
	set_selected_level(level_idx)
	level_selected.emit(level_idx)
	_sync_visibility()
	gameplay_resumed.emit()

func open_title_screen() -> void:
	_on_title_screen = true
	_is_paused = false
	_is_win_visible = false
	_pause_guard_until_ms = Time.get_ticks_msec() + 350
	_course_modal.visible = false
	_controls_modal.visible = false
	reset_timer()
	restart_requested.emit()
	_sync_visibility()

func open_pause_menu() -> void:
	if _on_title_screen or _is_win_visible or _is_paused:
		return
	if Time.get_ticks_msec() < _pause_guard_until_ms:
		return
	_pause_guard_until_ms = Time.get_ticks_msec() + 350
	_is_paused = true
	_sync_visibility()
	_spawn_pause_balls_from_top()

func resume_gameplay() -> void:
	if not _is_paused:
		return
	if Time.get_ticks_msec() < _pause_guard_until_ms:
		return
	_pause_guard_until_ms = Time.get_ticks_msec() + 350
	_is_paused = false
	_course_modal.visible = false
	_controls_modal.visible = false
	_sync_visibility()
	gameplay_resumed.emit()

func toggle_pause() -> void:
	if _course_modal.visible:
		_course_modal.visible = false
		return
	if _controls_modal.visible:
		_controls_modal.visible = false
		return
	if _is_paused:
		resume_gameplay()
	elif not _on_title_screen and not _is_win_visible:
		open_pause_menu()

func is_gameplay_blocked() -> bool:
	return _is_paused or _on_title_screen or _is_win_visible

func set_selected_level(index: int) -> void:
	_selected_level_idx = clampi(index, 0, COURSES.size() - 1)
	var def: Dictionary = COURSES[_selected_level_idx]
	_course_lbl.text = def["name"]

	var pb_val: Variant = _pbs.get(def["id"], null)
	if pb_val != null:
		_pb_lbl.text = "PB: " + _format_time(float(pb_val))
		_pb_lbl.add_theme_color_override("font_color", COL_GREEN)
	else:
		_pb_lbl.text = "PB: --:--.-"
		_pb_lbl.add_theme_color_override("font_color", Color("64748b"))

	for i in range(_course_cards.size()):
		var c: Dictionary = _course_cards[i]
		var btn: Button = c["btn"]
		btn.add_theme_stylebox_override("normal", c["active_sb"] if i == _selected_level_idx else c["normal_sb"])

func show_win_banner() -> void:
	_is_win_visible = true
	_is_paused = false
	var def: Dictionary = COURSES[_selected_level_idx]
	var prev_pb: Variant = _pbs.get(def["id"], null)
	if prev_pb == null or _elapsed_seconds < float(prev_pb):
		_pbs[def["id"]] = _elapsed_seconds
		_save_pbs()
		_win_time_lbl.text = "Finish Time: %s  ★ NEW RECORD!" % _format_time(_elapsed_seconds)
		set_selected_level(_selected_level_idx)
		var card_pb: Label = _course_cards[_selected_level_idx]["pb_lbl"]
		card_pb.text = "PB: " + _format_time(_elapsed_seconds)
		card_pb.add_theme_color_override("font_color", COL_GREEN)
	else:
		_win_time_lbl.text = "Finish Time: %s  (PB: %s)" % [_format_time(_elapsed_seconds), _format_time(float(prev_pb))]
	_sync_visibility()

func hide_win_banner() -> void:
	_is_win_visible = false
	_sync_visibility()

func reset_timer() -> void:
	_elapsed_seconds = 0.0
	_timer_lbl.text = "00:00.0"

func _sync_visibility() -> void:
	_title_overlay.visible = _on_title_screen
	_pause_overlay.visible = _is_paused
	_win_banner.visible = _is_win_visible
	_hud_root.visible = not _on_title_screen

	var needs_cursor := _on_title_screen or _is_paused or _is_win_visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if needs_cursor else Input.MOUSE_MODE_CAPTURED

func _sync_mute_ui() -> void:
	_mute_btn.text = "MUTED" if _is_muted else "SFX ON"
	_pause_canvas.is_muted = _is_muted
	_pause_canvas.queue_redraw()

func _format_time(sec: float) -> String:
	var mins := int(floor(sec / 60.0))
	var rem := fmod(sec, 60.0)
	return "%02d:%04.1f" % [mins, rem]

func _load_pbs() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PB_SAVE_PATH) != OK:
		return {}
	var out := {}
	for key in cfg.get_section_keys("pbs"):
		out[int(key)] = float(cfg.get_value("pbs", key))
	return out

func _save_pbs() -> void:
	var cfg := ConfigFile.new()
	for id_key in _pbs:
		cfg.set_value("pbs", str(id_key), _pbs[id_key])
	cfg.save(PB_SAVE_PATH)

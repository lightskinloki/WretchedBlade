extends CanvasLayer
class_name BossHealthBar
# BossHealthBar.gd — boss fight health bar (BOSS_DESIGN.md Build Order step 7).
#
# Created by Game.gd when a boss spawns; binds to the boss's signals.
# Shows: boss title, tweened HP fill, phase threshold markers.
# Hides itself and queue_frees on boss death.

const BAR_W := 280.0
const BAR_H := 10.0
const BAR_Y := 24.0

var _bg: ColorRect
var _fill: ColorRect
var _damage_trail: ColorRect   # delayed white trail behind the fill
var _title: Label
var _markers: Array = []

var _max_hp := 1
var _target_frac := 1.0

func bind_boss(boss: BossEnemy, title_text: String) -> void:
	_max_hp = boss.blueprint.max_hp
	_build_ui(title_text, boss.blueprint)
	boss.health_changed.connect(_on_health_changed)
	boss.phase_changed.connect(_on_phase_changed)
	boss.boss_defeated.connect(_on_boss_defeated)
	boss.tree_exited.connect(func(): if is_instance_valid(self): queue_free())

func _build_ui(title_text: String, bp: BossBlueprint) -> void:
	var vp_w := 700.0
	var vp := get_viewport()
	if vp:
		vp_w = vp.get_visible_rect().size.x
	var bar_x := (vp_w - BAR_W) * 0.5

	_title = Label.new()
	_title.text = title_text
	_title.position = Vector2(bar_x, BAR_Y - 18.0)
	_title.size = Vector2(BAR_W, 16.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 10)
	_title.add_theme_color_override("font_color", Color(0.95, 0.9, 1.0, 0.95))
	add_child(_title)

	_bg = ColorRect.new()
	_bg.position = Vector2(bar_x, BAR_Y)
	_bg.size = Vector2(BAR_W, BAR_H)
	_bg.color = Color(0.08, 0.05, 0.12, 0.85)
	add_child(_bg)

	_damage_trail = ColorRect.new()
	_damage_trail.position = Vector2(bar_x + 1, BAR_Y + 1)
	_damage_trail.size = Vector2(BAR_W - 2, BAR_H - 2)
	_damage_trail.color = Color(0.9, 0.85, 0.8, 0.7)
	add_child(_damage_trail)

	_fill = ColorRect.new()
	_fill.position = Vector2(bar_x + 1, BAR_Y + 1)
	_fill.size = Vector2(BAR_W - 2, BAR_H - 2)
	var glow: Color = BossHexThemes.get_data(bp.hex_theme)["glow"]
	_fill.color = glow
	add_child(_fill)

	# Phase threshold markers
	var thresholds: Array = [bp.phase2_threshold]
	if bp.phase_count >= 3:
		thresholds.append(bp.phase3_threshold)
	for t in thresholds:
		var mark := ColorRect.new()
		mark.position = Vector2(bar_x + BAR_W * t - 1.0, BAR_Y - 2.0)
		mark.size = Vector2(2.0, BAR_H + 4.0)
		mark.color = Color(1.0, 1.0, 1.0, 0.6)
		add_child(mark)
		_markers.append(mark)

func _on_health_changed(hp: int, max_hp: int) -> void:
	_max_hp = max_hp
	_target_frac = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var t := create_tween()
	t.tween_property(_fill, "size:x", (BAR_W - 2.0) * _target_frac, 0.15)
	# Trail catches up slowly — classic souls-style damage feedback
	var t2 := create_tween()
	t2.tween_interval(0.4)
	t2.tween_property(_damage_trail, "size:x", (BAR_W - 2.0) * _target_frac, 0.4)

func _on_phase_changed(_phase: int) -> void:
	# Flash the title on phase transition
	if _title:
		_title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
		var t := create_tween()
		t.tween_interval(0.6)
		t.tween_callback(func():
			if is_instance_valid(_title):
				_title.add_theme_color_override("font_color", Color(0.95, 0.9, 1.0, 0.95)))

func _on_boss_defeated() -> void:
	var t := create_tween()
	t.tween_interval(0.6)
	t.tween_property(_bg, "modulate:a", 0.0, 0.5)
	t.parallel().tween_property(_fill, "modulate:a", 0.0, 0.5)
	t.parallel().tween_property(_damage_trail, "modulate:a", 0.0, 0.5)
	t.parallel().tween_property(_title, "modulate:a", 0.0, 0.5)
	for m in _markers:
		t.parallel().tween_property(m, "modulate:a", 0.0, 0.5)
	t.tween_callback(queue_free)

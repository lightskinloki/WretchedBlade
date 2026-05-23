extends CanvasLayer
# TransitionScreen.gd — handles room transition animations.
#
# Sequence: fade to black (0.4s) → room generates → purple flash pulse
# → "Room N" text → fade back in (0.4s)

@onready var black_overlay: ColorRect = $BlackOverlay
@onready var flash_rect:    ColorRect = $FlashRect
@onready var room_label:    Label     = $RoomLabel

const FADE_DURATION  := 0.4
const FLASH_DURATION := 0.25
const LABEL_HOLD     := 0.8

func _ready() -> void:
	black_overlay.modulate = Color.TRANSPARENT
	flash_rect.modulate    = Color.TRANSPARENT
	room_label.modulate.a  = 0.0

func fade_in() -> void:
	var t := create_tween()
	t.tween_property(black_overlay, "modulate:a", 1.0, FADE_DURATION)
	await t.finished

func fade_out() -> void:
	var t := create_tween()
	t.tween_property(black_overlay, "modulate:a", 0.0, FADE_DURATION)
	await t.finished

func flash_purple() -> void:
	var t := create_tween()
	t.tween_property(flash_rect, "modulate:a", 0.85, 0.08)
	t.tween_property(flash_rect, "modulate:a", 0.0, FLASH_DURATION)

func show_room_text(text: String) -> void:
	room_label.text = text
	var t := create_tween()
	t.tween_property(room_label, "modulate:a", 1.0, 0.2)
	t.tween_interval(LABEL_HOLD)
	t.tween_property(room_label, "modulate:a", 0.0, 0.3)
	await t.finished

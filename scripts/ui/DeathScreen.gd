extends CanvasLayer
# DeathScreen.gd — shown when the blade shatters.
#
# Mobile adaptation of the VR reconstitution mechanic:
#   In VR:     extend your hand → grip the controller → blade reforms → body reforms
#   On mobile: hold your thumb on the screen for 1.5 seconds
#
# The hold duration gives the player a moment of deliberate agency — not just a tap.
# This mirrors the lore: you CHOOSE to reconstitute.

const HOLD_REQUIRED := 1.5  # Seconds of continuous hold to reconstitute

@onready var you_died_label:    Label       = $YouDiedLabel
@onready var hold_prompt:       Label       = $HoldPrompt
@onready var hold_bar:          ProgressBar = $HoldBar
@onready var flash_rect:        ColorRect   = $FlashRect

var touch_count := 0
var hold_timer  := 0.0
var is_done     := false  # Prevent double-triggering

func _ready() -> void:
	visible          = false
	flash_rect.color = Color(0.4, 0.0, 0.7, 0.0)  # Starts transparent

func show_death_screen() -> void:
	visible  = true
	is_done  = false
	hold_timer = 0.0
	hold_bar.value = 0.0

	# Animate "YOU DIED" fading in
	you_died_label.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(you_died_label, "modulate:a", 1.0, 1.2)
	t.tween_property(hold_prompt,    "modulate:a", 1.0, 0.6)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		touch_count += 1 if event.pressed else -1
		touch_count = max(touch_count, 0)

func _process(delta: float) -> void:
	if not visible or is_done:
		return

	if touch_count > 0:
		hold_timer += delta
		hold_bar.value = (hold_timer / HOLD_REQUIRED) * 100.0
		if hold_timer >= HOLD_REQUIRED:
			_reconstitute()
	else:
		# Release hold → progress drains back (more forgiving drain rate)
		hold_timer = maxf(hold_timer - delta * 1.5, 0.0)
		hold_bar.value = (hold_timer / HOLD_REQUIRED) * 100.0

func _reconstitute() -> void:
	is_done    = true
	touch_count = 0

	# --- Reconstitution animation ---
	# Step 1: Purple flash (the blade reforms from Nullpulse energy)
	var t := create_tween()
	t.tween_property(flash_rect, "color", Color(0.5, 0.0, 0.8, 0.9), 0.15)
	t.tween_property(flash_rect, "color", Color(0.5, 0.0, 0.8, 0.0), 0.60)

	# Step 2: Hide UI, return control
	t.tween_callback(func():
		visible = false
		you_died_label.modulate.a = 0.0
		hold_prompt.modulate.a    = 0.0
		GameManager.on_reconstitution_complete()
	)

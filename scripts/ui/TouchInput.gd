extends CanvasLayer
# TouchInput.gd — virtual controls for Android.
#
# Left half of screen  → virtual joystick (movement)
# Right half of screen → ATK / JMP / DGE buttons
#
# This node emits signals. Game.gd calls connect_to_player() to wire them up.

# ── Signals ───────────────────────────────────────────────────────────────────
signal move_changed(direction: float)  # -1.0 … 1.0, fires continuously on drag (horizontal)
signal move_vertical_changed(direction: float)  # -1.0 … 1.0, fires continuously on drag (vertical)
signal jump_pressed                    # fires once per tap
signal attack_pressed
signal dodge_pressed

# ── Constants ─────────────────────────────────────────────────────────────────
const JOYSTICK_RADIUS := 64.0   # Half-size of joystick base (128px / 2)
const DEADZONE        := 0.18   # Ignore tiny nudges

# ── Node references ───────────────────────────────────────────────────────────
@onready var js_base:    Control = $JoystickZone/JoystickBase
@onready var js_thumb:   Control = $JoystickZone/JoystickBase/Thumb
@onready var btn_attack: Control = $ButtonZone/AttackButton
@onready var btn_jump:   Control = $ButtonZone/JumpButton
@onready var btn_dodge:  Control = $ButtonZone/DodgeButton

# ── Internal state ────────────────────────────────────────────────────────────
var js_active  := false
var js_finger  := -1
var js_origin  := Vector2.ZERO

# Maps finger index → which button it is currently holding
var held_btns: Dictionary = {}

# Center position of thumb inside the joystick base (computed in _ready)
var _thumb_center := Vector2.ZERO

func _ready() -> void:
	js_base.visible = false
	# The thumb center inside JoystickBase:
	# JoystickBase is 128×128; thumb is 48×48 → center at (64-24, 64-24) = (40, 40)
	_thumb_center = js_base.size / 2.0 - js_thumb.size / 2.0

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_finger_down(event.index, event.position)
		else:
			_finger_up(event.index)
	elif event is InputEventScreenDrag:
		_finger_drag(event.index, event.position)

# ── Touch handling ────────────────────────────────────────────────────────────
func _finger_down(idx: int, pos: Vector2) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.48

	if pos.x < half:
		# Left side — activate joystick centred on the finger
		if not js_active:
			js_active = true
			js_finger = idx
			js_origin = pos
			js_base.global_position = pos - js_base.size * 0.5
			js_thumb.position       = _thumb_center
			js_base.visible         = true
	else:
		# Right side — check button hit
		var btn := _button_at(pos)
		if btn != "":
			held_btns[idx] = btn
			_emit_press(btn)

func _finger_drag(idx: int, pos: Vector2) -> void:
	if idx != js_finger:
		return

	var drag    := pos - js_origin  # renamed: "offset" shadows CanvasLayer.offset
	var clamped := drag if drag.length() <= JOYSTICK_RADIUS \
						else drag.normalized() * JOYSTICK_RADIUS

	# Move thumb: centered at rest, displaced in direction of drag
	js_thumb.position = _thumb_center + clamped

	# Output -1..1 with deadzone
	var raw_x := clamped.x / JOYSTICK_RADIUS
	var raw_y := clamped.y / JOYSTICK_RADIUS
	emit_signal("move_changed", 0.0 if absf(raw_x) < DEADZONE else raw_x)
	emit_signal("move_vertical_changed", 0.0 if absf(raw_y) < DEADZONE else raw_y)

func _finger_up(idx: int) -> void:
	if idx == js_finger:
		js_active         = false
		js_finger         = -1
		js_thumb.position = _thumb_center  # Reset thumb to centre
		js_base.visible   = false
		emit_signal("move_changed", 0.0)
		emit_signal("move_vertical_changed", 0.0)

	if held_btns.has(idx):
		held_btns.erase(idx)

# ── Button detection ──────────────────────────────────────────────────────────
func _button_at(pos: Vector2) -> String:
	if _hit(btn_attack, pos): return "attack"
	if _hit(btn_jump,   pos): return "jump"
	if _hit(btn_dodge,  pos): return "dodge"
	return ""

func _hit(ctrl: Control, pos: Vector2) -> bool:
	return Rect2(ctrl.global_position, ctrl.size).has_point(pos)

func _emit_press(btn: String) -> void:
	match btn:
		"attack": emit_signal("attack_pressed")
		"jump":   emit_signal("jump_pressed")
		"dodge":  emit_signal("dodge_pressed")

# ── Wire up to player ─────────────────────────────────────────────────────────
# Called from Game.gd after both nodes are ready.
func connect_to_player(player: CharacterBody2D) -> void:
	move_changed.connect(player.set_move_input)
	move_vertical_changed.connect(player.set_move_vertical_input)
	jump_pressed.connect(func():   player.set_jump_input(true))
	attack_pressed.connect(func(): player.set_attack_input(true))
	dodge_pressed.connect(func():  player.set_dodge_input(true))

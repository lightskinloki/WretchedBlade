extends CanvasLayer
# HUD.gd — the heads-up display.
#
# NOTE: There is NO traditional health bar here.
# The blade sprite degrading visually IS the health feedback.
# The HUD shows: Essence count, current weapon form name, lost essence indicator, combo counter.

@onready var essence_label:      Label = $EssenceLabel
@onready var form_label:         Label = $FormLabel
@onready var lost_essence_label: Label = $LostEssenceLabel
@onready var combo_label:        Label = $ComboLabel

# Form display names (matches the WeaponForm enum order)
const FORM_NAMES := ["EXECUTIONER", "PHANTOM", "INFERNO", "HOLLOW"]

# Combo tracking
var combo_count := 0
var combo_timer := 0.0
const COMBO_TIMEOUT := 1.5

func _ready() -> void:
	EssenceManager.essence_changed.connect(_on_essence_changed)
	EssenceManager.lost_essence_spawned.connect(_on_lost_essence_spawned)
	EssenceManager.lost_essence_recovered.connect(_on_lost_essence_recovered)
	lost_essence_label.visible = false
	_on_essence_changed(0)
	combo_label.visible = false

func _process(delta: float) -> void:
	if combo_count > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			# Fade out after timeout
			combo_label.modulate.a = move_toward(combo_label.modulate.a, 0.0, delta * 2.0)
			if combo_label.modulate.a <= 0.01:
				combo_label.visible = false
				combo_count = 0

func _on_essence_changed(amount: int) -> void:
	essence_label.text = str(amount) + "  ESS"

func _on_lost_essence_spawned(_pos: Vector2) -> void:
	lost_essence_label.text    = str(EssenceManager.lost_essence) + " LOST"
	lost_essence_label.visible = true

func _on_lost_essence_recovered() -> void:
	lost_essence_label.visible = false

# Called by Game.gd when the player's blade form changes
func on_form_changed(form_idx: int) -> void:
	form_label.text = FORM_NAMES[form_idx] if form_idx < FORM_NAMES.size() else ""

# Called by Game.gd each time a hit connects
func on_hit_connected() -> void:
	combo_count += 1
	combo_timer = COMBO_TIMEOUT

	# Show combo label with milestone effects
	var text := str(combo_count) + " COMBO"
	combo_label.text = text
	combo_label.visible = true
	combo_label.modulate.a = 1.0

	# Milestone scaling
	if combo_count >= 15:
		combo_label.add_theme_font_size_override("font_size", 40)
		combo_label.modulate = Color(1.0, 0.3, 0.8, 1.0)
	elif combo_count >= 10:
		combo_label.add_theme_font_size_override("font_size", 36)
		combo_label.modulate = Color(1.0, 0.6, 0.2, 1.0)
	elif combo_count >= 5:
		combo_label.add_theme_font_size_override("font_size", 32)
		combo_label.modulate = Color(0.5, 0.8, 1.0, 1.0)
	else:
		combo_label.add_theme_font_size_override("font_size", 28)
		combo_label.modulate = Color.WHITE

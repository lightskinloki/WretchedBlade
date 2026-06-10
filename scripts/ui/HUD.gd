extends CanvasLayer
# HUD.gd — the heads-up display.
#
# NOTE: There is NO traditional health bar here.
# The blade sprite degrading visually IS the health feedback.
# The HUD shows: Essence count, current weapon form name, lost essence indicator,
# combo counter, hex inventory overlay, and first-unlock flash.

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

# Hex inventory overlay
var _hex_inventory_panel: ColorRect
var _hex_inventory_visible := false
var _hex_entry_labels: Array[RichTextLabel] = []

# First-unlock flash
var _unlock_flash: ColorRect
var _unlock_timer := 0.0
const UNLOCK_FLASH_DURATION := 4.0

func _ready() -> void:
	EssenceManager.essence_changed.connect(_on_essence_changed)
	EssenceManager.lost_essence_spawned.connect(_on_lost_essence_spawned)
	EssenceManager.lost_essence_recovered.connect(_on_lost_essence_recovered)
	lost_essence_label.visible = false
	_on_essence_changed(0)
	combo_label.visible = false

	_build_hex_inventory()
	_build_unlock_flash()

	HexManager.hex_unlocked.connect(_on_hex_unlocked)


func _process(delta: float) -> void:
	if combo_count > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo_label.modulate.a = move_toward(combo_label.modulate.a, 0.0, delta * 2.0)
			if combo_label.modulate.a <= 0.01:
				combo_label.visible = false
				combo_count = 0

	if _unlock_timer > 0.0:
		_unlock_timer -= delta
		if _unlock_timer <= 0.0:
			_unlock_flash.visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("hex_inventory"):
		_toggle_hex_inventory()
	elif event.is_action_pressed("ui_cancel"):
		if _hex_inventory_visible:
			_toggle_hex_inventory()


func _toggle_hex_inventory() -> void:
	_hex_inventory_visible = not _hex_inventory_visible
	_hex_inventory_panel.visible = _hex_inventory_visible
	if _hex_inventory_visible:
		_refresh_hex_entries()


func _build_hex_inventory() -> void:
	_hex_inventory_panel = ColorRect.new()
	_hex_inventory_panel.visible = false
	_hex_inventory_panel.anchor_right = 1.0
	_hex_inventory_panel.anchor_bottom = 1.0
	_hex_inventory_panel.color = Color(0.0, 0.0, 0.0, 0.85)
	_hex_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_hex_inventory_panel)

	var title := Label.new()
	title.text = "=== HEX ABILITIES ==="
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.size = Vector2(844, 30)
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(1.0, 0.6, 1.0, 1.0)
	_hex_inventory_panel.add_child(title)

	var close_hint := Label.new()
	close_hint.text = "Press V or ESC to close"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.position = Vector2(0, 50)
	close_hint.size = Vector2(844, 20)
	close_hint.modulate = Color(0.6, 0.6, 0.6, 1.0)
	_hex_inventory_panel.add_child(close_hint)


func _refresh_hex_entries() -> void:
	# Clear old entries
	for label in _hex_entry_labels:
		label.queue_free()
	_hex_entry_labels.clear()

	var y := 80
	var all_hexes: Array = HexManager.get_all_hexes()
	for hex in all_hexes:
		var entry := RichTextLabel.new()
		entry.position = Vector2(40, y)
		entry.size = Vector2(764, 140)
		entry.bbcode_enabled = true
		entry.scroll_active = false
		entry.fit_content = true
		entry.add_theme_font_size_override("normal_font_size", 14)

		var cooldown_info: String = ""
		if HexManager.is_on_cooldown(hex.id):
			var rem: float = snapped(HexManager.get_cooldown_remaining(hex.id), 0.1)
			cooldown_info = " [color=yellow]CD: %ss[/color]" % rem

		var essence_str: String = " [color=cyan]%d ESS[/color]" % hex.essence_cost

		entry.text = "[b][color=#cc66ff]%s[/color][/b]%s%s\n" % [hex.display_name, cooldown_info, essence_str]
		entry.text += "[color=#aaaaaa]Input: [color=#ffffff]%s[/color]\n" % _describe_input(hex.input_definition)
		entry.text += "Lore: %s[/color]" % hex.lore_blurb

		_hex_inventory_panel.add_child(entry)
		_hex_entry_labels.append(entry)
		y += 150


func _describe_input(def: Dictionary) -> String:
	match def.get("type", ""):
		"hold":
			var raw_btn = def.get("button", "?")
			var raw_dur = def.get("duration", 0.0)
			var btn: String
			var dur: float
			btn = raw_btn
			dur = raw_dur
			return "Hold [%s] for %.1fs then release" % [btn.to_upper(), dur]
		"combo":
			var seq = def.get("sequence", [])
			var parts: Array[String] = []
			for item in seq:
				if typeof(item) == TYPE_STRING:
					parts.append("[%s]" % item.to_upper())
				elif typeof(item) == TYPE_FLOAT:
					parts.append("(pause %.1fs)" % item)
			return " → ".join(parts)
		"sequence":
			var seq = def.get("sequence", [])
			var parts: Array[String] = []
			for item in seq:
				parts.append("[%s]" % str(item).to_upper())
			return " → ".join(parts)
		_:
			return str(def)


func _build_unlock_flash() -> void:
	_unlock_flash = ColorRect.new()
	_unlock_flash.visible = false
	_unlock_flash.anchor_right = 1.0
	_unlock_flash.anchor_bottom = 1.0
	_unlock_flash.color = Color(0.0, 0.0, 0.0, 0.75)
	_unlock_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_unlock_flash)


func _on_hex_unlocked(hex_id: String) -> void:
	var hex: HexAbility = HexManager.get_hex(hex_id)
	if hex == null:
		return

	# Clear old flash content
	for child in _unlock_flash.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "★ NEW HEX UNLOCKED ★"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 60)
	title.size = Vector2(844, 40)
	title.add_theme_font_size_override("font_size", 28)
	title.modulate = Color(1.0, 0.8, 0.2, 1.0)
	_unlock_flash.add_child(title)

	var name_label := Label.new()
	name_label.text = hex.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0, 110)
	name_label.size = Vector2(844, 30)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.modulate = Color(0.8, 0.4, 1.0, 1.0)
	_unlock_flash.add_child(name_label)

	var input_label := Label.new()
	input_label.text = "Input: " + _describe_input(hex.input_definition)
	input_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	input_label.position = Vector2(0, 150)
	input_label.size = Vector2(844, 24)
	input_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_unlock_flash.add_child(input_label)

	var lore_label := Label.new()
	lore_label.text = hex.lore_blurb
	lore_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lore_label.position = Vector2(50, 200)
	lore_label.size = Vector2(744, 200)
	lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore_label.modulate = Color(0.8, 0.8, 0.8, 1.0)
	_unlock_flash.add_child(lore_label)

	_unlock_flash.visible = true
	_unlock_timer = UNLOCK_FLASH_DURATION


# ── Existing HUD functions ─────────────────────────────────────────────────────────

func _on_essence_changed(amount: int) -> void:
	essence_label.text = str(amount) + "  ESS"

func _on_lost_essence_spawned(_pos: Vector2) -> void:
	lost_essence_label.text    = str(EssenceManager.lost_essence) + " LOST"
	lost_essence_label.visible = true

func _on_lost_essence_recovered() -> void:
	lost_essence_label.visible = false

func on_form_changed(form_idx: int) -> void:
	form_label.text = FORM_NAMES[form_idx] if form_idx < FORM_NAMES.size() else ""

func on_hit_connected() -> void:
	combo_count += 1
	combo_timer = COMBO_TIMEOUT

	var text := str(combo_count) + " COMBO"
	combo_label.text = text
	combo_label.visible = true
	combo_label.modulate.a = 1.0

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

extends Node2D
# CampsiteHub.gd — Ashen Sanctuary (The Central Campaign Hub)
# Built using the EXACT same procedural generation pipeline (DungeonGraph +
# RoomTerrainGenerator + WorldGenerator) as the rest of Wretched Blade.
# 100% consistent with the game's core architecture and procedural pixel art aesthetics.

@onready var world_container: Node2D = $World

var world_gen: WorldGenerator = null
var _player: CharacterBody2D = null
var _near_station: String = ""  # Currently hovered station ID

# UI elements
var _ui_layer: CanvasLayer
var _prompt_label: Label
var _modal_rect: ColorRect
var _modal_title: Label
var _modal_subtitle: Label
var _modal_text: Label
var _modal_vbox: VBoxContainer
var _is_modal_open: bool = false

func _ready() -> void:
	world_gen = WorldGenerator.new()
	add_child(world_gen)

	_generate_sanctuary_level()
	_build_hub_ui()

# ── Procedural Sanctuary Level Generation ────────────────────────────────────
# Uses DungeonGraph + RoomTerrainGenerator + WorldGenerator
func _generate_sanctuary_level() -> void:
	var env_data: Dictionary = CampsiteEnvironmentGenerator.build(world_container, 77777)
	var spawn_pos: Vector2 = env_data.get("spawn", Vector2(600.0, 360.0))
	var floor_spots: Array[Vector2] = env_data.get("floor_spots", [])
	var room_w: int = env_data.get("room_w", 76)

	_spawn_player(spawn_pos)
	_setup_stations(floor_spots, room_w)

func _find_floor_spots(grid: Array, w: int, h: int) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for x in range(3, w - 3, 2):
		for y in range(5, h - 1):
			if grid[y][x] == WorldGenerator.FLOOR and grid[y - 1][x] == WorldGenerator.EMPTY:
				var px := float(x * WorldGenerator.TILE_SIZE + WorldGenerator.TILE_SIZE / 2)
				var py := float((y - 1) * WorldGenerator.TILE_SIZE)
				spots.append(Vector2(px, py))
				break
	return spots

func _spawn_player(spawn_pos: Vector2) -> void:
	var player_scene := load("res://scenes/player/Player.tscn")
	if player_scene != null:
		_player = player_scene.instantiate()
		_player.global_position = spawn_pos
		world_container.add_child(_player)
		GameManager.checkpoint_position = spawn_pos

# ── Interactive Stations & NPC Triggers ───────────────────────────────────────
func _setup_stations(floor_spots: Array[Vector2], room_w: int) -> void:
	if floor_spots.size() < 6:
		push_warning("CampsiteHub: not enough floor spots for stations, using fallback math")
		var base_y := 280.0
		floor_spots = [
			Vector2(100.0, base_y),
			Vector2(220.0, base_y),
			Vector2(340.0, base_y),
			Vector2(440.0, base_y),
			Vector2(560.0, base_y),
			Vector2(660.0, base_y),
		]

	var num_spots := floor_spots.size()
	var spot_archives := floor_spots[int(num_spots * 0.08)]
	var spot_anvil    := floor_spots[int(num_spots * 0.28)]
	var spot_pool     := floor_spots[int(num_spots * 0.42)]
	var spot_hearth   := floor_spots[int(num_spots * 0.55)]
	var spot_merchant := floor_spots[int(num_spots * 0.72)]
	var spot_gate     := floor_spots[int(num_spots * 0.90)]

	# 1. Attunement Archives (Glass Frequency Scholar)
	_create_station_trigger("archives", spot_archives, Vector2(48.0, 48.0),
		"Attunement Archives", "Glass Frequency Scholar", Color(0.4, 0.85, 1.0, 0.9))

	# 2. The Iron Anvil (Cinder Forge-Mason)
	_create_station_trigger("anvil", spot_anvil, Vector2(48.0, 48.0),
		"The Iron Anvil", "Cinder Forge-Mason", Color(0.95, 0.7, 0.3, 0.9))

	# 3. Lineage Reflector (Pool of Projection)
	_create_station_trigger("pool", spot_pool, Vector2(48.0, 48.0),
		"Lineage Reflector", "Altar of Projection", Color(0.7, 0.6, 0.9, 0.9))

	# 4. The Ashen Hearth
	_create_station_trigger("hearth", spot_hearth, Vector2(64.0, 48.0),
		"The Ashen Hearth", "Sanctuary Rest Flame", Color(1.0, 0.45, 0.2, 0.9))

	# 5. The Fringe Alcove (Dross Scrap-Broker)
	_create_station_trigger("merchant", spot_merchant, Vector2(48.0, 48.0),
		"Fringe Alcove", "Dross Scrap-Broker", Color(0.85, 0.85, 0.4, 0.9))

	# 6. Overworld Gate Arch
	_create_station_trigger("overworld_gate", spot_gate, Vector2(64.0, 64.0),
		"Overworld Gate Arch", "Deployment Archway", Color(0.95, 0.35, 0.35, 0.9))

func _create_station_trigger(station_id: String, pos: Vector2, size: Vector2, title: String, subtitle: String, color: Color) -> void:
	# Trigger Area
	var area := Area2D.new()
	area.name = "Area_" + station_id
	area.monitoring = true
	area.monitorable = false
	area.collision_mask = 4  # Player layer

	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	area.add_child(cs)

	area.body_entered.connect(func(body: Node2D):
		if body.is_in_group("player"):
			_near_station = station_id
			_show_prompt("[ Press E ] — %s (%s)" % [title, subtitle], color)
	)
	area.body_exited.connect(func(body: Node2D):
		if body.is_in_group("player") and _near_station == station_id:
			_near_station = ""
			_hide_prompt()
	)

	world_container.add_child(area)
	area.position = pos

# ── Hub UI & Dialog System ───────────────────────────────────────────────────
func _build_hub_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 15

	# Interactive Prompt
	_prompt_label = Label.new()
	_prompt_label.position = Vector2(0, 325)
	_prompt_label.size = Vector2(844, 30)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 12)
	_prompt_label.visible = false
	_ui_layer.add_child(_prompt_label)

	# Modal Menu Container (Pixel-bordered dark glass style)
	_modal_rect = ColorRect.new()
	_modal_rect.color = Color(0.06, 0.05, 0.08, 0.95)
	_modal_rect.position = Vector2(172, 35)
	_modal_rect.size = Vector2(500, 320)
	_modal_rect.visible = false

	var modal_border := ReferenceRect.new()
	modal_border.size = _modal_rect.size
	modal_border.border_color = Color(0.6, 0.45, 0.25, 0.7)
	modal_border.border_width = 2.0
	_modal_rect.add_child(modal_border)

	var modal_vbox := VBoxContainer.new()
	modal_vbox.position = Vector2(20, 15)
	modal_vbox.size = Vector2(460, 290)
	modal_vbox.add_theme_constant_override("separation", 8)
	_modal_rect.add_child(modal_vbox)

	_modal_title = Label.new()
	_modal_title.add_theme_font_size_override("font_size", 16)
	_modal_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.75, 1.0))
	modal_vbox.add_child(_modal_title)

	_modal_subtitle = Label.new()
	_modal_subtitle.add_theme_font_size_override("font_size", 10)
	_modal_subtitle.add_theme_color_override("font_color", Color(0.7, 0.6, 0.5, 1.0))
	modal_vbox.add_child(_modal_subtitle)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 1)
	sep.color = Color(0.3, 0.25, 0.2, 0.5)
	modal_vbox.add_child(sep)

	_modal_text = Label.new()
	_modal_text.custom_minimum_size = Vector2(460, 80)
	_modal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_modal_text.add_theme_font_size_override("font_size", 10)
	_modal_text.add_theme_color_override("font_color", Color(0.8, 0.75, 0.7, 1.0))
	modal_vbox.add_child(_modal_text)

	_modal_vbox = VBoxContainer.new()
	_modal_vbox.custom_minimum_size = Vector2(460, 140)
	_modal_vbox.add_theme_constant_override("separation", 6)
	modal_vbox.add_child(_modal_vbox)

	_ui_layer.add_child(_modal_rect)
	add_child(_ui_layer)

func _show_prompt(text: String, color: Color) -> void:
	_prompt_label.text = text
	_prompt_label.add_theme_color_override("font_color", color)
	_prompt_label.visible = true

func _hide_prompt() -> void:
	_prompt_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if _is_modal_open:
		if event.is_action_pressed("ui_cancel"):
			_close_modal()
		return

	if event.is_action_pressed("interact") and _near_station != "":
		get_viewport().set_input_as_handled()
		_open_station_modal(_near_station)

# ── Station Modal Handlers ───────────────────────────────────────────────────
func _open_station_modal(station_id: String) -> void:
	_is_modal_open = true
	_hide_prompt()
	if _player != null:
		_player.velocity = Vector2.ZERO
		_player.set_physics_process(false)

	_clear_modal_buttons()

	match station_id:
		"hearth":
			_modal_title.text = "THE ASHEN HEARTH"
			_modal_subtitle.text = "Sanctuary Rest & Checkpoint"
			_modal_text.text = "The sacred flame burns quietly amidst the ruins. Resting here restores the Wretched Blade, refills all Whetstones, and anchors your soul."
			
			_add_modal_button("Rest at Hearth (Refill Whetstones & Heal)", func():
				GameManager.whetstone_charges = GameManager.max_whetstone_capacity
				if _player != null and _player.has_method("heal"):
					_player.heal()
				_close_modal()
			)
			_add_modal_button("Leave", func(): _close_modal())

		"anvil":
			_modal_title.text = "THE IRON ANVIL"
			_modal_subtitle.text = "Cinder Forge-Mason"
			_modal_text.text = "\"A blade is not a hero's tool; it is an executioner's edge. Bring me Essence from the fallen, and I will sharpen your true form.\""
			
			var edge_cost := GameManager.get_edge_upgrade_cost()
			_add_modal_button("Sharpen Blade Edge [Level %d] — Cost: %d Essence" % [GameManager.blade_edge_level, edge_cost], func():
				if GameManager.upgrade_blade_edge():
					_open_station_modal("anvil")
			)

			var poise_cost := GameManager.get_poise_upgrade_cost()
			_add_modal_button("Reinforce Poise [Level %d] — Cost: %d Essence" % [GameManager.poise_level, poise_cost], func():
				if GameManager.upgrade_poise():
					_open_station_modal("anvil")
			)

			if GameManager.max_whetstone_capacity < 5:
				var whet_cost := GameManager.get_whetstone_upgrade_cost()
				_add_modal_button("Expand Whetstone Pouch [%d -> %d] — Cost: %d Essence" % [GameManager.max_whetstone_capacity, GameManager.max_whetstone_capacity + 1, whet_cost], func():
					if GameManager.upgrade_whetstone_capacity():
						_open_station_modal("anvil")
				)

			_add_modal_button("Leave", func(): _close_modal())

		"archives":
			_modal_title.text = "ATTUNEMENT ARCHIVES"
			_modal_subtitle.text = "Glass Frequency Scholar"
			_modal_text.text = "\"You are the primordial scar of the 1st Hexocaust. Bring me the Tuning Forks of the Dominators, and we shall align the Nullpulse's natural song.\""
			
			_add_modal_button("Inspect Resonance Arts & Frequency Log", func():
				_modal_text.text = "Resonance Arts: None equipped.\nHex Affinity Score: %.1f (Uncorrupted)\nCollect Tuning Forks from region Mini-Bosses to unlock new frequencies." % GameManager.hex_affinity_score
			)
			_add_modal_button("Leave", func(): _close_modal())

		"pool":
			_modal_title.text = "LINEAGE REFLECTOR"
			_modal_subtitle.text = "Altar of Projection"
			_modal_text.text = "Look into the reflective waters to choose the lineage template for your Projected Body."

			var lineages := [
				["cinder", "Cinder (Geocrash Resilience: High Poise, Knockback Resist)"],
				["hollow", "Hollow (Void Scavenger: High Essence Yield, Low HP)"],
				["glass", "Glass (Crystalline Precision: High Crit Chance, Illusion Immunity)"],
				["marrow", "Marrow (Bio-Resilient Vigor: High Max HP, Status Resist)"],
				["dross", "Dross (Fringe Scavenger: Max Item Yield, Stealth Bonus)"],
			]

			for entry in lineages:
				var code: String = entry[0]
				var label: String = entry[1]
				var is_current := (GameManager.current_lineage == code)
				var button_text := ("> " if is_current else "") + label
				_add_modal_button(button_text, func():
					GameManager.set_lineage(code)
					_open_station_modal("pool")
				)

			_add_modal_button("Leave", func(): _close_modal())

		"merchant":
			_modal_title.text = "THE FRINGE ALCOVE"
			_modal_subtitle.text = "Dross Scrap-Broker"
			_modal_text.text = "\"Scrap from the Severed Lands. Grit for your edge, fragments of forgotten weapons. All has a price in Essence.\""
			
			_add_modal_button("Refill Whetstones — 50 Essence", func():
				if EssenceManager.spend_essence(50):
					GameManager.whetstone_charges = GameManager.max_whetstone_capacity
					GameManager.emit_signal("whetstone_refilled", GameManager.whetstone_charges)
			)
			_add_modal_button("Leave", func(): _close_modal())

		"overworld_gate":
			_modal_title.text = "OVERWORLD GATE ARCH"
			_modal_subtitle.text = "Deployment Archway"
			_modal_text.text = "Step through the ancient monumental arch to open the campaign overworld map and deploy to active region fronts."

			_add_modal_button("Deploy to Overworld Map", func():
				_close_modal()
				get_tree().change_scene_to_file("res://scenes/ui/OverworldMap.tscn")
			)
			_add_modal_button("Stay in Sanctuary", func(): _close_modal())

	_modal_rect.visible = true

func _add_modal_button(text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 10)
	btn.pressed.connect(callback)
	_modal_vbox.add_child(btn)

func _clear_modal_buttons() -> void:
	for child in _modal_vbox.get_children():
		child.queue_free()

func _close_modal() -> void:
	_modal_rect.visible = false
	_is_modal_open = false
	if _player != null:
		_player.set_physics_process(true)

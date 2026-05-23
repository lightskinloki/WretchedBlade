extends Node2D
# Game.gd â€” main scene with graph-based dungeon traversal.

@onready var world            = $World
@onready var player           = $Player
@onready var touch_input      = $TouchInput
@onready var hud              = $HUD
@onready var death_screen     = $DeathScreen
@onready var transition_screen = $TransitionScreen

var world_gen           := WorldGenerator.new()
var dungeon_generator   := DungeonGenerator.new()
var dungeon_graph:      DungeonGraph
var current_seed        := 0
var _current_node       := -1
var _previous_node      := -1
var _transitioning      := false
var _triggered_nodes:   Dictionary = {}  # int node_id -> bool
var _near_portal_node:  int = -1        # connected_node of nearby portal
var _exit_interact_prompt: Label
var _player_hurt_flash:    ColorRect
var _checkpoint_nodes:     Array[int] = []

const TILE_SIZE := 16

func _ready() -> void:
	add_child(world_gen)

	var blade = player.get_node("WretchedBlade")
	blade.form_changed.connect(hud.on_form_changed)
	blade.blade_shattered.connect(func(): death_screen.show_death_screen())
	blade.hit_connected.connect(hud.on_hit_connected)

	touch_input.connect_to_player(player)
	world.add_to_group("world")
	EssenceManager.lost_essence_spawned.connect(_on_lost_essence_spawned)

	_player_hurt_flash = ColorRect.new()
	_player_hurt_flash.color = Color(1.0, 0.0, 0.0, 0.0)
	_player_hurt_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var canvas := CanvasLayer.new()
	canvas.add_child(_player_hurt_flash)
	add_child(canvas)

	player.connect("player_hurt", _on_player_hurt)

	_exit_interact_prompt = Label.new()
	_exit_interact_prompt.text = ""
	_exit_interact_prompt.visible = false
	_exit_interact_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exit_interact_prompt.position = Vector2(300, 300)
	var prompt_canvas := CanvasLayer.new()
	prompt_canvas.add_child(_exit_interact_prompt)
	add_child(prompt_canvas)

	if not InputMap.has_action("interact"):
		var ie := InputEventKey.new()
		ie.keycode = KEY_E
		InputMap.add_action("interact")
		InputMap.action_add_event("interact", ie)

	_start_dungeon(randi())

# â”€â”€ Dungeon lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
func _start_dungeon(seed_val: int) -> void:
	current_seed = seed_val
	_current_node = -1
	_previous_node = -1
	_triggered_nodes = {}
	_checkpoint_nodes = []

	dungeon_graph = dungeon_generator.generate_graph({
		"seed": seed_val,
		"is_boss": false,
		"hex_theme": "geocrash",
		"difficulty": 0.4,
	})

	_checkpoint_nodes = dungeon_graph.meta.get("checkpoint_nodes", [])
	_current_node = dungeon_graph.get_start_node()
	_previous_node = -1

	_load_room(_current_node, _previous_node)

func _load_room(node_id: int, prev_node_id: int) -> void:
	if dungeon_graph == null or not dungeon_graph.has_node(node_id):
		return

	var node: DungeonGraph.RoomNode = dungeon_graph.get_node(node_id)
	print("=== _load_room node=%d archetype=%s w=%d h=%d prev=%d ===" % [node_id, RoomArchetype.get_archetype_name(node.archetype), node.room_w, node.room_h, prev_node_id])

	for child in world.get_children():
		child.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = current_seed + node_id
	var theme_str: String = dungeon_graph.meta.get("hex_theme", "geocrash")
	var theme := _theme_string_to_enum(theme_str)

	var grid: Array = world_gen.build_grid_for_graph_node(dungeon_graph, node_id, rng, theme)
	world_gen.build_room(grid, world, true)

	# Move player to safe spawn BEFORE adding kill triggers or enemies
	# so body_entered can't fire from the old position overlapping new hazards.
	var spawn_pos := _find_spawn_from_grid(grid, node, prev_node_id)
	print("  spawn_pos=(%d, %d) grid_rows=%d grid_cols=%d" % [spawn_pos.x, spawn_pos.y, grid.size(), grid[0].size() if grid.size() > 0 else 0])
	GameManager.set_checkpoint(spawn_pos)
	player.global_position = spawn_pos
	player.velocity = Vector2.ZERO

	world_gen.add_abyss_kill_trigger_for_room(world, node.room_w, node.room_h)

	# Place portal triggers for ALL portals (including back to previous room)
	for portal in node.portals:
		_place_portal_exit(node_id, portal, node)

	# Puzzle trigger
	if dungeon_graph.meta.has("trigger_node") and dungeon_graph.meta["trigger_node"] == node_id:
		_place_puzzle_trigger(node)

	# Spawn enemies
	_spawn_enemies_for_node(node, grid)

# â”€â”€ Enemy spawning â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
func _spawn_enemies_for_node(node: DungeonGraph.RoomNode, grid: Array = []) -> void:
	var arch := node.archetype
	var spec := DungeonPlan.make_room_spec()

	# Determine enemy count based on archetype
	var nullman := 0
	var rival := 0
	match arch:
		RoomArchetype.Archetype.SANCTUARY:
			nullman = 0
		RoomArchetype.Archetype.GUARD_POST:
			nullman = 2
			rival = 1
		RoomArchetype.Archetype.BRIDGE_SPAN:
			nullman = 1
		RoomArchetype.Archetype.STORAGE_VAULT:
			nullman = 2
		RoomArchetype.Archetype.RITUAL_CHAMBER:
			rival = 1
		RoomArchetype.Archetype.COLLAPSED_HALL:
			nullman = 2
			rival = 1
		RoomArchetype.Archetype.WATCHTOWER:
			nullman = 1
		RoomArchetype.Archetype.QUARRY:
			nullman = 3
		_:
			nullman = 1

	# Boss room gets a champion
	if node.node_id == dungeon_graph.get_end_node():
		spec["has_champion"] = true
		nullman = 0
		rival = 0

	spec["enemies"] = {"nullman": nullman, "rival": rival}
	spec["room_w"] = node.room_w
	spec["room_h"] = node.room_h
	spec["grid"] = grid
	world_gen.spawn_enemies_from_spec(world, spec)

# â”€â”€ Portal exit system â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
func _place_portal_exit(_node_id: int, portal: RoomArchetype.PortalData, node: DungeonGraph.RoomNode) -> void:
	var slot_def := _find_slot_def(node.archetype, portal.slot_id)
	if slot_def == null:
		return

	var pos: Vector2i = slot_def.get_tile_position(node.room_w, node.room_h)
	# The bottom 2 rows of every portal slot are floor tiles, not walkable air.
	# Use only the air portion for the glow and blocking wall.
	var air_tiles := slot_def.tile_h - 2
	var door_w := float(slot_def.tile_w) * float(TILE_SIZE)
	var door_h := float(air_tiles) * float(TILE_SIZE)
	var cx := (float(pos.x) + float(slot_def.tile_w) * 0.5) * float(TILE_SIZE)
	var cy := (float(pos.y) + float(air_tiles) * 0.5) * float(TILE_SIZE)

	# Invisible wall blocking the doorway (air opening only — floor tiles cover the rest)
	var wall := StaticBody2D.new()
	wall.name = "PortalWall_%d" % portal.connected_node
	var wall_shape := CollisionShape2D.new()
	var wall_rect := RectangleShape2D.new()
	wall_rect.size = Vector2(door_w, door_h)
	wall_shape.shape = wall_rect
	wall.add_child(wall_shape)
	wall.position = Vector2(cx, cy)
	world.add_child(wall)

	# Visual glow indicator at doorway
	var glow_img := Image.create(int(door_w), int(door_h), false, Image.FORMAT_RGBA8)
	glow_img.fill(Color(0.2, 0.6, 1.0, 0.5))
	var glow_tex := ImageTexture.create_from_image(glow_img)
	var glow := Sprite2D.new()
	glow.name = "PortalGlow_%d" % portal.connected_node
	glow.texture = glow_tex
	glow.position = Vector2(cx, cy)
	world.add_child(glow)
	var tw := glow.create_tween().set_loops()
	tw.tween_property(glow, "modulate", Color(1, 1, 1, 0.8), 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(glow, "modulate", Color(1, 1, 1, 0.4), 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Detection zone: 1 tile wider than the wall, shifted inward so the player
	# is inside it when they walk up to the portal wall (wall stops them at the edge).
	var area := Area2D.new()
	area.name = "PortalArea_%d" % portal.connected_node
	area.monitoring  = true
	area.monitorable = false
	area.collision_mask = 4  # Detect player on layer 3

	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(door_w + float(TILE_SIZE), door_h)
	cs.shape = rect
	area.add_child(cs)

	var portal_connected := portal.connected_node
	var inward := 1.0 if slot_def.side == "left" else -1.0
	area.position = Vector2(cx + inward * float(TILE_SIZE) * 0.5, cy)

	area.body_entered.connect(func(body: Node2D):
		if body.is_in_group("player"):
			_near_portal_node = portal_connected
			_show_portal_prompt(portal_connected)
	)
	area.body_exited.connect(func(body: Node2D):
		if body.is_in_group("player"):
			_near_portal_node = -1
			_hide_portal_prompt()
	)

	world.add_child(area)

func _find_slot_def(archetype: int, slot_id: String) -> RoomArchetype.PortalSlot:
	var slots := RoomArchetype.get_available_portal_slots(archetype)
	for s in slots:
		if s.slot_id == slot_id:
			return s
	return null

func _show_portal_prompt(connected_node: int) -> void:
	if dungeon_graph == null:
		return
	# Check if this portal is locked
	var node: DungeonGraph.RoomNode = dungeon_graph.get_node(_current_node)
	if node == null:
		return
	for p in node.portals:
		if p.connected_node == connected_node and not p.is_open:
			_exit_interact_prompt.text = "Locked"
			_exit_interact_prompt.visible = true
			return
	_exit_interact_prompt.text = "Press E to enter"
	_exit_interact_prompt.visible = true

func _hide_portal_prompt() -> void:
	_exit_interact_prompt.text = ""
	_exit_interact_prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _near_portal_node >= 0:
		get_viewport().set_input_as_handled()
		_attempt_portal_transition(_near_portal_node)

# â”€â”€ Portal transition â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
func _attempt_portal_transition(target_node: int) -> void:
	if _transitioning or dungeon_graph == null:
		return

	var node: DungeonGraph.RoomNode = dungeon_graph.get_node(_current_node)
	if node == null:
		return

	# Check lock
	var target_locked := false
	for p in node.portals:
		if p.connected_node == target_node and not p.is_open:
			target_locked = true
			break

	if target_locked:
		return

	_transitioning = true
	var prev := _current_node

	# Freeze player physics before the fade so no velocity accumulates during blackout
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)

	await transition_screen.fade_in()
	_current_node = target_node
	_previous_node = prev
	_load_room(_current_node, _previous_node)

	# Re-enable physics after the room is built and player is placed
	player.set_physics_process(true)

	transition_screen.flash_purple()
	await transition_screen.show_room_text(_room_label_for(target_node))
	await transition_screen.fade_out()
	_transitioning = false

# â”€â”€ Puzzle trigger system â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
func _place_puzzle_trigger(node: DungeonGraph.RoomNode) -> void:
	var area := Area2D.new()
	area.name = "PuzzleTrigger"
	area.collision_mask = 4  # Detect player on layer 3

	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# Span the full walkable floor so the player can't bypass the trigger
	var trigger_w := float(node.room_w - 6) * float(TILE_SIZE)
	rect.size = Vector2(trigger_w, float(TILE_SIZE) * 3.0)
	cs.shape = rect
	area.add_child(cs)

	var cx := float(node.room_w) * float(TILE_SIZE) * 0.5
	var floor_y := node.room_h - 4
	var cy := float(floor_y - 1) * float(TILE_SIZE)
	area.position = Vector2(cx, cy)

	# Visual indicator: pressure plate sprite at center of trigger
	var plate_sprite := Sprite2D.new()
	plate_sprite.texture = PixelRenderer.generate_tile_texture(PixelRenderer.TileType.PRESSURE_PLATE, 8)
	plate_sprite.scale = Vector2(2.0, 2.0)
	plate_sprite.position = Vector2.ZERO
	area.add_child(plate_sprite)

	var trigger_nid := node.node_id
	area.body_entered.connect(func(body: Node2D):
		if body.is_in_group("player") and not _triggered_nodes.get(trigger_nid, false):
			_triggered_nodes[trigger_nid] = true
			_on_trigger_activated(trigger_nid)
			# Visual feedback: plate depresses
			var tween := plate_sprite.create_tween()
			tween.tween_property(plate_sprite, "scale", Vector2(2.2, 1.2), 0.08)
			tween.tween_property(plate_sprite, "modulate", Color(0.6, 1.0, 0.6, 1.0), 0.15)
	)

	world.add_child(area)

func _on_trigger_activated(_node_id: int) -> void:
	# Find and unlock the locked portal stored in graph meta
	var lock_from: int = dungeon_graph.meta.get("lock_from", -1)
	var lock_to: int = dungeon_graph.meta.get("lock_to", -1)
	if lock_from >= 0 and lock_to >= 0:
		dungeon_graph.unlock_portal(lock_from, lock_to)

	if _near_portal_node >= 0:
		_show_portal_prompt(_near_portal_node)

# â”€â”€ Spawn / entry position â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
func _find_spawn_from_grid(grid: Array, node: DungeonGraph.RoomNode, prev_node_id: int) -> Vector2:
	var w := node.room_w
	var h := node.room_h

	# If entering from a previous room, spawn inward from that portal
	if prev_node_id >= 0:
		for portal in node.portals:
			if portal.connected_node == prev_node_id:
				var slot := _find_slot_def(node.archetype, portal.slot_id)
				if slot != null:
					var pos := slot.get_tile_position(w, h)
					var portal_floor := pos.y + slot.tile_h - 2
					var inward := 1 if slot.side == "left" else -1
					var start_x: int
					if inward > 0:
						start_x = pos.x + slot.tile_w + 1
					else:
						start_x = pos.x - 2
					var safe := _scan_safe_spawn(grid, start_x, portal_floor, inward, w, h)
					if safe.x >= 0:
						return Vector2((float(safe.x) + 0.5) * float(TILE_SIZE), (float(safe.y) - 1.0) * float(TILE_SIZE))

	# First room or fallback: scan from the room's own portals
	for portal in node.portals:
		var slot := _find_slot_def(node.archetype, portal.slot_id)
		if slot != null:
			var pos := slot.get_tile_position(w, h)
			var portal_floor := pos.y + slot.tile_h - 2
			var inward := 1 if slot.side == "left" else -1
			var start_x: int
			if inward > 0:
				start_x = pos.x + slot.tile_w + 1
			else:
				start_x = pos.x - 2
			var safe := _scan_safe_spawn(grid, start_x, portal_floor, inward, w, h)
			if safe.x >= 0:
				return Vector2((float(safe.x) + 0.5) * float(TILE_SIZE), (float(safe.y) - 1.0) * float(TILE_SIZE))

	# Absolute fallback: hardcoded center
	return Vector2(float(TILE_SIZE) * 4.0, float(h - 6) * float(TILE_SIZE))

# Scans the grid for a column where grid[fy][tx] == FLOOR and grid[fy-1][tx] == EMPTY.
# Starts at start_x and moves in direction dx, covering the full room width.
# Returns Vector2i(column, floor_row) or (-1, -1) if nothing found.
static func _scan_safe_spawn(grid: Array, start_x: int, target_floor_y: int, dx: int, w: int, h: int) -> Vector2i:
	var max_steps := w
	for step in range(max_steps):
		var tx := start_x + step * dx
		if tx < 1 or tx >= w - 1:
			continue
		for fy in range(maxi(2, target_floor_y - 4), mini(h - 1, target_floor_y + 5)):
			if fy > 0 and grid[fy][tx] == 1 and grid[fy - 1][tx] == 0:
				return Vector2i(tx, fy)
	return Vector2i(-1, -1)

# â”€â”€ Room label â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
func _room_label_for(node_id: int) -> String:
	if dungeon_graph == null or not dungeon_graph.has_node(node_id):
		return ""
	var n: DungeonGraph.RoomNode = dungeon_graph.get_node(node_id)
	if n == null:
		return ""
	var room_name := RoomArchetype.get_archetype_name(n.archetype)
	var label := "- " + room_name + " -"
	if n.node_id == dungeon_graph.get_end_node():
		if dungeon_graph.meta.get("is_boss", false):
			label = "[ BOSS ]"
		else:
			label = "[ EXIT ]"
	return label

# â”€â”€ Theme helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
static func _theme_string_to_enum(theme: String) -> int:
	match theme.to_lower():
		"geocrash":     return RegionTheme.HexTheme.GEOCRASH
		"voidrend":     return RegionTheme.HexTheme.VOIDREND
		"echoscream":   return RegionTheme.HexTheme.ECHOSCREAM
		"memoreave":    return RegionTheme.HexTheme.MEMOREAVE
		"nullpulse":    return RegionTheme.HexTheme.NULLPULSE
		"technomantic": return RegionTheme.HexTheme.TECHNOMANTIC
	return RegionTheme.HexTheme.GEOCRASH

# â”€â”€ Lost essence â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
func _on_lost_essence_spawned(pos: Vector2) -> void:
	var orb = load("res://scenes/world/LostEssenceOrb.tscn").instantiate()
	orb.position = pos
	world.call_deferred("add_child", orb)

func _on_player_hurt() -> void:
	_player_hurt_flash.color.a = 0.4
	var t := create_tween()
	t.tween_property(_player_hurt_flash, "color:a", 0.0, 0.3)

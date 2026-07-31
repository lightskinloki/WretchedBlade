extends Node2D
# OverworldMap.gd — Interactive Overworld Campaign Map
# Rich procedural dark aesthetic: atmospheric hex background, ember particles,
# animated energy paths, hexagonal region seals, and detailed region panel.

const NODE_RADIUS := 20.0
const NODE_RADIUS_SELECTED := 26.0
const CONNECTION_WIDTH := 3.0

# Theme color palettes (Primary, Glow, Background Ambient)
const THEME_DATA := {
	"geocrash": {
		"primary": Color(0.95, 0.75, 0.30, 1.0),   # Earthen Amber
		"secondary": Color(0.55, 0.40, 0.22, 1.0), # Rust Brown
		"glow": Color(1.00, 0.85, 0.40, 0.8),
		"bg": Color(0.12, 0.08, 0.05, 1.0),
		"dominator": "The Shattered Sovereign",
	},
	"voidrend": {
		"primary": Color(0.70, 0.30, 1.00, 1.0),   # Void Purple
		"secondary": Color(0.20, 0.85, 0.40, 1.0), # Sickle Green Accent
		"glow": Color(0.80, 0.40, 1.00, 0.8),
		"bg": Color(0.06, 0.04, 0.12, 1.0),
		"dominator": "The Void Echo",
	},
	"echoscream": {
		"primary": Color(0.40, 0.85, 1.00, 1.0),   # Resonance Cyan
		"secondary": Color(0.85, 0.90, 0.95, 1.0), # Silver White
		"glow": Color(0.55, 0.95, 1.00, 0.8),
		"bg": Color(0.05, 0.09, 0.13, 1.0),
		"dominator": "The Screaming Spire",
	},
	"memoreave": {
		"primary": Color(0.95, 0.55, 0.80, 1.0),   # Memory Sepia Pink
		"secondary": Color(0.60, 0.35, 0.85, 1.0), # Violet Deep
		"glow": Color(0.98, 0.65, 0.90, 0.8),
		"bg": Color(0.12, 0.06, 0.11, 1.0),
		"dominator": "The Memory Thief",
	},
	"nullpulse": {
		"primary": Color(1.00, 0.30, 0.35, 1.0),   # Null Crimson
		"secondary": Color(0.95, 0.95, 0.95, 1.0), # White Void
		"glow": Color(1.00, 0.40, 0.45, 0.8),
		"bg": Color(0.09, 0.04, 0.06, 1.0),
		"dominator": "The Nullpulse Heart",
	},
	"technomantic": {
		"primary": Color(1.00, 0.65, 0.20, 1.0),   # Industrial Orange
		"secondary": Color(0.30, 0.70, 0.95, 1.0), # Electric Blue
		"glow": Color(1.00, 0.75, 0.30, 0.8),
		"bg": Color(0.08, 0.09, 0.07, 1.0),
		"dominator": "The Rust Tyrant",
	},
}

var _graph: OverworldGraph = null
var _selected_node_id: int = 0
var _selection_pulse: float = 0.0
var _bg_glow_target: Color = Color(0.06, 0.05, 0.08, 1.0)
var _bg_glow_current: Color = Color(0.06, 0.05, 0.08, 1.0)

# Ambient particles
var _particles: Array[Dictionary] = []
const NUM_PARTICLES := 40

# UI elements
var _bg_rect: ColorRect
var _title_label: Label
var _subtitle_label: Label
var _detail_panel: ColorRect
var _detail_border: ReferenceRect
var _detail_name: Label
var _detail_dominator: Label
var _detail_theme: Label
var _detail_difficulty: Label
var _detail_status: Label
var _detail_lore: Label
var _prompt_button: ColorRect
var _prompt_label: Label

func _ready() -> void:
	_graph = GameManager.overworld_graph
	if _graph == null:
		push_error("OverworldMap: no overworld graph in GameManager")
		return

	# Find starting selection — first unlocked non-cleared node, or campsite
	_selected_node_id = _graph.start_node_id
	for nid in _graph.nodes:
		var node: OverworldGraph.OverworldNode = _graph.nodes[nid]
		if node.unlocked and not node.cleared:
			_selected_node_id = nid
			break

	_init_particles()
	_build_ui()
	_update_detail_panel()

	# Register input actions
	if not InputMap.has_action("interact"):
		var ie := InputEventKey.new()
		ie.keycode = KEY_E
		InputMap.add_action("interact")
		InputMap.action_add_event("interact", ie)

func _init_particles() -> void:
	_particles.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(NUM_PARTICLES):
		_particles.append({
			"pos": Vector2(rng.randf_range(0, 844), rng.randf_range(0, 390)),
			"speed": rng.randf_range(12.0, 28.0),
			"size": rng.randf_range(1.5, 3.5),
			"alpha": rng.randf_range(0.2, 0.6),
			"drift": rng.randf_range(-6.0, 6.0),
		})

func _build_ui() -> void:
	# Full-screen dark background layer
	_bg_rect = ColorRect.new()
	_bg_rect.color = Color(0.06, 0.05, 0.08, 1.0)
	_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg_canvas := CanvasLayer.new()
	bg_canvas.layer = -1
	bg_canvas.add_child(_bg_rect)
	add_child(bg_canvas)

	# UI Overlay Canvas
	var ui_canvas := CanvasLayer.new()
	ui_canvas.layer = 10

	# Header Title & Subtitle
	var header_container := VBoxContainer.new()
	header_container.position = Vector2(0, 10)
	header_container.size = Vector2(540, 50)
	header_container.alignment = BoxContainer.ALIGNMENT_CENTER

	_title_label = Label.new()
	_title_label.text = "THE SEVERED LANDS"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(0.90, 0.82, 0.70, 1.0))
	header_container.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.text = "— CAMPAIGN REGION SELECTOR —"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 9)
	_subtitle_label.add_theme_color_override("font_color", Color(0.50, 0.45, 0.40, 1.0))
	header_container.add_child(_subtitle_label)

	ui_canvas.add_child(header_container)

	# Detail Panel (Right Side — Sleek Dark Glass Style)
	_detail_panel = ColorRect.new()
	_detail_panel.color = Color(0.07, 0.06, 0.09, 0.94)
	_detail_panel.position = Vector2(550, 20)
	_detail_panel.size = Vector2(280, 350)
	ui_canvas.add_child(_detail_panel)

	# Panel Border Accent
	_detail_border = ReferenceRect.new()
	_detail_border.size = _detail_panel.size
	_detail_border.border_color = Color(0.6, 0.45, 0.25, 0.6)
	_detail_border.border_width = 1.5
	_detail_panel.add_child(_detail_border)

	# Panel Contents VBox
	var content_vbox := VBoxContainer.new()
	content_vbox.position = Vector2(14, 12)
	content_vbox.size = Vector2(252, 326)
	content_vbox.add_theme_constant_override("separation", 6)
	_detail_panel.add_child(content_vbox)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 15)
	_detail_name.add_theme_color_override("font_color", Color(1.0, 0.92, 0.80, 1.0))
	content_vbox.add_child(_detail_name)

	_detail_dominator = Label.new()
	_detail_dominator.add_theme_font_size_override("font_size", 10)
	_detail_dominator.add_theme_color_override("font_color", Color(0.85, 0.65, 0.35, 1.0))
	content_vbox.add_child(_detail_dominator)

	_detail_theme = Label.new()
	_detail_theme.add_theme_font_size_override("font_size", 10)
	content_vbox.add_child(_detail_theme)

	_detail_difficulty = Label.new()
	_detail_difficulty.add_theme_font_size_override("font_size", 10)
	_detail_difficulty.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4, 1.0))
	content_vbox.add_child(_detail_difficulty)

	_detail_status = Label.new()
	_detail_status.add_theme_font_size_override("font_size", 10)
	content_vbox.add_child(_detail_status)

	var h_sep := ColorRect.new()
	h_sep.custom_minimum_size = Vector2(0, 1)
	h_sep.color = Color(0.3, 0.25, 0.2, 0.4)
	content_vbox.add_child(h_sep)

	_detail_lore = Label.new()
	_detail_lore.custom_minimum_size = Vector2(252, 130)
	_detail_lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_lore.add_theme_font_size_override("font_size", 9)
	_detail_lore.add_theme_color_override("font_color", Color(0.70, 0.65, 0.60, 1.0))
	content_vbox.add_child(_detail_lore)

	# Action Button Container at panel bottom
	_prompt_button = ColorRect.new()
	_prompt_button.custom_minimum_size = Vector2(252, 34)
	_prompt_button.color = Color(0.20, 0.15, 0.10, 0.9)
	content_vbox.add_child(_prompt_button)

	_prompt_label = Label.new()
	_prompt_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 11)
	_prompt_button.add_child(_prompt_label)

	add_child(ui_canvas)

func _update_detail_panel() -> void:
	if _graph == null:
		return
	var node: OverworldGraph.OverworldNode = _graph.get_node(_selected_node_id)
	if node == null:
		return

	var theme_info: Dictionary = THEME_DATA.get(node.hex_theme, THEME_DATA["geocrash"])
	var theme_color: Color = theme_info["primary"]
	_bg_glow_target = theme_info["bg"]

	_detail_name.text = node.display_name.to_upper()
	_detail_dominator.text = "Dominator: %s" % theme_info["dominator"]
	_detail_theme.text = "Hex Affliction: %s" % node.hex_theme.to_upper()
	_detail_theme.add_theme_color_override("font_color", theme_color)

	# Difficulty stars
	var stars := int(node.difficulty * 5.0)
	var star_str := ""
	for i in range(5):
		star_str += "★" if i < stars else "☆"
	_detail_difficulty.text = "Resonance Hazard: %s (%d%%)" % [star_str, int(node.difficulty * 100.0)]

	# Status
	if node.cleared:
		_detail_status.text = "Status: CLEARED (Resonance Secured)"
		_detail_status.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5, 1.0))
	elif node.unlocked:
		_detail_status.text = "Status: UNLOCKED (Active Breach)"
		_detail_status.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	else:
		_detail_status.text = "Status: LOCKED (Dominator Seal)"
		_detail_status.add_theme_color_override("font_color", Color(0.6, 0.25, 0.25, 1.0))

	_detail_lore.text = node.lore_blurb

	# Panel Border Accent color
	_detail_border.border_color = theme_color * 0.7

	# Prompt Button
	if node.unlocked and not node.cleared:
		_prompt_label.text = "[ PRESS E TO DEPLOY ]"
		_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85, 1.0))
		_prompt_button.color = theme_color * 0.35
	elif node.cleared:
		_prompt_label.text = "[ REVISIT REGION — PRESS E ]"
		_prompt_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7, 1.0))
		_prompt_button.color = Color(0.12, 0.22, 0.14, 0.8)
	else:
		_prompt_label.text = "[ SEALED REGION ]"
		_prompt_label.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3, 1.0))
		_prompt_button.color = Color(0.15, 0.08, 0.08, 0.8)

func _process(delta: float) -> void:
	_selection_pulse += delta * 3.5
	_bg_glow_current = _bg_glow_current.lerp(_bg_glow_target, delta * 2.0)
	if _bg_rect != null:
		_bg_rect.color = _bg_glow_current

	# Update particles
	for p in _particles:
		p["pos"].y -= p["speed"] * delta
		p["pos"].x += p["drift"] * delta
		if p["pos"].y < -10:
			p["pos"].y = 400
			p["pos"].x = randf_range(0, 844)

	queue_redraw()

func _draw() -> void:
	if _graph == null:
		return

	# 1. Background Particles
	for p in _particles:
		draw_circle(p["pos"], p["size"], Color(0.85, 0.75, 0.60, p["alpha"] * 0.5))

	# 2. Draw connections (with animated energy flow for unlocked paths)
	var time_ms := Time.get_ticks_msec() * 0.002
	for nid in _graph.nodes:
		var node: OverworldGraph.OverworldNode = _graph.nodes[nid]
		for adj_id in node.connections:
			if adj_id > nid:
				var adj: OverworldGraph.OverworldNode = _graph.get_node(adj_id)
				if adj == null:
					continue
				var both_unlocked := node.unlocked and adj.unlocked
				if both_unlocked:
					# Bright energy line
					draw_line(node.map_position, adj.map_position, Color(0.40, 0.35, 0.30, 0.7), CONNECTION_WIDTH, true)
					# Animated moving pulse along the line
					var dir := (adj.map_position - node.map_position)
					var dist := dir.length()
					var norm := dir.normalized()
					var pulse_pos := node.map_position + norm * fmod(time_ms * 40.0, dist)
					var theme_info: Dictionary = THEME_DATA.get(node.hex_theme, THEME_DATA["geocrash"])
					draw_circle(pulse_pos, 3.0, theme_info["primary"])
				else:
					# Dark broken line
					draw_line(node.map_position, adj.map_position, Color(0.18, 0.12, 0.12, 0.4), 1.5, true)

	# 3. Draw Region Nodes (Hexagonal Seals)
	for nid in _graph.nodes:
		var node: OverworldGraph.OverworldNode = _graph.nodes[nid]
		var is_selected: bool = (nid == _selected_node_id)
		var theme_info: Dictionary = THEME_DATA.get(node.hex_theme, THEME_DATA["geocrash"])
		var theme_color: Color = theme_info["primary"]
		var radius := NODE_RADIUS_SELECTED if is_selected else NODE_RADIUS

		# Outer glowing aura for selected node
		if is_selected:
			var pulse_scale := 1.0 + 0.12 * sin(_selection_pulse)
			var glow_r := radius * 1.5 * pulse_scale
			draw_circle(node.map_position, glow_r, theme_info["glow"] * 0.25)
			_draw_hexagon(node.map_position, glow_r, Color(theme_color.r, theme_color.g, theme_color.b, 0.5), 2.0)

		# Node base shape & fill
		if node.unlocked:
			if node.cleared:
				# Cleared: Dim, extinguished hex with gold seal outline
				_draw_hexagon(node.map_position, radius, Color(0.12, 0.15, 0.12, 0.9), 0.0, true)
				_draw_hexagon(node.map_position, radius, Color(0.4, 0.85, 0.4, 0.8), 2.0)
			else:
				# Unlocked: Bright theme fill & strong outline
				_draw_hexagon(node.map_position, radius, theme_color * 0.25, 0.0, true)
				_draw_hexagon(node.map_position, radius, theme_color, 2.5)
		else:
			# Locked: Dark iron hex with red seal outline
			_draw_hexagon(node.map_position, radius, Color(0.08, 0.05, 0.06, 0.9), 0.0, true)
			_draw_hexagon(node.map_position, radius, Color(0.45, 0.15, 0.15, 0.5), 1.5)

		# Custom Symbol Glyphs
		_draw_node_symbol(node, theme_color)

func _draw_hexagon(center: Vector2, radius: float, color: Color, width: float = 1.0, filled: bool = false) -> void:
	var pts := PackedVector2Array()
	for i in range(6):
		var angle := i * (TAU / 6.0) - (PI / 6.0)
		pts.append(center + Vector2(cos(angle), sin(angle)) * radius)

	if filled:
		draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])  # Close path
		draw_polyline(pts, color, width, true)

func _draw_node_symbol(node: OverworldGraph.OverworldNode, theme_color: Color) -> void:
	var center := node.map_position
	var is_selected: bool = (node.node_id == _selected_node_id)
	var col := theme_color if node.unlocked else Color(0.4, 0.25, 0.25, 0.5)
	if node.cleared:
		col = Color(0.5, 0.9, 0.5, 1.0)

	match node.node_type:
		OverworldGraph.NodeType.STARTER_VAULT:
			# Sword rune (vertical blade line + crossguard)
			draw_line(center + Vector2(0, -9), center + Vector2(0, 9), col, 2.0)
			draw_line(center + Vector2(-5, -2), center + Vector2(5, -2), col, 2.0)

		OverworldGraph.NodeType.CAMPSITE:
			# Tuning Fork / Rest Flame crest
			draw_line(center + Vector2(-4, -6), center + Vector2(-4, 2), col, 2.0)
			draw_line(center + Vector2(4, -6), center + Vector2(4, 2), col, 2.0)
			draw_line(center + Vector2(-4, 2), center + Vector2(4, 2), col, 2.0)
			draw_line(center + Vector2(0, 2), center + Vector2(0, 8), col, 2.0)

		OverworldGraph.NodeType.BOSS_GATE:
			# Dominator Crown / Hex Crest
			var crown := PackedVector2Array([
				center + Vector2(-7, 4),
				center + Vector2(-7, -4),
				center + Vector2(-3, 0),
				center + Vector2(0, -7),
				center + Vector2(3, 0),
				center + Vector2(7, -4),
				center + Vector2(7, 4),
			])
			draw_polyline(crown, col, 2.0, true)

		_:
			# Standard Dungeon / Rift diamond
			var diamond := PackedVector2Array([
				center + Vector2(0, -6),
				center + Vector2(6, 0),
				center + Vector2(0, 6),
				center + Vector2(-6, 0),
				center + Vector2(0, -6),
			])
			draw_polyline(diamond, col, 1.5, true)

	# Checkmark for cleared nodes
	if node.cleared:
		draw_polyline(PackedVector2Array([
			center + Vector2(-4, 0),
			center + Vector2(-1, 3),
			center + Vector2(5, -4)
		]), Color(0.4, 1.0, 0.4, 1.0), 2.5)

func _unhandled_input(event: InputEvent) -> void:
	if _graph == null:
		return

	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_navigate_selection(1)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_navigate_selection(-1)
	elif event.is_action_pressed("interact"):
		_enter_selected_node()

func _navigate_selection(direction: int) -> void:
	var current: OverworldGraph.OverworldNode = _graph.get_node(_selected_node_id)
	if current == null:
		return

	var best_id := -1
	var best_dist := INF

	for adj_id in current.connections:
		var adj: OverworldGraph.OverworldNode = _graph.get_node(adj_id)
		if adj == null or not adj.unlocked:
			continue
		var delta_x := adj.map_position.x - current.map_position.x
		var delta_y := adj.map_position.y - current.map_position.y
		var score: float = delta_x * float(direction) + delta_y * float(direction) * 0.5
		if score > 0.0:
			var dist := current.map_position.distance_to(adj.map_position)
			if dist < best_dist:
				best_dist = dist
				best_id = adj_id

	if best_id < 0:
		for adj_id in current.connections:
			var adj: OverworldGraph.OverworldNode = _graph.get_node(adj_id)
			if adj != null and adj.unlocked:
				best_id = adj_id
				break

	if best_id >= 0:
		_selected_node_id = best_id
		_update_detail_panel()

func _enter_selected_node() -> void:
	var node: OverworldGraph.OverworldNode = _graph.get_node(_selected_node_id)
	if node == null or not node.unlocked:
		return

	if node.node_type == OverworldGraph.NodeType.CAMPSITE:
		_graph.mark_cleared(_selected_node_id)
		GameManager.enter_campsite_hub()
		return

	GameManager.start_dungeon(_selected_node_id)

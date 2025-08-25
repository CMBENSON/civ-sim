# addons/world_analyzer/world_analyzer_panel.gd
@tool
extends PanelContainer

# UI Components
@onready var analysis_button: Button = $VBoxContainer/AnalysisButton
@onready var export_button: Button = $VBoxContainer/ExportButton
@onready var regenerate_button: Button = $VBoxContainer/RegenerateButton
@onready var progress_bar: ProgressBar = $VBoxContainer/ProgressBar
@onready var biome_display: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/BiomeStats
@onready var height_display: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/HeightStats
@onready var world_preview: TextureRect = $VBoxContainer/ScrollContainer/VBoxContainer/WorldPreview
@onready var parameter_controls: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer/Parameters

# Generation controls
@onready var sample_size_spin: SpinBox = $VBoxContainer/SampleControls/SampleSizeSpinBox
@onready var preview_resolution_spin: SpinBox = $VBoxContainer/SampleControls/PreviewResolutionSpinBox
@onready var verbose_toggle: CheckBox = $VBoxContainer/SampleControls/VerboseToggle

# Analysis data
var current_analysis: Dictionary = {}
var world_generator: RefCounted = null
var preview_image: Image

func _ready():
	# Create UI elements programmatically since we don't have a scene file
	_create_ui_elements()
	_connect_signals()
	
	# Initialize with default values
	sample_size_spin.value = 1000
	preview_resolution_spin.value = 256
	verbose_toggle.button_pressed = false

func _create_ui_elements():
	"""Create all UI elements programmatically"""
	# Main container
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	# Analysis button
	analysis_button = Button.new()
	analysis_button.text = "Analyze World Generation"
	analysis_button.name = "AnalysisButton"
	vbox.add_child(analysis_button)
	
	# Export button
	export_button = Button.new()
	export_button.text = "Export Analysis Data"
	export_button.disabled = true
	export_button.name = "ExportButton"
	vbox.add_child(export_button)
	
	# Regenerate button
	regenerate_button = Button.new()
	regenerate_button.text = "Regenerate with New Seed"
	regenerate_button.name = "RegenerateButton"
	vbox.add_child(regenerate_button)
	
	# Progress bar
	progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	vbox.add_child(progress_bar)
	
	# Sample controls
	var sample_controls = HBoxContainer.new()
	sample_controls.name = "SampleControls"
	vbox.add_child(sample_controls)
	
	sample_controls.add_child(Label.new())
	sample_controls.get_child(0).text = "Samples:"
	
	sample_size_spin = SpinBox.new()
	sample_size_spin.min_value = 100
	sample_size_spin.max_value = 10000
	sample_size_spin.step = 100
	sample_size_spin.name = "SampleSizeSpinBox"
	sample_controls.add_child(sample_size_spin)
	
	sample_controls.add_child(Label.new())
	sample_controls.get_child(2).text = "Preview Res:"
	
	preview_resolution_spin = SpinBox.new()
	preview_resolution_spin.min_value = 64
	preview_resolution_spin.max_value = 512
	preview_resolution_spin.step = 64
	preview_resolution_spin.name = "PreviewResolutionSpinBox"
	sample_controls.add_child(preview_resolution_spin)
	
	verbose_toggle = CheckBox.new()
	verbose_toggle.text = "Verbose Logging"
	verbose_toggle.name = "VerboseToggle"
	sample_controls.add_child(verbose_toggle)
	
	# Scroll container for results
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	vbox.add_child(scroll)
	
	var scroll_vbox = VBoxContainer.new()
	scroll.add_child(scroll_vbox)
	
	# Biome statistics
	var biome_label = Label.new()
	biome_label.text = "Biome Distribution:"
	biome_label.add_theme_stylebox_override("normal", _create_section_style())
	scroll_vbox.add_child(biome_label)
	
	biome_display = VBoxContainer.new()
	biome_display.name = "BiomeStats"
	scroll_vbox.add_child(biome_display)
	
	# Height statistics
	var height_label = Label.new()
	height_label.text = "Height Distribution:"
	height_label.add_theme_stylebox_override("normal", _create_section_style())
	scroll_vbox.add_child(height_label)
	
	height_display = VBoxContainer.new()
	height_display.name = "HeightStats"
	scroll_vbox.add_child(height_display)
	
	# World preview
	var preview_label = Label.new()
	preview_label.text = "World Preview:"
	preview_label.add_theme_stylebox_override("normal", _create_section_style())
	scroll_vbox.add_child(preview_label)
	
	world_preview = TextureRect.new()
	world_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	world_preview.custom_minimum_size = Vector2(256, 256)
	world_preview.name = "WorldPreview"
	scroll_vbox.add_child(world_preview)
	
	# Parameter controls
	var param_label = Label.new()
	param_label.text = "Tuning Parameters:"
	param_label.add_theme_stylebox_override("normal", _create_section_style())
	scroll_vbox.add_child(param_label)
	
	parameter_controls = VBoxContainer.new()
	parameter_controls.name = "Parameters"
	scroll_vbox.add_child(parameter_controls)

func _create_section_style() -> StyleBox:
	"""Create a style for section headers"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	style.border_color = Color(0.4, 0.4, 0.4, 1.0)
	style.set_border_width_all(1)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style

func _connect_signals():
	"""Connect UI signals"""
	analysis_button.pressed.connect(_on_analyze_pressed)
	export_button.pressed.connect(_on_export_pressed)
	regenerate_button.pressed.connect(_on_regenerate_pressed)
	verbose_toggle.toggled.connect(_on_verbose_toggled)

func _on_analyze_pressed():
	"""Analyze the current world generation"""
	print("WorldAnalyzer: Starting analysis...")
	analysis_button.disabled = true
	progress_bar.value = 0
	
	# Create or get the world generator
	if not world_generator:
		world_generator = _create_world_generator()
	
	if not world_generator:
		print("WorldAnalyzer: ERROR - Could not create world generator")
		analysis_button.disabled = false
		return
	
	# Set verbose logging
	world_generator.verbose_logging = verbose_toggle.button_pressed
	
	# Perform analysis
	var sample_size = int(sample_size_spin.value)
	current_analysis = world_generator.analyze_world_generation(sample_size)
	
	progress_bar.value = 50
	
	# Generate preview
	var preview_res = int(preview_resolution_spin.value)
	var preview_data = world_generator.get_world_preview_data(preview_res)
	_create_preview_image(preview_data)
	
	progress_bar.value = 75
	
	# Display results
	_display_analysis_results()
	_create_parameter_controls()
	
	progress_bar.value = 100
	analysis_button.disabled = false
	export_button.disabled = false
	
	print("WorldAnalyzer: Analysis complete!")

func _on_export_pressed():
	"""Export analysis data"""
	if current_analysis.is_empty():
		print("WorldAnalyzer: No analysis data to export")
		return
	
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var filename = "user://world_analysis_" + timestamp + ".json"
	
	if world_generator and world_generator.has_method("export_world_data"):
		world_generator.export_world_data(filename)
		print("WorldAnalyzer: Exported to ", filename)
	else:
		print("WorldAnalyzer: Export not available")

func _on_regenerate_pressed():
	"""Regenerate world with new seed"""
	if world_generator and world_generator.has_method("regenerate_with_new_seed"):
		world_generator.regenerate_with_new_seed()
		print("WorldAnalyzer: Regenerated with new seed")
		
		# Clear previous results
		_clear_displays()
		export_button.disabled = true
	else:
		print("WorldAnalyzer: Regenerate not available")

func _on_verbose_toggled(enabled: bool):
	"""Toggle verbose logging"""
	if world_generator and world_generator.has_method("set"):
		world_generator.verbose_logging = enabled

func _create_world_generator():
	"""Create a world generator for analysis"""
	# Try to find an existing world generator from a loaded world
	var world_nodes = _find_world_nodes()
	
	for world_node in world_nodes:
		if world_node.has_method("get") and world_node.generator:
			print("WorldAnalyzer: Using existing world generator")
			return world_node.generator
	
	# Create a new modular world generator
	print("WorldAnalyzer: Creating new modular world generator")
	var ModularWorldGenerator = load("res://src/core/world/ModularWorldGenerator.gd")
	if ModularWorldGenerator:
		return ModularWorldGenerator.new(1024, 16)
	
	# Fallback to original generator
	print("WorldAnalyzer: Falling back to original world generator")
	var WorldGenerator = load("res://src/core/world/WorldGenerator.gd")
	if WorldGenerator:
		return WorldGenerator.new(1024, 16)
	
	return null

func _find_world_nodes() -> Array:
	"""Find world nodes in the current scene"""
	var world_nodes = []
	var root = EditorInterface.get_edited_scene_root()
	
	if root:
		_search_for_world_nodes(root, world_nodes)
	
	return world_nodes

func _search_for_world_nodes(node: Node, results: Array):
	"""Recursively search for world nodes"""
	if node.get_script() and node.get_script().resource_path.ends_with("world.gd"):
		results.append(node)
	
	for child in node.get_children():
		_search_for_world_nodes(child, results)

func _display_analysis_results():
	"""Display the analysis results in the UI"""
	# Clear previous results
	_clear_displays()
	
	# Display biome distribution
	var biome_dist = current_analysis.get("biome_distribution", {})
	for biome_name in biome_dist.keys():
		var data = biome_dist[biome_name]
		var label = Label.new()
		label.text = "%s: %.1f%% (%d samples)" % [biome_name, data.percentage, data.count]
		
		# Color the label with biome color
		if data.has("color"):
			label.add_theme_color_override("font_color", data.color)
		
		biome_display.add_child(label)
	
	# Display height statistics
	var height_dist = current_analysis.get("height_distribution", {})
	for key in height_dist.keys():
		var label = Label.new()
		var value = height_dist[key]
		
		if typeof(value) == TYPE_FLOAT:
			label.text = "%s: %.2f" % [key.capitalize().replace("_", " "), value]
		else:
			label.text = "%s: %s" % [key.capitalize().replace("_", " "), str(value)]
		
		height_display.add_child(label)

func _create_preview_image(preview_data: Dictionary):
	"""Create a preview image from the analysis data"""
	var resolution = preview_data.resolution
	var biome_map = preview_data.biome_map
	
	preview_image = Image.create(resolution, resolution, false, Image.FORMAT_RGB8)
	
	# Get biome generator for colors (if available)
	var biome_generator = null
	if world_generator and world_generator.has_method("get_biome_generator"):
		biome_generator = world_generator.get_biome_generator()
	
	for y in range(resolution):
		for x in range(resolution):
			var biome = biome_map[y][x]
			var color = _get_biome_color(biome, biome_generator)
			preview_image.set_pixel(x, y, color)
	
	# Create texture and display
	var texture = ImageTexture.create_from_image(preview_image)
	world_preview.texture = texture

func _get_biome_color(biome: int, biome_generator) -> Color:
	"""Get color for a biome"""
	if biome_generator and biome_generator.has_method("get_biome_color"):
		return biome_generator.get_biome_color(biome)
	
	# Fallback colors
	match biome:
		0: return Color(0.1, 0.3, 0.8, 1.0)    # OCEAN
		1: return Color(0.5, 0.5, 0.5, 1.0)    # MOUNTAINS
		2: return Color(0.8, 0.8, 1.0, 1.0)    # TUNDRA
		3: return Color(0.4, 0.6, 0.2, 1.0)    # PLAINS
		4: return Color(0.8, 0.7, 0.5, 1.0)    # DESERT
		5: return Color(0.2, 0.4, 0.1, 1.0)    # JUNGLE
		6: return Color(0.15, 0.50, 0.20, 1.0) # FOREST
		7: return Color(0.3, 0.4, 0.2, 1.0)    # SWAMP
		_: return Color(0.5, 0.5, 0.5, 1.0)    # UNKNOWN

func _create_parameter_controls():
	"""Create controls for tuning parameters"""
	_clear_parameter_controls()
	
	if not world_generator or not world_generator.has_method("get_all_tuning_parameters"):
		var label = Label.new()
		label.text = "Parameter tuning not available"
		parameter_controls.add_child(label)
		return
	
	var all_params = world_generator.get_all_tuning_parameters()
	
	for category in all_params.keys():
		var category_label = Label.new()
		category_label.text = category.capitalize() + " Parameters:"
		category_label.add_theme_color_override("font_color", Color.YELLOW)
		parameter_controls.add_child(category_label)
		
		var params = all_params[category]
		for param_name in params.keys():
			var value = params[param_name]
			
			if typeof(value) == TYPE_FLOAT:
				_create_float_parameter_control(category, param_name, value)
			elif typeof(value) == TYPE_BOOL:
				_create_bool_parameter_control(category, param_name, value)
			else:
				_create_info_parameter_display(param_name, value)

func _create_float_parameter_control(category: String, param_name: String, value: float):
	"""Create a float parameter control"""
	var hbox = HBoxContainer.new()
	parameter_controls.add_child(hbox)
	
	var label = Label.new()
	label.text = param_name.replace("_", " ").capitalize() + ":"
	label.custom_minimum_size.x = 150
	hbox.add_child(label)
	
	var spinbox = SpinBox.new()
	spinbox.value = value
	spinbox.step = 0.1 if value < 10.0 else 1.0
	spinbox.allow_greater = true
	spinbox.allow_lesser = true
	
	# Set reasonable ranges based on parameter name
	if "threshold" in param_name.to_lower():
		spinbox.min_value = 0.0
		spinbox.max_value = 1.0
		spinbox.step = 0.05
	elif "amplitude" in param_name.to_lower():
		spinbox.min_value = 0.0
		spinbox.max_value = 100.0
	elif "distance" in param_name.to_lower():
		spinbox.min_value = 1.0
		spinbox.max_value = 50.0
	
	spinbox.value_changed.connect(_on_parameter_changed.bind(category, param_name))
	hbox.add_child(spinbox)

func _create_bool_parameter_control(category: String, param_name: String, value: bool):
	"""Create a boolean parameter control"""
	var checkbox = CheckBox.new()
	checkbox.text = param_name.replace("_", " ").capitalize()
	checkbox.button_pressed = value
	checkbox.toggled.connect(_on_parameter_changed.bind(category, param_name))
	parameter_controls.add_child(checkbox)

func _create_info_parameter_display(param_name: String, value):
	"""Create an info display for read-only parameters"""
	var label = Label.new()
	label.text = "%s: %s" % [param_name.replace("_", " ").capitalize(), str(value)]
	label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	parameter_controls.add_child(label)

func _on_parameter_changed(category: String, param_name: String, new_value):
	"""Handle parameter changes"""
	if not world_generator or not world_generator.has_method("set_all_tuning_parameters"):
		return
	
	var params = {category: {param_name: new_value}}
	world_generator.set_all_tuning_parameters(params)
	
	print("WorldAnalyzer: Updated ", category, ".", param_name, " to ", new_value)

func _clear_displays():
	"""Clear all result displays"""
	for child in biome_display.get_children():
		child.queue_free()
	
	for child in height_display.get_children():
		child.queue_free()
	
	world_preview.texture = null

func _clear_parameter_controls():
	"""Clear parameter controls"""
	for child in parameter_controls.get_children():
		child.queue_free()

# src/core/ui/debug_ui.gd
extends Control

@onready var fps_label = $MarginContainer/VBoxContainer/FPSLabel
@onready var pos_label = $MarginContainer/VBoxContainer/PosLabel
@onready var chunk_label = $MarginContainer/VBoxContainer/ChunkLabel
@onready var biome_label = $MarginContainer/VBoxContainer/BiomeLabel
@onready var height_label = $MarginContainer/VBoxContainer/HeightLabel
@onready var climate_label = $MarginContainer/VBoxContainer/ClimateLabel

# New labels for enhanced debug info
@onready var system_label = $MarginContainer/VBoxContainer/SystemLabel
@onready var generation_label = $MarginContainer/VBoxContainer/GenerationLabel

var player: CharacterBody3D
var world: Node3D

func _ready():
	# Create additional labels if they don't exist
	_ensure_all_labels_exist()

func _ensure_all_labels_exist():
	var vbox = $MarginContainer/VBoxContainer
	
	# Check and create missing labels
	var required_labels = [
		"FPSLabel", "PosLabel", "ChunkLabel", "BiomeLabel", 
		"HeightLabel", "ClimateLabel", "SystemLabel", "GenerationLabel"
	]
	
	for label_name in required_labels:
		if not has_node("MarginContainer/VBoxContainer/" + label_name):
			var new_label = Label.new()
			new_label.name = label_name
			new_label.theme_override_font_sizes/font_size = 24
			vbox.add_child(new_label)
			
			# Update references
			match label_name:
				"FPSLabel": fps_label = new_label
				"PosLabel": pos_label = new_label  
				"ChunkLabel": chunk_label = new_label
				"BiomeLabel": biome_label = new_label
				"HeightLabel": height_label = new_label
				"ClimateLabel": climate_label = new_label
				"SystemLabel": system_label = new_label
				"GenerationLabel": generation_label = new_label

func _process(_delta):
	# Basic performance info
	fps_label.text = "FPS: " + str(Engine.get_frames_per_second())

	if not is_instance_valid(player) or not is_instance_valid(world):
		return

	# Player position info
	var player_pos = player.global_position
	pos_label.text = "Pos: (%.1f, %.1f, %.1f)" % [player_pos.x, player_pos.y, player_pos.z]

	# Chunk position info
	var chunk_pos = world.current_player_chunk
	chunk_label.text = "Chunk: (%d, %d)" % [chunk_pos.x, chunk_pos.y]

	# System info - detect which generation system is in use
	_update_system_info()

	# Get world coordinates
	var world_x = floori(player_pos.x)
	var world_z = floori(player_pos.z)
	var wrapped_world_x = wrapi(world_x, 0, world.WORLD_CIRCUMFERENCE_IN_VOXELS)

	# Calculate local chunk coordinates
	var c_size = world.CHUNK_SIZE
	var c_pos_x = floor(wrapped_world_x / float(c_size))
	var c_pos_z = floor(world_z / float(c_size))
	var current_chunk_pos = Vector2i(c_pos_x, c_pos_z)

	# Get chunk and display terrain info
	var chunk = world.loaded_chunks.get(current_chunk_pos)
	_update_terrain_info(chunk, wrapped_world_x, world_z, c_size, world_x)

func _update_system_info():
	"""Update system information display"""
	var system_info = "System: "
	
	# Detect which generation system is active
	if world.has_method("use_modular_generation") and world.use_modular_generation:
		system_info += "Modular"
		
		# Show generation stats if available
		if world.generator and world.generator.has_method("get_all_tuning_parameters"):
			var loaded_chunks = world.loaded_chunks.size()
			var queue_size = 0
			if world.has_method("generation_queue"):
				queue_size = world.generation_queue.size()
			generation_label.text = "Chunks: %d loaded, %d queued" % [loaded_chunks, queue_size]
		else:
			generation_label.text = "Generation: Standard"
	else:
		system_info += "Original"
		generation_label.text = "Generation: WorldGenerator"
	
	# Add performance indicators
	if world.verbose_logging:
		system_info += " (Verbose)"
	
	system_label.text = system_info

func _update_terrain_info(chunk, wrapped_world_x: int, world_z: int, c_size: int, world_x: int):
	"""Update terrain-related debug information"""
	if is_instance_valid(chunk) and not chunk.biome_data.is_empty():
		var local_x = int(wrapped_world_x) % c_size
		var local_z = int(world_z) % c_size
		if local_z < 0: 
			local_z += c_size

		if _is_valid_chunk_coordinate(chunk, local_x, local_z):
			var biome_enum = chunk.biome_data[local_x][local_z]
			var biome_name = WorldData.Biome.keys()[biome_enum]
			biome_label.text = "Biome: " + biome_name
			
			_get_detailed_terrain_info(world_x, world_z)
		else:
			_set_loading_labels()
	else:
		_set_loading_labels()

func _is_valid_chunk_coordinate(chunk, local_x: int, local_z: int) -> bool:
	"""Check if chunk coordinates are valid"""
	return (chunk.biome_data.size() > local_x and 
			local_x >= 0 and 
			chunk.biome_data[local_x].size() > local_z and 
			local_z >= 0)

func _get_detailed_terrain_info(world_x: int, world_z: int):
	"""Get detailed terrain information from the generator"""
	if not world.generator:
		height_label.text = "Height: No generator"
		climate_label.text = "Climate: No generator" 
		return
		
	# Try to get debug info from generator
	if world.generator.has_method("get_debug_info"):
		var debug_info = world.generator.get_debug_info(world_x, world_z)
		_display_debug_info(debug_info)
	elif world.generator.has_method("get_height"):
		# Fallback to basic info
		var height = world.generator.get_height(world_x, world_z, world.CHUNK_HEIGHT)
		height_label.text = "Height: %.1f (Sea: %.1f)" % [height, world.generator.sea_level]
		
		if world.generator.has_method("get_temperature_01") and world.generator.has_method("get_moisture_01"):
			var temp = world.generator.get_temperature_01(world_x, world_z)
			var moisture = world.generator.get_moisture_01(world_x, world_z)
			climate_label.text = "Temp: %.2f, Moist: %.2f" % [temp, moisture]
		else:
			climate_label.text = "Climate: Basic generator"
	else:
		height_label.text = "Height: Unknown generator"
		climate_label.text = "Climate: Unknown generator"

func _display_debug_info(debug_info: Dictionary):
	"""Display comprehensive debug information"""
	# Height information
	if debug_info.has("height") and debug_info.has("sea_level"):
		height_label.text = "Height: %.1f (Sea: %.1f)" % [debug_info.height, debug_info.sea_level]
	elif debug_info.has("final_height") and debug_info.has("sea_level"):
		height_label.text = "Height: %.1f (Sea: %.1f)" % [debug_info.final_height, debug_info.sea_level]
	else:
		height_label.text = "Height: %.1f" % debug_info.get("height", 0.0)
	
	# Climate information  
	var climate_parts = []
	if debug_info.has("temperature") or debug_info.has("temperature_01"):
		var temp = debug_info.get("temperature", debug_info.get("temperature_01", 0.0))
		climate_parts.append("T: %.2f" % temp)
	if debug_info.has("moisture") or debug_info.has("moisture_01"):
		var moisture = debug_info.get("moisture", debug_info.get("moisture_01", 0.0))
		climate_parts.append("M: %.2f" % moisture)
	
	# Add additional info for modular system
	if debug_info.has("continent_value"):
		climate_parts.append("C: %.2f" % debug_info.continent_value)
	if debug_info.has("is_ocean"):
		climate_parts.append("Ocean: %s" % str(debug_info.is_ocean))
		
	climate_label.text = "Climate: " + ", ".join(climate_parts) if climate_parts.size() > 0 else "Climate: No data"

func _set_loading_labels():
	"""Set labels to loading state"""
	biome_label.text = "Biome: Loading..."
	height_label.text = "Height: Loading..."
	climate_label.text = "Climate: Loading..."

func get_debug_summary() -> Dictionary:
	"""Get a summary of current debug information for external tools"""
	if not is_instance_valid(player) or not is_instance_valid(world):
		return {"error": "Invalid references"}
	
	var player_pos = player.global_position
	var world_x = floori(player_pos.x)
	var world_z = floori(player_pos.z)
	
	var summary = {
		"fps": Engine.get_frames_per_second(),
		"player_position": player_pos,
		"chunk_position": world.current_player_chunk,
		"world_coordinates": Vector2i(world_x, world_z),
		"system_type": "Modular" if (world.has_method("use_modular_generation") and world.use_modular_generation) else "Original"
	}
	
	# Add generator-specific info
	if world.generator and world.generator.has_method("get_debug_info"):
		summary["terrain_debug"] = world.generator.get_debug_info(world_x, world_z)
	
	return summary

func set_debug_level(level: int):
	"""Set debug verbosity level"""
	match level:
		0: # Minimal
			system_label.visible = false
			generation_label.visible = false
		1: # Standard  
			system_label.visible = true
			generation_label.visible = false
		2: # Verbose
			system_label.visible = true  
			generation_label.visible = true
			if world and world.has_method("set"):
				world.verbose_logging = true

func toggle_verbose_mode():
	"""Toggle verbose logging mode"""
	if world and world.has_method("set"):
		world.verbose_logging = !world.verbose_logging
		print("Debug UI: Verbose logging ", "enabled" if world.verbose_logging else "disabled")

# Helper function for external debugging tools
func export_debug_data() -> String:
	"""Export current debug data as JSON string"""
	var debug_data = get_debug_summary()
	return JSON.stringify(debug_data)

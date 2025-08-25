# src/core/ui/debug_ui.gd
extends Control

# Label references - don't use @onready since we create them dynamically
var fps_label: Label
var pos_label: Label
var chunk_label: Label
var biome_label: Label
var height_label: Label
var climate_label: Label
var system_label: Label
var generation_label: Label

var player: CharacterBody3D
var world: Node3D

func _ready():
	# Create all labels programmatically
	_ensure_all_labels_exist()

func _ensure_all_labels_exist():
	var vbox = $MarginContainer/VBoxContainer
	
	# Check and create missing labels
	var required_labels = [
		"FPSLabel", "PosLabel", "ChunkLabel", "BiomeLabel", 
		"HeightLabel", "ClimateLabel", "SystemLabel", "GenerationLabel"
	]
	
	for label_name in required_labels:
		var label_node = vbox.get_node_or_null(label_name)
		
		if not label_node:
			# Create new label
			var new_label = Label.new()
			new_label.name = label_name
			new_label.add_theme_font_size_override("font_size", 24)
			vbox.add_child(new_label)
			label_node = new_label
		
		# Set references - this is the fix for the assignment error
		_assign_label_reference(label_name, label_node)

func _assign_label_reference(label_name: String, label_node: Label):
	"""Safely assign label references"""
	match label_name:
		"FPSLabel": 
			fps_label = label_node
		"PosLabel": 
			pos_label = label_node
		"ChunkLabel": 
			chunk_label = label_node
		"BiomeLabel": 
			biome_label = label_node
		"HeightLabel": 
			height_label = label_node
		"ClimateLabel": 
			climate_label = label_node
		"SystemLabel": 
			system_label = label_node
		"GenerationLabel": 
			generation_label = label_node

func _process(_delta):
	# Basic performance info
	if fps_label:
		fps_label.text = "FPS: " + str(Engine.get_frames_per_second())

	if not is_instance_valid(player) or not is_instance_valid(world):
		return

	# Player position info
	var player_pos = player.global_position
	if pos_label:
		pos_label.text = "Pos: (%.1f, %.1f, %.1f)" % [player_pos.x, player_pos.y, player_pos.z]

	# Chunk position info - now uses ChunkManager
	var chunk_pos = world.current_player_chunk
	if chunk_label:
		chunk_label.text = "Chunk: (%d, %d)" % [chunk_pos.x, chunk_pos.y]

	# System info - FIXED detection
	_update_system_info()

	# Get world coordinates
	var world_x = floori(player_pos.x)
	var world_z = floori(player_pos.z)
	var wrapped_world_x = wrapi(world_x, 0, world.WORLD_CIRCUMFERENCE_IN_VOXELS)

	# Use ChunkManager for chunk info
	_update_terrain_info_with_chunk_manager(wrapped_world_x, world_z, world_x)

func _update_system_info():
	"""Update system information display - FIXED"""
	if not system_label or not generation_label:
		return
		
	var system_info = "System: "
	
	# FIXED: Check for modular system properly
	if world.use_modular_generation and world.has_method("_initialize_modular_system"):
		system_info += "Modular"
		
		# Check if we're using ChunkManager
		if world.has_method("chunk_manager") or "chunk_manager" in world:
			system_info += " + ChunkManager"
		
		# Show chunk and generation stats
		var loaded_chunks = 0
		var queue_size = 0
		var active_threads = 0
		
		if world.chunk_manager:
			loaded_chunks = world.chunk_manager.get_chunk_count()
			if world.thread_manager:
				var stats = world.thread_manager.get_stats()
				queue_size = stats.get("queue_size", 0)
				active_threads = stats.get("active_threads", 0)
		else:
			loaded_chunks = world.loaded_chunks.size()
		
		generation_label.text = "Chunks: %d | Queue: %d | Threads: %d" % [loaded_chunks, queue_size, active_threads]
	else:
		system_info += "Legacy"
		generation_label.text = "Generation: WorldGenerator (Old System)"
	
	# Add performance indicators
	if world.verbose_logging:
		system_info += " (Verbose)"
	
	# Add spawn status
	if world.has_method("spawn_ready") or "spawn_ready" in world:
		if world.spawn_ready:
			system_info += " [Ready]"
		else:
			system_info += " [Loading...]"
	
	system_label.text = system_info

func _update_terrain_info_with_chunk_manager(wrapped_world_x: int, world_z: int, world_x: int):
	"""Update terrain information using ChunkManager"""
	if not biome_label or not height_label or not climate_label:
		return
	
	# Try to get chunk through ChunkManager
	var chunk = null
	if world.chunk_manager:
		chunk = world.chunk_manager.get_chunk_at_position(Vector3(wrapped_world_x, 0, world_z))
	else:
		# Fallback to old system
		var chunk_pos = Vector2i(
			floor(wrapped_world_x / float(world.CHUNK_SIZE)), 
			floor(world_z / float(world.CHUNK_SIZE))
		)
		chunk = world.loaded_chunks.get(chunk_pos)
	
	if is_instance_valid(chunk) and not chunk.biome_data.is_empty():
		var c_size = world.CHUNK_SIZE
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
	if biome_label:
		biome_label.text = "Biome: Loading..."
	if height_label:
		height_label.text = "Height: Loading..."
	if climate_label:
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
		"system_type": "Modular + ChunkManager" if world.use_modular_generation else "Legacy"
	}
	
	# Add generator-specific info
	if world.generator and world.generator.has_method("get_debug_info"):
		summary["terrain_debug"] = world.generator.get_debug_info(world_x, world_z)
	
	return summary

func set_debug_level(level: int):
	"""Set debug verbosity level"""
	match level:
		0: # Minimal
			if system_label: system_label.visible = false
			if generation_label: generation_label.visible = false
		1: # Standard  
			if system_label: system_label.visible = true
			if generation_label: generation_label.visible = false
		2: # Verbose
			if system_label: system_label.visible = true  
			if generation_label: generation_label.visible = true
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

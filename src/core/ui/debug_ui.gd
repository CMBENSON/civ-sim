# src/core/ui/debug_ui.gd
extends Control

@onready var fps_label = $MarginContainer/VBoxContainer/FPSLabel
@onready var pos_label = $MarginContainer/VBoxContainer/PosLabel
@onready var chunk_label = $MarginContainer/VBoxContainer/ChunkLabel
@onready var biome_label = $MarginContainer/VBoxContainer/BiomeLabel
@onready var height_label = $MarginContainer/VBoxContainer/HeightLabel
@onready var climate_label = $MarginContainer/VBoxContainer/ClimateLabel

var player: CharacterBody3D
var world: Node3D

func _ready():
	# Create labels if they don't exist
	if not height_label:
		height_label = Label.new()
		height_label.name = "HeightLabel"
		$MarginContainer/VBoxContainer.add_child(height_label)
	
	if not climate_label:
		climate_label = Label.new()
		climate_label.name = "ClimateLabel"
		$MarginContainer/VBoxContainer.add_child(climate_label)

func _process(_delta):
	fps_label.text = "FPS: " + str(Engine.get_frames_per_second())

	if not is_instance_valid(player) or not is_instance_valid(world):
		return

	var player_pos = player.global_position
	pos_label.text = "Pos: (%.1f, %.1f, %.1f)" % [player_pos.x, player_pos.y, player_pos.z]

	var chunk_pos = world.current_player_chunk
	chunk_label.text = "Chunk: (%d, %d)" % [chunk_pos.x, chunk_pos.y]

	var world_x = floori(player_pos.x)
	var world_z = floori(player_pos.z)

	var wrapped_world_x = wrapi(world_x, 0, world.WORLD_CIRCUMFERENCE_IN_VOXELS)

	var c_size = world.CHUNK_SIZE
	var c_pos_x = floor(wrapped_world_x / float(c_size))
	var c_pos_z = floor(world_z / float(c_size))

	var current_chunk_pos = Vector2i(c_pos_x, c_pos_z)

	var chunk = world.loaded_chunks.get(current_chunk_pos)

	if is_instance_valid(chunk) and not chunk.biome_data.is_empty():
		var local_x = int(wrapped_world_x) % c_size
		var local_z = int(world_z) % c_size
		if local_z < 0: local_z += c_size

		if chunk.biome_data.size() > local_x and chunk.biome_data[local_x].size() > local_z:
			var biome_enum = chunk.biome_data[local_x][local_z]
			var biome_name = WorldData.Biome.keys()[biome_enum]
			biome_label.text = "Biome: " + biome_name
			
			# Get detailed terrain info
			if world.generator and world.generator.has_method("get_debug_info"):
				var debug_info = world.generator.get_debug_info(world_x, world_z)
				height_label.text = "Height: %.1f (Sea: %.1f)" % [debug_info.height, debug_info.sea_level]
				climate_label.text = "Temp: %.2f, Moist: %.2f" % [debug_info.temperature, debug_info.moisture]
		else:
			biome_label.text = "Biome: Loading..."
			height_label.text = "Height: Loading..."
			climate_label.text = "Climate: Loading..."
	else:
		biome_label.text = "Biome: Loading..."
		height_label.text = "Height: Loading..."
		climate_label.text = "Climate: Loading..."

# debug_ui.gd
extends Control

@onready var fps_label = $MarginContainer/VBoxContainer/FPSLabel
@onready var pos_label = $MarginContainer/VBoxContainer/PosLabel
@onready var chunk_label = $MarginContainer/VBoxContainer/ChunkLabel
@onready var biome_label = $MarginContainer/VBoxContainer/BiomeLabel

var player: CharacterBody3D
var world: Node3D

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
	
	var c_pos_x = floor(wrapped_world_x / 32.0)
	var c_pos_z = floor(world_z / 32.0)
	
	var current_chunk_pos = Vector2i(c_pos_x, c_pos_z)
	
	var chunk = world.loaded_chunks.get(current_chunk_pos)
	
	if is_instance_valid(chunk) and not chunk.biome_data.is_empty():
		var local_x = int(wrapped_world_x) % 32
		var local_z = int(world_z) % 32
		if local_z < 0: local_z += 32
		
		if chunk.biome_data.size() > local_x and chunk.biome_data[local_x].size() > local_z:
			var biome_enum = chunk.biome_data[local_x][local_z]
			# --- FINAL FIX IS HERE ---
			# Access the Biome enum through the global WorldData autoload script.
			var biome_name = WorldData.Biome.keys()[biome_enum]
			biome_label.text = "Biome: " + biome_name
		else:
			biome_label.text = "Biome: Loading..."
	else:
		biome_label.text = "Biome: Loading..."

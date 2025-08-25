# main.gd
extends Node3D

@onready var player = $Player
@onready var world = $World
@onready var debug_ui = $CanvasLayer/DebugUI

var spawn_position = Vector3(8.0, 0, 8.0)  # Spawn at center of chunk (0,0)
var max_spawn_attempts = 10
var current_spawn_attempt = 0

func _ready():
	# We wait one frame to ensure all nodes are ready before connecting signals.
	await get_tree().process_frame
	
	world.player = player
	player.world_node = world
	debug_ui.player = player
	debug_ui.world = world
	
	# Connect to the world's signal. This is the robust way to handle startup.
	world.initial_chunks_generated.connect(on_world_ready)
	
	print("Main: Setup complete, waiting for world to be ready...")

func on_world_ready():
	print("Main: World is ready, attempting to spawn player...")
	
	# Wait a few more frames to ensure mesh generation is complete
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	
	_attempt_spawn()

func _attempt_spawn():
	current_spawn_attempt += 1
	print("Main: Spawn attempt ", current_spawn_attempt, " at position ", spawn_position)
	
	# Get the spawn chunk and verify it exists and has data
	var spawn_chunk_pos = Vector2i(
		int(floor(spawn_position.x / world.CHUNK_SIZE)),
		int(floor(spawn_position.z / world.CHUNK_SIZE))
	)
	
	print("Main: Looking for spawn chunk at ", spawn_chunk_pos)
	
	var spawn_chunk = null
	if world.chunk_manager:
		spawn_chunk = world.chunk_manager.get_chunk_at_chunk_position(spawn_chunk_pos)
	
	if not is_instance_valid(spawn_chunk):
		print("Main: ERROR - Spawn chunk not found! Available chunks: ", world.loaded_chunks.keys())
		if current_spawn_attempt < max_spawn_attempts:
			# Force load the spawn chunk
			if world.chunk_manager:
				world.chunk_manager.load_chunk(spawn_chunk_pos)
			await get_tree().create_timer(0.5).timeout
			_attempt_spawn()
		else:
			print("Main: FAILED to load spawn chunk after ", max_spawn_attempts, " attempts. Using fallback spawn.")
			_fallback_spawn()
		return
	
	# Check if chunk has voxel data
	if spawn_chunk.voxel_data.is_empty():
		print("Main: Spawn chunk exists but has no voxel data yet...")
		if current_spawn_attempt < max_spawn_attempts:
			await get_tree().create_timer(0.2).timeout
			_attempt_spawn()
		else:
			print("Main: Spawn chunk never got voxel data. Using fallback spawn.")
			_fallback_spawn()
		return
	
	# Get safe spawn height
	var surface_height = world.get_surface_height(spawn_position.x, spawn_position.z)
	var safe_spawn_height = surface_height + 2.0  # 2 units above surface
	
	spawn_position.y = safe_spawn_height
	
	print("Main: Surface height: ", surface_height, ", spawn height: ", safe_spawn_height)
	
	# Set player position
	player.global_position = spawn_position
	
	print("Main: Player spawned successfully at: ", player.global_position)

func _fallback_spawn():
	"""Fallback spawn method when proper terrain isn't ready"""
	print("Main: Using fallback spawn method")
	
	# Just spawn high in the air and let player fall/fly
	spawn_position.y = 50.0
	player.global_position = spawn_position
	player.is_flying = true  # Enable flying mode as fallback
	
	print("Main: Fallback spawn complete at: ", player.global_position, " (flying mode enabled)")

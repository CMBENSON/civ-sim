# main.gd
extends Node3D

@onready var player = $Player
@onready var world = $World
@onready var debug_ui = $CanvasLayer/DebugUI

func _ready():
	# We wait one frame to ensure all nodes are ready before connecting signals.
	await get_tree().process_frame
	
	world.player = player
	player.world_node = world
	debug_ui.player = player
	debug_ui.world = world
	
	# Connect to the world's signal. This is the robust way to handle startup.
	world.initial_chunks_generated.connect(on_world_ready)


func on_world_ready():
	print("on_world_ready called - waiting for origin chunk to be properly loaded")
	
	# Wait for physics to be ready
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Wait a bit more for mesh to be fully applied
	await get_tree().create_timer(0.5).timeout
	
	# Double check that the origin chunk is actually loaded
	if not world.is_chunk_loaded(Vector2i.ZERO):
		print("Origin chunk not yet loaded, waiting...")
		await get_tree().create_timer(1.0).timeout
	
	# Get a safe spawn position above the terrain
	var spawn_x = 0.0
	var spawn_z = 0.0
	print("Getting surface height at (0,0)...")
	var surface_height = world.get_surface_height(spawn_x, spawn_z)
	
	print("Surface height at (0,0): ", surface_height)
	print("Origin chunk loaded: ", world.is_chunk_loaded(Vector2i.ZERO))
	
	# If surface height seems wrong, use a safe default
	var sea_level = 28.0
	if world.generator and world.generator.has_method("sea_level"):
		sea_level = world.generator.sea_level
	
	var spawn_y = surface_height
	if surface_height < sea_level or surface_height > 200.0:  # Invalid height
		spawn_y = sea_level + 20.0  # Safe spawn above sea level
		print("Surface height invalid (", surface_height, "), using safe spawn height: ", spawn_y)
	else:
		spawn_y += 5.0  # Add buffer above surface
		print("Using calculated spawn height: ", spawn_y)
	
	# Try to use raycasting to find actual terrain surface as backup
	var space_state = world.get_world_3d().direct_space_state
	var ray_query = PhysicsRayQueryParameters3D.create(
		Vector3(spawn_x, 100.0, spawn_z),  # From high above
		Vector3(spawn_x, -50.0, spawn_z),  # To below expected terrain
		1  # Default collision mask
	)
	var ray_result = space_state.intersect_ray(ray_query)
	
	if ray_result:
		var terrain_y = ray_result.position.y
		print("Raycast found terrain at: ", terrain_y)
		# Use raycast result if it seems more reasonable
		if terrain_y > sea_level and abs(terrain_y - surface_height) < 20.0:
			spawn_y = terrain_y + 5.0
			print("Using raycast height: ", spawn_y)
	
	# Set player position
	player.global_position = Vector3(spawn_x, spawn_y, spawn_z)
	
	print("Player spawned at: ", player.global_position)
	print("Final surface height check: ", world.get_surface_height(spawn_x, spawn_z))

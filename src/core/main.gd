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
	# Wait for physics to be ready
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Get a safe spawn position above the terrain
	var spawn_x = 0.0
	var spawn_z = 0.0
	var spawn_y = world.get_surface_height(spawn_x, spawn_z)
	
	# Ensure we're well above the surface to avoid collision issues
	spawn_y += 5.0  # Add 5 units above surface
	
	# Set player position
	player.global_position = Vector3(spawn_x, spawn_y, spawn_z)
	
	print("Player spawned at: ", player.global_position)
	print("Surface height at spawn: ", world.get_surface_height(spawn_x, spawn_z))

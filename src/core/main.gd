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
	# --- THIS IS THE FIX ---
	# Instead of waiting for a process_frame, we wait for two physics_frames.
	# This gives the physics server ample time to register the newly created
	# collision shape for the spawn chunk before we place the player in the world.
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var spawn_y = world.get_surface_height(0, 0)
	player.global_position = Vector3(0, spawn_y + 2, 0)

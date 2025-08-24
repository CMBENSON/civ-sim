# res://src/core/main.gd
extends Node3D

@onready var player = $Player
@onready var world = $World
@onready var debug_ui = $CanvasLayer/DebugUI

func _ready():
	await get_tree().process_frame
	
	world.player = player
	player.world_node = world
	debug_ui.player = player
	debug_ui.world = world
	
	# Connect to the world's signal. This is the robust way to handle startup.
	world.initial_chunks_generated.connect(on_world_ready)

func on_world_ready():
	# This function will only be called when the world confirms the spawn chunk is solid.
	# We still wait one frame to be absolutely sure the physics server is updated.
	await get_tree().process_frame
	
	var spawn_y = world.get_surface_height(0, 0)
	player.global_position = Vector3(0, spawn_y + 2, 0)

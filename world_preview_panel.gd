@tool
extends PanelContainer

const WorldScene = preload("res://src/core/world/world.tscn")

@onready var generate_button = $VBoxContainer/Button
@onready var progress_bar = $VBoxContainer/ProgressBar
@onready var viewport_container = $VBoxContainer/SubViewportContainer
@onready var sub_viewport = SubViewport.new()

var preview_world = null
var preview_camera = null

func _ready():
	generate_button.text = "Generate Full Preview"
	generate_button.pressed.connect(_on_generate_pressed)
	
	viewport_container.add_child(sub_viewport)
	
	preview_camera = Camera3D.new()
	sub_viewport.add_child(preview_camera)
	
	var map_center = (32 * 32) / 2.0
	preview_camera.position = Vector3(map_center, 1200, map_center + 200)
	preview_camera.look_at(Vector3(map_center, 0, map_center))

func _process(_delta):
	# This function will now just update the progress bar based on the world's state.
	if is_instance_valid(preview_world) and not preview_world.generation_queue.is_empty():
		var total_chunks = preview_world.WORLD_WIDTH_IN_CHUNKS * preview_world.WORLD_WIDTH_IN_CHUNKS
		progress_bar.max_value = total_chunks
		# Progress is the number of chunks that are no longer in the queue
		progress_bar.value = total_chunks - preview_world.generation_queue.size()
		
		if preview_world.generation_queue.is_empty():
			generate_button.disabled = false
			progress_bar.value = progress_bar.max_value

func _on_generate_pressed():
	generate_button.disabled = true
	
	if is_instance_valid(preview_world):
		preview_world.queue_free()

	preview_world = WorldScene.instantiate()
	sub_viewport.add_child(preview_world)
	
	# --- NEW LOGIC ---
	# We no longer generate the mesh here. We just tell the world to load everything.
	# The world's own _process loop will handle the multithreaded generation.
	var world_width_in_chunks = preview_world.WORLD_WIDTH_IN_CHUNKS
	for x in range(world_width_in_chunks):
		for z in range(world_width_in_chunks):
			preview_world.load_chunk(Vector2i(x, z))

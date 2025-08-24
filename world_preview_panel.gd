@tool
extends PanelContainer

const WorldScene = preload("res://src/core/world/world.tscn")
const BATCH_SIZE = 16 # How many chunks to generate per frame. Adjust if needed.

@onready var generate_button = $VBoxContainer/Button
@onready var progress_bar = $VBoxContainer/ProgressBar # Make sure this path is correct
@onready var viewport_container = $VBoxContainer/SubViewportContainer
@onready var sub_viewport = SubViewport.new()

var preview_world = null
var preview_camera = null
var generation_queue = []

func _ready():
	generate_button.text = "Generate Full Preview"
	generate_button.pressed.connect(_on_generate_pressed)
	
	viewport_container.add_child(sub_viewport)
	# Removed the line that manually sets the viewport size to fix the warnings.
	
	# Create a camera for the preview
	preview_camera = Camera3D.new()
	sub_viewport.add_child(preview_camera)
	
	var map_center = (32 * 32) / 2.0
	preview_camera.position = Vector3(map_center, 1200, map_center + 200)
	preview_camera.look_at(Vector3(map_center, 0, map_center))

func _process(_delta):
	# If the queue is empty, do nothing.
	if generation_queue.is_empty():
		return

	# Process a batch of chunks from the queue
	for i in range(min(BATCH_SIZE, generation_queue.size())):
		var chunk_pos = generation_queue.pop_front()
		
		# Load and generate the chunk data
		preview_world.load_chunk(chunk_pos)
		
		# Immediately generate its mesh
		var chunk = preview_world.loaded_chunks[chunk_pos]
		var padded_data = preview_world.get_padded_data_for_chunk(chunk_pos)
		chunk.generate_mesh(padded_data)

	# Update the progress bar
	var total_chunks = preview_world.WORLD_WIDTH_IN_CHUNKS * preview_world.WORLD_WIDTH_IN_CHUNKS
	progress_bar.max_value = total_chunks
	progress_bar.value = total_chunks - generation_queue.size()

	# When the queue is finished, re-enable the button
	if generation_queue.is_empty():
		generate_button.disabled = false
		progress_bar.value = progress_bar.max_value


func _on_generate_pressed():
	# Disable the button to prevent multiple clicks
	generate_button.disabled = true
	
	# Clear the old world and the queue
	if is_instance_valid(preview_world):
		preview_world.queue_free()
	generation_queue.clear()

	# Create the new world instance
	preview_world = WorldScene.instantiate()
	sub_viewport.add_child(preview_world)
	
	# Populate the generation queue with all chunk positions
	var world_width_in_chunks = preview_world.WORLD_WIDTH_IN_CHUNKS
	for x in range(world_width_in_chunks):
		for z in range(world_width_in_chunks):
			generation_queue.append(Vector2i(x, z))

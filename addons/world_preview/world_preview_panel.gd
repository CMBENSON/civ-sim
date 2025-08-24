@tool
extends PanelContainer

const WorldScene = preload("res://src/core/world/world.tscn")

@onready var generate_button = $VBoxContainer/Button
@onready var progress_bar = $VBoxContainer/ProgressBar
@onready var viewport_container = $VBoxContainer/SubViewportContainer
@onready var verbose_toggle = $VBoxContainer/VerboseToggle
@onready var sub_viewport = SubViewport.new()

var preview_world = null
var preview_camera = null

func _ready():
	generate_button.text = "Generate Full Preview"
	generate_button.pressed.connect(_on_generate_pressed)
	
	viewport_container.add_child(sub_viewport)
	
	preview_camera = Camera3D.new()
	# --- FIX: Set the 'near' clip plane to a small value ---
	preview_camera.near = 0.1
	sub_viewport.add_child(preview_camera)
	
	# Set a safe default camera; will be repositioned after world instantiation
	preview_camera.position = Vector3(128, 800, 160)
	preview_camera.look_at(Vector3(128, 0, 128))

func _process(_delta):
	if is_instance_valid(preview_world):
		var total_chunks = preview_world.WORLD_WIDTH_IN_CHUNKS * preview_world.WORLD_WIDTH_IN_CHUNKS
		var generated_chunks = preview_world.loaded_chunks.size()
		
		progress_bar.max_value = total_chunks
		progress_bar.value = generated_chunks
		
		if generated_chunks == total_chunks and generate_button.disabled:
			generate_button.disabled = false
			progress_bar.value = progress_bar.max_value

func _on_generate_pressed():
	generate_button.disabled = true
	
	if is_instance_valid(preview_world):
		preview_world.queue_free()

	preview_world = WorldScene.instantiate()
	# --- FIX: Set the flag to allow processing in the editor ---
	preview_world.is_preview = true
	
	# Enable preview mode for better performance
	if preview_world.generator:
		preview_world.generator.preview_mode = true
		preview_world.generator.verbose_logging = verbose_toggle.button_pressed
	
	sub_viewport.add_child(preview_world)
	
	var world_width_in_chunks = preview_world.WORLD_WIDTH_IN_CHUNKS
	
	# Generate the ENTIRE world, not just a small preview
	print("Generating full world preview: ", world_width_in_chunks, "x", world_width_in_chunks, " chunks")
	for x in range(world_width_in_chunks):
		for z in range(world_width_in_chunks):
			preview_world.load_chunk(Vector2i(x, z))

	# Reposition camera to frame the entire world
	var world_center = (world_width_in_chunks * preview_world.CHUNK_SIZE) * 0.5
	var world_extent = (world_width_in_chunks * preview_world.CHUNK_SIZE)
	preview_camera.position = Vector3(world_center, max(400.0, preview_world.CHUNK_HEIGHT * 2.0), world_center + world_extent * 0.3)
	preview_camera.look_at(Vector3(world_center, 0, world_center))

@tool
extends PanelContainer

const WorldScene = preload("res://src/core/world/world.tscn")

@onready var generate_button = $VBoxContainer/Button
@onready var viewport_container = $VBoxContainer/SubViewportContainer
@onready var sub_viewport = SubViewport.new()

var preview_world = null
var preview_camera = null

func _ready():
	generate_button.text = "Generate Preview"
	generate_button.pressed.connect(_on_generate_pressed)

	viewport_container.add_child(sub_viewport)
	sub_viewport.size = viewport_container.size

	# Create a camera for the preview
	preview_camera = Camera3D.new()
	preview_camera.position = Vector3(32, 70, 32)
	preview_camera.look_at(Vector3.ZERO)
	sub_viewport.add_child(preview_camera)

func _on_generate_pressed():
	if is_instance_valid(preview_world):
		preview_world.queue_free()

	preview_world = WorldScene.instantiate()
	sub_viewport.add_child(preview_world)

	# Generate a 3x3 grid of chunks for the preview
	for x in range(-1, 2):
		for z in range(-1, 2):
			var chunk_pos = Vector2i(x, z)
			preview_world.load_chunk(chunk_pos)

	# Force immediate mesh generation
	for chunk_pos in preview_world.loaded_chunks:
		var chunk = preview_world.loaded_chunks[chunk_pos]
		var padded_data = preview_world.get_padded_data_for_chunk(chunk_pos)
		chunk.generate_mesh(padded_data)

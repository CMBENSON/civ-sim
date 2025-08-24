# addons/world_preview/world_preview_panel.gd
@tool
extends PanelContainer

const WorldScene = preload("res://src/core/world/world.tscn")

@onready var generate_button     = $VBoxContainer/Button
@onready var progress_bar        = $VBoxContainer/ProgressBar
@onready var viewport_container  = $VBoxContainer/SubViewportContainer
@onready var verbose_toggle      = $VBoxContainer/VerboseToggle

# The SubViewport we render the 3D world into
@onready var sub_viewport : SubViewport = SubViewport.new()

var preview_world : Node3D
var preview_camera : Camera3D

# 2D biome preview
var map_texture_rect : TextureRect
var map_image        : Image

# Stop button for cancelling generation
var stop_button : Button

# Flag to avoid regenerating the map on every process tick
var biome_map_generated : bool = false

func _ready() -> void:
	generate_button.text = "Generate Full Preview"
	generate_button.pressed.connect(_on_generate_pressed)

	# Create the stop button programmatically and add it next to the generate button
	stop_button = Button.new()
	stop_button.text = "Stop"
	stop_button.visible = false
	stop_button.pressed.connect(_on_stop_pressed)
	$VBoxContainer.add_child(stop_button)

	# Insert the SubViewport into the viewport container
	viewport_container.add_child(sub_viewport)

	# Set up the camera (orthographic)
	preview_camera = Camera3D.new()
	preview_camera.near = 0.1
	preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	sub_viewport.add_child(preview_camera)

	# Create a TextureRect for the biome map and add it to the panel
	map_texture_rect = TextureRect.new()
	map_texture_rect.expand = true
	map_texture_rect.size_flags_vertical = 3  # EXPAND | FILL
	map_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	$VBoxContainer.add_child(map_texture_rect)

func _process(_delta: float) -> void:
	# Update the progress bar
	if is_instance_valid(preview_world):
		var total_chunks     = preview_world.WORLD_WIDTH_IN_CHUNKS * preview_world.WORLD_WIDTH_IN_CHUNKS
		var generated_chunks = preview_world.loaded_chunks.size()
		progress_bar.max_value = total_chunks
		progress_bar.value     = generated_chunks

		# When generation finishes, enable the Generate button and build the map once
		if generated_chunks == total_chunks and generate_button.disabled:
			generate_button.disabled = false
			stop_button.visible = false
			progress_bar.value = progress_bar.max_value

			if not biome_map_generated:
				biome_map_generated = true
				_generate_biome_map_from_chunks()

func _on_generate_pressed() -> void:
	# Randomize the global random seed so WorldGenerator uses different seeds each time.
	randomize()

	generate_button.disabled = true
	stop_button.visible      = true
	biome_map_generated      = false

	# Clean up any existing world
	if is_instance_valid(preview_world):
		preview_world.queue_free()

	# Instantiate a new world for the preview
	preview_world = WorldScene.instantiate()
	preview_world.is_preview = true
	sub_viewport.add_child(preview_world)

	# Configure the generator for fast preview
	if preview_world.generator:
		preview_world.generator.preview_mode    = true
		preview_world.generator.verbose_logging = verbose_toggle.button_pressed

	# Load all chunks (square grid)
	var w_in_chunks = preview_world.WORLD_WIDTH_IN_CHUNKS
	for x in range(w_in_chunks):
		for z in range(w_in_chunks):
			preview_world.load_chunk(Vector2i(x, z))

	# Position the camera for an overhead orthographic view
	var chunk_sz     = preview_world.CHUNK_SIZE
	var grid_size    = w_in_chunks * chunk_sz
	var world_center = grid_size * 0.5

	preview_camera.projection       = Camera3D.PROJECTION_ORTHOGONAL
	preview_camera.size             = grid_size * 1.1
	preview_camera.far              = max(grid_size * 2.0, preview_world.CHUNK_HEIGHT * 4.0)
	preview_camera.position         = Vector3(world_center, preview_world.CHUNK_HEIGHT * 2.0, world_center)
	preview_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

func _on_stop_pressed() -> void:
	# Cancel any ongoing preview generation
	if is_instance_valid(preview_world):
		preview_world.queue_free()
	preview_world         = null
	biome_map_generated   = false
	generate_button.disabled = false
	stop_button.visible      = false
	progress_bar.value       = 0
	map_texture_rect.texture = null

# Generate a biome map by reading biome_data from each loaded chunk.
func _generate_biome_map_from_chunks() -> void:
	if not is_instance_valid(preview_world):
		return

	var w_in_chunks = preview_world.WORLD_WIDTH_IN_CHUNKS
	var chunk_sz    = preview_world.CHUNK_SIZE
	var img_sz      = w_in_chunks * chunk_sz

	# Create an image large enough to represent each voxel column exactly once.
	map_image = Image.create(img_sz, img_sz, false, Image.FORMAT_RGB8)

	# Colour palette indexed by biome ID. The order (0..7) follows WorldData.Biome:
	# 0: OCEAN, 1: MOUNTAINS, 2: TUNDRA, 3: PLAINS, 4: DESERT, 5: JUNGLE,
	# 6: FOREST, 7: SWAMP. Adjust colours as you refine your art direction.
	var biome_colours = {
		0: Color8(30, 144, 255),   # OCEAN
		1: Color8(107, 104, 103),  # MOUNTAINS
		2: Color8(143, 146, 150),  # TUNDRA
		3: Color8(101, 141, 65),   # PLAINS
		4: Color8(194, 178, 128),  # DESERT
		5: Color8(0, 102, 0),      # JUNGLE
		6: Color8(34, 139, 34),    # FOREST
		7: Color8(85, 107, 47)     # SWAMP
	}

	var gen = preview_world.generator

	# Iterate over every loaded chunk and fill in the corresponding pixels
	for chunk_pos in preview_world.loaded_chunks.keys():
		var chunk = preview_world.loaded_chunks[chunk_pos]
		if chunk == null or chunk.biome_data.is_empty():
			continue

		var base_x = chunk_pos.x * chunk_sz
		var base_z = chunk_pos.y * chunk_sz

		for local_x in range(chunk_sz):
			for local_z in range(chunk_sz):
				var biome_id = chunk.biome_data[local_x][local_z]
				var base_colour = biome_colours.get(biome_id, Color.GRAY)

				# Compute world coordinates for height shading
				var world_x = base_x + local_x
				var world_z = base_z + local_z

				var height = gen.get_height(world_x, world_z, preview_world.CHUNK_HEIGHT)
				# Apply height‑based shading: low areas dark, high areas light
				var norm = clamp((height - gen.sea_level) / 100.0, 0.0, 1.0)
				var shade = 0.6 + 0.4 * norm
				var final_colour = Color(base_colour.r * shade, base_colour.g * shade, base_colour.b * shade, 1.0)

				# Flip vertical axis so north is up
				map_image.set_pixel(world_x, img_sz - world_z - 1, final_colour)

	# Update the texture rect
	var tex = ImageTexture.create_from_image(map_image)
	map_texture_rect.texture = tex

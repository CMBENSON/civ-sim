# addons/world_preview/world_preview_panel.gd
@tool
extends PanelContainer

const WorldScene = preload("res://src/core/world/world.tscn")

@onready var generate_button     = $VBoxContainer/Button
@onready var progress_bar        = $VBoxContainer/ProgressBar
@onready var viewport_container  = $VBoxContainer/SubViewportContainer
@onready var verbose_toggle      = $VBoxContainer/VerboseToggle

# SubViewport created at run time
@onready var sub_viewport        : SubViewport = SubViewport.new()

var preview_world : Node3D
var preview_camera : Camera3D

# 2D biome preview
var map_texture_rect : TextureRect
var map_image        : Image

func _ready() -> void:
	generate_button.text = "Generate Full Preview"
	generate_button.pressed.connect(_on_generate_pressed)

	# Insert the SubViewport into the container
	viewport_container.add_child(sub_viewport)

	# Set up the camera once
	preview_camera = Camera3D.new()
	preview_camera.near = 0.1
	# start in perspective; we'll switch to orthographic later
	preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	sub_viewport.add_child(preview_camera)

	# Dynamically create a texture rect below the viewport for the biome map
	map_texture_rect = TextureRect.new()
	map_texture_rect.expand = true
	# 3 = SIZE_EXPAND_FILL (same flags used on the viewport)
	map_texture_rect.size_flags_vertical = 3
	map_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	$VBoxContainer.add_child(map_texture_rect)

func _process(_delta: float) -> void:
	# Update progress bar to reflect chunk loading
	if is_instance_valid(preview_world):
		var total_chunks      = preview_world.WORLD_WIDTH_IN_CHUNKS * preview_world.WORLD_WIDTH_IN_CHUNKS
		var generated_chunks  = preview_world.loaded_chunks.size()
		progress_bar.max_value = total_chunks
		progress_bar.value     = generated_chunks

		if generated_chunks == total_chunks and generate_button.disabled:
			generate_button.disabled = false
			progress_bar.value = progress_bar.max_value

func _on_generate_pressed() -> void:
	generate_button.disabled = true

	# Dispose of any previous preview world
	if is_instance_valid(preview_world):
		preview_world.queue_free()

	# Instantiate a fresh world for the preview
	preview_world = WorldScene.instantiate()
	preview_world.is_preview = true
	sub_viewport.add_child(preview_world)

	# Configure the generator for preview mode and verbose logging
	if preview_world.generator:
		preview_world.generator.preview_mode    = true
		preview_world.generator.verbose_logging = verbose_toggle.button_pressed

	# Load the entire world (square grid of chunks)
	var w_in_chunks    = preview_world.WORLD_WIDTH_IN_CHUNKS
	for x in range(w_in_chunks):
		for z in range(w_in_chunks):
			preview_world.load_chunk(Vector2i(x, z))

	# Reposition the camera for a top‑down orthographic view.
	var chunk_sz     = preview_world.CHUNK_SIZE
	var grid_size    = w_in_chunks * chunk_sz
	var world_center = grid_size * 0.5

	preview_camera.projection       = Camera3D.PROJECTION_ORTHOGONAL
	# Size defines the span of the orthographic projection (similar to zoom).
	# We add a margin so the world fits comfortably in view.
	preview_camera.size             = grid_size * 1.1
	preview_camera.far              = max(grid_size * 2.0, preview_world.CHUNK_HEIGHT * 4.0)
	# Position directly above the centre and look straight down
	preview_camera.position         = Vector3(world_center, preview_world.CHUNK_HEIGHT * 2.0, world_center)
	preview_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	# Build the 2D biome map to match the loaded area
	_generate_biome_map()

	generate_button.disabled = false

# Creates a top‑down colour map of biomes and height for debugging.
func _generate_biome_map() -> void:
	if not is_instance_valid(preview_world):
		return

	var gen    = preview_world.generator
	var width  = preview_world.WORLD_WIDTH_IN_CHUNKS * preview_world.CHUNK_SIZE
	# Down‑sample large worlds to keep generation time reasonable
	var resolution = min(512, width)
	var step       = width / float(resolution)

	map_image = Image.create(resolution, resolution, false, Image.FORMAT_RGB8)

	# Map biome names to colours. Tweak these values to suit your art style.
	var biome_colours = {
		"OCEAN":     Color8(30, 144, 255),
		"PLAINS":    Color8(101, 141, 65),
		"DESERT":    Color8(194, 178, 128),
		"MOUNTAINS": Color8(107, 104, 103),
		"TUNDRA":    Color8(143, 146, 150),
		"JUNGLE":    Color8(0, 102, 0),
		"FOREST":    Color8(34, 139, 34),
		"SWAMP":     Color8(85, 107, 47)
	}

	progress_bar.max_value = resolution
	progress_bar.value     = 0

	for x in range(resolution):
		for z in range(resolution):
			var wx   = x * step
			var wz   = z * step
			var info = gen.get_debug_info(wx, wz)
			var base = biome_colours.get(info.biome_name, Color.GRAY)

			# Use height to shade lighter (higher) or darker (lower) terrain
			var h_norm = clamp((info.height - gen.sea_level) / 100.0, 0.0, 1.0)
			var shade  = 0.6 + 0.4 * h_norm
			var final  = Color(base.r * shade, base.g * shade, base.b * shade, 1.0)

			# Flip the vertical axis so north is up
			map_image.set_pixel(x, resolution - z - 1, final)

		progress_bar.value = x
		# Yield a frame to update the UI during generation
		await get_tree().process_frame

	var tex = ImageTexture.create_from_image(map_image)
	map_texture_rect.texture = tex
	progress_bar.value = progress_bar.max_value

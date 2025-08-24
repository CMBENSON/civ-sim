@tool
extends PanelContainer

const WorldScene = preload("res://src/core/world/world.tscn")

@onready var generate_button     = $VBoxContainer/Button
@onready var progress_bar        = $VBoxContainer/ProgressBar
@onready var viewport_container  = $VBoxContainer/SubViewportContainer
@onready var verbose_toggle      = $VBoxContainer/VerboseToggle
@onready var sub_viewport        = SubViewport.new()

var preview_world: Node3D
var preview_camera: Camera3D
var map_texture_rect: TextureRect  # new: holds the 2D biome map
var map_image: Image               # new: used to build the map

func _ready() -> void:
	generate_button.text = "Generate Full Preview"
	generate_button.pressed.connect(_on_generate_pressed)

	viewport_container.add_child(sub_viewport)

	# Set up the preview camera as before
	preview_camera = Camera3D.new()
	preview_camera.near = 0.1
	sub_viewport.add_child(preview_camera)
	preview_camera.position = Vector3(128, 800, 160)
	preview_camera.look_at(Vector3(128, 0, 128))

	# Create a TextureRect for the biome map and add it to the panel
	map_texture_rect = TextureRect.new()
	map_texture_rect.expand = true
	map_texture_rect.size_flags_vertical = 3  # Control.SIZE_EXPAND_FILL
	map_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	$VBoxContainer.add_child(map_texture_rect)

func _process(_delta):
	if is_instance_valid(preview_world):
		var total_chunks = preview_world.WORLD_WIDTH_IN_CHUNKS * preview_world.WORLD_WIDTH_IN_CHUNKS
		var generated_chunks = preview_world.loaded_chunks.size()
		
		progress_bar.max_value = total_chunks
		progress_bar.value = generated_chunks
		
		if generated_chunks == total_chunks and generate_button.disabled:
			generate_button.disabled = false
			progress_bar.value = progress_bar.max_value

func _on_generate_pressed() -> void:
	generate_button.disabled = true

	# Remove the previous world, if any
	if is_instance_valid(preview_world):
		preview_world.queue_free()

	# Instantiate world and enable preview flags
	preview_world = WorldScene.instantiate()
	preview_world.is_preview = true
	if preview_world.generator:
		preview_world.generator.preview_mode = true
		preview_world.generator.verbose_logging = verbose_toggle.button_pressed

	sub_viewport.add_child(preview_world)

	var world_width_in_chunks = preview_world.WORLD_WIDTH_IN_CHUNKS
	for x in range(world_width_in_chunks):
		for z in range(world_width_in_chunks):
			preview_world.load_chunk(Vector2i(x, z))

	# Frame the whole world as before
	var world_center  = (world_width_in_chunks * preview_world.CHUNK_SIZE) * 0.5
	var world_extent  = world_width_in_chunks * preview_world.CHUNK_SIZE
	preview_camera.position = Vector3(world_center, max(400.0, preview_world.CHUNK_HEIGHT * 2.0), world_center + world_extent * 0.3)
	preview_camera.look_at(Vector3(world_center, 0, world_center))

	# Generate the 2D biome map
	_generate_biome_map()
	generate_button.disabled = false

func _generate_biome_map() -> void:
	if not is_instance_valid(preview_world):
		return
	var gen      = preview_world.generator
	var voxel_w  = preview_world.WORLD_WIDTH_IN_CHUNKS * preview_world.CHUNK_SIZE
	var resolution = min(512, voxel_w)  # down-sample large worlds
	var step    = voxel_w / float(resolution)

	map_image = Image.create(resolution, resolution, false, Image.FORMAT_RGB8)

	# Map biome names to colours; tweak as needed
	var biome_colours = {
		"OCEAN":    Color8(30, 144, 255),
		"PLAINS":   Color8(101, 141, 65),
		"DESERT":   Color8(194, 178, 128),
		"MOUNTAINS":Color8(107, 104, 103),
		"TUNDRA":   Color8(143, 146, 150),
		"JUNGLE":   Color8(0, 102, 0),
		"FOREST":   Color8(34, 139, 34),
		"SWAMP":    Color8(85, 107, 47)
	}

	progress_bar.max_value = resolution
	progress_bar.value     = 0

	for x in range(resolution):
		for z in range(resolution):
			var world_x = x * step
			var world_z = z * step
			var info    = gen.get_debug_info(world_x, world_z)
			var name    = info.biome_name
			var height  = info.height
			var base    = biome_colours.get(name, Color.GRAY)
			# Lighten or darken by height; values > sea_level appear brighter
			var norm    = clamp((height - gen.sea_level) / 100.0, 0.0, 1.0)
			var shade   = 0.6 + 0.4 * norm
			var final_c = Color(base.r * shade, base.g * shade, base.b * shade, 1.0)
			# Flip the z axis so north is at the top of the image
			map_image.set_pixel(x, resolution - z - 1, final_c)
		# update the progress bar each column; optional yield for UI update
		progress_bar.value = x
		await get_tree().process_frame

	var tex = ImageTexture.create_from_image(map_image)
	map_texture_rect.texture = tex
	progress_bar.value       = progress_bar.max_value

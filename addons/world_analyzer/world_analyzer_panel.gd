@tool
extends Control

const WorldGenerator = preload("res://src/core/world/WorldGenerator.gd")

var generator: RefCounted
var analysis_texture: ImageTexture

@onready var generate_button = $VBox/GenerateButton
@onready var texture_rect = $VBox/TextureRect
@onready var biome_info = $VBox/BiomeInfo

func _ready():
	generate_button.pressed.connect(_on_generate_pressed)
	_setup_ui()

func _setup_ui():
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	generate_button = Button.new()
	generate_button.text = "Generate World Analysis"
	vbox.add_child(generate_button)
	
	texture_rect = TextureRect.new()
	texture_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(texture_rect)
	
	biome_info = RichTextLabel.new()
	biome_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(biome_info)

func _on_generate_pressed():
	print("Generating world analysis...")
	generate_button.disabled = true
	
	generator = WorldGenerator.new(1024, 16)
	
	var img = Image.create(512, 512, false, Image.FORMAT_RGB8)
	var biome_counts = {}
	var total_samples = 0
	
	for x in range(512):
		for z in range(512):
			var world_x = (x / 512.0) * 1024
			var world_z = (z / 512.0) * 1024
			
			var height = generator.get_height(world_x, world_z, 64)
			var biome = generator.get_biome(world_x, world_z)
			var is_ocean = generator.is_ocean(world_x, world_z)
			
			# Count biomes
			biome_counts[biome] = biome_counts.get(biome, 0) + 1
			total_samples += 1
			
			# Color the pixel based on biome and height
			var color = _get_biome_color(biome, height, generator.sea_level)
			img.set_pixel(x, z, color)
	
	analysis_texture = ImageTexture.create_from_image(img)
	texture_rect.texture = analysis_texture
	
	# Show biome distribution
	_update_biome_info(biome_counts, total_samples)
	
	generate_button.disabled = false
	print("World analysis complete!")

func _get_biome_color(biome: int, height: float, sea_level: float) -> Color:
	var base_colors = {
		0: Color(0.1, 0.3, 0.8),    # OCEAN - blue
		1: Color(0.5, 0.5, 0.5),    # MOUNTAINS - gray
		2: Color(0.8, 0.8, 1.0),    # TUNDRA - light blue
		3: Color(0.2, 0.7, 0.2),    # PLAINS - green
		4: Color(0.9, 0.8, 0.4),    # DESERT - yellow
		5: Color(0.1, 0.5, 0.1),    # JUNGLE - dark green
		6: Color(0.2, 0.6, 0.2),    # FOREST - medium green
		7: Color(0.3, 0.4, 0.2)     # SWAMP - brown-green
	}
	
	var color = base_colors.get(biome, Color.MAGENTA)
	
	# Add height-based shading
	if biome != 0:  # Not ocean
		var height_factor = (height - sea_level) / 50.0
		height_factor = clamp(height_factor, -0.3, 0.3)
		color = color * (1.0 + height_factor)
	
	return color

func _update_biome_info(biome_counts: Dictionary, total: int):
	var biome_names = ["Ocean", "Mountains", "Tundra", "Plains", "Desert", "Jungle", "Forest", "Swamp"]
	var text = "[color=yellow]Biome Distribution:[/color]\n"
	
	for biome_id in biome_counts:
		var percentage = (biome_counts[biome_id] * 100.0) / total
		var name = biome_names[biome_id] if biome_id < biome_names.size() else "Unknown"
		text += "%s: %.1f%%\n" % [name, percentage]
	
	biome_info.text = text

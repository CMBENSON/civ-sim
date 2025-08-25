# src/core/world/ModularWorldGenerator.gd
extends RefCounted
class_name ModularWorldGenerator

# Component systems
var noise_manager: NoiseManager
var biome_generator: BiomeGenerator
var height_generator: HeightGenerator

# Compatibility interface for existing code
var sea_level: float = 28.0 :
	set(value):
		sea_level = value
		if height_generator:
			height_generator.set_sea_level(value)
		if biome_generator:
			biome_generator.set_sea_level(value)

var world_circumference_voxels: int :
	set(value):
		world_circumference_voxels = value
		if noise_manager:
			noise_manager.world_circumference_voxels = value

var chunk_size: int :
	set(value):
		chunk_size = value

var chunk_height: int = 64 :
	set(value):
		chunk_height = value
		if height_generator:
			height_generator.set_chunk_height(value)

var preview_mode: bool = false :
	set(value):
		preview_mode = value
		if height_generator:
			height_generator.set_preview_mode(value)

var verbose_logging: bool = false :
	set(value):
		verbose_logging = value
		if noise_manager:
			noise_manager.set_verbose_logging(value)
		if biome_generator:
			biome_generator.set_verbose_logging(value)
		if height_generator:
			height_generator.set_verbose_logging(value)

func _init(p_world_circumference_voxels: int, p_chunk_size: int):
	world_circumference_voxels = p_world_circumference_voxels
	chunk_size = p_chunk_size
	
	# Initialize component systems
	noise_manager = NoiseManager.new(p_world_circumference_voxels)
	biome_generator = BiomeGenerator.new(noise_manager)
	height_generator = HeightGenerator.new(noise_manager, biome_generator)
	
	# Set initial parameters
	biome_generator.set_sea_level(sea_level)
	height_generator.set_sea_level(sea_level)
	height_generator.set_chunk_height(chunk_height)
	
	if verbose_logging:
		print("ModularWorldGenerator: Initialized with circumference=", p_world_circumference_voxels, ", chunk_size=", p_chunk_size)

# Compatibility interface methods
func get_height(world_x: float, world_z: float, p_chunk_height: int) -> float:
	return height_generator.get_height(world_x, world_z)

func get_biome(world_x: float, world_z: float) -> int:
	var height = height_generator.get_height(world_x, world_z)
	return biome_generator.get_biome(world_x, world_z, height)

func is_ocean(world_x: float, world_z: float) -> bool:
	return biome_generator.is_ocean(world_x, world_z)

func get_temperature_01(world_x: float, world_z: float) -> float:
	return biome_generator.get_temperature_01(world_x, world_z)

func get_moisture_01(world_x: float, world_z: float) -> float:
	return biome_generator.get_moisture_01(world_x, world_z)

func get_debug_info(world_x: float, world_z: float) -> Dictionary:
	var height = height_generator.get_height(world_x, world_z)
	var biome_info = biome_generator.get_debug_info(world_x, world_z, height)
	var height_info = height_generator.get_debug_info(world_x, world_z)
	
	# Merge debug information
	var combined_info = {}
	combined_info.merge(biome_info)
	combined_info.merge(height_info)
	
	return combined_info

# Advanced analysis methods
func analyze_world_generation(sample_size: int = 1000) -> Dictionary:
	"""Analyze world generation quality across a sample of points"""
	var sample_points = []
	
	# Generate sample points across the world
	for i in range(sample_size):
		var x = randf() * world_circumference_voxels
		var z = (randf() - 0.5) * world_circumference_voxels  # Allow negative Z for north-south spread
		sample_points.append(Vector2(x, z))
	
	# Get biome and height analysis
	var biome_analysis = biome_generator.analyze_biome_distribution(sample_points)
	var height_analysis = height_generator.analyze_height_distribution(sample_points)
	
	return {
		"sample_size": sample_size,
		"biome_distribution": biome_analysis,
		"height_distribution": height_analysis,
		"generation_parameters": get_all_tuning_parameters()
	}

func get_all_tuning_parameters() -> Dictionary:
	"""Get all tuning parameters from all generators"""
	var all_params = {}
	
	if biome_generator:
		all_params["biome"] = biome_generator.get_tuning_parameters()
	
	if height_generator:
		all_params["height"] = height_generator.get_tuning_parameters()
	
	if noise_manager:
		all_params["noise"] = noise_manager.get_noise_info()
	
	return all_params

func set_all_tuning_parameters(params: Dictionary):
	"""Set tuning parameters for all generators"""
	if params.has("biome") and biome_generator:
		biome_generator.set_tuning_parameters(params.biome)
	
	if params.has("height") and height_generator:
		height_generator.set_tuning_parameters(params.height)

func regenerate_with_new_seed(new_seed: int = 0):
	"""Regenerate noise with a new seed"""
	if new_seed == 0:
		new_seed = randi()
	
	# Reinitialize noise manager with new seed
	noise_manager = NoiseManager.new(world_circumference_voxels, new_seed)
	
	# Update references
	biome_generator.noise_manager = noise_manager
	height_generator.noise_manager = noise_manager
	
	if verbose_logging:
		print("ModularWorldGenerator: Regenerated with new seed ", new_seed)

func get_world_preview_data(resolution: int = 256) -> Dictionary:
	"""Generate preview data for world visualization"""
	var preview_data = {
		"resolution": resolution,
		"biome_map": [],
		"height_map": [],
		"temperature_map": [],
		"moisture_map": []
	}
	
	var step = float(world_circumference_voxels) / float(resolution)
	
	for y in range(resolution):
		preview_data.biome_map.append([])
		preview_data.height_map.append([])
		preview_data.temperature_map.append([])
		preview_data.moisture_map.append([])
		
		for x in range(resolution):
			var world_x = x * step
			var world_z = (y - resolution / 2) * step  # Center on equator
			
			var height = height_generator.get_height(world_x, world_z)
			var biome = biome_generator.get_biome(world_x, world_z, height)
			var temp = biome_generator.get_temperature_01(world_x, world_z)
			var moisture = biome_generator.get_moisture_01(world_x, world_z)
			
			preview_data.biome_map[y].append(biome)
			preview_data.height_map[y].append(height)
			preview_data.temperature_map[y].append(temp)
			preview_data.moisture_map[y].append(moisture)
	
	return preview_data

func export_world_data(filename: String):
	"""Export world generation data to a file"""
	var analysis = analyze_world_generation(2000)
	var preview = get_world_preview_data(128)
	
	var export_data = {
		"timestamp": Time.get_datetime_string_from_system(),
		"world_parameters": {
			"circumference": world_circumference_voxels,
			"chunk_size": chunk_size,
			"chunk_height": chunk_height,
			"sea_level": sea_level
		},
		"analysis": analysis,
		"preview_data": preview
	}
	
	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(export_data))
		file.close()
		print("ModularWorldGenerator: Exported world data to ", filename)
	else:
		print("ModularWorldGenerator: Failed to export to ", filename)

# Component access methods for advanced usage
func get_noise_manager() -> NoiseManager:
	return noise_manager

func get_biome_generator() -> BiomeGenerator:
	return biome_generator

func get_height_generator() -> HeightGenerator:
	return height_generator

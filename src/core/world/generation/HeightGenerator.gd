# src/core/world/generation/HeightGenerator.gd
extends RefCounted
class_name HeightGenerator

var noise_manager: NoiseManager
var biome_generator: BiomeGenerator
var sea_level: float = 28.0
var chunk_height: int = 64
var preview_mode: bool = false
var verbose_logging: bool = false

# Height generation parameters - tunable
var base_height_amplitude: float = 12.0
var mountain_amplitude: float = 40.0
var mountain_variation_amplitude: float = 12.0
var detail_amplitude: float = 6.0
var minimum_land_height: float = 4.0
var maximum_height: float = 120.0

# Smoothing parameters
var smoothing_enabled: bool = true
var smoothing_distance: float = 8.0
var smoothing_weight_factor: float = 0.3

func _init(p_noise_manager: NoiseManager, p_biome_generator: BiomeGenerator = null):
	noise_manager = p_noise_manager
	biome_generator = p_biome_generator

func set_sea_level(level: float):
	sea_level = level
	if biome_generator:
		biome_generator.set_sea_level(level)

func set_chunk_height(height: int):
	chunk_height = height

func set_preview_mode(enabled: bool):
	preview_mode = enabled

func set_verbose_logging(enabled: bool):
	verbose_logging = enabled

func get_height(world_x: float, world_z: float) -> float:
	# Check if this is ocean first
	if biome_generator and biome_generator.is_ocean(world_x, world_z):
		return sea_level

	var mid = float(chunk_height) / 2.0  # Mid altitude baseline

	# Base terrain variation with smoother hills
	var hills = noise_manager.get_base_height(world_x, world_z) * base_height_amplitude
	var height = mid + hills

	# Mountain generation with better distribution
	var cont_val = noise_manager.get_continent_value(world_x, world_z)
	# Mountains appear in high continental areas
	if cont_val > 0.3:
		var mountain_strength = (cont_val - 0.3) / 0.7  # Normalize to 0–1
		
		# Primary mountain height
		var m_height = noise_manager.get_mountain_height(world_x, world_z) * mountain_amplitude
		height += mountain_strength * m_height

		# Add variation to mountains to prevent uniform peaks
		var var_height = noise_manager.get_mountain_variation(world_x, world_z) * mountain_variation_amplitude
		height += mountain_strength * var_height
		
		if verbose_logging and randi() % 1000 == 0:  # Log occasionally to avoid spam
			print("HeightGen[%.0f,%.0f]: Mountain height %.1f (strength=%.2f, base=%.1f)" % [world_x, world_z, height, mountain_strength, mid + hills])

	# Add detail noise for extra variation everywhere
	var detail_height = noise_manager.get_detail_height(world_x, world_z) * detail_amplitude
	height += detail_height

	# Apply smoothing in full mode (not in preview)
	if smoothing_enabled and not preview_mode:
		height = _smooth_height(world_x, world_z, height)

	# Ensure minimum land height above sea level
	if height < sea_level + minimum_land_height:
		height = sea_level + minimum_land_height

	# Cap maximum height to prevent extreme peaks
	var max_height = sea_level + maximum_height
	if height > max_height:
		height = max_height

	return height

func get_raw_height(world_x: float, world_z: float) -> float:
	"""Get height without smoothing - used internally and for analysis"""
	var mid = float(chunk_height) / 2.0
	var hills = noise_manager.get_base_height(world_x, world_z) * base_height_amplitude
	var height = mid + hills

	var cont_val = noise_manager.get_continent_value(world_x, world_z)
	if cont_val > 0.3:
		var mountain_strength = (cont_val - 0.3) / 0.7
		var m_height = noise_manager.get_mountain_height(world_x, world_z) * mountain_amplitude
		height += mountain_strength * m_height

		var var_height = noise_manager.get_mountain_variation(world_x, world_z) * mountain_variation_amplitude
		height += mountain_strength * var_height

	var detail_height = noise_manager.get_detail_height(world_x, world_z) * detail_amplitude
	height += detail_height

	return height

func _smooth_height(world_x: float, world_z: float, base_height: float) -> float:
	"""Apply smoothing to height for more natural terrain transitions"""
	var total_height = base_height
	var total_weight = 1.0

	# Sample fewer neighbors for performance
	var sample_points = [
		Vector2(-1, -1), Vector2(1, -1),
		Vector2(-1, 1),  Vector2(1, 1)
	]

	for sample_offset in sample_points:
		var sample_x = world_x + sample_offset.x * smoothing_distance
		var sample_z = world_z + sample_offset.y * smoothing_distance

		var distance = sample_offset.length()
		var weight = 1.0 / (1.0 + distance * smoothing_weight_factor)

		# Get raw height at sample point to avoid infinite recursion
		var sample_height = get_raw_height(sample_x, sample_z)

		total_height += sample_height * weight
		total_weight += weight

	return total_height / total_weight

func analyze_height_distribution(sample_points: Array) -> Dictionary:
	"""Analyze height distribution across given sample points"""
	var heights = []
	var ocean_count = 0
	var land_count = 0
	var mountain_count = 0
	
	for point in sample_points:
		if biome_generator and biome_generator.is_ocean(point.x, point.y):
			heights.append(sea_level)
			ocean_count += 1
		else:
			var height = get_height(point.x, point.y)
			heights.append(height)
			land_count += 1
			
			# Count as mountain if significantly above sea level
			if height > sea_level + 30.0:
				mountain_count += 1
	
	# Calculate statistics
	heights.sort()
	var total_points = sample_points.size()
	var min_height = heights[0] if heights.size() > 0 else sea_level
	var max_height = heights[heights.size() - 1] if heights.size() > 0 else sea_level
	var avg_height = 0.0
	
	for h in heights:
		avg_height += h
	avg_height = avg_height / float(heights.size()) if heights.size() > 0 else sea_level
	
	# Get median
	var median_height = heights[heights.size() / 2] if heights.size() > 0 else sea_level
	
	return {
		"total_samples": total_points,
		"ocean_percentage": (float(ocean_count) / float(total_points)) * 100.0,
		"land_percentage": (float(land_count) / float(total_points)) * 100.0,
		"mountain_percentage": (float(mountain_count) / float(total_points)) * 100.0,
		"min_height": min_height,
		"max_height": max_height,
		"average_height": avg_height,
		"median_height": median_height,
		"sea_level": sea_level,
		"height_range": max_height - min_height
	}

func get_tuning_parameters() -> Dictionary:
	"""Get current height generation parameters for tuning"""
	return {
		"base_height_amplitude": base_height_amplitude,
		"mountain_amplitude": mountain_amplitude,
		"mountain_variation_amplitude": mountain_variation_amplitude,
		"detail_amplitude": detail_amplitude,
		"minimum_land_height": minimum_land_height,
		"maximum_height": maximum_height,
		"smoothing_enabled": smoothing_enabled,
		"smoothing_distance": smoothing_distance,
		"smoothing_weight_factor": smoothing_weight_factor,
		"sea_level": sea_level,
		"chunk_height": chunk_height
	}

func set_tuning_parameters(params: Dictionary):
	"""Set height generation parameters for tuning"""
	if params.has("base_height_amplitude"):
		base_height_amplitude = params.base_height_amplitude
	if params.has("mountain_amplitude"):
		mountain_amplitude = params.mountain_amplitude
	if params.has("mountain_variation_amplitude"):
		mountain_variation_amplitude = params.mountain_variation_amplitude
	if params.has("detail_amplitude"):
		detail_amplitude = params.detail_amplitude
	if params.has("minimum_land_height"):
		minimum_land_height = params.minimum_land_height
	if params.has("maximum_height"):
		maximum_height = params.maximum_height
	if params.has("smoothing_enabled"):
		smoothing_enabled = params.smoothing_enabled
	if params.has("smoothing_distance"):
		smoothing_distance = params.smoothing_distance
	if params.has("smoothing_weight_factor"):
		smoothing_weight_factor = params.smoothing_weight_factor

func get_debug_info(world_x: float, world_z: float) -> Dictionary:
	"""Get detailed debug information for height generation at a point"""
	var is_ocean_val = biome_generator.is_ocean(world_x, world_z) if biome_generator else false
	var cont_val = noise_manager.get_continent_value(world_x, world_z)
	var base_height_val = noise_manager.get_base_height(world_x, world_z)
	var mountain_height_val = noise_manager.get_mountain_height(world_x, world_z)
	var detail_height_val = noise_manager.get_detail_height(world_x, world_z)
	
	var final_height = get_height(world_x, world_z)
	var raw_height = get_raw_height(world_x, world_z)
	
	return {
		"final_height": final_height,
		"raw_height": raw_height,
		"is_ocean": is_ocean_val,
		"continent_value": cont_val,
		"base_height_noise": base_height_val,
		"mountain_height_noise": mountain_height_val,
		"detail_height_noise": detail_height_val,
		"sea_level": sea_level,
		"chunk_height": chunk_height,
		"is_mountain_area": cont_val > 0.3,
		"height_difference": final_height - sea_level,
		"smoothing_applied": smoothing_enabled and not preview_mode
	}

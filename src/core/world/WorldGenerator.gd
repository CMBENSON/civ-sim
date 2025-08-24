# src/core/world/WorldGenerator.gd
extends RefCounted

# Public parameters
var sea_level: float = 28.0
var world_circumference_voxels: int
var chunk_size: int
var chunk_height: int = 64
var preview_mode: bool = false  # Performance toggle for preview
var verbose_logging: bool = false  # Debug output toggle

# Noise generators
var continent_noise: FastNoiseLite
var base_noise: FastNoiseLite
var mountain_noise: FastNoiseLite
var temp_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var detail_noise: FastNoiseLite

func _init(p_world_circumference_voxels: int, p_chunk_size: int) -> void:
	world_circumference_voxels = p_world_circumference_voxels
	chunk_size = p_chunk_size

	# Large-scale continents: very low frequency -> big land masses (planet scale)
	continent_noise = FastNoiseLite.new()
	continent_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	continent_noise.seed = randi()
	continent_noise.frequency = 0.0005   # Reduced for planet-scale continents

	# Base hills: moderate frequency -> rolling terrain
	base_noise = FastNoiseLite.new()
	base_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	base_noise.seed = randi()
	base_noise.frequency = 0.01  # Reduced for planet-scale features

	# Mountain peaks: smaller scale -> craggy mountains
	mountain_noise = FastNoiseLite.new()
	mountain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	mountain_noise.seed = randi()
	mountain_noise.frequency = 0.005  # Reduced for planet-scale mountains

	# Temperature & moisture
	temp_noise = FastNoiseLite.new()
	temp_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temp_noise.seed = randi()
	temp_noise.frequency = 0.004  # Reduced for planet-scale climate zones

	moisture_noise = FastNoiseLite.new()
	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	moisture_noise.seed = randi()
	moisture_noise.frequency = 0.004  # Reduced for planet-scale climate zones
	
	# Add detail noise for more interesting terrain
	detail_noise = FastNoiseLite.new()
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.seed = randi()
	detail_noise.frequency = 0.05  # Reduced for planet-scale detail

func is_ocean(world_x: float, world_z: float) -> bool:
	# Wrap east–west coordinate
	var nx = fmod(world_x, float(world_circumference_voxels))
	if nx < 0.0:
		nx += float(world_circumference_voxels)
	# Continents: noise in [-1,1]; threshold below -0.5 yields ocean (more land)
	return continent_noise.get_noise_2d(nx, world_z) < -0.5

func get_height(world_x: float, world_z: float, p_chunk_height: int) -> float:
	# Ocean cells: flat at sea level
	if is_ocean(world_x, world_z):
		return sea_level

	var mid = float(p_chunk_height) / 2.0  # mid altitude baseline

	# Base terrain variation with smoother hills (planet scale)
	var hills = base_noise.get_noise_2d(world_x, world_z) * 16.0  # Increased for planet scale
	var height = mid + hills

	# Mountain generation with better distribution (planet scale)
	var cont_val = continent_noise.get_noise_2d(world_x, world_z)
	if cont_val > 0.2:  # Lower threshold for more mountains
		var mountain_strength = (cont_val - 0.2) / 0.8  # Normalize to 0-1
		var m_height = mountain_noise.get_noise_2d(world_x, world_z) * 30.0  # Increased for planet scale
		height += mountain_strength * m_height
		
		# Add some variation to mountain heights
		var mountain_variation = FastNoiseLite.new()
		mountain_variation.seed = randi()
		mountain_variation.frequency = 0.025  # Reduced for planet scale
		height += mountain_variation.get_noise_2d(world_x, world_z) * 10.0  # Increased for planet scale

	# Add detail noise for more interesting terrain
	var detail_height = detail_noise.get_noise_2d(world_x, world_z) * 4.0  # Increased for planet scale
	height += detail_height

	# Apply smoothing to reduce height discontinuities (only in full mode)
	if not preview_mode:
		height = _smooth_height(world_x, world_z, height)

	# Ensure minimum land height above sea level
	if height < sea_level + 4.0:  # Increased for planet scale
		height = sea_level + 4.0
		
	# Cap maximum height to prevent extreme peaks (planet scale)
	var max_height = sea_level + 100.0  # Increased for planet scale
	if height > max_height:
		height = max_height
		
	return height

func _smooth_height(world_x: float, world_z: float, base_height: float) -> float:
	# Apply optimized smoothing with fewer samples for better performance
	var smoothing_distance = 8.0  # Increased distance, fewer samples
	var total_height = base_height
	var total_weight = 1.0
	
	# Sample only 4 nearby points instead of 25 for better performance
	var sample_points = [
		Vector2(-1, -1), Vector2(1, -1),
		Vector2(-1, 1), Vector2(1, 1)
	]
	
	for sample_offset in sample_points:
		var sample_x = world_x + sample_offset.x * smoothing_distance
		var sample_z = world_z + sample_offset.y * smoothing_distance
		
		# Calculate weight based on distance
		var distance = sample_offset.length()
		var weight = 1.0 / (1.0 + distance * 0.3)
		
		# Get height at sample point (avoiding ocean check to prevent infinite recursion)
		var sample_height = _get_raw_height(sample_x, sample_z)
		
		total_height += sample_height * weight
		total_weight += weight
	
	return total_height / total_weight

func _get_raw_height(world_x: float, world_z: float) -> float:
	# Get height without ocean check to avoid infinite recursion
	var mid = float(chunk_height) / 2.0
	var hills = base_noise.get_noise_2d(world_x, world_z) * 8.0
	var height = mid + hills
	
	var cont_val = continent_noise.get_noise_2d(world_x, world_z)
	if cont_val > 0.2:
		var mountain_strength = (cont_val - 0.2) / 0.8
		var m_height = mountain_noise.get_noise_2d(world_x, world_z) * 15.0
		height += mountain_strength * m_height
		
		var mountain_variation = FastNoiseLite.new()
		mountain_variation.seed = randi()
		mountain_variation.frequency = 0.05
		height += mountain_variation.get_noise_2d(world_x, world_z) * 5.0
	
	var detail_height = detail_noise.get_noise_2d(world_x, world_z) * 2.0
	height += detail_height
	
	return height

func get_temperature_01(world_x: float, world_z: float) -> float:
	var t = temp_noise.get_noise_2d(world_x, world_z)   # [-1,1]
	return (t + 1.0) * 0.5

func get_moisture_01(world_x: float, world_z: float) -> float:
	var m = moisture_noise.get_noise_2d(world_x, world_z)  # [-1,1]
	return (m + 1.0) * 0.5

func get_biome(world_x: float, world_z: float) -> int:
	if is_ocean(world_x, world_z):
		return WorldData.Biome.OCEAN
	
	var temp_01 = get_temperature_01(world_x, world_z)
	var moist_01 = get_moisture_01(world_x, world_z)
	var height = get_height(world_x, world_z, chunk_height)
	
	# Check for mountains first (based on height and continent noise)
	var cont_val = continent_noise.get_noise_2d(world_x, world_z)
	if cont_val > 0.2 and height > sea_level + 15.0:
		return WorldData.Biome.MOUNTAINS
	
	# Then check other biomes with improved logic
	if temp_01 < 0.25:  # Cold regions
		if moist_01 > 0.6:
			return WorldData.Biome.TUNDRA
		else:
			return WorldData.Biome.PLAINS
	elif temp_01 > 0.75:  # Hot regions
		if moist_01 < 0.35:
			return WorldData.Biome.DESERT
		elif moist_01 > 0.7:
			return WorldData.Biome.JUNGLE
		else:
			return WorldData.Biome.PLAINS
	else:  # Temperate regions
		if moist_01 > 0.7:
			return WorldData.Biome.FOREST
		elif moist_01 < 0.3:
			return WorldData.Biome.SWAMP
		else:
			return WorldData.Biome.PLAINS

func get_debug_info(world_x: float, world_z: float) -> Dictionary:
	var height = get_height(world_x, world_z, chunk_height)
	var biome = get_biome(world_x, world_z)
	var temp = get_temperature_01(world_x, world_z)
	var moist = get_moisture_01(world_x, world_z)
	var is_ocean_val = is_ocean(world_x, world_z)
	var cont_val = continent_noise.get_noise_2d(world_x, world_z)
	
	# Add biome name for easier debugging
	var biome_name = "UNKNOWN"
	if biome >= 0 and biome < WorldData.Biome.size():
		biome_name = WorldData.Biome.keys()[biome]
	
	return {
		"height": height,
		"biome": biome,
		"biome_name": biome_name,
		"temperature": temp,
		"moisture": moist,
		"is_ocean": is_ocean_val,
		"continent_value": cont_val,
		"sea_level": sea_level
	}

func print_biome_debug_info():
	# Only print debug info if verbose logging is enabled
	if not verbose_logging:
		return
		
	print("=== BIOME DEBUG INFO ===")
	print("Sea level: ", sea_level)
	print("Chunk height: ", chunk_height)
	
	# Test a few sample points to see biome distribution
	var test_points = [
		Vector2(0, 0),
		Vector2(50, 50),
		Vector2(100, 100),
		Vector2(150, 150),
		Vector2(200, 200)
	]
	
	for point in test_points:
		var debug_info = get_debug_info(point.x, point.y)
		print("Point (", point.x, ", ", point.y, "):")
		print("  Continent value: ", debug_info.continent_value)
		print("  Is ocean: ", debug_info.is_ocean)
		print("  Height: ", debug_info.height)
		print("  Biome: ", debug_info.biome_name, " (", debug_info.biome, ")")
		print("  Temperature: ", debug_info.temperature)
		print("  Moisture: ", debug_info.moisture)
		print("---")
	
	print("=== END BIOME DEBUG ===")

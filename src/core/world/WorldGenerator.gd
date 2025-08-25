# src/core/world/WorldGenerator.gd
extends RefCounted

# Public parameters
var sea_level: float = 28.0
var world_circumference_voxels: int
var chunk_size: int
var chunk_height: int = 64
var preview_mode: bool = false  # Performance toggle for preview
var verbose_logging: bool = false  # Debug output toggle - OFF by default

# Noise generators
var continent_noise: FastNoiseLite
var base_noise: FastNoiseLite
var mountain_noise: FastNoiseLite
var temp_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var detail_noise: FastNoiseLite

# Additional noise to vary mountain heights
var mountain_variation: FastNoiseLite

func _init(p_world_circumference_voxels: int, p_chunk_size: int) -> void:
	world_circumference_voxels = p_world_circumference_voxels
	chunk_size = p_chunk_size

	# Large-scale continents: slightly higher frequency so a 64-chunk world contains multiple landmasses.
	continent_noise = FastNoiseLite.new()
	continent_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	continent_noise.seed = randi()
	continent_noise.frequency = 0.0008

	# Base hills: higher frequency for more varied rolling terrain
	base_noise = FastNoiseLite.new()
	base_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	base_noise.seed = randi()
	base_noise.frequency = 0.02

	# Mountain peaks: higher frequency and larger amplitude for dramatic ranges
	mountain_noise = FastNoiseLite.new()
	mountain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	mountain_noise.seed = randi()
	mountain_noise.frequency = 0.01

	# Temperature & moisture: adjust for more distinct climate bands
	temp_noise = FastNoiseLite.new()
	temp_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temp_noise.seed = randi()
	temp_noise.frequency = 0.002

	moisture_noise = FastNoiseLite.new()
	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	moisture_noise.seed = randi()
	moisture_noise.frequency = 0.002

	# Detail noise adds small-scale variation
	detail_noise = FastNoiseLite.new()
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.seed = randi()
	detail_noise.frequency = 0.1

	# Pre-create a noise source for mountain variation to avoid per-call instantiation
	mountain_variation = FastNoiseLite.new()
	mountain_variation.noise_type = FastNoiseLite.TYPE_PERLIN
	mountain_variation.seed = randi()
	mountain_variation.frequency = 0.05

func is_ocean(world_x: float, world_z: float) -> bool:
	# Wrap east–west coordinate for cylindrical world
	var nx = fmod(world_x, float(world_circumference_voxels))
	if nx < 0.0:
		nx += float(world_circumference_voxels)
	# Adjust threshold: values below −0.3 are ocean. A less negative threshold yields more ocean.
	return continent_noise.get_noise_2d(nx, world_z) < -0.3

func get_height(world_x: float, world_z: float, p_chunk_height: int) -> float:
	# Ocean cells: flat at sea level
	if is_ocean(world_x, world_z):
		return sea_level

	var mid = float(p_chunk_height) / 2.0  # mid altitude baseline

	# Base terrain variation with smoother hills
	var hills = base_noise.get_noise_2d(world_x, world_z) * 12.0
	var height = mid + hills

	# Mountain generation with better distribution
	var cont_val = continent_noise.get_noise_2d(world_x, world_z)
	# Raise the threshold slightly so only the highest continental values spawn mountains
	if cont_val > 0.3:
		var mountain_strength = (cont_val - 0.3) / 0.7  # Normalize to 0–1
		# Increase mountain peak amplitude for more dramatic mountains
		var m_height = mountain_noise.get_noise_2d(world_x, world_z) * 40.0
		height += mountain_strength * m_height

		# Add precomputed variation noise to mountains
		var var_height = mountain_variation.get_noise_2d(world_x, world_z) * 12.0
		height += mountain_strength * var_height

	# Add detail noise for extra variation everywhere
	var detail_height = detail_noise.get_noise_2d(world_x, world_z) * 6.0
	height += detail_height

	# Optionally smooth heights in full mode (preview_mode off)
	if not preview_mode:
		height = _smooth_height(world_x, world_z, height)

	# Ensure minimum land height above sea level
	if height < sea_level + 4.0:
		height = sea_level + 4.0

	# Cap maximum height to prevent extreme peaks
	var max_height = sea_level + 120.0
	if height > max_height:
		height = max_height

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

	var temp_01  = get_temperature_01(world_x, world_z)
	var moist_01 = get_moisture_01(world_x, world_z)
	var height   = get_height(world_x, world_z, chunk_height)

	# Check for mountains first (based on height and continent noise)
	var cont_val = continent_noise.get_noise_2d(world_x, world_z)
	if cont_val > 0.3 and height > sea_level + 20.0:
		return WorldData.Biome.MOUNTAINS

	# Biome classification: adjust moisture/temperature thresholds if needed
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

# Smoothing logic unchanged; sample fewer neighbours for performance.
func _smooth_height(world_x: float, world_z: float, base_height: float) -> float:
	var smoothing_distance = 8.0
	var total_height = base_height
	var total_weight = 1.0

	var sample_points = [
		Vector2(-1, -1), Vector2(1, -1),
		Vector2(-1, 1),  Vector2(1, 1)
	]

	for sample_offset in sample_points:
		var sample_x = world_x + sample_offset.x * smoothing_distance
		var sample_z = world_z + sample_offset.y * smoothing_distance

		var distance = sample_offset.length()
		var weight   = 1.0 / (1.0 + distance * 0.3)

		# Get height at sample point (avoiding ocean check to prevent infinite recursion)
		var sample_height = _get_raw_height(sample_x, sample_z)

		total_height += sample_height * weight
		total_weight += weight

	return total_height / total_weight

# Raw height calculation without smoothing (used inside smoothing)
func _get_raw_height(world_x: float, world_z: float) -> float:
	var mid    = float(chunk_height) / 2.0
	var hills  = base_noise.get_noise_2d(world_x, world_z) * 8.0
	var height = mid + hills

	var cont_val = continent_noise.get_noise_2d(world_x, world_z)
	if cont_val > 0.3:
		var mountain_strength = (cont_val - 0.3) / 0.7
		var m_height = mountain_noise.get_noise_2d(world_x, world_z) * 30.0
		height += mountain_strength * m_height

		var var_height = mountain_variation.get_noise_2d(world_x, world_z) * 8.0
		height += mountain_strength * var_height

	var detail_height = detail_noise.get_noise_2d(world_x, world_z) * 4.0
	height += detail_height

	return height
	
func get_debug_info(world_x: float, world_z: float) -> Dictionary:
	var height = get_height(world_x, world_z, chunk_height)
	var biome = get_biome(world_x, world_z)
	var temp = get_temperature_01(world_x, world_z)
	var moisture = get_moisture_01(world_x, world_z)
	var cont_val = continent_noise.get_noise_2d(world_x, world_z)
	
	return {
		"height": height,
		"biome": biome,
		"temperature": temp,
		"moisture": moisture,
		"continent_value": cont_val,
		"sea_level": sea_level,
		"is_ocean": is_ocean(world_x, world_z)
	}

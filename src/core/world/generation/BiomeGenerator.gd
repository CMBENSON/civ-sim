# src/core/world/generation/BiomeGenerator.gd
extends RefCounted
class_name BiomeGenerator

var noise_manager: NoiseManager
var sea_level: float = 28.0
var verbose_logging: bool = false

# Biome classification thresholds - tunable parameters
var mountain_continent_threshold: float = 0.3
var mountain_height_threshold: float = 20.0
var cold_temperature_threshold: float = 0.25
var hot_temperature_threshold: float = 0.75
var dry_moisture_threshold: float = 0.3
var wet_moisture_threshold: float = 0.7
var jungle_moisture_threshold: float = 0.7
var desert_moisture_threshold: float = 0.35
var tundra_moisture_threshold: float = 0.6

func _init(p_noise_manager: NoiseManager):
	noise_manager = p_noise_manager

func set_sea_level(level: float):
	sea_level = level

func set_verbose_logging(enabled: bool):
	verbose_logging = enabled

func get_biome(world_x: float, world_z: float, height: float) -> int:
	# Check for ocean first
	if is_ocean(world_x, world_z):
		if verbose_logging:
			_log_biome_decision(world_x, world_z, "OCEAN", "below sea level")
		return WorldData.Biome.OCEAN

	var temp_01 = get_temperature_01(world_x, world_z)
	var moist_01 = get_moisture_01(world_x, world_z)
	
	# Check for mountains based on continent noise and height
	var cont_val = noise_manager.get_continent_value(world_x, world_z)
	if cont_val > mountain_continent_threshold and height > sea_level + mountain_height_threshold:
		if verbose_logging:
			_log_biome_decision(world_x, world_z, "MOUNTAINS", "cont_val=%.2f, height=%.1f" % [cont_val, height])
		return WorldData.Biome.MOUNTAINS

	# Biome classification based on temperature and moisture
	var biome_name = ""
	var reason = ""
	var biome_type: int
	
	if temp_01 < cold_temperature_threshold:  # Cold regions
		if moist_01 > tundra_moisture_threshold:
			biome_type = WorldData.Biome.TUNDRA
			biome_name = "TUNDRA"
			reason = "cold + wet"
		else:
			biome_type = WorldData.Biome.PLAINS
			biome_name = "PLAINS"
			reason = "cold + dry"
	elif temp_01 > hot_temperature_threshold:  # Hot regions
		if moist_01 < desert_moisture_threshold:
			biome_type = WorldData.Biome.DESERT
			biome_name = "DESERT"
			reason = "hot + dry"
		elif moist_01 > jungle_moisture_threshold:
			biome_type = WorldData.Biome.JUNGLE
			biome_name = "JUNGLE"
			reason = "hot + wet"
		else:
			biome_type = WorldData.Biome.PLAINS
			biome_name = "PLAINS"
			reason = "hot + moderate"
	else:  # Temperate regions
		if moist_01 > wet_moisture_threshold:
			biome_type = WorldData.Biome.FOREST
			biome_name = "FOREST"
			reason = "temperate + wet"
		elif moist_01 < dry_moisture_threshold:
			biome_type = WorldData.Biome.SWAMP
			biome_name = "SWAMP"
			reason = "temperate + dry"
		else:
			biome_type = WorldData.Biome.PLAINS
			biome_name = "PLAINS"
			reason = "temperate + moderate"
	
	if verbose_logging:
		_log_biome_decision(world_x, world_z, biome_name, reason + " (T=%.2f, M=%.2f)" % [temp_01, moist_01])
	
	return biome_type

func is_ocean(world_x: float, world_z: float) -> bool:
	var cont_val = noise_manager.get_continent_value(world_x, world_z)
	return cont_val < -0.3  # Values below -0.3 are ocean

func get_temperature_01(world_x: float, world_z: float) -> float:
	var t = noise_manager.get_temperature(world_x, world_z)   # [-1,1]
	return (t + 1.0) * 0.5

func get_moisture_01(world_x: float, world_z: float) -> float:
	var m = noise_manager.get_moisture(world_x, world_z)  # [-1,1]
	return (m + 1.0) * 0.5

func get_biome_color(biome: int) -> Color:
	"""Get the representative color for a biome (used for mapping and visualization)"""
	match biome:
		WorldData.Biome.OCEAN:
			return Color(0.1, 0.3, 0.8, 1.0)      # Blue
		WorldData.Biome.MOUNTAINS:
			return Color(0.5, 0.5, 0.5, 1.0)      # Gray
		WorldData.Biome.TUNDRA:
			return Color(0.8, 0.8, 1.0, 1.0)      # Light blue-white
		WorldData.Biome.PLAINS:
			return Color(0.4, 0.6, 0.2, 1.0)      # Green
		WorldData.Biome.DESERT:
			return Color(0.8, 0.7, 0.5, 1.0)      # Sand color
		WorldData.Biome.JUNGLE:
			return Color(0.2, 0.4, 0.1, 1.0)      # Dark green
		WorldData.Biome.FOREST:
			return Color(0.15, 0.50, 0.20, 1.0)   # Forest green
		WorldData.Biome.SWAMP:
			return Color(0.3, 0.4, 0.2, 1.0)      # Dark green-brown
		_:
			return Color(0.4, 0.6, 0.2, 1.0)      # Default green

func get_biome_name(biome: int) -> String:
	"""Get the string name for a biome type"""
	if biome >= 0 and biome < WorldData.Biome.size():
		return WorldData.Biome.keys()[biome]
	return "UNKNOWN"

func analyze_biome_distribution(sample_points: Array) -> Dictionary:
	"""Analyze biome distribution across given sample points"""
	var biome_counts = {}
	var total_points = sample_points.size()
	
	# Initialize counters
	for biome_id in range(WorldData.Biome.size()):
		biome_counts[biome_id] = 0
	
	# Count biomes at sample points
	for point in sample_points:
		var height = 50.0  # Use average height for analysis
		var biome = get_biome(point.x, point.y, height)
		biome_counts[biome] += 1
	
	# Calculate percentages
	var distribution = {}
	for biome_id in biome_counts:
		var count = biome_counts[biome_id]
		var percentage = (float(count) / float(total_points)) * 100.0
		distribution[get_biome_name(biome_id)] = {
			"count": count,
			"percentage": percentage,
			"color": get_biome_color(biome_id)
		}
	
	return distribution

func get_tuning_parameters() -> Dictionary:
	"""Get current biome classification parameters for tuning"""
	return {
		"mountain_continent_threshold": mountain_continent_threshold,
		"mountain_height_threshold": mountain_height_threshold,
		"cold_temperature_threshold": cold_temperature_threshold,
		"hot_temperature_threshold": hot_temperature_threshold,
		"dry_moisture_threshold": dry_moisture_threshold,
		"wet_moisture_threshold": wet_moisture_threshold,
		"jungle_moisture_threshold": jungle_moisture_threshold,
		"desert_moisture_threshold": desert_moisture_threshold,
		"tundra_moisture_threshold": tundra_moisture_threshold
	}

func set_tuning_parameters(params: Dictionary):
	"""Set biome classification parameters for tuning"""
	if params.has("mountain_continent_threshold"):
		mountain_continent_threshold = params.mountain_continent_threshold
	if params.has("mountain_height_threshold"):
		mountain_height_threshold = params.mountain_height_threshold
	if params.has("cold_temperature_threshold"):
		cold_temperature_threshold = params.cold_temperature_threshold
	if params.has("hot_temperature_threshold"):
		hot_temperature_threshold = params.hot_temperature_threshold
	if params.has("dry_moisture_threshold"):
		dry_moisture_threshold = params.dry_moisture_threshold
	if params.has("wet_moisture_threshold"):
		wet_moisture_threshold = params.wet_moisture_threshold
	if params.has("jungle_moisture_threshold"):
		jungle_moisture_threshold = params.jungle_moisture_threshold
	if params.has("desert_moisture_threshold"):
		desert_moisture_threshold = params.desert_moisture_threshold
	if params.has("tundra_moisture_threshold"):
		tundra_moisture_threshold = params.tundra_moisture_threshold

func _log_biome_decision(world_x: float, world_z: float, biome_name: String, reason: String):
	"""Internal logging for biome decisions"""
	print("BiomeGen[%.0f,%.0f]: %s (%s)" % [world_x, world_z, biome_name, reason])

func get_debug_info(world_x: float, world_z: float, height: float) -> Dictionary:
	"""Get detailed debug information for biome generation at a point"""
	var temp_01 = get_temperature_01(world_x, world_z)
	var moist_01 = get_moisture_01(world_x, world_z)
	var cont_val = noise_manager.get_continent_value(world_x, world_z)
	var is_ocean_val = is_ocean(world_x, world_z)
	var biome = get_biome(world_x, world_z, height)
	
	return {
		"biome": biome,
		"biome_name": get_biome_name(biome),
		"temperature_01": temp_01,
		"moisture_01": moist_01,
		"continent_value": cont_val,
		"is_ocean": is_ocean_val,
		"height": height,
		"sea_level": sea_level,
		"classification_reason": _get_classification_reason(temp_01, moist_01, cont_val, height, is_ocean_val)
	}

func _get_classification_reason(temp_01: float, moist_01: float, cont_val: float, height: float, is_ocean_val: bool) -> String:
	"""Get human-readable reason for biome classification"""
	if is_ocean_val:
		return "Ocean (continent value %.2f < -0.3)" % cont_val
	
	if cont_val > mountain_continent_threshold and height > sea_level + mountain_height_threshold:
		return "Mountains (continent %.2f > %.2f, height %.1f > %.1f)" % [cont_val, mountain_continent_threshold, height, sea_level + mountain_height_threshold]
	
	var temp_desc = "cold" if temp_01 < cold_temperature_threshold else ("hot" if temp_01 > hot_temperature_threshold else "temperate")
	var moist_desc = "dry" if moist_01 < dry_moisture_threshold else ("wet" if moist_01 > wet_moisture_threshold else "moderate")
	
	return "%s + %s (T=%.2f, M=%.2f)" % [temp_desc, moist_desc, temp_01, moist_01]

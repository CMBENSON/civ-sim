# src/core/world/data/BiomeData.gd
extends RefCounted
class_name BiomeData

# Biome configuration and data management
static var biome_configs: Dictionary = {}
static var initialized: bool = false

# Biome properties structure
class BiomeConfig:
	var name: String
	var color: Color
	var temperature_range: Vector2  # min, max
	var moisture_range: Vector2     # min, max
	var height_preference: float    # preferred height above sea level
	var resources: Array[String]    # available resources
	var characteristics: Dictionary # additional properties
	
	func _init(p_name: String = ""):
		name = p_name
		color = Color.WHITE
		temperature_range = Vector2(0, 1)
		moisture_range = Vector2(0, 1)
		height_preference = 0.0
		resources = []
		characteristics = {}

static func initialize():
	"""Initialize default biome configurations"""
	if initialized:
		return
	
	_setup_default_biomes()
	initialized = true
	print("BiomeData: Initialized with ", biome_configs.size(), " biome configurations")

static func _setup_default_biomes():
	"""Setup default biome configurations"""
	
	# Ocean
	var ocean = BiomeConfig.new("Ocean")
	ocean.color = Color(0.1, 0.3, 0.8, 1.0)
	ocean.temperature_range = Vector2(0.0, 1.0)
	ocean.moisture_range = Vector2(1.0, 1.0)  # Always wet
	ocean.height_preference = -10.0  # Below sea level
	ocean.resources = ["fish", "seaweed", "salt"]
	ocean.characteristics = {
		"water_depth": "variable",
		"wave_action": true,
		"marine_life": true
	}
	biome_configs[WorldData.Biome.OCEAN] = ocean
	
	# Mountains
	var mountains = BiomeConfig.new("Mountains")
	mountains.color = Color(0.5, 0.5, 0.5, 1.0)
	mountains.temperature_range = Vector2(0.0, 0.6)  # Generally cooler
	mountains.moisture_range = Vector2(0.2, 0.8)
	mountains.height_preference = 40.0  # High elevation
	mountains.resources = ["stone", "ore", "gems", "snow"]
	mountains.characteristics = {
		"elevation": "high",
		"slope": "steep",
		"weather": "harsh"
	}
	biome_configs[WorldData.Biome.MOUNTAINS] = mountains
	
	# Tundra
	var tundra = BiomeConfig.new("Tundra")
	tundra.color = Color(0.8, 0.8, 1.0, 1.0)
	tundra.temperature_range = Vector2(0.0, 0.25)  # Very cold
	tundra.moisture_range = Vector2(0.4, 1.0)
	tundra.height_preference = 5.0
	tundra.resources = ["ice", "fur", "herbs", "lichen"]
	tundra.characteristics = {
		"permafrost": true,
		"growing_season": "short",
		"wildlife": "arctic"
	}
	biome_configs[WorldData.Biome.TUNDRA] = tundra
	
	# Plains
	var plains = BiomeConfig.new("Plains")
	plains.color = Color(0.4, 0.6, 0.2, 1.0)
	plains.temperature_range = Vector2(0.25, 0.75)  # Moderate
	plains.moisture_range = Vector2(0.3, 0.7)
	plains.height_preference = 8.0
	plains.resources = ["grain", "grass", "wildflowers", "game"]
	plains.characteristics = {
		"terrain": "flat",
		"fertility": "high",
		"visibility": "excellent"
	}
	biome_configs[WorldData.Biome.PLAINS] = plains
	
	# Desert
	var desert = BiomeConfig.new("Desert")
	desert.color = Color(0.8, 0.7, 0.5, 1.0)
	desert.temperature_range = Vector2(0.6, 1.0)  # Hot
	desert.moisture_range = Vector2(0.0, 0.35)    # Dry
	desert.height_preference = 12.0
	desert.resources = ["sand", "cactus", "gems", "spices"]
	desert.characteristics = {
		"water": "scarce",
		"temperature_variation": "extreme",
		"sandstorms": true
	}
	biome_configs[WorldData.Biome.DESERT] = desert
	
	# Jungle
	var jungle = BiomeConfig.new("Jungle")
	jungle.color = Color(0.2, 0.4, 0.1, 1.0)
	jungle.temperature_range = Vector2(0.7, 1.0)   # Hot
	jungle.moisture_range = Vector2(0.7, 1.0)     # Very wet
	jungle.height_preference = 15.0
	jungle.resources = ["exotic_fruits", "vines", "medicinal_plants", "hardwood"]
	jungle.characteristics = {
		"density": "very_high",
		"biodiversity": "maximum",
		"canopy": "thick"
	}
	biome_configs[WorldData.Biome.JUNGLE] = jungle
	
	# Forest
	var forest = BiomeConfig.new("Forest")
	forest.color = Color(0.15, 0.50, 0.20, 1.0)
	forest.temperature_range = Vector2(0.3, 0.8)   # Temperate
	forest.moisture_range = Vector2(0.6, 0.9)     # Moist
	forest.height_preference = 18.0
	forest.resources = ["wood", "berries", "mushrooms", "game"]
	forest.characteristics = {
		"canopy": "moderate",
		"undergrowth": "dense",
		"wildlife": "diverse"
	}
	biome_configs[WorldData.Biome.FOREST] = forest
	
	# Swamp
	var swamp = BiomeConfig.new("Swamp")
	swamp.color = Color(0.3, 0.4, 0.2, 1.0)
	swamp.temperature_range = Vector2(0.4, 0.8)    # Warm
	swamp.moisture_range = Vector2(0.8, 1.0)      # Very wet
	swamp.height_preference = 2.0  # Low elevation
	swamp.resources = ["reeds", "peat", "medicinal_plants", "fish"]
	swamp.characteristics = {
		"water_level": "high",
		"soil": "waterlogged",
		"insects": "abundant"
	}
	biome_configs[WorldData.Biome.SWAMP] = swamp

static func get_biome_config(biome_type: int) -> BiomeConfig:
	"""Get configuration for a biome type"""
	if not initialized:
		initialize()
	
	if biome_configs.has(biome_type):
		return biome_configs[biome_type]
	
	print("BiomeData: WARNING - No config for biome type ", biome_type)
	return biome_configs.get(WorldData.Biome.PLAINS, BiomeConfig.new("Unknown"))

static func get_biome_name(biome_type: int) -> String:
	"""Get human-readable name for biome type"""
	var config = get_biome_config(biome_type)
	return config.name

static func get_biome_color(biome_type: int) -> Color:
	"""Get representative color for biome type"""
	var config = get_biome_config(biome_type)
	return config.color

static func get_biome_resources(biome_type: int) -> Array[String]:
	"""Get available resources for biome type"""
	var config = get_biome_config(biome_type)
	return config.resources

static func is_biome_suitable_for_temperature_moisture(biome_type: int, temperature: float, moisture: float) -> bool:
	"""Check if biome is suitable for given temperature and moisture"""
	var config = get_biome_config(biome_type)
	
	var temp_suitable = temperature >= config.temperature_range.x and temperature <= config.temperature_range.y
	var moist_suitable = moisture >= config.moisture_range.x and moisture <= config.moisture_range.y
	
	return temp_suitable and moist_suitable

static func find_best_biome_for_conditions(temperature: float, moisture: float, height: float, is_ocean: bool = false) -> int:
	"""Find the best biome match for given environmental conditions"""
	if not initialized:
		initialize()
	
	if is_ocean:
		return WorldData.Biome.OCEAN
	
	var best_biome = WorldData.Biome.PLAINS
	var best_score = 0.0
	
	for biome_type in biome_configs:
		var config = biome_configs[biome_type]
		
		# Skip ocean for land searches
		if biome_type == WorldData.Biome.OCEAN:
			continue
		
		var score = _calculate_biome_fitness(config, temperature, moisture, height)
		
		if score > best_score:
			best_score = score
			best_biome = biome_type
	
	return best_biome

static func _calculate_biome_fitness(config: BiomeConfig, temperature: float, moisture: float, height: float) -> float:
	"""Calculate how well a biome fits the given conditions"""
	var score = 0.0
	
	# Temperature fitness
	if temperature >= config.temperature_range.x and temperature <= config.temperature_range.y:
		score += 40.0  # Perfect temperature match
	else:
		var temp_distance = min(
			abs(temperature - config.temperature_range.x),
			abs(temperature - config.temperature_range.y)
		)
		score += max(0.0, 40.0 - (temp_distance * 100.0))
	
	# Moisture fitness
	if moisture >= config.moisture_range.x and moisture <= config.moisture_range.y:
		score += 40.0  # Perfect moisture match
	else:
		var moist_distance = min(
			abs(moisture - config.moisture_range.x),
			abs(moisture - config.moisture_range.y)
		)
		score += max(0.0, 40.0 - (moist_distance * 100.0))
	
	# Height preference (less important)
	var height_diff = abs(height - config.height_preference)
	score += max(0.0, 20.0 - (height_diff * 0.5))
	
	return score

static func get_all_biome_types() -> Array:
	"""Get all available biome types"""
	if not initialized:
		initialize()
	
	return biome_configs.keys()

static func validate_biome_type(biome_type: int) -> bool:
	"""Check if biome type is valid"""
	if not initialized:
		initialize()
	
	return biome_configs.has(biome_type)

static func get_debug_info() -> Dictionary:
	"""Get debug information about biome data"""
	if not initialized:
		initialize()
	
	var info = {
		"initialized": initialized,
		"biome_count": biome_configs.size(),
		"available_biomes": []
	}
	
	for biome_type in biome_configs:
		var config = biome_configs[biome_type]
		info.available_biomes.append({
			"type": biome_type,
			"name": config.name,
			"color": config.color,
			"temperature_range": config.temperature_range,
			"moisture_range": config.moisture_range,
			"resources": config.resources.size()
		})
	
	return info
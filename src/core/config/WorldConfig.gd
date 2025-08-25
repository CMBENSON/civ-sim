# src/core/config/WorldConfig.gd
extends RefCounted
class_name WorldConfig

# Centralized configuration management for the world system
static var _instance: WorldConfig = null
static var _config_data: Dictionary = {}
static var _is_initialized: bool = false

# Configuration categories
enum ConfigCategory {
	WORLD,
	GENERATION,
	PERFORMANCE,
	DEBUG,
	PLAYER,
	RENDERING
}

# Default configuration values
static var _default_config: Dictionary = {
	# World settings
	"world.width_chunks": 64,
	"world.chunk_size": 16,
	"world.chunk_height": 256,
	"world.sea_level": 28.0,
	"world.view_distance": 10,
	"world.cylindrical_wrap": true,
	
	# Generation settings
	"generation.use_modular": true,
	"generation.noise_seed": 0,  # 0 = random
	"generation.continent_frequency": 0.0008,
	"generation.terrain_frequency": 0.02,
	"generation.mountain_frequency": 0.01,
	"generation.climate_frequency": 0.002,
	"generation.detail_frequency": 0.1,
	
	# Performance settings
	"performance.max_threads": 0,  # 0 = auto-detect
	"performance.chunk_generation_timeout_ms": 5000,
	"performance.enable_lod": false,
	"performance.memory_limit_mb": 1024,
	
	# Debug settings
	"debug.verbose_logging": false,
	"debug.log_chunk_generation": false,
	"debug.log_player_movement": false,
	"debug.enable_wireframe": false,
	"debug.show_chunk_boundaries": false,
	
	# Player settings
	"player.walk_speed": 8.0,
	"player.fly_speed": 25.0,
	"player.mouse_sensitivity": 0.002,
	"player.interaction_distance": 10.0,
	"player.terrain_edit_strength": 2.0,
	"player.terrain_edit_radius": 3,
	
	# Rendering settings
	"rendering.enable_triplanar_shader": true,
	"rendering.enable_ambient_occlusion": true,
	"rendering.shadow_distance": 200.0,
	"rendering.vsync_enabled": true,
	"rendering.max_fps": 60
}

static func get_instance() -> WorldConfig:
	"""Get singleton instance"""
	if not _instance:
		_instance = WorldConfig.new()
		_initialize()
	return _instance

static func _initialize():
	"""Initialize configuration system"""
	if _is_initialized:
		return
	
	_config_data = _default_config.duplicate(true)
	_load_from_file()
	_validate_config()
	_is_initialized = true
	
	print("WorldConfig: Initialized with ", _config_data.size(), " settings")

static func get_value(key: String, default_value = null):
	"""Get configuration value by key"""
	if not _is_initialized:
		_initialize()
	
	if _config_data.has(key):
		return _config_data[key]
	elif _default_config.has(key):
		print("WorldConfig: Using default for missing key: ", key)
		return _default_config[key]
	else:
		print("WorldConfig: Unknown config key: ", key)
		return default_value

static func set_value(key: String, value) -> bool:
	"""Set configuration value"""
	if not _is_initialized:
		_initialize()
	
	if not _is_valid_key(key):
		print("WorldConfig: Invalid config key: ", key)
		return false
	
	var old_value = _config_data.get(key)
	_config_data[key] = value
	
	print("WorldConfig: Changed '%s' from %s to %s" % [key, str(old_value), str(value)])
	return true

static func reset_to_default(key: String = "") -> bool:
	"""Reset configuration to default values"""
	if not _is_initialized:
		_initialize()
	
	if key.is_empty():
		# Reset all values
		_config_data = _default_config.duplicate(true)
		print("WorldConfig: Reset all settings to defaults")
		return true
	elif _default_config.has(key):
		_config_data[key] = _default_config[key]
		print("WorldConfig: Reset '%s' to default value: %s" % [key, str(_default_config[key])])
		return true
	else:
		print("WorldConfig: Cannot reset unknown key: ", key)
		return false

static func save_to_file(file_path: String = "user://world_config.json") -> bool:
	"""Save current configuration to file"""
	if not _is_initialized:
		return false
	
	var save_data = {
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(),
		"config": _config_data
	}
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		print("WorldConfig: Failed to open file for writing: ", file_path)
		return false
	
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	
	print("WorldConfig: Saved configuration to ", file_path)
	return true

static func _load_from_file(file_path: String = "user://world_config.json") -> bool:
	"""Load configuration from file"""
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("WorldConfig: No config file found, using defaults")
		return false
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		print("WorldConfig: Failed to parse config file: ", file_path)
		return false
	
	var data = json.get_data()
	if not data is Dictionary:
		print("WorldConfig: Invalid config file format")
		return false
	
	if data.has("config") and data.config is Dictionary:
		# Merge loaded config with defaults
		for key in data.config:
			if _default_config.has(key):
				_config_data[key] = data.config[key]
			else:
				print("WorldConfig: Ignoring unknown config key from file: ", key)
		
		print("WorldConfig: Loaded configuration from ", file_path)
		return true
	
	return false

static func _validate_config():
	"""Validate configuration values"""
	var errors = []
	
	# Validate world settings
	if get_value("world.width_chunks") <= 0:
		errors.append("world.width_chunks must be positive")
	if get_value("world.chunk_size") < 8 or get_value("world.chunk_size") > 256:
		errors.append("world.chunk_size must be between 8 and 256")
	if get_value("world.chunk_height") < 64 or get_value("world.chunk_height") > 512:
		errors.append("world.chunk_height must be between 64 and 512")
	if get_value("world.sea_level") < 0:
		errors.append("world.sea_level cannot be negative")
	
	# Validate performance settings
	if get_value("performance.max_threads") < 0:
		errors.append("performance.max_threads cannot be negative")
	if get_value("performance.memory_limit_mb") < 128:
		errors.append("performance.memory_limit_mb must be at least 128MB")
	
	# Validate player settings
	if get_value("player.walk_speed") <= 0:
		errors.append("player.walk_speed must be positive")
	if get_value("player.fly_speed") <= 0:
		errors.append("player.fly_speed must be positive")
	if get_value("player.interaction_distance") <= 0:
		errors.append("player.interaction_distance must be positive")
	
	if errors.size() > 0:
		print("WorldConfig: Configuration validation errors:")
		for error in errors:
			print("  - ", error)
		return false
	
	return true

static func _is_valid_key(key: String) -> bool:
	"""Check if configuration key is valid"""
	return _default_config.has(key)

static func get_category_keys(category: ConfigCategory) -> Array:
	"""Get all configuration keys for a category"""
	var prefix = ""
	match category:
		ConfigCategory.WORLD:
			prefix = "world."
		ConfigCategory.GENERATION:
			prefix = "generation."
		ConfigCategory.PERFORMANCE:
			prefix = "performance."
		ConfigCategory.DEBUG:
			prefix = "debug."
		ConfigCategory.PLAYER:
			prefix = "player."
		ConfigCategory.RENDERING:
			prefix = "rendering."
	
	var keys = []
	for key in _default_config.keys():
		if key.begins_with(prefix):
			keys.append(key)
	
	return keys

static func get_all_values() -> Dictionary:
	"""Get all current configuration values"""
	if not _is_initialized:
		_initialize()
	return _config_data.duplicate(true)

static func get_debug_info() -> Dictionary:
	"""Get debug information about configuration system"""
	return {
		"initialized": _is_initialized,
		"total_settings": _config_data.size(),
		"default_settings": _default_config.size(),
		"categories": ConfigCategory.size(),
		"world_settings": get_category_keys(ConfigCategory.WORLD).size(),
		"generation_settings": get_category_keys(ConfigCategory.GENERATION).size(),
		"performance_settings": get_category_keys(ConfigCategory.PERFORMANCE).size(),
		"debug_settings": get_category_keys(ConfigCategory.DEBUG).size(),
		"player_settings": get_category_keys(ConfigCategory.PLAYER).size(),
		"rendering_settings": get_category_keys(ConfigCategory.RENDERING).size()
	}

# Convenience methods for common settings
static func get_world_size() -> Vector2i:
	"""Get world size in chunks"""
	var width = get_value("world.width_chunks")
	return Vector2i(width, width)

static func get_chunk_size() -> int:
	"""Get chunk size in voxels"""
	return get_value("world.chunk_size")

static func get_chunk_height() -> int:
	"""Get chunk height in voxels"""
	return get_value("world.chunk_height")

static func get_world_circumference() -> int:
	"""Get world circumference in voxels"""
	return get_value("world.width_chunks") * get_value("world.chunk_size")

static func get_max_threads() -> int:
	"""Get maximum thread count (auto-detect if 0)"""
	var max_threads = get_value("performance.max_threads")
	if max_threads <= 0:
		return max(1, OS.get_processor_count() - 1)
	return max_threads

static func is_verbose_logging_enabled() -> bool:
	"""Check if verbose logging is enabled"""
	return get_value("debug.verbose_logging")

static func get_player_speeds() -> Dictionary:
	"""Get player movement speeds"""
	return {
		"walk": get_value("player.walk_speed"),
		"fly": get_value("player.fly_speed")
	}

static func get_terrain_edit_params() -> Dictionary:
	"""Get terrain editing parameters"""
	return {
		"strength": get_value("player.terrain_edit_strength"),
		"radius": get_value("player.terrain_edit_radius"),
		"distance": get_value("player.interaction_distance")
	}

static func apply_runtime_overrides(overrides: Dictionary):
	"""Apply runtime configuration overrides (e.g., from command line)"""
	for key in overrides:
		if _is_valid_key(key):
			set_value(key, overrides[key])
		else:
			print("WorldConfig: Ignoring invalid runtime override: ", key)
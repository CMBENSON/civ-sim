# src/core/world/systems/PlanetaryCycles.gd
extends RefCounted
class_name PlanetaryCycles

signal cycle_started(cycle_type: CycleType, intensity: float)
signal cycle_ended(cycle_type: CycleType)
signal biome_shift(world_pos: Vector3, old_biome: int, new_biome: int)

enum CycleType {
	ICE_AGE,        # Snow expansion, animals migrate south
	DROUGHT,        # Water sources dry up, desertification
	VOLCANIC_SURGE, # Ash clouds, but fertile soil afterwards
	MAGNETIC_SHIFT, # Aurora activity, animal navigation disrupted
	FLOOD_SEASON,   # Rivers overflow, temporary lakes form
	GROWTH_BLOOM    # Accelerated plant/animal growth
}

var active_cycles: Dictionary = {}
var cycle_timers: Dictionary = {}
var planet_health: float = 100.0
var cycle_history: Array = []

# Cycle parameters
var cycle_data: Dictionary = {
	CycleType.ICE_AGE: {
		"duration_range": [1200, 2400],  # 20-40 minutes
		"intensity_range": [0.3, 0.8],
		"cooldown": 3600,  # 1 hour before can happen again
		"effects": ["snow_expansion", "temperature_drop", "animal_migration"]
	},
	CycleType.DROUGHT: {
		"duration_range": [600, 1200],   # 10-20 minutes
		"intensity_range": [0.2, 0.6],
		"cooldown": 1800,
		"effects": ["water_reduction", "vegetation_die", "desert_expansion"]
	},
	CycleType.VOLCANIC_SURGE: {
		"duration_range": [300, 600],    # 5-10 minutes
		"intensity_range": [0.4, 1.0],
		"cooldown": 2400,
		"effects": ["ash_cloud", "fertility_bonus", "temperature_change"]
	}
}

func _init():
	_setup_random_cycle_schedule()

func _setup_random_cycle_schedule():
	"""Set up initial random timing for cycles"""
	for cycle_type in CycleType.values():
		var data = cycle_data.get(cycle_type, {})
		var cooldown = data.get("cooldown", 3600)
		cycle_timers[cycle_type] = Time.get_unix_time_from_system() + randi_range(cooldown, cooldown * 2)

func update_cycles(delta: float):
	"""Update all planetary cycles - call from world._process"""
	var current_time = Time.get_unix_time_from_system()
	
	# Check for new cycles to start
	for cycle_type in cycle_timers:
		if current_time >= cycle_timers[cycle_type] and not active_cycles.has(cycle_type):
			_start_cycle(cycle_type)
	
	# Update active cycles
	for cycle_type in active_cycles.keys():
		var cycle = active_cycles[cycle_type]
		cycle.elapsed_time += delta
		
		if cycle.elapsed_time >= cycle.duration:
			_end_cycle(cycle_type)

func _start_cycle(cycle_type: CycleType):
	"""Start a new planetary cycle"""
	var data = cycle_data.get(cycle_type, {})
	var duration_range = data.get("duration_range", [600, 1200])
	var intensity_range = data.get("intensity_range", [0.3, 0.8])
	
	var cycle = {
		"type": cycle_type,
		"duration": randi_range(duration_range[0], duration_range[1]),
		"intensity": randf_range(intensity_range[0], intensity_range[1]),
		"elapsed_time": 0.0,
		"start_time": Time.get_unix_time_from_system(),
		"effects": data.get("effects", [])
	}
	
	active_cycles[cycle_type] = cycle
	cycle_started.emit(cycle_type, cycle.intensity)
	
	print("PlanetaryCycles: Started ", CycleType.keys()[cycle_type], " cycle with intensity ", cycle.intensity)
	
	# Apply immediate effects
	_apply_cycle_effects(cycle, true)

func _end_cycle(cycle_type: CycleType):
	"""End a planetary cycle"""
	var cycle = active_cycles.get(cycle_type, {})
	if cycle.is_empty():
		return
	
	# Apply end effects (some cycles have lingering effects)
	_apply_cycle_effects(cycle, false)
	
	# Remove from active cycles
	active_cycles.erase(cycle_type)
	
	# Schedule next possible occurrence
	var data = cycle_data.get(cycle_type, {})
	var cooldown = data.get("cooldown", 3600)
	cycle_timers[cycle_type] = Time.get_unix_time_from_system() + cooldown + randi_range(0, cooldown)
	
	# Add to history
	cycle_history.append({
		"type": cycle_type,
		"start_time": cycle.start_time,
		"duration": cycle.elapsed_time,
		"intensity": cycle.intensity
	})
	
	cycle_ended.emit(cycle_type)
	print("PlanetaryCycles: Ended ", CycleType.keys()[cycle_type], " cycle")

func _apply_cycle_effects(cycle: Dictionary, is_starting: bool):
	"""Apply the effects of a cycle"""
	match cycle.type:
		CycleType.ICE_AGE:
			_apply_ice_age_effects(cycle, is_starting)
		CycleType.DROUGHT:
			_apply_drought_effects(cycle, is_starting)
		CycleType.VOLCANIC_SURGE:
			_apply_volcanic_effects(cycle, is_starting)
		CycleType.MAGNETIC_SHIFT:
			_apply_magnetic_effects(cycle, is_starting)

func _apply_ice_age_effects(cycle: Dictionary, is_starting: bool):
	"""Apply ice age effects to the world"""
	if is_starting:
		# Start expanding snow/ice biomes
		# Trigger animal migrations
		# Reduce temperature globally
		pass
	else:
		# Gradually warm up
		# Allow animals to return
		pass

func _apply_drought_effects(cycle: Dictionary, is_starting: bool):
	"""Apply drought effects"""
	if is_starting:
		# Reduce water levels
		# Start converting some biomes to desert
		# Animals migrate to water sources
		pass

func _apply_volcanic_effects(cycle: Dictionary, is_starting: bool):
	"""Apply volcanic surge effects"""
	if is_starting:
		# Ash clouds block sunlight
		# Some areas become more fertile
		pass

func _apply_magnetic_effects(cycle: Dictionary, is_starting: bool):
	"""Apply magnetic shift effects"""
	if is_starting:
		# Animals get confused navigation
		# Aurora activity increases
		pass

func get_cycle_modifier_for_biome(biome: int, world_pos: Vector3) -> float:
	"""Get how active cycles should modify biome generation"""
	var modifier = 1.0
	
	for cycle in active_cycles.values():
		match cycle.type:
			CycleType.ICE_AGE:
				# Push biomes toward colder variants
				if biome == WorldData.Biome.PLAINS:
					# Plains might become tundra during ice age
					modifier -= cycle.intensity * 0.3
				elif biome == WorldData.Biome.TUNDRA:
					# Tundra becomes more likely
					modifier += cycle.intensity * 0.2
			
			CycleType.DROUGHT:
				# Push toward drier biomes
				if biome == WorldData.Biome.FOREST:
					modifier -= cycle.intensity * 0.4
				elif biome == WorldData.Biome.DESERT:
					modifier += cycle.intensity * 0.3
	
	return modifier

func get_active_cycles() -> Array:
	"""Get list of currently active cycles"""
	return active_cycles.values()

func get_planet_health() -> float:
	"""Get overall planet health metric"""
	return planet_health

func modify_planet_health(change: float):
	"""Modify planet health (from player actions, etc.)"""
	planet_health = clamp(planet_health + change, 0.0, 100.0)
	
	# Low planet health increases chance of negative cycles
	if planet_health < 30.0:
		_increase_negative_cycle_probability()

func _increase_negative_cycle_probability():
	"""Increase probability of negative cycles when planet health is low"""
	# Reduce timers for negative cycles
	for cycle_type in [CycleType.DROUGHT, CycleType.VOLCANIC_SURGE]:
		if cycle_timers.has(cycle_type):
			cycle_timers[cycle_type] = min(cycle_timers[cycle_type], 
				Time.get_unix_time_from_system() + 300)  # May start in 5 minutes

func force_cycle(cycle_type: CycleType, intensity: float = 0.5):
	"""Force start a cycle (for testing/events)"""
	if active_cycles.has(cycle_type):
		_end_cycle(cycle_type)
	
	# Override the timer
	cycle_timers[cycle_type] = Time.get_unix_time_from_system()
	
	# Manually set intensity
	var data = cycle_data.get(cycle_type, {})
	data["intensity_range"] = [intensity, intensity]
	
	_start_cycle(cycle_type)

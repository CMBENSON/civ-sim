# src/core/world/generation/NoiseManager.gd
extends RefCounted
class_name NoiseManager

var continent_noise: FastNoiseLite
var base_noise: FastNoiseLite
var mountain_noise: FastNoiseLite
var temperature_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var detail_noise: FastNoiseLite

func _init(seed_value: int = 0):
    setup_continent_noise(seed_value)
    setup_terrain_noise(seed_value + 1)
    setup_climate_noise(seed_value + 2)

func setup_continent_noise(seed_val: int):
    continent_noise = FastNoiseLite.new()
    continent_noise.noise_type = FastNoiseLite.TYPE_PERLIN
    continent_noise.seed = seed_val
    # CRITICAL: Much lower frequency for continent-scale features
    continent_noise.frequency = 0.0005  # Was 0.0015 - too high!

func get_continent_value(world_x: float, world_z: float) -> float:
    return continent_noise.get_noise_2d(world_x, world_z)
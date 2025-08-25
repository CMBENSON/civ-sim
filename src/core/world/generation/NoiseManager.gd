# src/core/world/generation/NoiseManager.gd
extends RefCounted
class_name NoiseManager

var continent_noise: FastNoiseLite
var base_noise: FastNoiseLite
var mountain_noise: FastNoiseLite
var temperature_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var mountain_variation: FastNoiseLite

func _init(seed_value: int = 0):
	setup_continent_noise(seed_value)
	setup_terrain_noise(seed_value + 1)
	setup_climate_noise(seed_value + 2)

func setup_continent_noise(seed_val: int):
	continent_noise = FastNoiseLite.new()
	continent_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	continent_noise.seed = seed_val
	continent_noise.frequency = 0.0008  # Much lower for continent-scale

func setup_terrain_noise(seed_val: int):
	base_noise = FastNoiseLite.new()
	base_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	base_noise.seed = seed_val
	base_noise.frequency = 0.02

	mountain_noise = FastNoiseLite.new()
	mountain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	mountain_noise.seed = seed_val + 1
	mountain_noise.frequency = 0.01

	mountain_variation = FastNoiseLite.new()
	mountain_variation.noise_type = FastNoiseLite.TYPE_PERLIN
	mountain_variation.seed = seed_val + 2
	mountain_variation.frequency = 0.05

	detail_noise = FastNoiseLite.new()
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.seed = seed_val + 3
	detail_noise.frequency = 0.1

func setup_climate_noise(seed_val: int):
	temperature_noise = FastNoiseLite.new()
	temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temperature_noise.seed = seed_val
	temperature_noise.frequency = 0.002  # Lower for broader climate zones

	moisture_noise = FastNoiseLite.new()
	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	moisture_noise.seed = seed_val + 1
	moisture_noise.frequency = 0.002

func get_continent_value(world_x: float, world_z: float) -> float:
	return continent_noise.get_noise_2d(world_x, world_z)

func get_base_height(world_x: float, world_z: float) -> float:
	return base_noise.get_noise_2d(world_x, world_z)

func get_mountain_height(world_x: float, world_z: float) -> float:
	return mountain_noise.get_noise_2d(world_x, world_z)

func get_temperature(world_x: float, world_z: float) -> float:
	return temperature_noise.get_noise_2d(world_x, world_z)

func get_moisture(world_x: float, world_z: float) -> float:
	return moisture_noise.get_noise_2d(world_x, world_z)

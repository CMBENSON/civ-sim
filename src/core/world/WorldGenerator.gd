# src/core/world/WorldGenerator.gd
extends RefCounted

# Public tuning knobs (safe defaults)
var sea_level: float = 28.0
var world_circumference_voxels: int
var chunk_size: int
var pole_influence: float = 0.6          # 0..1, stronger = colder poles
@export var base_variation := 20.0
@export var mountain_boost := 45.0
@export var continent_threshold := 0.0
var pole_sink: float = 0.0               # optionally lower land near poles

# Noises (created in _init)
var n_continent: FastNoiseLite
var n_elev_mid: FastNoiseLite
var n_elev_detail: FastNoiseLite
var n_temp: FastNoiseLite
var n_moist: FastNoiseLite



func _init(p_world_circumference_voxels: int, p_chunk_size: int) -> void:
		world_circumference_voxels = p_world_circumference_voxels
		chunk_size = p_chunk_size

		# Large‑scale continents — frequency ~ 1 cycle across circumference
		n_continent = FastNoiseLite.new()
		n_continent.noise_type = FastNoiseLite.TYPE_PERLIN
		n_continent.seed = randi()
		n_continent.frequency = 1.0  # one cycle across [0,1]
		


		# Mid‑scale elevation (regional variation)
		n_elev_mid = FastNoiseLite.new()
		n_elev_mid.noise_type = FastNoiseLite.TYPE_PERLIN
		n_elev_mid.seed = randi()
		n_elev_mid.frequency = 0.015

		# High‑frequency detail
		n_elev_detail = FastNoiseLite.new()
		n_elev_detail.noise_type = FastNoiseLite.TYPE_PERLIN
		n_elev_detail.seed = randi()
		n_elev_detail.frequency = 0.06

		# Temperature & moisture
		n_temp = FastNoiseLite.new()
		n_temp.noise_type = FastNoiseLite.TYPE_PERLIN
		n_temp.seed = randi()
		n_temp.frequency = 0.01

		n_moist = FastNoiseLite.new()
		n_moist.noise_type = FastNoiseLite.TYPE_PERLIN
		n_moist.seed = randi()
		n_moist.frequency = 0.01

func _wrap_x(x: float) -> float:
		# Wrap X to [0, circumference)
		var wx = fmod(x, float(world_circumference_voxels))
		if wx < 0.0: wx += float(world_circumference_voxels)
		return wx

func get_continent_value(world_x: float, world_z: float) -> float:
		# Sample continent noise with normalized wrapped X, Z (Z not wrapped)
		var nx = _wrap_x(world_x) / float(world_circumference_voxels)
		var nz = world_z / float(world_circumference_voxels)
		return n_continent.get_noise_2d(nx, nz)  # [-1, 1]

func is_ocean(world_x: float, world_z: float) -> bool:
		return get_continent_value(world_x, world_z) < continent_threshold

func get_height(world_x: float, world_z: float, chunk_height: int) -> float:
		# Ocean clamp
		if is_ocean(world_x, world_z):
				return float(sea_level)

		# Base height around mid‑altitude of chunk
		var mid = float(chunk_height) / 2.0

		# Blend continent value into overall height (smoothstep around threshold)
		var c = get_continent_value(world_x, world_z) # [-1, 1]
		var c01 = (c + 1.0) * 0.5
		var land_mask = _smoothstep((continent_threshold + 1.0) * 0.5, 1.0, c01)

		var elev_mid = n_elev_mid.get_noise_2d(world_x, world_z) # [-1,1]
		var elev_detail = n_elev_detail.get_noise_2d(world_x, world_z) # [-1,1]

		var height = mid \
				   + elev_mid * base_variation \
				   + elev_detail * (base_variation * 0.5) \
				   + land_mask * mountain_boost

		# Optional polar sink (lower terrain near poles)
		var polar = _polar_factor(world_z)
		height -= polar * pole_sink

		# Keep at least sea level in ocean cells
		if height < sea_level and not is_ocean(world_x, world_z):
				height = sea_level + 1.0

		return height

func get_temperature_01(world_x: float, world_z: float) -> float:
		# Latitude effect: colder toward poles (|z| large)
		var polar = _polar_factor(world_z) # 0 at equator, ->1 toward poles
		var t = n_temp.get_noise_2d(world_x * 0.008, world_z * 0.008) # [-1,1]
		var t01 = (t + 1.0) * 0.5
		# Mix: poles pull temperature down
		return clamp(t01 * (1.0 - pole_influence) + (1.0 - polar) * pole_influence, 0.0, 1.0)

func get_moisture_01(world_x: float, world_z: float) -> float:
		var m = n_moist.get_noise_2d(world_x * 0.01, world_z * 0.01) # [-1,1]
		var m01 = (m + 1.0) * 0.5
		# A tiny elevation rain‑shadow effect (higher -> slightly drier)
		var e = n_elev_mid.get_noise_2d(world_x, world_z) # [-1,1]
		return clamp(m01 - max(e, 0.0) * 0.1, 0.0, 1.0)

func get_biome(world_x: float, world_z: float) -> int:
		if is_ocean(world_x, world_z):
				return WorldData.Biome.OCEAN

		var t = get_temperature_01(world_x, world_z)
		var m = get_moisture_01(world_x, world_z)

		# Simple, readable mapping first — you can refine later.
		if t < 0.2:
				return WorldData.Biome.TUNDRA
		elif t > 0.8:
				if m < 0.3:
						return WorldData.Biome.DESERT
				else:
						return WorldData.Biome.JUNGLE
		elif m > 0.65:
				return WorldData.Biome.FOREST
		elif m < 0.25:
				return WorldData.Biome.SWAMP
		else:
				return WorldData.Biome.PLAINS

# Utility

func _polar_factor(world_z: float) -> float:
		# A softstep that increases with distance from "equator" (z=0).
		# The denominator defines how quickly we hit the poles (tune it).
		var d = abs(world_z) / float(world_circumference_voxels * 0.25)
		return clamp(d, 0.0, 1.0)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
		var t = clamp((x - edge0) / max(edge1 - edge0, 0.00001), 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)

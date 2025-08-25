# src/core/world/simulation/WorldSimulation.gd
extends RefCounted
class_name WorldSimulation

var noise_manager: NoiseManager
var biome_generator: BiomeGenerator
var height_generator: HeightGenerator
var chunk_manager: ChunkManager

func _init(world_size: int, chunk_size: int):
    noise_manager = NoiseManager.new()
    biome_generator = BiomeGenerator.new(noise_manager)
    height_generator = HeightGenerator.new(noise_manager)
    chunk_manager = ChunkManager.new(world_size, chunk_size)
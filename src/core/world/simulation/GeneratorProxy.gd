# scripts/GeneratorProxy.gd
# This proxy provides the interface that VoxelMesher expects while using the new modular system
extends RefCounted

var noise_manager: NoiseManager
var biome_generator: BiomeGenerator  
var height_generator: HeightGenerator
var sea_level: float = 28.0
var verbose_logging: bool = false

func setup(p_noise_manager: NoiseManager, p_biome_generator: BiomeGenerator, p_height_generator: HeightGenerator):
	noise_manager = p_noise_manager
	biome_generator = p_biome_generator
	height_generator = p_height_generator
	sea_level = height_generator.sea_level if height_generator else 28.0
	verbose_logging = height_generator.verbose_logging if height_generator else false

# Interface methods that VoxelMesher expects
func get_height(world_x: float, world_z: float, chunk_height: int) -> float:
	if height_generator:
		return height_generator.get_height(world_x, world_z)
	return sea_level

func get_biome(world_x: float, world_z: float) -> int:
	if biome_generator:
		var height = height_generator.get_height(world_x, world_z) if height_generator else sea_level
		return biome_generator.get_biome(world_x, world_z, height)
	return WorldData.Biome.PLAINS

func is_ocean(world_x: float, world_z: float) -> bool:
	if biome_generator:
		return biome_generator.is_ocean(world_x, world_z)
	return false

func get_debug_info(world_x: float, world_z: float) -> Dictionary:
	var height = height_generator.get_height(world_x, world_z) if height_generator else sea_level
	var biome_info = biome_generator.get_debug_info(world_x, world_z, height) if biome_generator else {}
	var height_info = height_generator.get_debug_info(world_x, world_z) if height_generator else {}
	
	# Merge the debug info
	var combined_info = {}
	combined_info.merge(biome_info)
	combined_info.merge(height_info)
	
	return combined_info

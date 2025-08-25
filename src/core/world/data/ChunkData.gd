# src/core/world/data/ChunkData.gd
extends RefCounted
class_name ChunkData

# Chunk dimensions
const CHUNK_WIDTH = 16
const CHUNK_HEIGHT = 256
const CHUNK_DEPTH = 16

# Core data
var position: Vector2i
var voxel_data: Array = []
var biome_data: Array = []
var generation_state: GenerationState = GenerationState.NOT_GENERATED
var timestamp_created: int
var timestamp_modified: int

# Generation metadata
var generation_version: int = 1
var generator_params: Dictionary = {}

enum GenerationState {
	NOT_GENERATED,
	QUEUED,
	GENERATING,
	GENERATED,
	ERROR
}

func _init(chunk_pos: Vector2i = Vector2i.ZERO):
	position = chunk_pos
	timestamp_created = Time.get_unix_time_from_system()
	timestamp_modified = timestamp_created
	_initialize_arrays()

func _initialize_arrays():
	"""Initialize voxel and biome data arrays"""
	voxel_data = []
	biome_data = []
	
	# Initialize voxel data [x][y][z]
	voxel_data.resize(CHUNK_WIDTH)
	for x in range(CHUNK_WIDTH):
		voxel_data[x] = []
		voxel_data[x].resize(CHUNK_HEIGHT)
		for y in range(CHUNK_HEIGHT):
			voxel_data[x][y] = []
			voxel_data[x][y].resize(CHUNK_DEPTH)
			for z in range(CHUNK_DEPTH):
				voxel_data[x][y][z] = 0.0
	
	# Initialize biome data [x][z]
	biome_data.resize(CHUNK_WIDTH)
	for x in range(CHUNK_WIDTH):
		biome_data[x] = []
		biome_data[x].resize(CHUNK_DEPTH)
		for z in range(CHUNK_DEPTH):
			biome_data[x][z] = WorldData.Biome.PLAINS

func set_voxel_data(new_voxel_data: Array):
	"""Set voxel data and update timestamp"""
	voxel_data = new_voxel_data
	timestamp_modified = Time.get_unix_time_from_system()
	generation_state = GenerationState.GENERATED

func set_biome_data(new_biome_data: Array):
	"""Set biome data and update timestamp"""
	biome_data = new_biome_data
	timestamp_modified = Time.get_unix_time_from_system()

func get_voxel_density(x: int, y: int, z: int) -> float:
	"""Get voxel density at local coordinates"""
	if _is_valid_coordinate(x, y, z):
		return voxel_data[x][y][z]
	return 0.0

func set_voxel_density(x: int, y: int, z: int, density: float):
	"""Set voxel density at local coordinates"""
	if _is_valid_coordinate(x, y, z):
		voxel_data[x][y][z] = density
		timestamp_modified = Time.get_unix_time_from_system()

func get_biome(x: int, z: int) -> int:
	"""Get biome at local coordinates"""
	if _is_valid_biome_coordinate(x, z):
		return biome_data[x][z]
	return WorldData.Biome.PLAINS

func set_biome(x: int, z: int, biome: int):
	"""Set biome at local coordinates"""
	if _is_valid_biome_coordinate(x, z):
		biome_data[x][z] = biome
		timestamp_modified = Time.get_unix_time_from_system()

func _is_valid_coordinate(x: int, y: int, z: int) -> bool:
	"""Check if coordinates are within chunk bounds"""
	return (x >= 0 and x < CHUNK_WIDTH and 
			y >= 0 and y < CHUNK_HEIGHT and 
			z >= 0 and z < CHUNK_DEPTH)

func _is_valid_biome_coordinate(x: int, z: int) -> bool:
	"""Check if biome coordinates are within chunk bounds"""
	return (x >= 0 and x < CHUNK_WIDTH and 
			z >= 0 and z < CHUNK_DEPTH)

func get_memory_usage() -> Dictionary:
	"""Get memory usage statistics for this chunk"""
	var voxel_size = CHUNK_WIDTH * CHUNK_HEIGHT * CHUNK_DEPTH * 4  # float = 4 bytes
	var biome_size = CHUNK_WIDTH * CHUNK_DEPTH * 4  # int = 4 bytes
	
	return {
		"voxel_data_bytes": voxel_size,
		"biome_data_bytes": biome_size,
		"total_bytes": voxel_size + biome_size,
		"total_kb": (voxel_size + biome_size) / 1024.0
	}

func serialize() -> Dictionary:
	"""Serialize chunk data for saving"""
	return {
		"position": {"x": position.x, "y": position.y},
		"voxel_data": voxel_data,
		"biome_data": biome_data,
		"generation_state": generation_state,
		"timestamp_created": timestamp_created,
		"timestamp_modified": timestamp_modified,
		"generation_version": generation_version,
		"generator_params": generator_params
	}

func deserialize(data: Dictionary):
	"""Deserialize chunk data from saved format"""
	if data.has("position"):
		position = Vector2i(data.position.x, data.position.y)
	if data.has("voxel_data"):
		voxel_data = data.voxel_data
	if data.has("biome_data"):
		biome_data = data.biome_data
	if data.has("generation_state"):
		generation_state = data.generation_state
	if data.has("timestamp_created"):
		timestamp_created = data.timestamp_created
	if data.has("timestamp_modified"):
		timestamp_modified = data.timestamp_modified
	if data.has("generation_version"):
		generation_version = data.generation_version
	if data.has("generator_params"):
		generator_params = data.generator_params

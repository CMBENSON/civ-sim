# src/core/world/world.gd
@tool
extends Node3D

signal initial_chunks_generated

const ChunkScene = preload("res://src/core/world/chunk.tscn")
const VoxelMesher = preload("res://src/core/world/VoxelMesher.gd")
const MarchingCubesData = preload("res://src/core/world/marching_cubes.gd")

@export var WORLD_WIDTH_IN_CHUNKS: int = 64 : set = _set_world_width_in_chunks
@export var CHUNK_SIZE: int = 16 : set = _set_chunk_size
@export var WORLD_CIRCUMFERENCE_IN_VOXELS: int = WORLD_WIDTH_IN_CHUNKS * CHUNK_SIZE
@export var CHUNK_HEIGHT : int = 256
var use_modular_generation: bool = true
var modular_generator: ModularWorldGenerator
var is_preview = false
var verbose_logging: bool = false  # Control debug output

const WorldGenerator = preload("res://src/core/world/WorldGenerator.gd")
var generator: RefCounted

var world_material = ShaderMaterial.new()

var player: CharacterBody3D
var loaded_chunks = {}
var current_player_chunk = Vector2i(999, 999)
var is_first_update = true

# NEW: ThreadManager replaces old threading system
var thread_manager: ThreadManager
var max_threads = max(1, OS.get_processor_count() - 1)

# Marching cubes data
var tri_table_copy: Array
var edge_table_copy: Array

const VIEW_DISTANCE = 10

func _ready():
	var triplanar_shader = load("res://assets/shaders/triplanar.gdshader")
	if triplanar_shader == null:
		print("ERROR: Failed to load triplanar shader!")
		return
		
	world_material.shader = triplanar_shader
	
	if verbose_logging:
		print("World: Triplanar shader loaded successfully")

	# Ensure export variables are properly set
	WORLD_WIDTH_IN_CHUNKS = 64
	CHUNK_SIZE = 16
	CHUNK_HEIGHT = 256
	WORLD_CIRCUMFERENCE_IN_VOXELS = WORLD_WIDTH_IN_CHUNKS * CHUNK_SIZE
	
	if verbose_logging:
		print("World dimensions: ", WORLD_WIDTH_IN_CHUNKS, " chunks x ", CHUNK_SIZE, " voxels = ", WORLD_CIRCUMFERENCE_IN_VOXELS, " total voxels")

	# Initialize world generation system
	if use_modular_generation:
		_initialize_modular_system()
	else:
		# Keep existing system for fallback
		generator = WorldGenerator.new(WORLD_CIRCUMFERENCE_IN_VOXELS, CHUNK_SIZE)
		generator.chunk_height = CHUNK_HEIGHT
		generator.verbose_logging = verbose_logging
		generator.sea_level = 28.0

	# Initialize marching cubes data
	tri_table_copy = MarchingCubesData.TRI_TABLE.duplicate(true)
	edge_table_copy = MarchingCubesData.EDGE_TABLE.duplicate(true)

	# Create and setup thread manager
	thread_manager = ThreadManager.new(max_threads)
	thread_manager.setup_dependencies(generator, tri_table_copy, edge_table_copy)
	thread_manager.set_verbose_logging(verbose_logging)
	
	# Connect thread manager signal
	thread_manager.chunk_generation_completed.connect(_on_chunk_generation_completed)
	
	# Create biome texture and load initial chunks
	create_biome_texture()
	load_initial_chunks()

func _process(_delta):
	if Engine.is_editor_hint() and not is_preview:
		return

	# Update player chunk and load/unload chunks as needed
	if not is_instance_valid(player):
		return

	var player_pos = player.global_position
	var new_player_chunk_x = floor(player_pos.x / float(CHUNK_SIZE))
	var new_player_chunk_z = floor(player_pos.z / float(CHUNK_SIZE))
	
	# Wrap east-west coordinate for cylindrical world
	new_player_chunk_x = wrapi(int(new_player_chunk_x), 0, WORLD_WIDTH_IN_CHUNKS)
	var new_player_chunk = Vector2i(new_player_chunk_x, new_player_chunk_z)

	if new_player_chunk != current_player_chunk:
		current_player_chunk = new_player_chunk
		update_chunks()

func _exit_tree():
	# Clean up thread manager and chunks
	if verbose_logging:
		print("World: Cleaning up...")
	
	if thread_manager:
		thread_manager.cleanup()
	
	# Clear all loaded chunks
	for chunk_pos in loaded_chunks:
		if is_instance_valid(loaded_chunks[chunk_pos]):
			loaded_chunks[chunk_pos].queue_free()
	loaded_chunks.clear()
	
	if verbose_logging:
		print("World: Cleanup complete")

func update_chunks():
	var chunks_to_load = {}
	var chunks_to_remove = []

	# Determine which chunks should be loaded
	for x in range(-VIEW_DISTANCE, VIEW_DISTANCE + 1):
		for z in range(-VIEW_DISTANCE, VIEW_DISTANCE + 1):
			var chunk_pos = current_player_chunk + Vector2i(x, z)
			# Wrap east-west coordinate for cylindrical world
			chunk_pos.x = wrapi(chunk_pos.x, 0, WORLD_WIDTH_IN_CHUNKS)
			chunks_to_load[chunk_pos] = true

	# Find chunks to remove
	for chunk_pos in loaded_chunks:
		if not chunks_to_load.has(chunk_pos):
			chunks_to_remove.append(chunk_pos)

	# Remove distant chunks
	for chunk_pos in chunks_to_remove:
		unload_chunk(chunk_pos)

	# Load new chunks
	for chunk_pos in chunks_to_load:
		if not loaded_chunks.has(chunk_pos):
			load_chunk(chunk_pos)

func load_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		return

	var chunk = ChunkScene.instantiate()
	chunk.world = self
	chunk.chunk_position = chunk_pos
	chunk.world_material = world_material
	chunk.position = Vector3(chunk_pos.x * CHUNK_SIZE, 0, chunk_pos.y * CHUNK_SIZE)

	add_child(chunk)
	loaded_chunks[chunk_pos] = chunk

	# Request generation from thread manager
	if thread_manager:
		thread_manager.request_chunk_generation(chunk_pos)
	
	if verbose_logging:
		print("World: Loaded chunk at position ", chunk_pos, " (total loaded: ", loaded_chunks.size(), ")")

func unload_chunk(chunk_pos: Vector2i):
	if not loaded_chunks.has(chunk_pos):
		return

	# Cancel generation if in progress
	if thread_manager:
		thread_manager.cancel_chunk_generation(chunk_pos)

	if is_instance_valid(loaded_chunks[chunk_pos]):
		loaded_chunks[chunk_pos].queue_free()
	loaded_chunks.erase(chunk_pos)
	
	if verbose_logging:
		print("World: Unloaded chunk ", chunk_pos, " (remaining: ", loaded_chunks.size(), ")")

func get_surface_height(world_x: float, world_z: float) -> float:
	# First try to get height from loaded chunks
	var chunk = _get_chunk_at_world(world_x, world_z)
	if is_instance_valid(chunk) and not chunk.voxel_data.is_empty():
		# Fix local coordinate calculation for new chunk size
		var local_x = int(world_x) % CHUNK_SIZE
		var local_z = int(world_z) % CHUNK_SIZE
		if local_x < 0: local_x += CHUNK_SIZE
		if local_z < 0: local_z += CHUNK_SIZE
		
		# Ensure coordinates are within bounds
		if local_x >= 0 and local_x < chunk.voxel_data.size() and \
		   local_z >= 0 and local_z < chunk.voxel_data[0].size():
			# Find the highest solid voxel in this column
			for y in range(chunk.CHUNK_HEIGHT - 1, -1, -1):
				if y < chunk.voxel_data[0].size() and \
				   local_x < chunk.voxel_data.size() and \
				   local_z < chunk.voxel_data[local_x].size() and \
				   chunk.voxel_data[local_x][y][local_z] > 0.0:
					return float(y) + 1.0  # Add 1 to be above the surface
	
	# Fallback to generator if chunk not loaded or no solid voxels
	var generator_height = generator.get_height(world_x, world_z, CHUNK_HEIGHT)
	return max(generator_height, generator.sea_level + 1.0)

func get_biome(world_x: float, world_z: float) -> int:
	return generator.get_biome(world_x, world_z)

func edit_terrain(world_point: Vector3, amount: float) -> void:
	if verbose_logging:
		print("World: edit_terrain called at world point ", world_point, " with amount ", amount)
	
	# Determine which chunk this world point is in (with east-west wrapping)
	var chunk_x = wrapi(int(floor(world_point.x / CHUNK_SIZE)), 0, WORLD_WIDTH_IN_CHUNKS)
	var chunk_z = int(floor(world_point.z / CHUNK_SIZE))
	var chunk_pos = Vector2i(chunk_x, chunk_z)
	
	if verbose_logging:
		print("World: Calculated chunk position: ", chunk_pos)

	var chunk = loaded_chunks.get(chunk_pos)
	if not is_instance_valid(chunk):
		if verbose_logging:
			print("World: ERROR - Chunk not found at position ", chunk_pos)
		return

	# Convert to local coordinates within the chunk
	var local_x = world_point.x - float(chunk_pos.x * CHUNK_SIZE)
	var local_y = world_point.y
	var local_z = world_point.z - float(chunk_pos.y * CHUNK_SIZE)
	
	if verbose_logging:
		print("World: Converted to local coords: (", local_x, ", ", local_y, ", ", local_z, ")")

	var affected_chunks := {}
	chunk.edit_density_data(Vector3(local_x, local_y, local_z), amount, affected_chunks)

	# Force regeneration of affected chunks using thread manager
	for pos in affected_chunks.keys():
		if loaded_chunks.has(pos) and thread_manager:
			thread_manager.force_regenerate_chunk(pos)

	if verbose_logging:
		print("World: Terrain edit complete. Affected chunks: ", affected_chunks.keys())

func _get_chunk_at_world(world_x: float, world_z: float):
	# Proper cylindrical world wrapping: east-west wraps around, north-south extends infinitely
	var chunk_x = wrapi(int(floor(world_x / CHUNK_SIZE)), 0, WORLD_WIDTH_IN_CHUNKS)
	var chunk_z = int(floor(world_z / CHUNK_SIZE))
	var chunk_pos = Vector2i(chunk_x, chunk_z)
	return loaded_chunks.get(chunk_pos)

func create_biome_texture():
	var img = Image.create(2, 4, false, Image.FORMAT_RGB8)
	var grass = Color("658d41")
	var dirt = Color("5a412b")
	var sand = Color("c2b280")
	var water = Color("1e90ff")
	img.set_pixel(0, 0, grass)
	img.set_pixel(0, 1, dirt)
	img.set_pixel(0, 2, sand)
	img.set_pixel(0, 3, water)

	var snow = Color("f0f8ff")
	var tundra_rock = Color("8d9296")
	var desert_rock = Color("bca48b")
	var mountain_rock = Color("6b6867")
	img.set_pixel(1, 0, snow)
	img.set_pixel(1, 1, tundra_rock)
	img.set_pixel(1, 2, desert_rock)
	img.set_pixel(1, 3, mountain_rock)

	var texture = ImageTexture.create_from_image(img)
	world_material.set_shader_parameter("texture_atlas", texture)

func _set_world_width_in_chunks(v: int) -> void:
	WORLD_WIDTH_IN_CHUNKS = max(1, v)
	WORLD_CIRCUMFERENCE_IN_VOXELS = WORLD_WIDTH_IN_CHUNKS * CHUNK_SIZE
	_on_world_dimensions_changed()

func _set_chunk_size(v: int) -> void:
	CHUNK_SIZE = clamp(v, 8, 256)
	WORLD_CIRCUMFERENCE_IN_VOXELS = WORLD_WIDTH_IN_CHUNKS * CHUNK_SIZE
	_on_world_dimensions_changed()

func _on_world_dimensions_changed() -> void:
	if generator != null:
		generator.world_circumference_voxels = WORLD_CIRCUMFERENCE_IN_VOXELS
		generator.chunk_size = CHUNK_SIZE
		generator.chunk_height = CHUNK_HEIGHT

func load_initial_chunks():
	# Load chunks around origin to get started
	var initial_chunks = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)
	]
	
	for chunk_pos in initial_chunks:
		# Wrap east-west coordinates
		var wrapped_pos = Vector2i(wrapi(chunk_pos.x, 0, WORLD_WIDTH_IN_CHUNKS), chunk_pos.y)
		load_chunk(wrapped_pos)

func _initialize_modular_system():
	print("World: Initializing modular generation system")
	
	# Create modular generator
	modular_generator = ModularWorldGenerator.new(WORLD_CIRCUMFERENCE_IN_VOXELS, CHUNK_SIZE)
	modular_generator.sea_level = 28.0
	modular_generator.chunk_height = CHUNK_HEIGHT
	modular_generator.verbose_logging = verbose_logging
	
	# Use modular generator as the main generator
	generator = modular_generator
	
	print("World: Modular system initialized successfully")

func _on_chunk_generation_completed(chunk_pos: Vector2i, result_data: Dictionary):
	"""Handle completed chunk generation from thread manager"""
	if loaded_chunks.has(chunk_pos) and is_instance_valid(loaded_chunks[chunk_pos]):
		loaded_chunks[chunk_pos].apply_mesh_data(
			result_data.voxel_data, 
			result_data.mesh_arrays, 
			result_data.biome_data
		)

		if is_first_update and chunk_pos == Vector2i.ZERO:
			is_first_update = false
			initial_chunks_generated.emit()
		
		if verbose_logging:
			print("World: Applied mesh data for chunk ", chunk_pos)

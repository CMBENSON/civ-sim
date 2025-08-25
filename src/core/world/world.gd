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
var verbose_logging: bool = false

const WorldGenerator = preload("res://src/core/world/WorldGenerator.gd")
var generator: RefCounted

var world_material = ShaderMaterial.new()
var player: CharacterBody3D

# NEW: Use the proper ChunkManager system
var chunk_manager: ChunkManager
var thread_manager: ThreadManager
var max_threads = max(1, OS.get_processor_count() - 1)

# Access loaded chunks through chunk_manager
var loaded_chunks: Dictionary :
	get:
		return chunk_manager.loaded_chunks if chunk_manager else {}

# Marching cubes data
var tri_table_copy: Array
var edge_table_copy: Array

const VIEW_DISTANCE = 3  # Reduced for better performance

# Track initial spawn state
var initial_chunks_loaded = false
var spawn_ready = false

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
	_initialize_modular_system()

	# Initialize marching cubes data
	tri_table_copy = MarchingCubesData.TRI_TABLE.duplicate(true)
	edge_table_copy = MarchingCubesData.EDGE_TABLE.duplicate(true)

	# Create and setup systems in proper order
	_setup_generation_systems()
	_setup_chunk_management()
	
	# Load initial chunks BEFORE signaling ready
	_load_initial_chunks_and_spawn()

func _setup_generation_systems():
	"""Setup thread manager and generation systems"""
	thread_manager = ThreadManager.new(max_threads)
	thread_manager.setup_dependencies(generator, tri_table_copy, edge_table_copy)
	thread_manager.set_verbose_logging(verbose_logging)
	thread_manager.chunk_generation_completed.connect(_on_chunk_generation_completed)
	
	if verbose_logging:
		print("World: Generation systems initialized")

func _setup_chunk_management():
	"""Setup the proper ChunkManager system"""
	chunk_manager = ChunkManager.new(WORLD_WIDTH_IN_CHUNKS, CHUNK_SIZE, VIEW_DISTANCE)
	chunk_manager.setup_dependencies(self, ChunkScene, world_material, thread_manager)
	chunk_manager.set_verbose_logging(verbose_logging)
	
	# Connect ChunkManager signals
	chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
	chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
	chunk_manager.player_chunk_changed.connect(_on_player_chunk_changed)
	
	if verbose_logging:
		print("World: ChunkManager initialized")

func _load_initial_chunks_and_spawn():
	"""Load initial chunks around origin, then signal spawn ready"""
	if verbose_logging:
		print("World: Loading initial chunks...")
	
	# FIXED: Load chunks around spawn position (8, 8) which is in chunk (0, 0)
	var spawn_world_pos = Vector3(8.0, 0, 8.0)
	var spawn_chunk_pos = Vector2i(
		int(floor(spawn_world_pos.x / CHUNK_SIZE)),
		int(floor(spawn_world_pos.z / CHUNK_SIZE))
	)
	
	print("World: Spawn world position: ", spawn_world_pos)
	print("World: Spawn chunk position: ", spawn_chunk_pos)
	
	# Load the spawn chunk and immediate neighbors
	var initial_chunks = [
		spawn_chunk_pos,  # The spawn chunk itself - CRITICAL!
		spawn_chunk_pos + Vector2i(1, 0),
		spawn_chunk_pos + Vector2i(0, 1), 
		spawn_chunk_pos + Vector2i(1, 1),
		spawn_chunk_pos + Vector2i(-1, 0),
		spawn_chunk_pos + Vector2i(0, -1),
		spawn_chunk_pos + Vector2i(-1, -1),
		spawn_chunk_pos + Vector2i(1, -1),
		spawn_chunk_pos + Vector2i(-1, 1)
	]
	
	# Load each chunk explicitly
	for chunk_pos in initial_chunks:
		# Wrap east-west coordinates properly
		var wrapped_pos = Vector2i(wrapi(chunk_pos.x, 0, WORLD_WIDTH_IN_CHUNKS), chunk_pos.y)
		chunk_manager.load_chunk(wrapped_pos)
		if verbose_logging:
			print("World: Requested load of chunk ", wrapped_pos)
	
	# Track when initial chunks are generated
	_check_initial_chunks_ready(spawn_chunk_pos)

func _check_initial_chunks_ready(spawn_chunk_pos: Vector2i):
	"""Check if initial chunks have been generated and are ready for spawn"""
	await get_tree().process_frame
	
	# Wait for the spawn chunk specifically to be generated
	var spawn_chunk = chunk_manager.get_chunk_at_chunk_position(spawn_chunk_pos)
	if is_instance_valid(spawn_chunk) and not spawn_chunk.voxel_data.is_empty():
		if verbose_logging:
			print("World: Spawn chunk ", spawn_chunk_pos, " ready with voxel data, signaling spawn")
		initial_chunks_loaded = true
		spawn_ready = true
		initial_chunks_generated.emit()
	else:
		if verbose_logging:
			var chunk_status = "not found" if not is_instance_valid(spawn_chunk) else "no voxel data"
			print("World: Spawn chunk ", spawn_chunk_pos, " not ready (", chunk_status, "), waiting...")
		
		# Check again next frame
		_check_initial_chunks_ready(spawn_chunk_pos)

func _process(_delta):
	if Engine.is_editor_hint() and not is_preview:
		return

	# Only update chunk management if we have a valid player and chunk manager
	if is_instance_valid(player) and chunk_manager and spawn_ready:
		chunk_manager.update_player_position(player.global_position)

func _exit_tree():
	if verbose_logging:
		print("World: Cleaning up...")
	
	if chunk_manager:
		chunk_manager.cleanup()
	
	if verbose_logging:
		print("World: Cleanup complete")

# REMOVED: All the old chunk management functions (update_chunks, load_chunk, unload_chunk)
# These are now handled by ChunkManager

func get_surface_height(world_x: float, world_z: float) -> float:
	"""Get surface height - now uses ChunkManager"""
	if chunk_manager:
		return chunk_manager.get_surface_height(world_x, world_z)
	
	# Fallback to generator
	var generator_height = generator.get_height(world_x, world_z, CHUNK_HEIGHT)
	return max(generator_height, generator.sea_level + 1.0)

func get_biome(world_x: float, world_z: float) -> int:
	return generator.get_biome(world_x, world_z)

func edit_terrain(world_point: Vector3, amount: float) -> void:
	if verbose_logging:
		print("World: edit_terrain called at world point ", world_point, " with amount ", amount)
	
	if not chunk_manager:
		print("World: ERROR - No chunk manager available")
		return
	
	var chunk = chunk_manager.get_chunk_at_position(world_point)
	if not is_instance_valid(chunk):
		if verbose_logging:
			print("World: ERROR - No chunk found at world position ", world_point)
		return

	# Convert to local coordinates within the chunk
	var chunk_world_pos = chunk.position
	var local_pos = world_point - chunk_world_pos
	
	if verbose_logging:
		print("World: Converted to local coords: ", local_pos)

	var affected_chunks := {}
	chunk.edit_density_data(local_pos, amount, affected_chunks)

	# Force regeneration of affected chunks
	for pos in affected_chunks.keys():
		chunk_manager.force_regenerate_chunk(pos)

	if verbose_logging:
		print("World: Terrain edit complete. Affected chunks: ", affected_chunks.keys())

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

# ChunkManager signal handlers
func _on_chunk_loaded(chunk_position: Vector2i, chunk_node: Node3D):
	if verbose_logging:
		print("World: Chunk loaded at ", chunk_position)

func _on_chunk_unloaded(chunk_position: Vector2i):
	if verbose_logging:
		print("World: Chunk unloaded at ", chunk_position)

func _on_player_chunk_changed(old_chunk: Vector2i, new_chunk: Vector2i):
	if verbose_logging:
		print("World: Player moved from chunk ", old_chunk, " to ", new_chunk)

func _on_chunk_generation_completed(chunk_pos: Vector2i, result_data: Dictionary):
	"""Handle completed chunk generation from thread manager"""
	var chunk = chunk_manager.get_chunk_at_chunk_position(chunk_pos)
	if is_instance_valid(chunk):
		chunk.apply_mesh_data(
			result_data.voxel_data, 
			result_data.mesh_arrays, 
			result_data.biome_data
		)

		if verbose_logging:
			print("World: Applied mesh data for chunk ", chunk_pos)

# Compatibility properties for existing code
var current_player_chunk: Vector2i :
	get:
		return chunk_manager.current_player_chunk if chunk_manager else Vector2i(999, 999)

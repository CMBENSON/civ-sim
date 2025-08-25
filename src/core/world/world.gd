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
var is_first_update = true

# NEW: ThreadManager replaces old threading system
var thread_manager: ThreadManager
var max_threads = max(1, OS.get_processor_count() - 1)
var chunk_manager: ChunkManager

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
	thread_manager.chunk_generation_completed.connect(_on_chunk_generation_completed)

	# Initialize ChunkManager
	chunk_manager = ChunkManager.new(WORLD_WIDTH_IN_CHUNKS, CHUNK_SIZE, VIEW_DISTANCE)
	chunk_manager.setup_dependencies(self, ChunkScene, world_material, thread_manager)
	chunk_manager.set_verbose_logging(verbose_logging)
	
	# Connect ChunkManager signals
	chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
	chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
	chunk_manager.player_chunk_changed.connect(_on_player_chunk_changed)

	create_biome_texture()
	
	# Load initial chunks through ChunkManager
	chunk_manager.load_initial_chunks()
	
	# Test cylindrical wrapping (remove after testing)
	if verbose_logging:
		test_cylindrical_wrapping()

func _process(_delta):
	if Engine.is_editor_hint() and not is_preview:
		return

	if not is_instance_valid(player):
		return

	# Let ChunkManager handle player position updates
	var canonical_player_pos = get_canonical_world_pos(player.global_position)
	chunk_manager.update_player_position(canonical_player_pos)

func _exit_tree():
	if verbose_logging:
		print("World: Cleaning up...")
	
	if chunk_manager:
		chunk_manager.cleanup()
	
	if verbose_logging:
		print("World: Cleanup complete")


func get_biome(world_x: float, world_z: float) -> int:
	return generator.get_biome(world_x, world_z)

func edit_terrain(world_point: Vector3, amount: float) -> void:
	if verbose_logging:
		print("World: edit_terrain called at world point ", world_point, " with amount ", amount)
	
	var canonical_point = get_canonical_world_pos(world_point)
	var chunk_pos = world_pos_to_chunk_pos(canonical_point)
	
	var chunk = chunk_manager.get_chunk_at_chunk_position(chunk_pos)
	if not is_instance_valid(chunk):
		if verbose_logging:
			print("World: ERROR - Chunk not found at position ", chunk_pos)
		return

	# Convert to local coordinates within the chunk
	var chunk_world_pos = chunk_pos_to_world_pos(chunk_pos)
	var local_pos = canonical_point - chunk_world_pos
	
	if verbose_logging:
		print("World: Local edit pos: ", local_pos)

	var affected_chunks := {}
	chunk.edit_density_data(local_pos, amount, affected_chunks)

	# Force regeneration of affected chunks
	for pos in affected_chunks.keys():
		chunk_manager.force_regenerate_chunk(pos)

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
	var chunk = chunk_manager.get_chunk_at_chunk_position(chunk_pos)
	if is_instance_valid(chunk):
		chunk.apply_mesh_data(
			result_data.voxel_data, 
			result_data.mesh_arrays, 
			result_data.biome_data
		)

		if is_first_update and chunk_pos == Vector2i.ZERO:
			is_first_update = false
			initial_chunks_generated.emit()
		
		if verbose_logging:
			print("World: Applied mesh data for chunk ", chunk_pos)
			
func _on_chunk_loaded(chunk_position: Vector2i, chunk_node: Node3D):
	if verbose_logging:
		print("World: Chunk loaded at ", chunk_position)

func _on_chunk_unloaded(chunk_position: Vector2i):
	if verbose_logging:
		print("World: Chunk unloaded at ", chunk_position)

func _on_player_chunk_changed(old_chunk: Vector2i, new_chunk: Vector2i):
	if verbose_logging:
		print("World: Player moved from chunk ", old_chunk, " to ", new_chunk)

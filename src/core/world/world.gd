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
@export var CHUNK_HEIGHT: int = 256

# System configuration
var use_modular_generation: bool = true
var is_preview: bool = false
var verbose_logging: bool = false

# Core systems
var generator: RefCounted
var world_material: ShaderMaterial = ShaderMaterial.new()
var chunk_manager: ChunkManager
var thread_manager: ThreadManager

# Player reference
var player: CharacterBody3D

# Internal state
var is_first_update: bool = true
var max_threads: int = max(1, OS.get_processor_count() - 1)
var tri_table_copy: Array
var edge_table_copy: Array

# Cylindrical world coordinate system helpers
const VIEW_DISTANCE: int = 10

# Properties for external access (compatibility with existing code)
var current_player_chunk: Vector2i :
	get:
		return chunk_manager.current_player_chunk if chunk_manager else Vector2i.ZERO

var loaded_chunks: Dictionary :
	get:
		return chunk_manager.loaded_chunks if chunk_manager else {}

func _ready():
	print("World: Initializing consolidated world system...")
	
	# Load shader
	_initialize_shader()
	
	# Set up world dimensions
	_initialize_dimensions()
	
	# Initialize generation system
	_initialize_generation_system()
	
	# Initialize chunk management
	_initialize_chunk_system()
	
	# Create visual assets
	create_biome_texture()
	
	# Load initial chunks
	chunk_manager.load_initial_chunks()
	
	# Debug output
	if verbose_logging:
		_print_system_info()
		_test_coordinate_system()
	
	print("World: Initialization complete")

func _process(_delta):
	if Engine.is_editor_hint() and not is_preview:
		return
	
	if not is_instance_valid(player):
		return
	
	# Update chunk management based on player position
	var canonical_pos = get_canonical_world_pos(player.global_position)
	chunk_manager.update_player_position(canonical_pos)

func _exit_tree():
	print("World: Starting cleanup...")
	
	if chunk_manager:
		chunk_manager.cleanup()
	
	print("World: Cleanup complete")

# === INITIALIZATION METHODS ===

func _initialize_shader():
	"""Initialize the triplanar shader system"""
	var triplanar_shader = load("res://assets/shaders/triplanar.gdshader")
	if not triplanar_shader:
		print("ERROR: Failed to load triplanar shader!")
		return
	
	world_material.shader = triplanar_shader
	
	if verbose_logging:
		print("World: Triplanar shader loaded successfully")

func _initialize_dimensions():
	"""Set up world dimensions"""
	WORLD_WIDTH_IN_CHUNKS = 64
	CHUNK_SIZE = 16
	CHUNK_HEIGHT = 256
	WORLD_CIRCUMFERENCE_IN_VOXELS = WORLD_WIDTH_IN_CHUNKS * CHUNK_SIZE
	
	if verbose_logging:
		print("World: Dimensions set - ", WORLD_WIDTH_IN_CHUNKS, " chunks × ", CHUNK_SIZE, " = ", WORLD_CIRCUMFERENCE_IN_VOXELS, " voxels circumference")

func _initialize_generation_system():
	"""Initialize the modular world generation system"""
	if use_modular_generation:
		print("World: Using modular generation system")
		var ModularWorldGenerator = load("res://src/core/world/ModularWorldGenerator.gd")
		generator = ModularWorldGenerator.new(WORLD_CIRCUMFERENCE_IN_VOXELS, CHUNK_SIZE)
	else:
		print("World: Using legacy generation system")
		var WorldGenerator = load("res://src/core/world/WorldGenerator.gd")
		generator = WorldGenerator.new(WORLD_CIRCUMFERENCE_IN_VOXELS, CHUNK_SIZE)
	
	# Configure generator
	generator.sea_level = 28.0
	generator.chunk_height = CHUNK_HEIGHT
	generator.verbose_logging = verbose_logging
	
	if verbose_logging:
		print("World: Generator initialized with sea level ", generator.sea_level)

func _initialize_chunk_system():
	"""Initialize chunk management and threading systems"""
	# Initialize marching cubes data
	tri_table_copy = MarchingCubesData.TRI_TABLE.duplicate(true)
	edge_table_copy = MarchingCubesData.EDGE_TABLE.duplicate(true)
	
	# Create thread manager
	thread_manager = ThreadManager.new(max_threads)
	thread_manager.setup_dependencies(generator, tri_table_copy, edge_table_copy)
	thread_manager.set_verbose_logging(verbose_logging)
	thread_manager.chunk_generation_completed.connect(_on_chunk_generation_completed)
	
	# Create chunk manager
	chunk_manager = ChunkManager.new(WORLD_WIDTH_IN_CHUNKS, CHUNK_SIZE, VIEW_DISTANCE)
	chunk_manager.setup_dependencies(self, ChunkScene, world_material, thread_manager)
	chunk_manager.set_verbose_logging(verbose_logging)
	
	# Connect chunk manager signals
	chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
	chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
	chunk_manager.player_chunk_changed.connect(_on_player_chunk_changed)
	
	if verbose_logging:
		print("World: Chunk system initialized with ", max_threads, " threads")

# === COORDINATE SYSTEM ===

func get_canonical_world_pos(world_pos: Vector3) -> Vector3:
	"""Convert any world position to canonical coordinates with proper wrapping"""
	var canonical_x = fmod(world_pos.x, float(WORLD_CIRCUMFERENCE_IN_VOXELS))
	if canonical_x < 0:
		canonical_x += float(WORLD_CIRCUMFERENCE_IN_VOXELS)
	
	return Vector3(canonical_x, world_pos.y, world_pos.z)

func world_pos_to_chunk_pos(world_pos: Vector3) -> Vector2i:
	"""Convert world position to chunk coordinates"""
	var canonical_pos = get_canonical_world_pos(world_pos)
	var chunk_x = wrapi(int(floor(canonical_pos.x / CHUNK_SIZE)), 0, WORLD_WIDTH_IN_CHUNKS)
	var chunk_z = int(floor(canonical_pos.z / CHUNK_SIZE))
	return Vector2i(chunk_x, chunk_z)

func chunk_pos_to_world_pos(chunk_pos: Vector2i) -> Vector3:
	"""Convert chunk position to world coordinates (bottom-left corner)"""
	return Vector3(chunk_pos.x * CHUNK_SIZE, 0, chunk_pos.y * CHUNK_SIZE)

func wrap_world_x(world_x: float) -> float:
	"""Wrap X coordinate for cylindrical world"""
	var wrapped = fmod(world_x, float(WORLD_CIRCUMFERENCE_IN_VOXELS))
	if wrapped < 0:
		wrapped += float(WORLD_CIRCUMFERENCE_IN_VOXELS)
	return wrapped

func calculate_wrapped_distance(pos1: Vector3, pos2: Vector3) -> Vector3:
	"""Calculate shortest distance between two points considering cylindrical wrapping"""
	var dx = pos2.x - pos1.x
	var circumference = float(WORLD_CIRCUMFERENCE_IN_VOXELS)
	
	# Check if wrapping around gives a shorter distance
	if dx > circumference * 0.5:
		dx -= circumference
	elif dx < -circumference * 0.5:
		dx += circumference
	
	return Vector3(dx, pos2.y - pos1.y, pos2.z - pos1.z)

# === WORLD INTERACTION ===

func get_surface_height(world_x: float, world_z: float) -> float:
	"""Get surface height at world coordinates, checking chunks first then generator"""
	# Try chunk data first
	if chunk_manager:
		var height = chunk_manager.get_surface_height(world_x, world_z)
		if height > generator.sea_level:  # Valid height found
			return height
	
	# Fallback to generator
	if generator:
		var canonical_x = wrap_world_x(world_x)
		return max(generator.get_height(canonical_x, world_z, CHUNK_HEIGHT), generator.sea_level + 1.0)
	
	# Last resort fallback
	return 30.0

func get_biome(world_x: float, world_z: float) -> int:
	"""Get biome at world coordinates"""
	if generator:
		var canonical_x = wrap_world_x(world_x)
		return generator.get_biome(canonical_x, world_z)
	return WorldData.Biome.PLAINS

func edit_terrain(world_point: Vector3, amount: float) -> void:
	"""Edit terrain at a world position"""
	if verbose_logging:
		print("World: Editing terrain at ", world_point, " with amount ", amount)
	
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
		print("World: Local edit position: ", local_pos)
	
	var affected_chunks := {}
	chunk.edit_density_data(local_pos, amount, affected_chunks)
	
	# Force regeneration of affected chunks
	for pos in affected_chunks.keys():
		chunk_manager.force_regenerate_chunk(pos)
	
	if verbose_logging:
		print("World: Terrain edit complete. Affected chunks: ", affected_chunks.keys())

# === CHUNK MANAGEMENT INTERFACE ===

func load_chunk(chunk_pos: Vector2i):
	"""Load a chunk at the given position"""
	if chunk_manager:
		chunk_manager.load_chunk(chunk_pos)

func unload_chunk(chunk_pos: Vector2i):
	"""Unload a chunk at the given position"""
	if chunk_manager:
		chunk_manager.unload_chunk(chunk_pos)

func get_chunk_at_position(world_pos: Vector3):
	"""Get chunk at world position"""
	if chunk_manager:
		return chunk_manager.get_chunk_at_position(world_pos)
	return null

func is_chunk_loaded(chunk_pos: Vector2i) -> bool:
	"""Check if a chunk is loaded"""
	if chunk_manager:
		return chunk_manager.is_chunk_loaded(chunk_pos)
	return false

# === SIGNAL HANDLERS ===

func _on_chunk_generation_completed(chunk_pos: Vector2i, result_data: Dictionary):
	"""Handle completed chunk generation"""
	var chunk = chunk_manager.get_chunk_at_chunk_position(chunk_pos)
	if is_instance_valid(chunk):
		chunk.apply_mesh_data(
			result_data.voxel_data,
			result_data.mesh_arrays,
			result_data.biome_data
		)
		
		# Emit signal for initial world ready state
		if is_first_update and chunk_pos == Vector2i.ZERO:
			is_first_update = false
			call_deferred("emit_signal", "initial_chunks_generated")
		
		if verbose_logging:
			print("World: Applied mesh data for chunk ", chunk_pos)

func _on_chunk_loaded(chunk_position: Vector2i, chunk_node: Node3D):
	"""Handle chunk loaded"""
	if verbose_logging:
		print("World: Chunk loaded at ", chunk_position)

func _on_chunk_unloaded(chunk_position: Vector2i):
	"""Handle chunk unloaded"""
	if verbose_logging:
		print("World: Chunk unloaded at ", chunk_position)

func _on_player_chunk_changed(old_chunk: Vector2i, new_chunk: Vector2i):
	"""Handle player chunk change"""
	if verbose_logging:
		print("World: Player moved from chunk ", old_chunk, " to ", new_chunk)

# === VISUAL ASSETS ===

func create_biome_texture():
	"""Create the biome texture atlas"""
	var img = Image.create(2, 4, false, Image.FORMAT_RGB8)
	
	# First row: basic biome colors
	var grass = Color("658d41")
	var dirt = Color("5a412b") 
	var sand = Color("c2b280")
	var water = Color("1e90ff")
	img.set_pixel(0, 0, grass)
	img.set_pixel(0, 1, dirt)
	img.set_pixel(0, 2, sand)
	img.set_pixel(0, 3, water)
	
	# Second row: variant colors
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
	
	if verbose_logging:
		print("World: Biome texture created and applied")

# === PROPERTY SETTERS ===

func _set_world_width_in_chunks(v: int) -> void:
	WORLD_WIDTH_IN_CHUNKS = max(1, v)
	WORLD_CIRCUMFERENCE_IN_VOXELS = WORLD_WIDTH_IN_CHUNKS * CHUNK_SIZE
	_on_world_dimensions_changed()

func _set_chunk_size(v: int) -> void:
	CHUNK_SIZE = clamp(v, 8, 256)
	WORLD_CIRCUMFERENCE_IN_VOXELS = WORLD_WIDTH_IN_CHUNKS * CHUNK_SIZE
	_on_world_dimensions_changed()

func _on_world_dimensions_changed() -> void:
	"""Handle world dimension changes"""
	if generator:
		generator.world_circumference_voxels = WORLD_CIRCUMFERENCE_IN_VOXELS
		generator.chunk_size = CHUNK_SIZE
		generator.chunk_height = CHUNK_HEIGHT
	
	if verbose_logging:
		print("World: Dimensions updated - circumference now ", WORLD_CIRCUMFERENCE_IN_VOXELS, " voxels")

# === DEBUG AND TESTING ===

func _print_system_info():
	"""Print system information for debugging"""
	print("=== WORLD SYSTEM INFO ===")
	print("Generation System: ", "Modular" if use_modular_generation else "Legacy")
	print("World Size: ", WORLD_WIDTH_IN_CHUNKS, " × ", WORLD_WIDTH_IN_CHUNKS, " chunks")
	print("Chunk Size: ", CHUNK_SIZE, " × ", CHUNK_SIZE, " × ", CHUNK_HEIGHT, " voxels")
	print("World Circumference: ", WORLD_CIRCUMFERENCE_IN_VOXELS, " voxels")
	print("Thread Count: ", max_threads)
	print("View Distance: ", VIEW_DISTANCE, " chunks")
	
	if generator:
		print("Sea Level: ", generator.sea_level)
		if generator.has_method("get_all_tuning_parameters"):
			print("Generator Type: Advanced Modular")
		else:
			print("Generator Type: Basic")

func _test_coordinate_system():
	"""Test coordinate system functions"""
	print("=== COORDINATE SYSTEM TEST ===")
	var test_points = [
		Vector3(0, 0, 0),
		Vector3(WORLD_CIRCUMFERENCE_IN_VOXELS - 1, 0, 0),
		Vector3(-10, 0, 0),
		Vector3(WORLD_CIRCUMFERENCE_IN_VOXELS + 10, 0, 100)
	]
	
	for point in test_points:
		var canonical = get_canonical_world_pos(point)
		var chunk_pos = world_pos_to_chunk_pos(point)
		var back_to_world = chunk_pos_to_world_pos(chunk_pos)
		
		print("Original: ", point)
		print("  Canonical: ", canonical)
		print("  Chunk: ", chunk_pos)
		print("  Back to World: ", back_to_world)
		print("  ---")

# === STATISTICS AND MONITORING ===

func get_world_stats() -> Dictionary:
	"""Get comprehensive world statistics"""
	var stats = {
		"world_dimensions": {
			"chunks": Vector2i(WORLD_WIDTH_IN_CHUNKS, WORLD_WIDTH_IN_CHUNKS),
			"chunk_size": CHUNK_SIZE,
			"chunk_height": CHUNK_HEIGHT,
			"circumference_voxels": WORLD_CIRCUMFERENCE_IN_VOXELS
		},
		"generation_system": "Modular" if use_modular_generation else "Legacy",
		"sea_level": generator.sea_level if generator else 28.0
	}
	
	if chunk_manager:
		stats.merge(chunk_manager.get_stats())
	
	return stats

func enable_verbose_logging(enabled: bool = true):
	"""Enable or disable verbose logging across all systems"""
	verbose_logging = enabled
	
	if generator and generator.has_method("set"):
		generator.verbose_logging = enabled
	
	if chunk_manager:
		chunk_manager.set_verbose_logging(enabled)
	
	if thread_manager:
		thread_manager.set_verbose_logging(enabled)
	
	print("World: Verbose logging ", "enabled" if enabled else "disabled")

# === LEGACY COMPATIBILITY ===

# Provide access to old chunk management interface for compatibility
func update_chunks():
	"""Legacy method - now handled automatically by ChunkManager"""
	pass  # ChunkManager handles this automatically

# Make sure generator access works for debug UI and other systems
func get_generator():
	"""Get the world generator"""
	return generator

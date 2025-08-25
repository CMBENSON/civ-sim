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

var threads = []
var generation_queue = []
var results_queue = []
var chunks_being_generated = {}
var max_threads = max(1, OS.get_processor_count() - 1)

var tri_table_copy: Array
var edge_table_copy: Array

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

	if use_modular_generation:
		_initialize_modular_system()
	else:
		# Keep existing system
		generator = WorldGenerator.new(WORLD_CIRCUMFERENCE_IN_VOXELS, CHUNK_SIZE)
		generator.chunk_height = CHUNK_HEIGHT
		generator.verbose_logging = verbose_logging
		generator.sea_level = 28.0

	# Print debug info to help diagnose terrain issues (only if verbose logging enabled)
	if generator.has_method("print_biome_debug_info") and verbose_logging:
		generator.print_biome_debug_info()

	create_biome_texture()

	# Verify material setup
	if verbose_logging:
		print("World: Material shader: ", world_material.shader)
		print("World: Material resource: ", world_material)

	tri_table_copy = MarchingCubesData.TRI_TABLE.duplicate(true)
	edge_table_copy = MarchingCubesData.EDGE_TABLE.duplicate(true)

	for i in range(max_threads):
		var thread = Thread.new()
		threads.append(thread)
	
	# Load initial chunks immediately to get started
	load_initial_chunks()

func _process(_delta):
	if Engine.is_editor_hint() and not is_preview:
		return

	# Process completed chunk generation results
	while not results_queue.is_empty():
		var result = results_queue.pop_front()
		var chunk_pos = result.chunk_position

		chunks_being_generated.erase(chunk_pos)

		if loaded_chunks.has(chunk_pos) and is_instance_valid(loaded_chunks[chunk_pos]):
			loaded_chunks[chunk_pos].apply_mesh_data(result.voxel_data, result.mesh_arrays, result.biome_data)

			if is_first_update and chunk_pos == Vector2i.ZERO:
				is_first_update = false
				initial_chunks_generated.emit()
			
			if verbose_logging:
				print("World: Completed generation for chunk ", chunk_pos)

	# Start new chunk generation if threads are available (rate limited)
	if not generation_queue.is_empty():
		var chunks_started_this_frame = 0
		var max_chunks_per_frame = 4  # Increased from 2 to 4 for better performance
		
		# Debug: Show queue state every few seconds (only if verbose)
		if verbose_logging and Engine.get_process_frames() % 180 == 0:  # Every 3 seconds at 60fps
			print("World: Queue size: ", generation_queue.size(), ", Being generated: ", chunks_being_generated.size())
		
		for i in range(threads.size()):
			if chunks_started_this_frame >= max_chunks_per_frame:
				break
				
			if not threads[i].is_started() and not generation_queue.is_empty():
				var chunk_pos = generation_queue.pop_front()

				# Check if this chunk is already being generated
				if chunks_being_generated.has(chunk_pos):
					if verbose_logging:
						print("World: Skipping chunk ", chunk_pos, " - already being generated")
					continue

				chunks_being_generated[chunk_pos] = true
				var mesher = VoxelMesher.new(chunk_pos, generator, tri_table_copy, edge_table_copy)
				threads[i].start(Callable(self, "_thread_function").bind(mesher, threads[i], chunk_pos))
				chunks_started_this_frame += 1
				
				if verbose_logging:
					print("World: Started generation for chunk ", chunk_pos)

	# Update player chunk and load/unload chunks as needed
	if not is_instance_valid(player):
		return

	var player_pos = player.global_position
	# Fix chunk calculation: use proper chunk size for positioning
	var new_player_chunk_x = floor(player_pos.x / float(CHUNK_SIZE))
	var new_player_chunk_z = floor(player_pos.z / float(CHUNK_SIZE))

	# Wrap east-west coordinate for cylindrical world
	new_player_chunk_x = wrapi(int(new_player_chunk_x), 0, WORLD_WIDTH_IN_CHUNKS)

	var new_player_chunk = Vector2i(new_player_chunk_x, new_player_chunk_z)

	if new_player_chunk != current_player_chunk:
		current_player_chunk = new_player_chunk
		update_chunks()

func _thread_function(mesher, thread, chunk_pos):
	if verbose_logging:
		print("Starting generation for chunk ", chunk_pos)
	var result_data = mesher.run()
	result_data.chunk_position = chunk_pos
	if verbose_logging:
		print("Completed generation for chunk ", chunk_pos)
	call_deferred("_handle_thread_result", result_data, thread)

func _handle_thread_result(result_data, thread):
	thread.wait_to_finish()
	results_queue.append(result_data)

func _exit_tree():
	# Properly stop all threads to prevent hanging
	if verbose_logging:
		print("World: Cleaning up threads and chunks...")
	
	# Clear generation queue first
	generation_queue.clear()
	
	# Wait for all threads to finish
	for i in range(threads.size()):
		if threads[i].is_started():
			if verbose_logging:
				print("World: Waiting for thread ", i, " to finish...")
			threads[i].wait_to_finish()
	
	# Clear all loaded chunks
	for chunk_pos in loaded_chunks:
		if is_instance_valid(loaded_chunks[chunk_pos]):
			loaded_chunks[chunk_pos].queue_free()
	loaded_chunks.clear()
	
	# Clear generation tracking
	chunks_being_generated.clear()
	results_queue.clear()
	
	if verbose_logging:
		print("World: Cleanup complete")

func update_chunks():
	var chunks_to_load = {}
	var chunks_to_remove = []

	# Load chunks in a larger area to ensure no gaps
	for x in range(-VIEW_DISTANCE, VIEW_DISTANCE + 1):
		for z in range(-VIEW_DISTANCE, VIEW_DISTANCE + 1):
			var chunk_pos = current_player_chunk + Vector2i(x, z)
			# Wrap east-west coordinate for cylindrical world
			chunk_pos.x = wrapi(chunk_pos.x, 0, WORLD_WIDTH_IN_CHUNKS)
			chunks_to_load[chunk_pos] = true

	for chunk_pos in loaded_chunks:
		if not chunks_to_load.has(chunk_pos):
			chunks_to_remove.append(chunk_pos)

	for chunk_pos in chunks_to_remove:
		unload_chunk(chunk_pos)

	for chunk_pos in chunks_to_load:
		if not loaded_chunks.has(chunk_pos):
			load_chunk(chunk_pos)

const VIEW_DISTANCE = 10  # Reduced from 4 to 3 for better performance

func load_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		return

	var chunk = ChunkScene.instantiate()
	chunk.world = self
	chunk.chunk_position = chunk_pos
	chunk.world_material = world_material

	# Fix chunk positioning: multiply by actual chunk size to eliminate gaps
	chunk.position = Vector3(chunk_pos.x * CHUNK_SIZE, 0, chunk_pos.y * CHUNK_SIZE)

	add_child(chunk)
	loaded_chunks[chunk_pos] = chunk

	# Add to generation queue if not already there
	if not chunk_pos in generation_queue and not chunks_being_generated.has(chunk_pos):
		generation_queue.append(chunk_pos)
		# Only print for first few chunks to avoid spam
		if verbose_logging and generation_queue.size() <= 10:
			print("Added chunk ", chunk_pos, " to generation queue. Queue size: ", generation_queue.size())
	
	if verbose_logging:
		print("World: Loaded chunk at position ", chunk_pos, " (total loaded: ", loaded_chunks.size(), ")")

func unload_chunk(chunk_pos: Vector2i):
	if not loaded_chunks.has(chunk_pos):
		return

	if chunk_pos in generation_queue:
		generation_queue.erase(chunk_pos)
	chunks_being_generated.erase(chunk_pos)

	if is_instance_valid(loaded_chunks[chunk_pos]):
		loaded_chunks[chunk_pos].queue_free()
	loaded_chunks.erase(chunk_pos)

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
				   chunk.voxel_data[local_x][y][local_z] > 0.0:  # Use 0.0 as threshold
					return float(y) + 1.0  # Add 1 to be above the surface
	
	# Fallback to generator if chunk not loaded or no solid voxels
	var generator_height = generator.get_height(world_x, world_z, CHUNK_HEIGHT)
	return max(generator_height, generator.sea_level + 1.0)  # Ensure minimum height

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

	# Force regeneration of affected chunks by clearing their generation state
	for pos in affected_chunks.keys():
		if loaded_chunks.has(pos):
			# Force immediate regeneration
			if chunks_being_generated.has(pos):
				# Wait for current generation to finish
				continue
			
			# Clear from queue and regenerate
			generation_queue.erase(pos)
			
			# Create new mesher and start immediately if thread available
			for i in range(threads.size()):
				if not threads[i].is_started():
					chunks_being_generated[pos] = true
					var mesher = VoxelMesher.new(pos, generator, tri_table_copy, edge_table_copy)
					threads[i].start(Callable(self, "_thread_function").bind(mesher, threads[i], pos))
					break

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

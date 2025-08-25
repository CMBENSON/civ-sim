# src/core/world/simulation/ChunkManager.gd
extends RefCounted
class_name ChunkManager

signal chunk_loaded(chunk_position: Vector2i)
signal chunk_unloaded(chunk_position: Vector2i)
signal chunk_generation_started(chunk_position: Vector2i)
signal chunk_generation_completed(chunk_position: Vector2i)

var world_width_in_chunks: int
var chunk_size: int
var chunk_height: int
var view_distance: int = 3
var verbose_logging: bool = false

var loaded_chunks: Dictionary = {}
var current_player_chunk: Vector2i = Vector2i(999, 999)
var generation_queue: Array = []
var chunks_being_generated: Dictionary = {}

# Thread management
var threads: Array = []
var results_queue: Array = []
var max_threads: int
var max_chunks_per_frame: int = 4

# References to world components
var world_node: Node3D
var chunk_scene: PackedScene
var world_material: Material
var noise_manager: NoiseManager
var biome_generator: BiomeGenerator
var height_generator: HeightGenerator

func _init(p_world_width: int, p_chunk_size: int, p_chunk_height: int = 256):
	world_width_in_chunks = p_world_width
	chunk_size = p_chunk_size
	chunk_height = p_chunk_height
	max_threads = max(1, OS.get_processor_count() - 1)
	
	# Initialize threads
	for i in range(max_threads):
		var thread = Thread.new()
		threads.append(thread)

func setup_dependencies(p_world_node: Node3D, p_chunk_scene: PackedScene, p_material: Material, 
						p_noise_manager: NoiseManager, p_biome_gen: BiomeGenerator, p_height_gen: HeightGenerator):
	"""Setup references to world components"""
	world_node = p_world_node
	chunk_scene = p_chunk_scene
	world_material = p_material
	noise_manager = p_noise_manager
	biome_generator = p_biome_gen
	height_generator = p_height_gen

func set_view_distance(distance: int):
	view_distance = max(1, distance)

func set_verbose_logging(enabled: bool):
	verbose_logging = enabled

func update_player_position(player_position: Vector3):
	"""Update player chunk position and manage chunk loading/unloading"""
	var new_player_chunk_x = floor(player_position.x / float(chunk_size))
	var new_player_chunk_z = floor(player_position.z / float(chunk_size))

	# Wrap east-west coordinate for cylindrical world
	new_player_chunk_x = wrapi(int(new_player_chunk_x), 0, world_width_in_chunks)

	var new_player_chunk = Vector2i(new_player_chunk_x, new_player_chunk_z)

	if new_player_chunk != current_player_chunk:
		current_player_chunk = new_player_chunk
		update_chunks()
		
		if verbose_logging:
			print("ChunkManager: Player moved to chunk ", current_player_chunk)

func update_chunks():
	"""Update which chunks should be loaded based on player position"""
	var chunks_to_load = {}
	var chunks_to_remove = []

	# Determine which chunks should be loaded
	for x in range(-view_distance, view_distance + 1):
		for z in range(-view_distance, view_distance + 1):
			var chunk_pos = current_player_chunk + Vector2i(x, z)
			# Wrap east-west coordinate for cylindrical world
			chunk_pos.x = wrapi(chunk_pos.x, 0, world_width_in_chunks)
			chunks_to_load[chunk_pos] = true

	# Find chunks to remove
	for chunk_pos in loaded_chunks:
		if not chunks_to_load.has(chunk_pos):
			chunks_to_remove.append(chunk_pos)

	# Remove chunks that are too far away
	for chunk_pos in chunks_to_remove:
		unload_chunk(chunk_pos)

	# Load new chunks
	for chunk_pos in chunks_to_load:
		if not loaded_chunks.has(chunk_pos):
			load_chunk(chunk_pos)

func load_chunk(chunk_pos: Vector2i):
	"""Load a chunk at the given position"""
	if loaded_chunks.has(chunk_pos):
		if verbose_logging:
			print("ChunkManager: Chunk ", chunk_pos, " already loaded")
		return

	if not chunk_scene:
		print("ChunkManager: ERROR - No chunk scene provided")
		return

	var chunk = chunk_scene.instantiate()
	chunk.world = world_node
	chunk.chunk_position = chunk_pos
	chunk.world_material = world_material

	# Position the chunk correctly in world space
	chunk.position = Vector3(chunk_pos.x * chunk_size, 0, chunk_pos.y * chunk_size)

	world_node.add_child(chunk)
	loaded_chunks[chunk_pos] = chunk

	# Add to generation queue if not already there
	if not chunk_pos in generation_queue and not chunks_being_generated.has(chunk_pos):
		generation_queue.append(chunk_pos)
		
		if verbose_logging:
			print("ChunkManager: Loaded chunk ", chunk_pos, " and added to generation queue")

	chunk_loaded.emit(chunk_pos)

func unload_chunk(chunk_pos: Vector2i):
	"""Unload a chunk at the given position"""
	if not loaded_chunks.has(chunk_pos):
		return

	# Remove from queues
	if chunk_pos in generation_queue:
		generation_queue.erase(chunk_pos)
	chunks_being_generated.erase(chunk_pos)

	# Free the chunk
	if is_instance_valid(loaded_chunks[chunk_pos]):
		loaded_chunks[chunk_pos].queue_free()
	loaded_chunks.erase(chunk_pos)

	if verbose_logging:
		print("ChunkManager: Unloaded chunk ", chunk_pos)

	chunk_unloaded.emit(chunk_pos)

func process_generation(tri_table_copy: Array, edge_table_copy: Array):
	"""Process chunk generation on each frame"""
	# Process completed generation results
	while not results_queue.is_empty():
		var result = results_queue.pop_front()
		var chunk_pos = result.chunk_position

		chunks_being_generated.erase(chunk_pos)

		if loaded_chunks.has(chunk_pos) and is_instance_valid(loaded_chunks[chunk_pos]):
			loaded_chunks[chunk_pos].apply_mesh_data(result.voxel_data, result.mesh_arrays, result.biome_data)
			chunk_generation_completed.emit(chunk_pos)

			if verbose_logging:
				print("ChunkManager: Completed generation for chunk ", chunk_pos)

	# Start new chunk generation if threads are available
	if not generation_queue.is_empty():
		var chunks_started_this_frame = 0
		
		# Debug queue state occasionally
		if verbose_logging and Engine.get_process_frames() % 180 == 0:
			print("ChunkManager: Queue size: ", generation_queue.size(), ", Being generated: ", chunks_being_generated.size())
		
		for i in range(threads.size()):
			if chunks_started_this_frame >= max_chunks_per_frame:
				break
				
			if not threads[i].is_started() and not generation_queue.is_empty():
				var chunk_pos = generation_queue.pop_front()

				# Skip if already being generated
				if chunks_being_generated.has(chunk_pos):
					if verbose_logging:
						print("ChunkManager: Skipping chunk ", chunk_pos, " - already being generated")
					continue

				chunks_being_generated[chunk_pos] = true
				
				# Create the mesher with all dependencies
				var mesher = preload("res://src/core/world/VoxelMesher.gd").new(chunk_pos, _create_generator_proxy(), tri_table_copy, edge_table_copy)
				threads[i].start(Callable(self, "_thread_function").bind(mesher, threads[i], chunk_pos))
				chunks_started_this_frame += 1
				
				chunk_generation_started.emit(chunk_pos)
				if verbose_logging:
					print("ChunkManager: Started generation for chunk ", chunk_pos)

func _create_generator_proxy():
	"""Create a proxy object that VoxelMesher can use for generation"""
	var proxy = RefCounted.new()
	
	# Add methods that VoxelMesher expects
	proxy.set_script(preload("res://src/core/world/simulation/GeneratorProxy.gd"))
	proxy.setup(noise_manager, biome_generator, height_generator)
	
	return proxy

func _thread_function(mesher, thread, chunk_pos):
	"""Thread function for chunk generation"""
	if verbose_logging:
		print("ChunkManager: Starting generation thread for chunk ", chunk_pos)
	
	var result_data = mesher.run()
	result_data.chunk_position = chunk_pos
	
	if verbose_logging:
		print("ChunkManager: Completed generation thread for chunk ", chunk_pos)
	
	call_deferred("_handle_thread_result", result_data, thread)

func _handle_thread_result(result_data, thread):
	"""Handle completion of thread generation"""
	thread.wait_to_finish()
	results_queue.append(result_data)

func load_initial_chunks(center_pos: Vector2i = Vector2i.ZERO):
	"""Load a set of initial chunks around a center position"""
	var initial_chunks = [
		center_pos, center_pos + Vector2i(1, 0), center_pos + Vector2i(0, 1), center_pos + Vector2i(1, 1),
		center_pos + Vector2i(-1, 0), center_pos + Vector2i(0, -1), center_pos + Vector2i(-1, -1), 
		center_pos + Vector2i(1, -1), center_pos + Vector2i(-1, 1)
	]
	
	for chunk_pos in initial_chunks:
		# Wrap east-west coordinates
		var wrapped_pos = Vector2i(wrapi(chunk_pos.x, 0, world_width_in_chunks), chunk_pos.y)
		load_chunk(wrapped_pos)
	
	if verbose_logging:
		print("ChunkManager: Loaded ", initial_chunks.size(), " initial chunks around ", center_pos)

func get_chunk_at_position(world_pos: Vector3) -> Node3D:
	"""Get the chunk at a given world position"""
	var chunk_x = wrapi(int(floor(world_pos.x / chunk_size)), 0, world_width_in_chunks)
	var chunk_z = int(floor(world_pos.z / chunk_size))
	var chunk_pos = Vector2i(chunk_x, chunk_z)
	return loaded_chunks.get(chunk_pos)

func force_regenerate_chunk(chunk_pos: Vector2i):
	"""Force regeneration of a specific chunk"""
	if not loaded_chunks.has(chunk_pos):
		return

	# Remove from current generation if active
	generation_queue.erase(chunk_pos)
	
	# Wait for current generation to finish if active
	if chunks_being_generated.has(chunk_pos):
		if verbose_logging:
			print("ChunkManager: Waiting for chunk ", chunk_pos, " to finish current generation")
		return

	# Add back to generation queue
	if not chunk_pos in generation_queue:
		generation_queue.append(chunk_pos)
		if verbose_logging:
			print("ChunkManager: Forced regeneration of chunk ", chunk_pos)

func cleanup():
	"""Clean up all threads and chunks"""
	if verbose_logging:
		print("ChunkManager: Starting cleanup...")
	
	# Clear generation queue
	generation_queue.clear()
	
	# Wait for all threads to finish
	for i in range(threads.size()):
		if threads[i].is_started():
			if verbose_logging:
				print("ChunkManager: Waiting for thread ", i, " to finish...")
			threads[i].wait_to_finish()
	
	# Clear all loaded chunks
	for chunk_pos in loaded_chunks:
		if is_instance_valid(loaded_chunks[chunk_pos]):
			loaded_chunks[chunk_pos].queue_free()
	loaded_chunks.clear()
	
	# Clear tracking data
	chunks_being_generated.clear()
	results_queue.clear()
	
	if verbose_logging:
		print("ChunkManager: Cleanup complete")

func get_stats() -> Dictionary:
	"""Get statistics about chunk management"""
	return {
		"loaded_chunks": loaded_chunks.size(),
		"generation_queue_size": generation_queue.size(),
		"chunks_being_generated": chunks_being_generated.size(),
		"current_player_chunk": current_player_chunk,
		"view_distance": view_distance,
		"max_threads": max_threads,
		"active_threads": _get_active_thread_count()
	}

func _get_active_thread_count() -> int:
	"""Get count of currently active threads"""
	var count = 0
	for thread in threads:
		if thread.is_started():
			count += 1
	return count

# src/core/world/simulation/ThreadManager.gd
extends RefCounted
class_name ThreadManager

signal chunk_generation_completed(chunk_pos: Vector2i, result_data: Dictionary)

var threads: Array[Thread] = []
var generation_queue: Array[Vector2i] = []
var chunks_being_generated: Dictionary = {}
var max_threads: int
var generator: RefCounted
var tri_table_copy: Array
var edge_table_copy: Array
var verbose_logging: bool = false

func _init(p_max_threads: int = 0):
	max_threads = p_max_threads if p_max_threads > 0 else max(1, OS.get_processor_count() - 1)
	
	# Initialize threads
	threads.resize(max_threads)
	for i in range(max_threads):
		threads[i] = Thread.new()
	
	if verbose_logging:
		print("ThreadManager: Initialized with ", max_threads, " threads")

func setup_dependencies(p_generator: RefCounted, p_tri_table: Array, p_edge_table: Array):
	"""Setup generation dependencies"""
	generator = p_generator
	tri_table_copy = p_tri_table.duplicate(true)
	edge_table_copy = p_edge_table.duplicate(true)

func request_chunk_generation(chunk_pos: Vector2i):
	"""Request generation of a chunk"""
	if chunks_being_generated.has(chunk_pos):
		if verbose_logging:
			print("ThreadManager: Chunk ", chunk_pos, " already being generated")
		return
	
	if not chunk_pos in generation_queue:
		generation_queue.append(chunk_pos)
		if verbose_logging:
			print("ThreadManager: Added chunk ", chunk_pos, " to queue")
	
	_try_start_generation()

func cancel_chunk_generation(chunk_pos: Vector2i):
	"""Cancel generation of a chunk"""
	if chunk_pos in generation_queue:
		generation_queue.erase(chunk_pos)
	
	chunks_being_generated.erase(chunk_pos)

func force_regenerate_chunk(chunk_pos: Vector2i):
	"""Force regeneration of a chunk"""
	cancel_chunk_generation(chunk_pos)
	request_chunk_generation(chunk_pos)

func _try_start_generation():
	"""Try to start chunk generation on available threads"""
	if generation_queue.is_empty():
		return
	
	for i in range(threads.size()):
		if generation_queue.is_empty():
			break
		
		if not threads[i].is_started():
			var chunk_pos = generation_queue.pop_front()
			chunks_being_generated[chunk_pos] = true
			
			var mesher = load("res://src/core/world/VoxelMesher.gd").new(
				chunk_pos, generator, tri_table_copy, edge_table_copy
			)
			
			threads[i].start(_thread_function.bind(mesher, chunk_pos, threads[i]))
			
			if verbose_logging:
				print("ThreadManager: Started generation for chunk ", chunk_pos, " on thread ", i)

func _thread_function(mesher: RefCounted, chunk_pos: Vector2i, thread: Thread):
	"""Thread function for chunk generation"""
	var result_data = mesher.run()
	result_data.chunk_position = chunk_pos
	
	# Signal completion on main thread
	call_deferred("_handle_generation_complete", result_data, thread)

func _handle_generation_complete(result_data: Dictionary, thread: Thread):
	"""Handle completed chunk generation"""
	thread.wait_to_finish()
	var chunk_pos = result_data.chunk_position
	chunks_being_generated.erase(chunk_pos)
	
	chunk_generation_completed.emit(chunk_pos, result_data)
	
	if verbose_logging:
		print("ThreadManager: Completed generation for chunk ", chunk_pos)
	
	# Try to start next generation
	_try_start_generation()

func get_stats() -> Dictionary:
	"""Get thread manager statistics"""
	return {
		"max_threads": max_threads,
		"active_threads": _get_active_thread_count(),
		"queue_size": generation_queue.size(),
		"chunks_being_generated": chunks_being_generated.size()
	}

func _get_active_thread_count() -> int:
	"""Get number of currently active threads"""
	var count = 0
	for thread in threads:
		if thread.is_started():
			count += 1
	return count

func cleanup():
	"""Clean up all threads"""
	if verbose_logging:
		print("ThreadManager: Starting cleanup...")
	
	# Clear queue
	generation_queue.clear()
	chunks_being_generated.clear()
	
	# Wait for all threads to finish
	for i in range(threads.size()):
		if threads[i].is_started():
			threads[i].wait_to_finish()
	
	if verbose_logging:
		print("ThreadManager: Cleanup complete")

func set_verbose_logging(enabled: bool):
	verbose_logging = enabled

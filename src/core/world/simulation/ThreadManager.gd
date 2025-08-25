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

# Thread synchronization
var _queue_mutex: Mutex = Mutex.new()
var _generation_mutex: Mutex = Mutex.new()
var _is_shutting_down: bool = false

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
	"""Request generation of a chunk (thread-safe)"""
	if verbose_logging:
		print("ThreadManager: Received request to generate chunk ", chunk_pos)
	
	if _is_shutting_down:
		return
	
	_queue_mutex.lock()
	
	_generation_mutex.lock()
	var already_generating = chunks_being_generated.has(chunk_pos)
	_generation_mutex.unlock()
	
	if already_generating:
		if verbose_logging:
			print("ThreadManager: Chunk ", chunk_pos, " already being generated")
		_queue_mutex.unlock()
		return
	
	if not chunk_pos in generation_queue:
		generation_queue.append(chunk_pos)
		if verbose_logging:
			print("ThreadManager: Added chunk ", chunk_pos, " to queue (queue size: ", generation_queue.size(), ")")
	
	_try_start_generation()
	_queue_mutex.unlock()

func cancel_chunk_generation(chunk_pos: Vector2i):
	"""Cancel generation of a chunk (thread-safe)"""
	_queue_mutex.lock()
	
	if chunk_pos in generation_queue:
		generation_queue.erase(chunk_pos)
		if verbose_logging:
			print("ThreadManager: Cancelled chunk ", chunk_pos, " (removed from queue)")
	
	_queue_mutex.unlock()
	
	_generation_mutex.lock()
	chunks_being_generated.erase(chunk_pos)
	_generation_mutex.unlock()

func force_regenerate_chunk(chunk_pos: Vector2i):
	"""Force regeneration of a chunk"""
	cancel_chunk_generation(chunk_pos)
	request_chunk_generation(chunk_pos)

func _try_start_generation():
	"""Try to start chunk generation on available threads (assumes queue is locked)"""
	if _is_shutting_down or generation_queue.is_empty():
		return
	
	for i in range(threads.size()):
		if generation_queue.is_empty():
			break
		
		if not threads[i].is_started():
			var chunk_pos = generation_queue.pop_front()
			
			_generation_mutex.lock()
			chunks_being_generated[chunk_pos] = true
			_generation_mutex.unlock()
			
			# Validate dependencies before creating mesher
			if not _validate_generation_dependencies():
				print("ThreadManager: ERROR - Invalid dependencies for chunk generation")
				_generation_mutex.lock()
				chunks_being_generated.erase(chunk_pos)
				_generation_mutex.unlock()
				continue
			
			var VoxelMesher = load("res://src/core/world/VoxelMesher.gd")
			if not VoxelMesher:
				print("ThreadManager: ERROR - Failed to load VoxelMesher")
				_generation_mutex.lock()
				chunks_being_generated.erase(chunk_pos)
				_generation_mutex.unlock()
				continue
			
			if verbose_logging:
				print("ThreadManager: VoxelMesher loaded successfully for chunk ", chunk_pos)
			
			var mesher = VoxelMesher.new(
				chunk_pos, generator, tri_table_copy, edge_table_copy
			)
			
			if not mesher:
				print("ThreadManager: ERROR - Failed to create VoxelMesher")
				_generation_mutex.lock()
				chunks_being_generated.erase(chunk_pos)
				_generation_mutex.unlock()
				continue
			
			threads[i].start(_thread_function.bind(mesher, chunk_pos, threads[i]))
			
			if verbose_logging:
				print("ThreadManager: Started generation for chunk ", chunk_pos, " on thread ", i)

func _thread_function(mesher: RefCounted, chunk_pos: Vector2i, thread: Thread):
	"""Thread function for chunk generation"""
	if _is_shutting_down:
		return
	
	if not is_instance_valid(mesher):
		print("ThreadManager: ERROR - Invalid mesher in thread function")
		call_deferred("_handle_generation_failed", chunk_pos, thread)
		return
	
	var result_data = mesher.run()
	if not result_data:
		print("ThreadManager: ERROR - Mesher returned null result")
		call_deferred("_handle_generation_failed", chunk_pos, thread)
		return
	
	result_data.chunk_position = chunk_pos
	
	# Signal completion on main thread
	call_deferred("_handle_generation_complete", result_data, thread)

func _handle_generation_complete(result_data: Dictionary, thread: Thread):
	"""Handle completed chunk generation"""
	if _is_shutting_down:
		return
	
	thread.wait_to_finish()
	
	if not result_data.has("chunk_position"):
		print("ThreadManager: ERROR - Result data missing chunk position")
		return
	
	var chunk_pos = result_data.chunk_position
	
	_generation_mutex.lock()
	chunks_being_generated.erase(chunk_pos)
	_generation_mutex.unlock()
	
	chunk_generation_completed.emit(chunk_pos, result_data)
	
	if verbose_logging:
		print("ThreadManager: Completed generation for chunk ", chunk_pos)
	
	# Try to start next generation
	_queue_mutex.lock()
	_try_start_generation()
	_queue_mutex.unlock()

func _handle_generation_failed(chunk_pos: Vector2i, thread: Thread):
	"""Handle failed chunk generation"""
	if thread.is_started():
		thread.wait_to_finish()
	
	_generation_mutex.lock()
	chunks_being_generated.erase(chunk_pos)
	_generation_mutex.unlock()
	
	print("ThreadManager: Failed generation for chunk ", chunk_pos)
	
	# Try to start next generation
	_queue_mutex.lock()
	_try_start_generation()
	_queue_mutex.unlock()

func get_stats() -> Dictionary:
	"""Get thread manager statistics (thread-safe)"""
	_queue_mutex.lock()
	var queue_size = generation_queue.size()
	_queue_mutex.unlock()
	
	_generation_mutex.lock()
	var generating_count = chunks_being_generated.size()
	_generation_mutex.unlock()
	
	return {
		"max_threads": max_threads,
		"active_threads": _get_active_thread_count(),
		"queue_size": queue_size,
		"chunks_being_generated": generating_count,
		"is_shutting_down": _is_shutting_down
	}

func _get_active_thread_count() -> int:
	"""Get number of currently active threads"""
	var count = 0
	for thread in threads:
		if thread.is_started():
			count += 1
	return count

func cleanup():
	"""Clean up all threads safely"""
	if verbose_logging:
		print("ThreadManager: Starting cleanup...")
	
	_is_shutting_down = true
	
	# Clear queue safely
	_queue_mutex.lock()
	generation_queue.clear()
	_queue_mutex.unlock()
	
	# Clear generation tracking
	_generation_mutex.lock()
	chunks_being_generated.clear()
	_generation_mutex.unlock()
	
	# Wait for all threads to finish
	for i in range(threads.size()):
		if threads[i].is_started():
			threads[i].wait_to_finish()
	
	if verbose_logging:
		print("ThreadManager: Cleanup complete")

func _validate_generation_dependencies() -> bool:
	"""Validate all dependencies are available for generation"""
	return generator != null and tri_table_copy.size() > 0 and edge_table_copy.size() > 0

func set_verbose_logging(enabled: bool):
	verbose_logging = enabled

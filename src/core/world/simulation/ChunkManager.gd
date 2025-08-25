# src/core/world/simulation/ChunkManager.gd
extends RefCounted
class_name ChunkManager

signal chunk_loaded(chunk_position: Vector2i, chunk_node: Node3D)
signal chunk_unloaded(chunk_position: Vector2i)
signal player_chunk_changed(old_chunk: Vector2i, new_chunk: Vector2i)

# Configuration
var world_width_in_chunks: int
var chunk_size: int
var view_distance: int = 3
var verbose_logging: bool = false

# State tracking
var loaded_chunks: Dictionary = {}
var current_player_chunk: Vector2i = Vector2i(999, 999)

# References
var world_node: Node3D
var chunk_scene: PackedScene
var world_material: Material
var thread_manager: ThreadManager

func _init(p_world_width: int, p_chunk_size: int, p_view_distance: int = 3):
	world_width_in_chunks = p_world_width
	chunk_size = p_chunk_size
	view_distance = p_view_distance

func setup_dependencies(p_world_node: Node3D, p_chunk_scene: PackedScene, p_material: Material, p_thread_manager: ThreadManager):
	"""Setup references to world components"""
	world_node = p_world_node
	chunk_scene = p_chunk_scene
	world_material = p_material
	thread_manager = p_thread_manager

func set_verbose_logging(enabled: bool):
	verbose_logging = enabled

func update_player_position(player_position: Vector3) -> bool:
	"""Update player chunk position and manage chunk loading/unloading. Returns true if chunk changed."""
	var new_player_chunk_x = floor(player_position.x / float(chunk_size))
	var new_player_chunk_z = floor(player_position.z / float(chunk_size))

	# Wrap east-west coordinate for cylindrical world  
	new_player_chunk_x = wrapi(int(new_player_chunk_x), 0, world_width_in_chunks)

	var new_player_chunk = Vector2i(new_player_chunk_x, new_player_chunk_z)

	if new_player_chunk != current_player_chunk:
		var old_chunk = current_player_chunk
		current_player_chunk = new_player_chunk
		player_chunk_changed.emit(old_chunk, new_player_chunk)
		
		update_chunks()
		
		if verbose_logging:
			print("ChunkManager: Player moved to chunk ", current_player_chunk)
		
		return true
	
	return false

func update_chunks():
	"""Update which chunks should be loaded based on player position with priority loading"""
	var chunks_to_load = {}
	var chunks_to_remove = []
	var chunk_priorities = []  # Store chunks with distances for priority loading

	# Determine which chunks should be loaded and calculate priorities
	for x in range(-view_distance, view_distance + 1):
		for z in range(-view_distance, view_distance + 1):
			var chunk_pos = current_player_chunk + Vector2i(x, z)
			# Wrap east-west coordinate for cylindrical world
			chunk_pos.x = wrapi(chunk_pos.x, 0, world_width_in_chunks)
			
			# Calculate priority (distance from player)
			var distance = Vector2i(x, z).length()
			chunk_priorities.append({
				"position": chunk_pos,
				"distance": distance,
				"offset": Vector2i(x, z)
			})
			chunks_to_load[chunk_pos] = true

	# Sort chunks by distance (closest first)
	chunk_priorities.sort_custom(func(a, b): return a.distance < b.distance)

	# Find chunks to remove
	for chunk_pos in loaded_chunks:
		if not chunks_to_load.has(chunk_pos):
			chunks_to_remove.append(chunk_pos)

	# Remove distant chunks first
	for chunk_pos in chunks_to_remove:
		unload_chunk(chunk_pos)

	# Load new chunks in priority order (closest first)
	for chunk_info in chunk_priorities:
		var chunk_pos = chunk_info.position
		if not loaded_chunks.has(chunk_pos):
			load_chunk(chunk_pos)

func load_chunk(chunk_pos: Vector2i) -> Node3D:
	"""Load a chunk at the given position"""
	if loaded_chunks.has(chunk_pos):
		if verbose_logging:
			print("ChunkManager: Chunk ", chunk_pos, " already loaded")
		return loaded_chunks[chunk_pos]

	if not chunk_scene:
		print("ChunkManager: ERROR - No chunk scene provided")
		return null

	var chunk = chunk_scene.instantiate()
	chunk.world = world_node
	chunk.chunk_position = chunk_pos
	chunk.world_material = world_material

	# Position the chunk correctly in world space
	chunk.position = Vector3(chunk_pos.x * chunk_size, 0, chunk_pos.y * chunk_size)

	world_node.add_child(chunk)
	loaded_chunks[chunk_pos] = chunk

	# Request chunk generation from thread manager
	if thread_manager:
		thread_manager.request_chunk_generation(chunk_pos)

	chunk_loaded.emit(chunk_pos, chunk)
	
	if verbose_logging:
		print("ChunkManager: Loaded chunk at ", chunk_pos, " (total: ", loaded_chunks.size(), ")")

	return chunk

func unload_chunk(chunk_pos: Vector2i):
	"""Unload a chunk at the given position"""
	if not loaded_chunks.has(chunk_pos):
		return

	# Cancel generation if in progress
	if thread_manager:
		thread_manager.cancel_chunk_generation(chunk_pos)

	# Free the chunk
	if is_instance_valid(loaded_chunks[chunk_pos]):
		loaded_chunks[chunk_pos].queue_free()
	loaded_chunks.erase(chunk_pos)

	chunk_unloaded.emit(chunk_pos)
	
	if verbose_logging:
		print("ChunkManager: Unloaded chunk ", chunk_pos, " (remaining: ", loaded_chunks.size(), ")")

func get_chunk_at_position(world_pos: Vector3) -> Node3D:
	"""Get the chunk at a given world position"""
	var chunk_x = wrapi(int(floor(world_pos.x / chunk_size)), 0, world_width_in_chunks)
	var chunk_z = int(floor(world_pos.z / chunk_size))
	var chunk_pos = Vector2i(chunk_x, chunk_z)
	return loaded_chunks.get(chunk_pos)

func get_chunk_at_chunk_position(chunk_pos: Vector2i) -> Node3D:
	"""Get chunk by chunk coordinates"""
	return loaded_chunks.get(chunk_pos)

func is_chunk_loaded(chunk_pos: Vector2i) -> bool:
	"""Check if a chunk is currently loaded"""
	return loaded_chunks.has(chunk_pos)

func load_initial_chunks(center_pos: Vector2i = Vector2i.ZERO):
	"""Load initial chunks in spiral/priority order from center outward"""
	var initial_chunks_with_priority = []
	
	# Create a larger initial set for better coverage
	for x in range(-2, 3):  # 5x5 grid of chunks
		for z in range(-2, 3):
			var chunk_pos = center_pos + Vector2i(x, z)
			# Wrap east-west coordinates
			chunk_pos.x = wrapi(chunk_pos.x, 0, world_width_in_chunks)
			
			var distance = Vector2i(x, z).length()
			initial_chunks_with_priority.append({
				"position": chunk_pos,
				"distance": distance
			})
	
	# Sort by distance (closest first)
	initial_chunks_with_priority.sort_custom(func(a, b): return a.distance < b.distance)
	
	# Load chunks in priority order
	for chunk_info in initial_chunks_with_priority:
		load_chunk(chunk_info.position)
	
	if verbose_logging:
		print("ChunkManager: Loaded ", initial_chunks_with_priority.size(), " initial chunks in priority order around ", center_pos)


func force_regenerate_chunk(chunk_pos: Vector2i):
	"""Force regeneration of a specific chunk"""
	if not loaded_chunks.has(chunk_pos):
		return

	if thread_manager:
		thread_manager.force_regenerate_chunk(chunk_pos)
	
	if verbose_logging:
		print("ChunkManager: Forced regeneration of chunk ", chunk_pos)

func get_loaded_chunk_positions() -> Array:
	"""Get array of all currently loaded chunk positions"""
	return loaded_chunks.keys()

func get_chunk_count() -> int:
	"""Get number of currently loaded chunks"""
	return loaded_chunks.size()

func cleanup():
	"""Clean up all chunks"""
	if verbose_logging:
		print("ChunkManager: Starting cleanup...")
	
	# Cancel all generation
	if thread_manager:
		thread_manager.cleanup()
	
	# Free all chunks
	for chunk_pos in loaded_chunks:
		if is_instance_valid(loaded_chunks[chunk_pos]):
			loaded_chunks[chunk_pos].queue_free()
	
	loaded_chunks.clear()
	current_player_chunk = Vector2i(999, 999)
	
	if verbose_logging:
		print("ChunkManager: Cleanup complete")

func get_stats() -> Dictionary:
	"""Get enhanced statistics about chunk management"""
	var chunks_by_distance = get_chunks_by_distance()
	var closest_chunk = chunks_by_distance[0] if chunks_by_distance.size() > 0 else null
	var farthest_chunk = chunks_by_distance[-1] if chunks_by_distance.size() > 0 else null
	
	var stats = {
		"loaded_chunks": loaded_chunks.size(),
		"current_player_chunk": current_player_chunk,
		"view_distance": view_distance,
		"world_width_in_chunks": world_width_in_chunks,
		"chunk_size": chunk_size,
		"closest_chunk_distance": closest_chunk.distance if closest_chunk else 0.0,
		"farthest_chunk_distance": farthest_chunk.distance if farthest_chunk else 0.0,
		"average_chunk_distance": _calculate_average_chunk_distance(chunks_by_distance)
	}
	
	if thread_manager:
		var thread_stats = thread_manager.get_stats()
		stats.merge(thread_stats)
	
	return stats

func get_chunks_in_radius(center_chunk: Vector2i, radius: int) -> Array:
	"""Get all loaded chunks within a given radius of a center chunk"""
	var result = []
	
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			var chunk_pos = center_chunk + Vector2i(x, z)
			chunk_pos.x = wrapi(chunk_pos.x, 0, world_width_in_chunks)
			
			if loaded_chunks.has(chunk_pos):
				result.append({
					"position": chunk_pos,
					"chunk": loaded_chunks[chunk_pos],
					"distance": Vector2i(x, z).length()
				})
	
	return result

func get_surface_height(world_x: float, world_z: float) -> float:
	"""Get surface height at world coordinates, checking loaded chunks first"""
	var chunk = get_chunk_at_position(Vector3(world_x, 0, world_z))
	
	if is_instance_valid(chunk) and not chunk.voxel_data.is_empty():
		var local_x = int(world_x) % chunk_size
		var local_z = int(world_z) % chunk_size
		if local_x < 0: local_x += chunk_size
		if local_z < 0: local_z += chunk_size
		
		# Find highest solid voxel in this column
		if local_x < chunk.voxel_data.size() and chunk.voxel_data[local_x].size() > 0:
			for y in range(chunk.CHUNK_HEIGHT - 1, -1, -1):
				if y < chunk.voxel_data[local_x].size() and \
				   local_z < chunk.voxel_data[local_x][y].size() and \
				   chunk.voxel_data[local_x][y][local_z] > 0.0:
					return float(y) + 1.0
	
	# Fallback: return sea level + some default height
	return 30.0
	
func get_chunks_by_distance() -> Array:
	"""Get all loaded chunks sorted by distance from player"""
	var chunks_with_distance = []
	
	for chunk_pos in loaded_chunks:
		var offset = chunk_pos - current_player_chunk
		# Handle wrap-around distance calculation
		if offset.x > world_width_in_chunks / 2:
			offset.x -= world_width_in_chunks
		elif offset.x < -world_width_in_chunks / 2:
			offset.x += world_width_in_chunks
		
		var distance = offset.length()
		chunks_with_distance.append({
			"position": chunk_pos,
			"chunk": loaded_chunks[chunk_pos],
			"distance": distance,
			"offset": offset
		})
	
	chunks_with_distance.sort_custom(func(a, b): return a.distance < b.distance)
	return chunks_with_distance


func _calculate_average_chunk_distance(chunks_by_distance: Array) -> float:
	if chunks_by_distance.is_empty():
		return 0.0
	
	var total_distance = 0.0
	for chunk_info in chunks_by_distance:
		total_distance += chunk_info.distance
	
	return total_distance / float(chunks_by_distance.size())

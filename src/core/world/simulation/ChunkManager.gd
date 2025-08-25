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

	# Remove distant chunks
	for chunk_pos in chunks_to_remove:
		unload_chunk(chunk_pos)

	# Load new chunks
	for chunk_pos in chunks_to_load:
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
	"""Get statistics about chunk management"""
	var stats = {
		"loaded_chunks": loaded_chunks.size(),
		"current_player_chunk": current_player_chunk,
		"view_distance": view_distance,
		"world_width_in_chunks": world_width_in_chunks,
		"chunk_size": chunk_size
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
		if local_x < chunk.voxel_data.size() and local_z < chunk.voxel_data[0].size():
			for y in range(chunk.CHUNK_HEIGHT - 1, -1, -1):
				if y < chunk.voxel_data[0].size() and \
				   chunk.voxel_data[local_x][y][local_z] > 0.0:
					return float(y) + 1.0
	
	# Fallback: return sea level + some default height
	return 30.0

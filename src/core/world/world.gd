@tool
extends Node3D

signal initial_chunks_generated

const ChunkScene = preload("res://src/core/world/chunk.tscn")
const VoxelMesher = preload("res://src/core/world/VoxelMesher.gd")
const MarchingCubesData = preload("res://src/core/world/marching_cubes.gd")
const VIEW_DISTANCE = 3

const WORLD_WIDTH_IN_CHUNKS = 32
const WORLD_CIRCUMFERENCE_IN_VOXELS = WORLD_WIDTH_IN_CHUNKS * 32
const CHUNK_SIZE = 32

var is_preview = false

var noise = FastNoiseLite.new()
var temperature_noise = FastNoiseLite.new()
var moisture_noise = FastNoiseLite.new()
var elevation_noise = FastNoiseLite.new()
var world_material = ShaderMaterial.new()

var player: CharacterBody3D
var loaded_chunks = {}
var current_player_chunk = Vector2i(999, 999)
var is_first_update = true

var threads = []
var generation_queue = []
var results_queue = []
var chunks_being_generated = {} # Track chunks currently being generated
var max_threads = max(1, OS.get_processor_count() - 1)

var tri_table_copy: Array
var edge_table_copy: Array

func _ready():
	var triplanar_shader = load("res://assets/shaders/triplanar.gdshader")
	world_material.shader = triplanar_shader

	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = randi()
	noise.frequency = 0.03
	
	temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temperature_noise.seed = randi()
	temperature_noise.frequency = 0.009
	
	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	moisture_noise.seed = randi()
	moisture_noise.frequency = 0.008
	
	elevation_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	elevation_noise.seed = randi()
	elevation_noise.frequency = 0.002
	
	create_biome_texture()
	
	tri_table_copy = MarchingCubesData.TRI_TABLE.duplicate(true)
	edge_table_copy = MarchingCubesData.EDGE_TABLE.duplicate(true)
	
	for i in range(max_threads):
		var thread = Thread.new()
		threads.append(thread)

func _process(_delta):
	if Engine.is_editor_hint() and not is_preview:
		return

	# Process generation results
	while not results_queue.is_empty():
		var result = results_queue.pop_front()
		var chunk_pos = result.chunk_position
		
		# Remove from being generated list
		chunks_being_generated.erase(chunk_pos)
		
		# Apply the mesh if the chunk still exists
		if loaded_chunks.has(chunk_pos) and is_instance_valid(loaded_chunks[chunk_pos]):
			loaded_chunks[chunk_pos].apply_mesh_data(result.voxel_data, result.mesh_arrays, result.biome_data)
			
			if is_first_update and chunk_pos == Vector2i.ZERO:
				is_first_update = false
				initial_chunks_generated.emit()

	# Start new generation tasks
	if not generation_queue.is_empty():
		for i in range(threads.size()):
			if not threads[i].is_started() and not generation_queue.is_empty():
				var chunk_pos = generation_queue.pop_front()
				
				# Skip if chunk is already being generated or no longer loaded
				if chunks_being_generated.has(chunk_pos) or not loaded_chunks.has(chunk_pos):
					continue
				
				chunks_being_generated[chunk_pos] = true
				var mesher = VoxelMesher.new(chunk_pos, noise, temperature_noise, moisture_noise, 
											elevation_noise, tri_table_copy, edge_table_copy)
				threads[i].start(Callable(self, "_thread_function").bind(mesher, threads[i], chunk_pos))

	# Update chunks based on player position
	if not is_instance_valid(player):
		return
	
	var player_pos = player.global_position
	var wrapped_x = wrapi(int(player_pos.x), 0, WORLD_CIRCUMFERENCE_IN_VOXELS)
	var new_player_chunk_x = floor(float(wrapped_x) / CHUNK_SIZE)
	var new_player_chunk_z = floor(player_pos.z / CHUNK_SIZE)
	var new_player_chunk = Vector2i(new_player_chunk_x, new_player_chunk_z)
	
	if new_player_chunk != current_player_chunk:
		current_player_chunk = new_player_chunk
		update_chunks()

func _thread_function(mesher, thread, chunk_pos):
	var result_data = mesher.run()
	result_data.chunk_position = chunk_pos
	call_deferred("_handle_thread_result", result_data, thread)

func _handle_thread_result(result_data, thread):
	thread.wait_to_finish()
	results_queue.append(result_data)

func _exit_tree():
	generation_queue.clear()
	for thread in threads:
		if thread.is_started():
			thread.wait_to_finish()

func update_chunks():
	var chunks_to_load = {}
	var chunks_to_remove = []
	
	for x in range(-VIEW_DISTANCE, VIEW_DISTANCE + 1):
		for z in range(-VIEW_DISTANCE, VIEW_DISTANCE + 1):
			var chunk_pos = current_player_chunk + Vector2i(x, z)
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

func load_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		return
	
	var chunk = ChunkScene.instantiate()
	chunk.world = self
	chunk.chunk_position = chunk_pos
	chunk.world_material = world_material
	
	# Handle cylindrical wrapping for chunk position
	var actual_x = chunk_pos.x * CHUNK_SIZE
	if chunk_pos.x >= WORLD_WIDTH_IN_CHUNKS / 2:
		actual_x -= WORLD_CIRCUMFERENCE_IN_VOXELS
	
	chunk.position = Vector3(float(actual_x), 0, float(chunk_pos.y * CHUNK_SIZE))
	add_child(chunk)
	loaded_chunks[chunk_pos] = chunk
	
	# Queue for generation if not already queued
	if not chunk_pos in generation_queue and not chunks_being_generated.has(chunk_pos):
		generation_queue.append(chunk_pos)

func unload_chunk(chunk_pos: Vector2i):
	if not loaded_chunks.has(chunk_pos):
		return
	
	# Remove from all queues
	if chunk_pos in generation_queue:
		generation_queue.erase(chunk_pos)
	chunks_being_generated.erase(chunk_pos)
	
	# Free the chunk
	if is_instance_valid(loaded_chunks[chunk_pos]):
		loaded_chunks[chunk_pos].queue_free()
	loaded_chunks.erase(chunk_pos)

func get_surface_height(world_x, world_z):
	var wrapped_x = wrapi(int(world_x), 0, WORLD_CIRCUMFERENCE_IN_VOXELS)
	var chunk_x = floor(float(wrapped_x) / CHUNK_SIZE)
	var chunk_z = floor(float(world_z) / CHUNK_SIZE)
	var chunk_pos = Vector2i(chunk_x, chunk_z)
	
	var chunk = loaded_chunks.get(chunk_pos)
	if not is_instance_valid(chunk) or chunk.voxel_data.is_empty():
		var noise_val = noise.get_noise_2d(world_x, world_z)
		return (noise_val * 10) + 32.0

	var local_x = wrapped_x % CHUNK_SIZE
	var local_z = int(world_z) % CHUNK_SIZE
	if local_z < 0:
		local_z += CHUNK_SIZE

	for y in range(chunk.CHUNK_HEIGHT - 1, -1, -1):
		if chunk.voxel_data[local_x][y][local_z] > chunk.ISO_LEVEL:
			return y
	
	return chunk.SEA_LEVEL

func get_biome(world_x, world_z):
	var elev = elevation_noise.get_noise_2d(world_x, world_z)
	if elev < -0.1:
		return WorldData.Biome.OCEAN
	
	var temp = temperature_noise.get_noise_2d(world_x, world_z)
	var moist = moisture_noise.get_noise_2d(world_x, world_z)
	var temp_norm = (temp + 1.0) / 2.0
	var moist_norm = (moist + 1.0) / 2.0

	if temp_norm < 0.2:
		return WorldData.Biome.TUNDRA
	elif temp_norm > 0.8:
		if moist_norm < 0.3:
			return WorldData.Biome.DESERT
		else:
			return WorldData.Biome.JUNGLE
	elif moist_norm > 0.6:
		return WorldData.Biome.FOREST
	elif moist_norm < 0.2:
		return WorldData.Biome.SWAMP
	else:
		return WorldData.Biome.PLAINS

func edit_terrain(world_pos: Vector3, edit_strength: float):
	var wrapped_x = wrapi(int(world_pos.x), 0, WORLD_CIRCUMFERENCE_IN_VOXELS)
	var chunk_x = floor(float(wrapped_x) / CHUNK_SIZE)
	var chunk_z = floor(float(world_pos.z) / CHUNK_SIZE)
	var center_chunk_pos = Vector2i(chunk_x, chunk_z)
	
	if not loaded_chunks.has(center_chunk_pos):
		return
	
	var center_chunk = loaded_chunks[center_chunk_pos]
	if not is_instance_valid(center_chunk):
		return
	
	# Calculate local position within the chunk
	var local_x = wrapped_x % CHUNK_SIZE
	var local_z = int(world_pos.z) % CHUNK_SIZE
	if local_z < 0:
		local_z += CHUNK_SIZE
	var local_pos = Vector3(local_x, world_pos.y, local_z)
	
	# Edit the center chunk
	var affected_chunks = {}
	center_chunk.edit_density_data(local_pos, edit_strength, affected_chunks)
	
	# Check if we need to update neighboring chunks
	var edit_radius = 3
	var chunks_to_update = {}
	chunks_to_update[center_chunk_pos] = true
	
	# Check each neighbor direction
	if local_x < edit_radius:  # Left edge
		var left_chunk = Vector2i(wrapi(center_chunk_pos.x - 1, 0, WORLD_WIDTH_IN_CHUNKS), center_chunk_pos.y)
		chunks_to_update[left_chunk] = true
	if local_x >= CHUNK_SIZE - edit_radius:  # Right edge
		var right_chunk = Vector2i(wrapi(center_chunk_pos.x + 1, 0, WORLD_WIDTH_IN_CHUNKS), center_chunk_pos.y)
		chunks_to_update[right_chunk] = true
	if local_z < edit_radius:  # Front edge
		var front_chunk = Vector2i(center_chunk_pos.x, center_chunk_pos.y - 1)
		chunks_to_update[front_chunk] = true
	if local_z >= CHUNK_SIZE - edit_radius:  # Back edge
		var back_chunk = Vector2i(center_chunk_pos.x, center_chunk_pos.y + 1)
		chunks_to_update[back_chunk] = true
	
	# Corner chunks
	if local_x < edit_radius and local_z < edit_radius:
		var corner_chunk = Vector2i(wrapi(center_chunk_pos.x - 1, 0, WORLD_WIDTH_IN_CHUNKS), center_chunk_pos.y - 1)
		chunks_to_update[corner_chunk] = true
	if local_x >= CHUNK_SIZE - edit_radius and local_z < edit_radius:
		var corner_chunk = Vector2i(wrapi(center_chunk_pos.x + 1, 0, WORLD_WIDTH_IN_CHUNKS), center_chunk_pos.y - 1)
		chunks_to_update[corner_chunk] = true
	if local_x < edit_radius and local_z >= CHUNK_SIZE - edit_radius:
		var corner_chunk = Vector2i(wrapi(center_chunk_pos.x - 1, 0, WORLD_WIDTH_IN_CHUNKS), center_chunk_pos.y + 1)
		chunks_to_update[corner_chunk] = true
	if local_x >= CHUNK_SIZE - edit_radius and local_z >= CHUNK_SIZE - edit_radius:
		var corner_chunk = Vector2i(wrapi(center_chunk_pos.x + 1, 0, WORLD_WIDTH_IN_CHUNKS), center_chunk_pos.y + 1)
		chunks_to_update[corner_chunk] = true
	
	# Queue all affected chunks for regeneration
	for chunk_pos in chunks_to_update:
		if loaded_chunks.has(chunk_pos) and not chunks_being_generated.has(chunk_pos):
			if not chunk_pos in generation_queue:
				generation_queue.push_front(chunk_pos)  # Priority queue for edited chunks

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

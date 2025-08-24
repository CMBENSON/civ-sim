@tool
extends Node3D

signal initial_chunks_generated

const ChunkScene = preload("res://src/core/world/chunk.tscn")
const VoxelMesher = preload("res://src/core/world/VoxelMesher.gd")
const MarchingCubesData = preload("res://src/core/world/marching_cubes.gd")
const VIEW_DISTANCE = 3

const WORLD_WIDTH_IN_CHUNKS = 32
const WORLD_CIRCUMFERENCE_IN_VOXELS = WORLD_WIDTH_IN_CHUNKS * 32

var noise = FastNoiseLite.new()
var temperature_noise = FastNoiseLite.new()
var moisture_noise = FastNoiseLite.new()
var world_material = load("res://assets/materials/world_shader_material.tres")

var player: CharacterBody3D
var loaded_chunks = {}
var current_player_chunk = Vector2i(999, 999)
var is_first_update = true

var threads = []
var generation_queue = []
var results_queue = []
var max_threads = max(1, OS.get_processor_count() - 1)

var tri_table_copy: Array
var edge_table_copy: Array

func _ready():
	noise.noise_type = FastNoiseLite.TYPE_PERLIN; noise.seed = randi(); noise.frequency = 0.03
	temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN; temperature_noise.seed = randi(); temperature_noise.frequency = 0.009
	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN; moisture_noise.seed = randi(); moisture_noise.frequency = 0.008
	create_biome_texture()
	
	tri_table_copy = MarchingCubesData.TRI_TABLE.duplicate(true)
	edge_table_copy = MarchingCubesData.EDGE_TABLE.duplicate(true)
	
	for i in range(max_threads):
		var thread = Thread.new()
		threads.append(thread)

func _process(_delta):
	if Engine.is_editor_hint():
		return

	if not results_queue.is_empty():
		var result = results_queue.pop_front()
		if is_instance_valid(result.chunk):
			result.chunk.apply_mesh_data(result.voxel_data, result.mesh_arrays, result.biome_data)
			if is_first_update and result.chunk.chunk_position == Vector2i.ZERO:
				is_first_update = false
				initial_chunks_generated.emit()

	if not generation_queue.is_empty():
		for i in range(threads.size()):
			if not threads[i].is_started() and not generation_queue.is_empty():
				var chunk_pos = generation_queue.pop_front()
				var mesher = VoxelMesher.new(chunk_pos, noise, temperature_noise, moisture_noise, tri_table_copy, edge_table_copy)
				threads[i].start(Callable(self, "_thread_function").bind(mesher, threads[i]))

	if not is_instance_valid(player): return
	
	var player_pos = player.global_position
	var wrapped_player_x = wrapi(floor(player_pos.x), 0, WORLD_CIRCUMFERENCE_IN_VOXELS)
	var new_player_chunk_x = floor(wrapped_player_x / 32.0)
	var new_player_chunk_z = floor(player_pos.z / 32.0)
	var new_player_chunk = Vector2i(new_player_chunk_x, new_player_chunk_z)
	
	if new_player_chunk != current_player_chunk:
		current_player_chunk = new_player_chunk
		update_chunks()

func _thread_function(mesher, thread):
	var result_data = mesher.run()
	call_deferred("_handle_thread_result", result_data, thread)

func _handle_thread_result(result_data, thread):
	thread.wait_to_finish()
	var chunk_pos = result_data.chunk_position
	if loaded_chunks.has(chunk_pos):
		var result_payload = {
			"chunk": loaded_chunks[chunk_pos],
			"voxel_data": result_data.voxel_data,
			"mesh_arrays": result_data.mesh_arrays,
			"biome_data": result_data.biome_data
		}
		results_queue.append(result_payload)

func _exit_tree():
	for thread in threads:
		if thread.is_started():
			thread.wait_to_finish()

func update_chunks():
	var chunks_to_load = {}; var chunks_to_remove = []
	for x in range(-VIEW_DISTANCE, VIEW_DISTANCE + 1):
		for z in range(-VIEW_DISTANCE, VIEW_DISTANCE + 1):
			var chunk_pos = current_player_chunk + Vector2i(x, z)
			chunk_pos.x = wrapi(chunk_pos.x, 0, WORLD_WIDTH_IN_CHUNKS)
			chunks_to_load[chunk_pos] = true
			
	for chunk_pos in loaded_chunks:
		if not chunks_to_load.has(chunk_pos): chunks_to_remove.append(chunk_pos)
	for chunk_pos in chunks_to_remove: unload_chunk(chunk_pos)
	for chunk_pos in chunks_to_load:
		if not loaded_chunks.has(chunk_pos): load_chunk(chunk_pos)

func load_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos): return
	var chunk = ChunkScene.instantiate()
	chunk.world = self
	chunk.chunk_position = chunk_pos
	chunk.world_material = world_material
	chunk.position = Vector3(float(chunk_pos.x * 32), 0, float(chunk_pos.y * 32))
	add_child(chunk)
	loaded_chunks[chunk_pos] = chunk
	
	if not chunk_pos in generation_queue:
		generation_queue.append(chunk_pos)

func unload_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		if chunk_pos in generation_queue:
			generation_queue.erase(chunk_pos)
		loaded_chunks[chunk_pos].queue_free()
		loaded_chunks.erase(chunk_pos)

func get_surface_height(world_x, world_z):
	var chunk_pos = Vector2i(floori(world_x / 32.0), floori(world_z / 32.0))
	var chunk = loaded_chunks.get(chunk_pos)
	if not is_instance_valid(chunk) or chunk.voxel_data.is_empty():
		var noise_val = noise.get_noise_2d(world_x, world_z)
		return (noise_val * 10) + 32.0

	var local_x = wrapi(world_x, 0, 32)
	var local_z = wrapi(world_z, 0, 32)

	for y in range(chunk.CHUNK_HEIGHT - 1, -1, -1):
		if chunk.voxel_data[local_x][y][local_z] > chunk.ISO_LEVEL:
			return y
	
	return chunk.SEA_LEVEL

# --- FIX: Improved biome logic for more variety ---
func get_biome(world_x, world_z):
	var wrapped_world_x = wrapi(world_x, 0, WORLD_CIRCUMFERENCE_IN_VOXELS)
	var temp = temperature_noise.get_noise_2d(wrapped_world_x, world_z)
	var moist = moisture_noise.get_noise_2d(wrapped_world_x, world_z)

	# Normalize noise from [-1, 1] to [0, 1] for easier thresholds
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
		return WorldData.Biome.SWAMP # Swamps can be cool or warm
	else:
		return WorldData.Biome.PLAINS

# --- FIX: Re-implement terrain editing ---
func edit_terrain(world_pos: Vector3, amount: float):
	var wrapped_x = wrapi(floor(world_pos.x), 0, WORLD_CIRCUMFERENCE_IN_VOXELS)
	var chunk_pos_x = floor(wrapped_x / 32.0)
	var chunk_pos_z = floor(world_pos.z / 32.0)
	var chunk_pos = Vector2i(chunk_pos_x, chunk_pos_z)

	if loaded_chunks.has(chunk_pos):
		var chunk = loaded_chunks[chunk_pos]
		var local_pos = world_pos - chunk.global_position
		
		# We tell the chunk to edit its data. It will handle the remeshing.
		chunk.edit_density_data(local_pos, amount)

func update_chunk_and_neighbors(chunk_pos: Vector2i):
	for x in range(-1, 2):
		for z in range(-1, 2):
			var pos = chunk_pos + Vector2i(x, z)
			pos.x = wrapi(pos.x, 0, WORLD_WIDTH_IN_CHUNKS)
			if not pos in generation_queue:
				generation_queue.append(pos)

func create_biome_texture():
	var img = Image.create(2, 4, false, Image.FORMAT_RGB8)
	var grass = Color("658d41"); var dirt = Color("5a412b"); var sand = Color("c2b280"); var water = Color("1e90ff")
	img.set_pixel(0, 0, grass); img.set_pixel(0, 1, dirt); img.set_pixel(0, 2, sand); img.set_pixel(0, 3, water)
	var snow = Color("f0f8ff"); var tundra_rock = Color("8d9296"); var desert_rock = Color("bca48b"); var mountain_rock = Color("6b6867")
	img.set_pixel(1, 0, snow); img.set_pixel(1, 1, tundra_rock); img.set_pixel(1, 2, desert_rock); img.set_pixel(1, 3, mountain_rock)
	var texture = ImageTexture.create_from_image(img)
	world_material.set_shader_parameter("texture_atlas", texture)

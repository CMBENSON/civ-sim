@tool
extends Node3D

signal initial_chunks_generated

const ChunkScene = preload("res://src/core/world/chunk.tscn")
const VIEW_DISTANCE = 3

const WORLD_WIDTH_IN_CHUNKS = 32
const WORLD_CIRCUMFERENCE_IN_VOXELS = WORLD_WIDTH_IN_CHUNKS * 32
enum Biome { PLAINS, FOREST, DESERT, MOUNTAINS, JUNGLE, TUNDRA, SWAMP, OCEAN }
var noise = FastNoiseLite.new()
var temperature_noise = FastNoiseLite.new()
var moisture_noise = FastNoiseLite.new()
var world_material = load("res://assets/materials/world_shader_material.tres")

var player: CharacterBody3D

var loaded_chunks = {}
var current_player_chunk = Vector2i(999, 999)
var is_first_update = true

var generation_queue = []


func _ready():
	noise.noise_type = FastNoiseLite.TYPE_PERLIN; noise.seed = randi(); noise.frequency = 0.03
	
	temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN;
	temperature_noise.seed = randi();
	temperature_noise.frequency = 0.009

	moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN; moisture_noise.seed = randi(); moisture_noise.frequency = 0.008
	create_biome_texture()

func _process(_delta):
	if not generation_queue.is_empty():
		var chunk_pos = generation_queue.pop_front()
		if loaded_chunks.has(chunk_pos):
			regenerate_chunk_mesh(chunk_pos)
			if is_first_update and chunk_pos == Vector2i.ZERO:
				is_first_update = false
				initial_chunks_generated.emit()

	if not is_instance_valid(player): return
		
	var player_pos = player.global_position
	var wrapped_player_x = wrapi(floor(player_pos.x), 0, WORLD_CIRCUMFERENCE_IN_VOXELS)
	var new_player_chunk_x = floor(wrapped_player_x / 32.0)
	var new_player_chunk_z = floor(player_pos.z / 32.0)
	var new_player_chunk = Vector2i(new_player_chunk_x, new_player_chunk_z)
	
	if new_player_chunk != current_player_chunk:
		current_player_chunk = new_player_chunk
		update_chunks()

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
	chunk.chunk_position = chunk_pos;
	chunk.noise = noise;
	chunk.temperature_noise = temperature_noise
	chunk.moisture_noise = moisture_noise;
	chunk.world_material = world_material
	chunk.position = Vector3(float(chunk_pos.x * 32), 0, float(chunk_pos.y * 32))
	add_child(chunk);
	loaded_chunks[chunk_pos] = chunk
	
	chunk.generate_initial_data()
	
	update_chunk_and_neighbors(chunk_pos)

func unload_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		if chunk_pos in generation_queue:
			generation_queue.erase(chunk_pos)
		loaded_chunks[chunk_pos].queue_free()
		loaded_chunks.erase(chunk_pos)

func edit_terrain(world_pos: Vector3, amount: float):
	var wrapped_x = wrapi(floor(world_pos.x), 0, WORLD_CIRCUMFERENCE_IN_VOXELS)
	var chunk_pos_x = floor(wrapped_x / 32.0)
	var chunk_pos_z = floor(world_pos.z / 32.0)
	var chunk_pos = Vector2i(chunk_pos_x, chunk_pos_z)

	if loaded_chunks.has(chunk_pos):
		var chunk = loaded_chunks[chunk_pos]
		var local_pos = Vector3(wrapped_x - chunk.position.x, world_pos.y, world_pos.z - chunk.position.z)
		chunk.edit_density_data(local_pos, amount)
		update_chunk_and_neighbors(chunk_pos)

func update_chunk_and_neighbors(chunk_pos: Vector2i):
	for x in range(-1, 2):
		for z in range(-1, 2):
			var pos = chunk_pos + Vector2i(x, z)
			pos.x = wrapi(pos.x, 0, WORLD_WIDTH_IN_CHUNKS)
			if not pos in generation_queue:
				generation_queue.append(pos)

func regenerate_chunk_mesh(chunk_pos: Vector2i):
	if not loaded_chunks.has(chunk_pos): return
	var chunk = loaded_chunks[chunk_pos]
	var padded_data = get_padded_data_for_chunk(chunk_pos)
	chunk.generate_mesh(padded_data)

func get_padded_data_for_chunk(chunk_pos: Vector2i):
	var padded_data = []; var size = 33; var height = 65
	padded_data.resize(size); for x in range(size):
		padded_data[x] = []; padded_data[x].resize(height)
		for y in range(height): padded_data[x][y] = []; padded_data[x][y].resize(size)
	for x in range(size):
		for y in range(height):
			for z in range(size):
				padded_data[x][y][z] = get_voxel_density(
					chunk_pos.x * 32 + x, y, chunk_pos.y * 32 + z)
	return padded_data

func get_voxel_density(world_x, world_y, world_z):
	var wrapped_world_x = wrapi(world_x, 0, WORLD_CIRCUMFERENCE_IN_VOXELS)
	var chunk_pos_x = floor(wrapped_world_x / 32.0)
	var chunk_pos_z = floor(world_z / 32.0)
	var chunk_pos = Vector2i(chunk_pos_x, chunk_pos_z)

	if loaded_chunks.has(chunk_pos):
		var chunk = loaded_chunks[chunk_pos]
		var local_x = wrapped_world_x - chunk.chunk_position.x * 32
		var local_z = world_z - chunk.chunk_position.y * 32
		if local_x >= 0 and local_x < 32 and world_y >= 0 and world_y < 64 and local_z >= 0 and local_z < 32:
			if chunk.voxel_data.size() > local_x and chunk.voxel_data[local_x].size() > world_y and chunk.voxel_data[local_x][world_y].size() > local_z:
				return chunk.voxel_data[local_x][world_y][local_z]

	var biome = get_biome(wrapped_world_x, world_z)
	var noise_val = noise.get_noise_2d(wrapped_world_x, world_z)
	var ground_height = (noise_val * 10) + 32.0

	match biome:
		Biome.MOUNTAINS:
			ground_height += 20

	var density = ground_height - world_y
	if ground_height < 28 and world_y <= 28: density = float(28 - world_y)
	return density

func create_biome_texture():
	var img = Image.create(2, 4, false, Image.FORMAT_RGB8)
	var grass = Color("658d41"); var dirt = Color("5a412b"); var sand = Color("c2b280"); var water = Color("1e90ff")
	img.set_pixel(0, 0, grass); img.set_pixel(0, 1, dirt); img.set_pixel(0, 2, sand); img.set_pixel(0, 3, water)
	var snow = Color("f0f8ff"); var tundra_rock = Color("8d9296"); var desert_rock = Color("bca48b"); var mountain_rock = Color("6b6867")
	img.set_pixel(1, 0, snow); img.set_pixel(1, 1, tundra_rock); img.set_pixel(1, 2, desert_rock); img.set_pixel(1, 3, mountain_rock)
	var texture = ImageTexture.create_from_image(img)
	world_material.set_shader_parameter("texture_atlas", texture)

func get_surface_height(world_x, world_z):
	var chunk_pos = Vector2i(floori(world_x / 32.0), floori(world_z / 32.0))
	var chunk = loaded_chunks.get(chunk_pos)
	if not is_instance_valid(chunk):
		# Fallback to noise if chunk isn't loaded (shouldn't happen at spawn)
		var noise_val = noise.get_noise_2d(world_x, world_z)
		return (noise_val * 10) + 32.0

	var local_x = wrapi(world_x, 0, 32)
	var local_z = wrapi(world_z, 0, 32)

	# Scan from top to bottom to find the first solid voxel
	for y in range(chunk.CHUNK_HEIGHT - 1, 0, -1):
		if chunk.voxel_data[local_x][y][local_z] > chunk.ISO_LEVEL:
			return y
	
	return chunk.SEA_LEVEL # Default to sea level if no ground is found

func get_biome(world_x, world_z):
	var wrapped_world_x = wrapi(world_x, 0, WORLD_CIRCUMFERENCE_IN_VOXELS)
	var temp = temperature_noise.get_noise_2d(wrapped_world_x, world_z)
	var moist = moisture_noise.get_noise_2d(wrapped_world_x, world_z)

	if temp > 0.5:
		if moist > 0.5:
			return Biome.JUNGLE
		else:
			return Biome.DESERT
	elif temp < -0.5:
		if moist > 0.5:
			return Biome.SWAMP
		else:
			return Biome.TUNDRA
	else:
		if moist > 0.5:
			return Biome.FOREST
		else:
			return Biome.PLAINS

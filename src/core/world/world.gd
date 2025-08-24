# src/core/world/world.gd
@tool
extends Node3D

signal initial_chunks_generated

const ChunkScene = preload("res://src/core/world/chunk.tscn")
const VoxelMesher = preload("res://src/core/world/VoxelMesher.gd")
const MarchingCubesData = preload("res://src/core/world/marching_cubes.gd")

@export var WORLD_WIDTH_IN_CHUNKS: int = 32 : set = _set_world_width_in_chunks
@export var CHUNK_SIZE: int = 32 : set = _set_chunk_size
@export var WORLD_CIRCUMFERENCE_IN_VOXELS: int = WORLD_WIDTH_IN_CHUNKS * CHUNK_SIZE
@export var CHUNK_HEIGHT : int = 64

var is_preview = false

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
	world_material.shader = triplanar_shader

	generator = WorldGenerator.new(WORLD_CIRCUMFERENCE_IN_VOXELS, CHUNK_SIZE)
	generator.sea_level = 28.0
	generator.continent_threshold = 0.0
	generator.base_variation = 20.0
	generator.mountain_boost = 45.0
	generator.pole_influence = 0.6
	generator.pole_sink = 0.0

	create_biome_texture()

	tri_table_copy = MarchingCubesData.TRI_TABLE.duplicate(true)
	edge_table_copy = MarchingCubesData.EDGE_TABLE.duplicate(true)

	for i in range(max_threads):
		var thread = Thread.new()
		threads.append(thread)

func _process(_delta):
	if Engine.is_editor_hint() and not is_preview:
		return

	while not results_queue.is_empty():
		var result = results_queue.pop_front()
		var chunk_pos = result.chunk_position

		chunks_being_generated.erase(chunk_pos)

		if loaded_chunks.has(chunk_pos) and is_instance_valid(loaded_chunks[chunk_pos]):
			loaded_chunks[chunk_pos].apply_mesh_data(result.voxel_data, result.mesh_arrays, result.biome_data)

			if is_first_update and chunk_pos == Vector2i.ZERO:
				is_first_update = false
				initial_chunks_generated.emit()

	if not generation_queue.is_empty():
		for i in range(threads.size()):
			if not threads[i].is_started() and not generation_queue.is_empty():
				var chunk_pos = generation_queue.pop_front()

				if chunks_being_generated.has(chunk_pos) or not loaded_chunks.has(chunk_pos):
					continue

				chunks_being_generated[chunk_pos] = true
				var mesher = VoxelMesher.new(chunk_pos, generator, tri_table_copy, edge_table_copy)
				threads[i].start(Callable(self, "_thread_function").bind(mesher, threads[i], chunk_pos))

	if not is_instance_valid(player):
		return

	var player_pos = player.global_position
	var new_player_chunk_x = floor(player_pos.x / CHUNK_SIZE)
	var new_player_chunk_z = floor(player_pos.z / CHUNK_SIZE)

	new_player_chunk_x = wrapi(int(new_player_chunk_x), 0, WORLD_WIDTH_IN_CHUNKS)

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

const VIEW_DISTANCE = 3

func load_chunk(chunk_pos: Vector2i):
	if loaded_chunks.has(chunk_pos):
		return

	var chunk = ChunkScene.instantiate()
	chunk.world = self
	chunk.chunk_position = chunk_pos
	chunk.world_material = world_material

	chunk.position = Vector3(chunk_pos.x * CHUNK_SIZE, 0, chunk_pos.y * CHUNK_SIZE)

	add_child(chunk)
	loaded_chunks[chunk_pos] = chunk

	if not chunk_pos in generation_queue and not chunks_being_generated.has(chunk_pos):
		generation_queue.append(chunk_pos)

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
	var chunk = _get_chunk_at_world(world_x, world_z)
	if not is_instance_valid(chunk) or chunk.voxel_data.is_empty():
		return generator.get_height(world_x, world_z, CHUNK_HEIGHT)

	var local_x = int(world_x) % CHUNK_SIZE
	var local_z = int(world_z) % CHUNK_SIZE
	if local_x < 0: local_x += CHUNK_SIZE
	if local_z < 0: local_z += CHUNK_SIZE

	for y in range(chunk.CHUNK_HEIGHT - 1, -1, -1):
		if chunk.voxel_data[local_x][y][local_z] > chunk.ISO_LEVEL:
			return y
	return generator.sea_level

func get_biome(world_x: float, world_z: float) -> int:
	return generator.get_biome(world_x, world_z)

func _get_chunk_at_world(world_x: float, world_z: float):
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

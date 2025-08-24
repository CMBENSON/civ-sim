@tool
extends Node3D

var world

var voxel_data = []
var biome_data = []

const CHUNK_WIDTH = 32
const CHUNK_HEIGHT = 64
const CHUNK_DEPTH = 32
const SEA_LEVEL = 28
const ISO_LEVEL = 0.5

var chunk_position = Vector2i(0, 0)
var world_material: Material

var mesh_instance = MeshInstance3D.new()
var static_body = StaticBody3D.new()
var collision_shape = CollisionShape3D.new()

# Flag to prevent multiple simultaneous regenerations
var is_generating = false

func _ready():
	add_child(mesh_instance)
	add_child(static_body)
	static_body.add_child(collision_shape)

func apply_mesh_data(p_voxel_data: Array, p_mesh_arrays: Array, p_biome_data: Array):
	self.voxel_data = p_voxel_data
	self.biome_data = p_biome_data
	is_generating = false

	if p_mesh_arrays.is_empty() or p_mesh_arrays[Mesh.ARRAY_VERTEX].is_empty():
		mesh_instance.mesh = null
		collision_shape.shape = null
		return

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, p_mesh_arrays)
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = world_material
	
	# Create collision shape
	collision_shape.shape = mesh.create_trimesh_shape()

func edit_density_data(local_pos: Vector3, amount: float, affected_chunks: Dictionary):
	if voxel_data.is_empty():
		return

	var radius = 3
	var changes_made = false
	
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var offset = Vector3(x, y, z)
				if offset.length_squared() <= radius * radius:
					var edit_pos = (local_pos + offset).floor()
					
					# Check if edit is within this chunk
					if edit_pos.x >= 0 and edit_pos.x < CHUNK_WIDTH and \
					   edit_pos.y >= 0 and edit_pos.y < CHUNK_HEIGHT and \
					   edit_pos.z >= 0 and edit_pos.z < CHUNK_DEPTH:
						voxel_data[int(edit_pos.x)][int(edit_pos.y)][int(edit_pos.z)] += amount
						changes_made = true
					else:
						# Edit spills into neighboring chunk
						_handle_neighbor_edit(edit_pos, amount, affected_chunks)
	
	if changes_made:
		affected_chunks[chunk_position] = true

func _handle_neighbor_edit(edit_pos: Vector3, amount: float, affected_chunks: Dictionary):
	# Calculate which neighboring chunk this edit affects
	var neighbor_offset = Vector2i(0, 0)
	var neighbor_local_pos = edit_pos
	
	# Handle X axis wrapping
	if edit_pos.x < 0:
		neighbor_offset.x = -1
		neighbor_local_pos.x += CHUNK_WIDTH
	elif edit_pos.x >= CHUNK_WIDTH:
		neighbor_offset.x = 1
		neighbor_local_pos.x -= CHUNK_WIDTH
	
	# Handle Z axis (no wrapping)
	if edit_pos.z < 0:
		neighbor_offset.y = -1
		neighbor_local_pos.z += CHUNK_DEPTH
	elif edit_pos.z >= CHUNK_DEPTH:
		neighbor_offset.y = 1
		neighbor_local_pos.z -= CHUNK_DEPTH
	
	# Skip if Y is out of bounds
	if edit_pos.y < 0 or edit_pos.y >= CHUNK_HEIGHT:
		return
	
	# Calculate neighbor chunk position with cylindrical wrapping
	var neighbor_chunk_pos = chunk_position + neighbor_offset
	neighbor_chunk_pos.x = wrapi(neighbor_chunk_pos.x, 0, world.WORLD_WIDTH_IN_CHUNKS)
	
	# Get the neighbor chunk if it exists
	if world.loaded_chunks.has(neighbor_chunk_pos):
		var neighbor_chunk = world.loaded_chunks[neighbor_chunk_pos]
		if is_instance_valid(neighbor_chunk) and not neighbor_chunk.voxel_data.is_empty():
			# Apply the edit to the neighbor chunk's data
			var nx = int(neighbor_local_pos.x)
			var ny = int(neighbor_local_pos.y)
			var nz = int(neighbor_local_pos.z)
			
			if nx >= 0 and nx < CHUNK_WIDTH and \
			   ny >= 0 and ny < CHUNK_HEIGHT and \
			   nz >= 0 and nz < CHUNK_DEPTH:
				neighbor_chunk.voxel_data[nx][ny][nz] += amount
				affected_chunks[neighbor_chunk_pos] = true

func get_density_at(local_x: int, local_y: int, local_z: int) -> float:
	if voxel_data.is_empty():
		return 0.0
	
	if local_x >= 0 and local_x < CHUNK_WIDTH and \
	   local_y >= 0 and local_y < CHUNK_HEIGHT and \
	   local_z >= 0 and local_z < CHUNK_DEPTH:
		return voxel_data[local_x][local_y][local_z]
	
	return 0.0

func get_neighbor_density(x: int, y: int, z: int) -> float:
	# If the position is within this chunk, return the density directly
	if x >= 0 and x < CHUNK_WIDTH and \
	   y >= 0 and y < CHUNK_HEIGHT and \
	   z >= 0 and z < CHUNK_DEPTH:
		if not voxel_data.is_empty():
			return voxel_data[x][y][z]
		return 0.0
	
	# Otherwise, we need to query a neighboring chunk
	var neighbor_offset = Vector2i(0, 0)
	var neighbor_local_x = x
	var neighbor_local_z = z
	
	# Handle X axis with wrapping
	if x < 0:
		neighbor_offset.x = -1
		neighbor_local_x += CHUNK_WIDTH
	elif x >= CHUNK_WIDTH:
		neighbor_offset.x = 1
		neighbor_local_x -= CHUNK_WIDTH
	
	# Handle Z axis
	if z < 0:
		neighbor_offset.y = -1
		neighbor_local_z += CHUNK_DEPTH
	elif z >= CHUNK_DEPTH:
		neighbor_offset.y = 1
		neighbor_local_z -= CHUNK_DEPTH
	
	# Y out of bounds returns 0
	if y < 0 or y >= CHUNK_HEIGHT:
		return 0.0
	
	# Calculate neighbor chunk position with wrapping
	var neighbor_chunk_pos = chunk_position + neighbor_offset
	neighbor_chunk_pos.x = wrapi(neighbor_chunk_pos.x, 0, world.WORLD_WIDTH_IN_CHUNKS)
	
	# Get density from neighbor chunk
	if world.loaded_chunks.has(neighbor_chunk_pos):
		var neighbor_chunk = world.loaded_chunks[neighbor_chunk_pos]
		if is_instance_valid(neighbor_chunk):
			return neighbor_chunk.get_density_at(neighbor_local_x, y, neighbor_local_z)
	
	# If neighbor doesn't exist, calculate from noise
	var world_x = chunk_position.x * CHUNK_WIDTH + x
	var world_z = chunk_position.y * CHUNK_DEPTH + z
	return _calculate_density_from_noise(world_x, y, world_z)

func _calculate_density_from_noise(world_x: int, world_y: int, world_z: int) -> float:
	if not is_instance_valid(world):
		return 0.0
	
	var biome = world.get_biome(world_x, world_z)
	var noise_val = world.noise.get_noise_2d(world_x, world_z)
	var ground_height = (noise_val * 10) + (CHUNK_HEIGHT / 2.0)
	
	if biome == WorldData.Biome.MOUNTAINS:
		ground_height += 20
	
	var density = ground_height - world_y
	if ground_height < SEA_LEVEL and world_y <= SEA_LEVEL:
		density = float(SEA_LEVEL - world_y)
	
	return density

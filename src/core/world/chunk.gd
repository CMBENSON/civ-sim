# src/core/world/chunk.gd
@tool
extends Node3D

var world

var voxel_data = []
var biome_data = []

const CHUNK_WIDTH = 16
const CHUNK_HEIGHT = 256
const CHUNK_DEPTH = 16
const SEA_LEVEL = 28
const ISO_LEVEL = 0.0  # Match VoxelMesher.gd

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
		# Only print for first few chunks to avoid spam
		if chunk_position == Vector2i.ZERO or chunk_position == Vector2i(1, 0) or chunk_position == Vector2i(0, 1):
			print("Chunk ", chunk_position, ": Applying mesh data")
			print("  Voxel data size: ", p_voxel_data.size())
			print("  Mesh arrays size: ", p_mesh_arrays.size())
			print("  Biome data size: ", p_biome_data.size())
		
		self.voxel_data = p_voxel_data
		self.biome_data = p_biome_data
		is_generating = false

		if p_mesh_arrays.is_empty() or p_mesh_arrays[Mesh.ARRAY_VERTEX].is_empty():
			if chunk_position == Vector2i.ZERO or chunk_position == Vector2i(1, 0) or chunk_position == Vector2i(0, 1):
				print("Chunk ", chunk_position, ": No mesh data, clearing mesh")
			mesh_instance.mesh = null
			collision_shape.shape = null
			return

		if chunk_position == Vector2i.ZERO or chunk_position == Vector2i(1, 0) or chunk_position == Vector2i(0, 1):
			print("Chunk ", chunk_position, ": Creating mesh with ", p_mesh_arrays[Mesh.ARRAY_VERTEX].size(), " vertices")
		
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, p_mesh_arrays)

		mesh_instance.mesh = mesh
		mesh_instance.material_override = world_material
		
		# Debug material assignment
		if chunk_position == Vector2i.ZERO or chunk_position == Vector2i(1, 0) or chunk_position == Vector2i(0, 1):
			print("Chunk ", chunk_position, ": Material assigned: ", world_material)
			print("Chunk ", chunk_position, ": Material shader: ", world_material.shader if world_material else "null")
			print("Chunk ", chunk_position, ": Mesh instance material: ", mesh_instance.material_override)

		# Create collision shape
		collision_shape.shape = mesh.create_trimesh_shape()
		
		if chunk_position == Vector2i.ZERO or chunk_position == Vector2i(1, 0) or chunk_position == Vector2i(0, 1):
			print("Chunk ", chunk_position, ": Mesh applied successfully")
			print("Chunk ", chunk_position, ": Final mesh instance: ", mesh_instance)
			print("Chunk ", chunk_position, ": Final material: ", mesh_instance.material_override)

func edit_density_data(local_pos: Vector3, amount: float, affected_chunks: Dictionary):
		if voxel_data.is_empty():
			print("Chunk ", chunk_position, ": Cannot edit - no voxel data")
			return

		var radius = 3
		var changes_made = false
		print("Chunk ", chunk_position, ": Editing terrain at local pos ", local_pos, " with amount ", amount)
		print("Chunk ", chunk_position, ": Voxel data size: ", voxel_data.size(), "x", voxel_data[0].size() if voxel_data.size() > 0 else "0", "x", voxel_data[0][0].size() if voxel_data.size() > 0 and voxel_data[0].size() > 0 else "0")

		for x in range(-radius, radius + 1):
				for y in range(-radius, radius + 1):
						for z in range(-radius, radius + 1):
								var offset = Vector3(x, y, z)
								if offset.length_squared() <= radius * radius:
										var edit_pos = (local_pos + offset).floor()

										if edit_pos.x >= 0 and edit_pos.x < CHUNK_WIDTH and \
										   edit_pos.y >= 0 and edit_pos.y < CHUNK_HEIGHT and \
										   edit_pos.z >= 0 and edit_pos.z < CHUNK_DEPTH:
												var old_value = voxel_data[int(edit_pos.x)][int(edit_pos.y)][int(edit_pos.z)]
												voxel_data[int(edit_pos.x)][int(edit_pos.y)][int(edit_pos.z)] += amount
												var new_value = voxel_data[int(edit_pos.x)][int(edit_pos.y)][int(edit_pos.z)]
												if abs(amount) > 0.1:  # Only print for significant changes
													print("Chunk ", chunk_position, ": Changed voxel at (", edit_pos.x, ", ", edit_pos.y, ", ", edit_pos.z, ") from ", old_value, " to ", new_value)
												changes_made = true
										else:
												_handle_neighbor_edit(edit_pos, amount, affected_chunks)

		if changes_made:
				affected_chunks[chunk_position] = true
				print("Chunk ", chunk_position, ": Made changes, affected chunks: ", affected_chunks.keys())
				print("Chunk ", chunk_position, ": Voxel data modified - will need re-meshing")
		else:
			print("Chunk ", chunk_position, ": No changes made")

func _handle_neighbor_edit(edit_pos: Vector3, amount: float, affected_chunks: Dictionary):
		var neighbor_offset = Vector2i(0, 0)
		var neighbor_local_pos = edit_pos

		if edit_pos.x < 0:
				neighbor_offset.x = -1
				neighbor_local_pos.x += CHUNK_WIDTH
		elif edit_pos.x >= CHUNK_WIDTH:
				neighbor_offset.x = 1
				neighbor_local_pos.x -= CHUNK_WIDTH

		if edit_pos.z < 0:
				neighbor_offset.y = -1
				neighbor_local_pos.z += CHUNK_DEPTH
		elif edit_pos.z >= CHUNK_DEPTH:
				neighbor_offset.y = 1
				neighbor_local_pos.z -= CHUNK_DEPTH

		if edit_pos.y < 0 or edit_pos.y >= CHUNK_HEIGHT:
				return

		var neighbor_chunk_pos = chunk_position + neighbor_offset
		neighbor_chunk_pos.x = wrapi(neighbor_chunk_pos.x, 0, world.WORLD_WIDTH_IN_CHUNKS)

		if world.loaded_chunks.has(neighbor_chunk_pos):
				var neighbor_chunk = world.loaded_chunks[neighbor_chunk_pos]
				if is_instance_valid(neighbor_chunk) and not neighbor_chunk.voxel_data.is_empty():
						var nx = int(neighbor_local_pos.x)
						var ny = int(neighbor_local_pos.y)
						var nz = int(neighbor_local_pos.z)
						if nx >= 0 and nx < CHUNK_WIDTH and ny >= 0 and ny < CHUNK_HEIGHT and nz >= 0 and nz < CHUNK_DEPTH:
								neighbor_chunk.voxel_data[nx][ny][nz] += amount
								affected_chunks[neighbor_chunk_pos] = true

func get_density_at(local_x: int, local_y: int, local_z: int) -> float:
		if voxel_data.is_empty():
				return 0.0
		if local_x >= 0 and local_x < CHUNK_WIDTH and local_y >= 0 and local_y < CHUNK_HEIGHT and local_z >= 0 and local_z < CHUNK_DEPTH:
				return voxel_data[local_x][local_y][local_z]
		return 0.0

func get_neighbor_density(x: int, y: int, z: int) -> float:
		if x >= 0 and x < CHUNK_WIDTH and y >= 0 and y < CHUNK_HEIGHT and z >= 0 and z < CHUNK_DEPTH:
				if not voxel_data.is_empty():
						return voxel_data[x][y][z]
				return 0.0

		var neighbor_offset = Vector2i(0, 0)
		var neighbor_local_x = x
		var neighbor_local_z = z

		if x < 0:
				neighbor_offset.x = -1
				neighbor_local_x += CHUNK_WIDTH
		elif x >= CHUNK_WIDTH:
				neighbor_offset.x = 1
				neighbor_local_x -= CHUNK_WIDTH

		if z < 0:
				neighbor_offset.y = -1
				neighbor_local_z += CHUNK_DEPTH
		elif z >= CHUNK_DEPTH:
				neighbor_offset.y = 1
				neighbor_local_z -= CHUNK_DEPTH

		if y < 0 or y >= CHUNK_HEIGHT:
				return 0.0

		var neighbor_chunk_pos = chunk_position + neighbor_offset
		neighbor_chunk_pos.x = wrapi(neighbor_chunk_pos.x, 0, world.WORLD_WIDTH_IN_CHUNKS)

		if world.loaded_chunks.has(neighbor_chunk_pos):
				var neighbor_chunk = world.loaded_chunks[neighbor_chunk_pos]
				if is_instance_valid(neighbor_chunk):
						return neighbor_chunk.get_density_at(neighbor_local_x, y, neighbor_local_z)

		# Fallback to generator if neighbor chunk not present
		var world_x = chunk_position.x * CHUNK_WIDTH + x
		var world_z = chunk_position.y * CHUNK_DEPTH + z
		return _calculate_density_from_noise(world_x, y, world_z)

func _calculate_density_from_noise(world_x: int, world_y: int, world_z: int) -> float:
		if not is_instance_valid(world) or world.generator == null:
				return 0.0
		var gh = world.generator.get_height(world_x, world_z, CHUNK_HEIGHT)
		var density = gh - float(world_y)
		if world.generator.is_ocean(world_x, world_z) and world_y <= int(world.generator.sea_level):
				density = float(world.generator.sea_level - world_y)
		return density

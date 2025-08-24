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

func _ready():
	add_child(mesh_instance)
	add_child(static_body)
	static_body.add_child(collision_shape)

func apply_mesh_data(p_voxel_data: Array, p_mesh_arrays: Array, p_biome_data: Array):
	self.voxel_data = p_voxel_data
	self.biome_data = p_biome_data

	if p_mesh_arrays[Mesh.ARRAY_VERTEX].is_empty():
		mesh_instance.mesh = null
		collision_shape.shape = null
		return

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, p_mesh_arrays)
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = world_material
	collision_shape.shape = mesh.create_trimesh_shape()

# --- FIX: Re-implement terrain editing ---
func edit_density_data(local_pos: Vector3, amount: float):
	if voxel_data.is_empty(): return

	var radius = 3
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var offset = Vector3(x, y, z)
				if offset.length_squared() <= radius * radius:
					var edit_pos = (local_pos + offset).floor()
					
					if edit_pos.x >= 0 and edit_pos.x < CHUNK_WIDTH and \
					   edit_pos.y >= 0 and edit_pos.y < CHUNK_HEIGHT and \
					   edit_pos.z >= 0 and edit_pos.z < CHUNK_DEPTH:
						voxel_data[int(edit_pos.x)][int(edit_pos.y)][int(edit_pos.z)] += amount

	# After editing, tell the world to regenerate this chunk and its neighbors
	world.update_chunk_and_neighbors(chunk_position)

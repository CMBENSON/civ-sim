# res://src/core/world/chunk.gd
extends Node3D

# --- NEW: Added MOUNTAIN to the Biome enum ---
enum Biome { TUNDRA, PLAINS, DESERT, MOUNTAIN }

const CHUNK_WIDTH = 32
const CHUNK_HEIGHT = 64
const CHUNK_DEPTH = 32
const SEA_LEVEL = 28
const ISO_LEVEL = 0.5
# --- NEW: Define the height where mountains start ---
const MOUNTAIN_LEVEL = 45

var chunk_position = Vector2i(0, 0)
var noise: FastNoiseLite
var temperature_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var world_material: Material

var mesh_instance = MeshInstance3D.new()
var static_body = StaticBody3D.new()
var collision_shape = CollisionShape3D.new()

const MarchingCubes = preload("res://src/core/world/marching_cubes.gd")

var voxel_data = []
var biome_data = []

func _ready():
	add_child(mesh_instance)
	add_child(static_body)
	static_body.add_child(collision_shape)

func generate_initial_data():
	voxel_data.resize(CHUNK_WIDTH)
	biome_data.resize(CHUNK_WIDTH)
	for x in range(CHUNK_WIDTH):
		voxel_data[x] = []
		voxel_data[x].resize(CHUNK_HEIGHT)
		biome_data[x] = []
		biome_data[x].resize(CHUNK_DEPTH)
		for y in range(CHUNK_HEIGHT):
			voxel_data[x][y] = []
			voxel_data[x][y].resize(CHUNK_DEPTH)

	for x in range(CHUNK_WIDTH):
		for z in range(CHUNK_DEPTH):
			var world_x = x + chunk_position.x * CHUNK_WIDTH
			var world_z = z + chunk_position.y * CHUNK_DEPTH
			
			var temp = temperature_noise.get_noise_2d(world_x, world_z)
			var moisture = moisture_noise.get_noise_2d(world_x, world_z)
			var noise_val = noise.get_noise_2d(world_x, world_z)
			var ground_height = (noise_val * 10) + (CHUNK_HEIGHT / 2.0)
			
			# --- NEW: Pass ground_height to the biome function ---
			biome_data[x][z] = get_biome(temp, moisture, ground_height)
			
			for y in range(CHUNK_HEIGHT):
				var density = ground_height - y
				if ground_height < SEA_LEVEL and y <= SEA_LEVEL:
					density = float(SEA_LEVEL - y)
				voxel_data[x][y][z] = density

# --- NEW: This function now considers height ---
func get_biome(temp: float, moisture: float, height: float) -> Biome:
	if height > MOUNTAIN_LEVEL:
		return Biome.MOUNTAIN
	
	# We make Tundra and Desert require more extreme values, making Plains more common.
	if temp < -0.5:
		return Biome.TUNDRA
	elif temp > 0.6 and moisture < -0.4:
		return Biome.DESERT
	else:
		return Biome.PLAINS

func edit_density_data(local_pos: Vector3, amount: float):
	var radius = 3
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var offset = Vector3(x, y, z)
				if offset.length() <= radius:
					var edit_pos = (local_pos + offset).floor()
					if edit_pos.x >= 0 and edit_pos.x < CHUNK_WIDTH and \
					   edit_pos.y >= 0 and edit_pos.y < CHUNK_HEIGHT and \
					   edit_pos.z >= 0 and edit_pos.z < CHUNK_DEPTH:
						voxel_data[int(edit_pos.x)][int(edit_pos.y)][int(edit_pos.z)] += amount

func generate_mesh(padded_voxel_data):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x in range(CHUNK_WIDTH):
		for y in range(CHUNK_HEIGHT):
			for z in range(CHUNK_DEPTH):
				var biome = biome_data[x][z]
				# --- NEW: Set a new vertex color for mountains ---
				# We'll use the Alpha channel (A) for this.
				match biome:
					Biome.TUNDRA:
						st.set_color(Color(1.0, 0.0, 0.0)) # R
					Biome.PLAINS:
						st.set_color(Color(0.0, 1.0, 0.0)) # G
					Biome.DESERT:
						st.set_color(Color(0.0, 0.0, 1.0)) # B
					Biome.MOUNTAIN:
						st.set_color(Color(0.0, 0.0, 0.0, 1.0)) # A
				
				var cube_corners = [
					padded_voxel_data[x][y][z+1], padded_voxel_data[x+1][y][z+1],
					padded_voxel_data[x+1][y][z], padded_voxel_data[x][y][z],
					padded_voxel_data[x][y+1][z+1], padded_voxel_data[x+1][y+1][z+1],
					padded_voxel_data[x+1][y+1][z], padded_voxel_data[x][y+1][z]
				]

				var cube_index = 0
				if cube_corners[0] > ISO_LEVEL: cube_index |= 1
				if cube_corners[1] > ISO_LEVEL: cube_index |= 2
				if cube_corners[2] > ISO_LEVEL: cube_index |= 4
				if cube_corners[3] > ISO_LEVEL: cube_index |= 8
				if cube_corners[4] > ISO_LEVEL: cube_index |= 16
				if cube_corners[5] > ISO_LEVEL: cube_index |= 32
				if cube_corners[6] > ISO_LEVEL: cube_index |= 64
				if cube_corners[7] > ISO_LEVEL: cube_index |= 128

				var edges = MarchingCubes.TRI_TABLE[cube_index]

				for i in range(0, 15, 3):
					if edges[i] == -1: break
					
					var v1_index = MarchingCubes.EDGE_TABLE[edges[i]][0]
					var v2_index = MarchingCubes.EDGE_TABLE[edges[i]][1]
					var v1 = get_vertex_pos(x, y, z, v1_index)
					var v2 = get_vertex_pos(x, y, z, v2_index)
					var vert1 = v1.lerp(v2, (ISO_LEVEL - cube_corners[v1_index]) / (cube_corners[v2_index] - cube_corners[v1_index]))

					v1_index = MarchingCubes.EDGE_TABLE[edges[i+1]][0]
					v2_index = MarchingCubes.EDGE_TABLE[edges[i+1]][1]
					v1 = get_vertex_pos(x, y, z, v1_index)
					v2 = get_vertex_pos(x, y, z, v2_index)
					var vert2 = v1.lerp(v2, (ISO_LEVEL - cube_corners[v1_index]) / (cube_corners[v2_index] - cube_corners[v1_index]))

					v1_index = MarchingCubes.EDGE_TABLE[edges[i+2]][0]
					v2_index = MarchingCubes.EDGE_TABLE[edges[i+2]][1]
					v1 = get_vertex_pos(x, y, z, v1_index)
					v2 = get_vertex_pos(x, y, z, v2_index)
					var vert3 = v1.lerp(v2, (ISO_LEVEL - cube_corners[v1_index]) / (cube_corners[v2_index] - cube_corners[v1_index]))
					
					st.add_vertex(vert1); st.add_vertex(vert2); st.add_vertex(vert3)

	st.generate_normals()
	var mesh = st.commit()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = world_material
	collision_shape.shape = mesh.create_trimesh_shape()

func get_vertex_pos(x, y, z, index):
	match index:
		0:
			return Vector3(x, y, z + 1)
		1:
			return Vector3(x + 1, y, z + 1)
		2:
			return Vector3(x + 1, y, z)
		3:
			return Vector3(x, y, z)
		4:
			return Vector3(x, y + 1, z + 1)
		5:
			return Vector3(x + 1, y + 1, z + 1)
		6:
			return Vector3(x + 1, y + 1, z)
		7:
			return Vector3(x, y + 1, z)
	return Vector3.ZERO

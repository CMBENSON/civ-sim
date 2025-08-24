# src/core/world/VoxelMesher.gd
extends RefCounted

var chunk_position: Vector2i
var generator: RefCounted
var TRI_TABLE: Array
var EDGE_TABLE: Array

const CHUNK_WIDTH  = 32
const CHUNK_HEIGHT = 64
const CHUNK_DEPTH  = 32
const ISO_LEVEL    = 0.5

var mesh_arrays: Array
var biome_data: Array
var voxel_data: Array

func _init(p_chunk_pos, p_generator, p_tri_table, p_edge_table):
		chunk_position = p_chunk_pos
		generator = p_generator
		TRI_TABLE = p_tri_table
		EDGE_TABLE = p_edge_table

func run():
		voxel_data = _generate_voxel_data()
		var padded_data = _get_padded_data(voxel_data)
		_generate_mesh(padded_data)
		return {
				"chunk_position": chunk_position,
				"voxel_data": voxel_data,
				"mesh_arrays": mesh_arrays,
				"biome_data": biome_data
		}

func _generate_voxel_data():
		var data = []
		biome_data = []
		data.resize(CHUNK_WIDTH)
		biome_data.resize(CHUNK_WIDTH)
		for x in range(CHUNK_WIDTH):
				data[x] = []
				data[x].resize(CHUNK_HEIGHT)
				biome_data[x] = []
				biome_data[x].resize(CHUNK_DEPTH)
				for y in range(CHUNK_HEIGHT):
						data[x][y] = []
						data[x][y].resize(CHUNK_DEPTH)

		for x in range(CHUNK_WIDTH):
				for z in range(CHUNK_DEPTH):
						var world_x = chunk_position.x * CHUNK_WIDTH + x
						var world_z = chunk_position.y * CHUNK_DEPTH + z
						var biome = generator.get_biome(world_x, world_z)
						biome_data[x][z] = biome

						var ground_h = generator.get_height(world_x, world_z, CHUNK_HEIGHT)
						for y in range(CHUNK_HEIGHT):
								var density = ground_h - y
								# Fill ocean water to sea level (solid for now; later swap to fluid)
								if generator.is_ocean(world_x, world_z) and y <= int(generator.sea_level):
										density = float(generator.sea_level - y)
								data[x][y][z] = density

		# Optional: simple “trees” in forests (kept from your version)
		# (You can port your previous tree logic here if desired.)

		return data

func _get_padded_data(p_voxel_data):
		var size = 33
		var height = 65
		var padded = []
		padded.resize(size)
		for x in range(size):
				padded[x] = []
				padded[x].resize(height)
				for y in range(height):
						padded[x][y] = []
						padded[x][y].resize(size)

		for x in range(size):
				for y in range(height):
						for z in range(size):
								if x < CHUNK_WIDTH and y < CHUNK_HEIGHT and z < CHUNK_DEPTH:
										padded[x][y][z] = p_voxel_data[x][y][z]
								else:
										var world_x = chunk_position.x * CHUNK_WIDTH + x
										var world_y = y
										var world_z = chunk_position.y * CHUNK_DEPTH + z
										var gh = generator.get_height(world_x, world_z, CHUNK_HEIGHT)
										var density = gh - world_y
										if generator.is_ocean(world_x, world_z) and world_y <= int(generator.sea_level):
												density = float(generator.sea_level - world_y)
										padded[x][y][z] = density
		return padded

func _generate_mesh(padded_voxel_data):
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for x in range(CHUNK_WIDTH):
				for y in range(CHUNK_HEIGHT):
						for z in range(CHUNK_DEPTH):
								# Simple color by biome (you’re already using a triplanar shader,
								# so these vertex colors can also feed into your material if needed)
								var biome = biome_data[x][z]
								match biome:
										WorldData.Biome.TUNDRA:
												st.set_color(Color(1, 0, 0, 0))
										WorldData.Biome.PLAINS:
												st.set_color(Color(0, 1, 0, 0))
										WorldData.Biome.DESERT:
												st.set_color(Color(0, 0, 1, 0))
										WorldData.Biome.MOUNTAINS:
												st.set_color(Color(0, 0, 0, 1))
										WorldData.Biome.OCEAN:
												st.set_color(Color(0, 0.5, 1, 0))
										_:
												st.set_color(Color(0, 1, 0, 0))

								# Marching cubes sampling
								var cube_corners = [
										padded_voxel_data[x][y][z+1],
										padded_voxel_data[x+1][y][z+1],
										padded_voxel_data[x+1][y][z],
										padded_voxel_data[x][y][z],
										padded_voxel_data[x][y+1][z+1],
										padded_voxel_data[x+1][y+1][z+1],
										padded_voxel_data[x+1][y+1][z],
										padded_voxel_data[x][y+1][z]
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

								var tri_indices = TRI_TABLE[cube_index]
								if tri_indices[0] == -1: continue

								var vertices = []
								for i in range(0, 16, 3):
										if tri_indices[i] == -1:
												break
										var a = _interpolate_edge(x, y, z, tri_indices[i+0], padded_voxel_data)
										var b = _interpolate_edge(x, y, z, tri_indices[i+1], padded_voxel_data)
										var c = _interpolate_edge(x, y, z, tri_indices[i+2], padded_voxel_data)
										st.add_vertex(a)
										st.add_vertex(b)
										st.add_vertex(c)

		var mesh = st.commit()
		mesh_arrays = mesh.surface_get_arrays(0)

func _interpolate_edge(x, y, z, edge_index, data):
		var edges = EDGE_TABLE
		var e = edges[edge_index]
		var a = _corner_pos(x, y, z, e[0])
		var b = _corner_pos(x, y, z, e[1])
		# Linear interpolation at ISO level
		var da = data[a.x][a.y][a.z]
		var db = data[b.x][b.y][b.z]
		var t = (ISO_LEVEL - da) / max(db - da, 0.00001)
		return Vector3(a.x, a.y, a.z).lerp(Vector3(b.x, b.y, b.z), t)

func _corner_pos(x, y, z, i):
		# Corner order matches your TRI/EDGE tables
		match i:
				0:  return Vector3(x,   y,   z+1)
				1:  return Vector3(x+1, y,   z+1)
				2:  return Vector3(x+1, y,   z)
				3:  return Vector3(x,   y,   z)
				4:  return Vector3(x,   y+1, z+1)
				5:  return Vector3(x+1, y+1, z+1)
				6:  return Vector3(x+1, y+1, z)
				7:  return Vector3(x,   y+1, z)
				_:  return Vector3(x,   y,   z)

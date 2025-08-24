extends RefCounted

var chunk_position: Vector2i
var noise: FastNoiseLite
var temperature_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var TRI_TABLE: Array
var EDGE_TABLE: Array

const CHUNK_WIDTH = 32
const CHUNK_HEIGHT = 64
const CHUNK_DEPTH = 32
const SEA_LEVEL = 28
const ISO_LEVEL = 0.5

var mesh_arrays: Array
var biome_data: Array
var voxel_data: Array

func _init(p_chunk_pos, p_noise, p_temp_noise, p_moisture_noise, p_tri_table, p_edge_table):
	self.chunk_position = p_chunk_pos
	self.noise = p_noise
	self.temperature_noise = p_temp_noise
	self.moisture_noise = p_moisture_noise
	self.TRI_TABLE = p_tri_table
	self.EDGE_TABLE = p_edge_table

func run():
	self.voxel_data = _generate_voxel_data()
	# --- MODIFICATION: Pass our own voxel data to the padding function ---
	var padded_data = _get_padded_data(self.voxel_data)
	_generate_mesh(padded_data)
	return self

func _generate_voxel_data():
	var data = []; biome_data = []
	data.resize(CHUNK_WIDTH); biome_data.resize(CHUNK_WIDTH)
	for x in range(CHUNK_WIDTH):
		data[x] = []; data[x].resize(CHUNK_HEIGHT)
		biome_data[x] = []; biome_data[x].resize(CHUNK_DEPTH)
		for y in range(CHUNK_HEIGHT):
			data[x][y] = []; data[x][y].resize(CHUNK_DEPTH)

	for x in range(CHUNK_WIDTH):
		for z in range(CHUNK_DEPTH):
			var world_x = chunk_position.x * CHUNK_WIDTH + x
			var world_z = chunk_position.y * CHUNK_DEPTH + z
			var current_biome = _get_biome_at(world_x, world_z)
			biome_data[x][z] = current_biome
			var noise_val = noise.get_noise_2d(world_x, world_z)
			var ground_height = (noise_val * 10) + (CHUNK_HEIGHT / 2.0)
			if current_biome == WorldData.Biome.MOUNTAINS: ground_height += 20
			for y in range(CHUNK_HEIGHT):
				var density = ground_height - y
				if ground_height < SEA_LEVEL and y <= SEA_LEVEL: density = float(SEA_LEVEL - y)
				data[x][y][z] = density
			if current_biome == WorldData.Biome.FOREST:
				var tree_noise = noise.get_noise_2d(world_x + 1000, world_z + 1000)
				if tree_noise > 0.7:
					var tree_height = 4 + randi() % 4
					for i in range(tree_height):
						if ground_height + i < CHUNK_HEIGHT:
							data[x][int(ground_height) + i][z] = 1.0
	return data
	
func _get_padded_data(p_voxel_data):
	var padded_data = []; var size = 33; var height = 65
	padded_data.resize(size); for x in range(size):
		padded_data[x] = []; padded_data[x].resize(height)
		for y in range(height): padded_data[x][y] = []; padded_data[x][y].resize(size)
	
	for x in range(size):
		for y in range(height):
			for z in range(size):
				# If the coordinate is inside our main chunk data, just use it.
				if x < CHUNK_WIDTH and y < CHUNK_HEIGHT and z < CHUNK_DEPTH:
					padded_data[x][y][z] = p_voxel_data[x][y][z]
				# Otherwise, we are in the "padding" and need to calculate the density.
				else:
					var world_x = chunk_position.x * CHUNK_WIDTH + x
					var world_y = y
					var world_z = chunk_position.y * CHUNK_DEPTH + z
					padded_data[x][y][z] = _get_voxel_density_at(world_x, world_y, world_z)
	return padded_data

# --- NEW FUNCTION: Calculates density for any world coordinate ---
func _get_voxel_density_at(world_x, world_y, world_z):
	var biome = _get_biome_at(world_x, world_z)
	var noise_val = noise.get_noise_2d(world_x, world_z)
	var ground_height = (noise_val * 10) + (CHUNK_HEIGHT / 2.0)

	if biome == WorldData.Biome.MOUNTAINS:
		ground_height += 20

	var density = ground_height - world_y
	if ground_height < SEA_LEVEL and world_y <= SEA_LEVEL:
		density = float(SEA_LEVEL - world_y)
	return density

func _generate_mesh(padded_voxel_data):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in range(CHUNK_WIDTH):
		for y in range(CHUNK_HEIGHT):
			for z in range(CHUNK_DEPTH):
				# ... (match biome and set_color logic is the same) ...
				var biome = biome_data[x][z]
				match biome:
					WorldData.Biome.TUNDRA: st.set_color(Color(1,0,0,0))
					WorldData.Biome.PLAINS: st.set_color(Color(0,1,0,0))
					WorldData.Biome.DESERT: st.set_color(Color(0,0,1,0))
					WorldData.Biome.MOUNTAINS: st.set_color(Color(0,0,0,1))
					_: st.set_color(Color(0,1,0,0))

				var cube_corners=[padded_voxel_data[x][y][z+1],padded_voxel_data[x+1][y][z+1],padded_voxel_data[x+1][y][z],padded_voxel_data[x][y][z],padded_voxel_data[x][y+1][z+1],padded_voxel_data[x+1][y+1][z+1],padded_voxel_data[x+1][y+1][z],padded_voxel_data[x][y+1][z]]
				var cube_index=0
				if cube_corners[0]>ISO_LEVEL:cube_index|=1
				if cube_corners[1]>ISO_LEVEL:cube_index|=2
				if cube_corners[2]>ISO_LEVEL:cube_index|=4
				if cube_corners[3]>ISO_LEVEL:cube_index|=8
				if cube_corners[4]>ISO_LEVEL:cube_index|=16
				if cube_corners[5]>ISO_LEVEL:cube_index|=32
				if cube_corners[6]>ISO_LEVEL:cube_index|=64
				if cube_corners[7]>ISO_LEVEL:cube_index|=128

				# --- FIX: Use the local table copies ---
				var edges = TRI_TABLE[cube_index]

				for i in range(0, 15, 3):
					if edges[i] == -1: break
					
					var v1_index = EDGE_TABLE[edges[i]][0]
					var v2_index = EDGE_TABLE[edges[i]][1]
					var p1 = get_vertex_pos(x, y, z, v1_index)
					var p2 = get_vertex_pos(x, y, z, v2_index)
					var vert1 = p1.lerp(p2, (ISO_LEVEL - cube_corners[v1_index]) / (cube_corners[v2_index] - cube_corners[v1_index]))

					v1_index = EDGE_TABLE[edges[i+1]][0]
					v2_index = EDGE_TABLE[edges[i+1]][1]
					p1 = get_vertex_pos(x, y, z, v1_index)
					p2 = get_vertex_pos(x, y, z, v2_index)
					var vert2 = p1.lerp(p2, (ISO_LEVEL - cube_corners[v1_index]) / (cube_corners[v2_index] - cube_corners[v1_index]))

					v1_index = EDGE_TABLE[edges[i+2]][0]
					v2_index = EDGE_TABLE[edges[i+2]][1]
					p1 = get_vertex_pos(x, y, z, v1_index)
					p2 = get_vertex_pos(x, y, z, v2_index)
					var vert3 = p1.lerp(p2, (ISO_LEVEL - cube_corners[v1_index]) / (cube_corners[v2_index] - cube_corners[v1_index]))
					
					st.add_vertex(vert1); st.add_vertex(vert2); st.add_vertex(vert3)
	
	st.generate_normals()
	mesh_arrays = st.commit_to_arrays()

func get_vertex_pos(x,y,z,index):
	match index:
		0:return Vector3(x,y,z+1)
		1:return Vector3(x+1,y,z+1)
		2:return Vector3(x+1,y,z)
		3:return Vector3(x,y,z)
		4:return Vector3(x,y+1,z+1)
		5:return Vector3(x+1,y+1,z+1)
		6:return Vector3(x+1,y+1,z)
		7:return Vector3(x,y+1,z)
	return Vector3.ZERO

func _get_biome_at(world_x, world_z):
	var temp=temperature_noise.get_noise_2d(world_x, world_z)
	var moist=moisture_noise.get_noise_2d(world_x, world_z)
	if temp > 0.5: return WorldData.Biome.DESERT if moist < 0.5 else WorldData.Biome.JUNGLE
	elif temp < -0.5: return WorldData.Biome.TUNDRA if moist < 0.5 else WorldData.Biome.SWAMP
	else: return WorldData.Biome.PLAINS if moist < 0.5 else WorldData.Biome.FOREST

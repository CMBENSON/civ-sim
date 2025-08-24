# res://src/core/world/VoxelMesher.gd
extends Object

const CHUNK_WIDTH = 32
const CHUNK_HEIGHT = 64
const ISO_LEVEL = 0.5
const MarchingCubes = preload("res://src/core/world/marching_cubes.gd")

func generate_mesh_data(packed_data_bundle):
	var padded_voxel_data = unpack_data(packed_data_bundle.density_data)
	var biome_data = packed_data_bundle.biome_data

	if padded_voxel_data.is_empty():
		return {}

	var visual_mesh_arrays = generate_visual_mesh(padded_voxel_data, biome_data)
	var collision_mesh_arrays = generate_collision_mesh(padded_voxel_data)
	
	return {
		"visual": visual_mesh_arrays,
		"collision": collision_mesh_arrays
	}

func unpack_data(byte_array: PackedByteArray) -> Array:
	var arr = []
	var size = 33
	var height = 65
	arr.resize(size)
	var offset = 0
	for x in range(size):
		arr[x] = []
		arr[x].resize(height)
		for y in range(height):
			arr[x][y] = []
			arr[x][y].resize(size)
			for z in range(size):
				arr[x][y][z] = byte_array.decode_float(offset)
				offset += 4
	return arr

func generate_visual_mesh(padded_voxel_data, biome_data):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x in range(CHUNK_WIDTH):
		for y in range(CHUNK_HEIGHT):
			for z in range(CHUNK_WIDTH):
				var biome = biome_data[x][z]
				match biome:
					0: st.set_color(Color.RED)
					1: st.set_color(Color.GREEN)
					2: st.set_color(Color.BLUE)
				
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
					
					var v1_idx = MarchingCubes.EDGE_TABLE[edges[i]][0]
					var v2_idx = MarchingCubes.EDGE_TABLE[edges[i]][1]
					var v1 = get_vertex_pos(x, y, z, v1_idx)
					var v2 = get_vertex_pos(x, y, z, v2_idx)
					var vert1 = v1.lerp(v2, (ISO_LEVEL - cube_corners[v1_idx]) / (cube_corners[v2_idx] - cube_corners[v1_idx]))

					v1_idx = MarchingCubes.EDGE_TABLE[edges[i+1]][0]
					v2_idx = MarchingCubes.EDGE_TABLE[edges[i+1]][1]
					v1 = get_vertex_pos(x, y, z, v1_idx)
					v2 = get_vertex_pos(x, y, z, v2_idx)
					var vert2 = v1.lerp(v2, (ISO_LEVEL - cube_corners[v1_idx]) / (cube_corners[v2_idx] - cube_corners[v1_idx]))

					v1_idx = MarchingCubes.EDGE_TABLE[edges[i+2]][0]
					v2_idx = MarchingCubes.EDGE_TABLE[edges[i+2]][1]
					v1 = get_vertex_pos(x, y, z, v1_idx)
					v2 = get_vertex_pos(x, y, z, v2_idx)
					var vert3 = v1.lerp(v2, (ISO_LEVEL - cube_corners[v1_idx]) / (cube_corners[v2_idx] - cube_corners[v1_idx]))
					
					st.add_vertex(vert1); st.add_vertex(vert2); st.add_vertex(vert3)

	st.generate_normals()
	return st.commit_to_arrays()

func generate_collision_mesh(padded_voxel_data):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x in range(CHUNK_WIDTH):
		for y in range(CHUNK_HEIGHT):
			for z in range(CHUNK_WIDTH):
				if padded_voxel_data[x][y][z] <= ISO_LEVEL:
					continue
				if y + 1 < 65 and padded_voxel_data[x][y+1][z] <= ISO_LEVEL:
					add_blocky_face(st, Vector3(x,y,z), Vector3.UP)
				if y > 0 and padded_voxel_data[x][y-1][z] <= ISO_LEVEL:
					add_blocky_face(st, Vector3(x,y,z), Vector3.DOWN)
				if x + 1 < 33 and padded_voxel_data[x+1][y][z] <= ISO_LEVEL:
					add_blocky_face(st, Vector3(x,y,z), Vector3.RIGHT)
				if x > 0 and padded_voxel_data[x-1][y][z] <= ISO_LEVEL:
					add_blocky_face(st, Vector3(x,y,z), Vector3.LEFT)
				if z + 1 < 33 and padded_voxel_data[x][y][z+1] <= ISO_LEVEL:
					add_blocky_face(st, Vector3(x,y,z), Vector3.FORWARD)
				if z > 0 and padded_voxel_data[x][y][z-1] <= ISO_LEVEL:
					add_blocky_face(st, Vector3(x,y,z), Vector3.BACK)
	
	var collision_mesh = st.commit()
	return collision_mesh

func add_blocky_face(st: SurfaceTool, pos: Vector3, direction: Vector3):
	var v000=pos+Vector3(0,0,0);var v100=pos+Vector3(1,0,0);var v010=pos+Vector3(0,1,0);var v110=pos+Vector3(1,1,0)
	var v001=pos+Vector3(0,0,1);var v101=pos+Vector3(1,0,1);var v011=pos+Vector3(0,1,1);var v111=pos+Vector3(1,1,1)
	match direction:
		Vector3.UP: st.add_vertex(v011);st.add_vertex(v110);st.add_vertex(v111);st.add_vertex(v011);st.add_vertex(v010);st.add_vertex(v110)
		Vector3.DOWN: st.add_vertex(v000);st.add_vertex(v101);st.add_vertex(v100);st.add_vertex(v000);st.add_vertex(v001);st.add_vertex(v101)
		Vector3.RIGHT: st.add_vertex(v100);st.add_vertex(v111);st.add_vertex(v110);st.add_vertex(v100);st.add_vertex(v101);st.add_vertex(v111)
		Vector3.LEFT: st.add_vertex(v001);st.add_vertex(v010);st.add_vertex(v011);st.add_vertex(v001);st.add_vertex(v000);st.add_vertex(v010)
		Vector3.FORWARD: st.add_vertex(v001);st.add_vertex(v111);st.add_vertex(v101);st.add_vertex(v001);st.add_vertex(v011);st.add_vertex(v111)
		Vector3.BACK: st.add_vertex(v000);st.add_vertex(v110);st.add_vertex(v100);st.add_vertex(v000);st.add_vertex(v010);st.add_vertex(v110)

func get_vertex_pos(x, y, z, index):
	match index:
		0: return Vector3(x, y, z + 1)
		1: return Vector3(x + 1, y, z + 1)
		2: return Vector3(x + 1, y, z)
		3: return Vector3(x, y, z)
		4: return Vector3(x, y + 1, z + 1)
		5: return Vector3(x + 1, y + 1, z + 1)
		6: return Vector3(x + 1, y + 1, z)
		7: return Vector3(x, y + 1, z)
	return Vector3.ZERO

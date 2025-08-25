# src/core/world/VoxelMesher.gd
extends RefCounted

var chunk_position: Vector2i
var generator: RefCounted
var TRI_TABLE: Array
var EDGE_TABLE: Array

const CHUNK_WIDTH = 16
const CHUNK_HEIGHT = 256
const CHUNK_DEPTH = 16
const ISO_LEVEL = 0.0

var mesh_arrays: Array
var biome_data: Array
var voxel_data: Array

# Debug and performance tracking
var debug_enabled: bool = false
var generation_start_time: int = 0
var vertex_count: int = 0
var triangle_count: int = 0

# Memory management
var _cached_colors: Dictionary = {}

func _init(p_chunk_pos, p_generator, p_tri_table, p_edge_table):
	if not p_chunk_pos or not p_generator or not p_tri_table or not p_edge_table:
		print("VoxelMesher: ERROR - Invalid parameters provided")
		return
	
	chunk_position = p_chunk_pos
	generator = p_generator
	TRI_TABLE = p_tri_table
	EDGE_TABLE = p_edge_table
	
	# Only enable debug for origin chunk or if generator has verbose logging
	debug_enabled = (chunk_position == Vector2i.ZERO and generator.has_method("verbose_logging") and generator.verbose_logging)
	
	# Pre-cache biome colors for performance
	_precache_biome_colors()
	generation_start_time = Time.get_ticks_msec()

# Helper functions for marching cubes
func _corner_pos(x, y, z, i):
	match i:
		0: return Vector3(x, y, z+1)
		1: return Vector3(x+1, y, z+1)
		2: return Vector3(x+1, y, z)
		3: return Vector3(x, y, z)
		4: return Vector3(x, y+1, z+1)
		5: return Vector3(x+1, y+1, z+1)
		6: return Vector3(x+1, y+1, z)
		7: return Vector3(x, y+1, z)
		_: return Vector3(x, y, z)

func _interpolate_edge(x, y, z, edge_index, data):
	# Bounds check for edge index
	if edge_index < 0 or edge_index >= EDGE_TABLE.size():
		return Vector3(x, y, z)
	
	var edges = EDGE_TABLE
	var e = edges[edge_index]
	var a = _corner_pos(x, y, z, e[0])
	var b = _corner_pos(x, y, z, e[1])
	
	# Bounds check for data access
	if a.x < 0 or a.x >= data.size() or a.y < 0 or a.y >= data[0].size() or a.z < 0 or a.z >= data[0][0].size():
		return Vector3(x, y, z)
	
	if b.x < 0 or b.x >= data.size() or b.y < 0 or b.y >= data[0].size() or b.z < 0 or b.z >= data[0][0].size():
		return Vector3(x, y, z)
	
	var da = data[a.x][a.y][a.z]
	var db = data[b.x][b.y][b.z]
	
	# Avoid division by zero and degenerate positions
	var diff = db - da
	if abs(diff) < 1e-6:
		return (Vector3(a.x, a.y, a.z) + Vector3(b.x, b.y, b.z)) * 0.5
	
	# Improved interpolation for smoother transitions
	var t = (ISO_LEVEL - da) / diff
	t = clamp(t, 0.0, 1.0)
	
	# Use smoothstep for better interpolation
	t = smoothstep(0.0, 1.0, t)
	
	return Vector3(a.x, a.y, a.z).lerp(Vector3(b.x, b.y, b.z), t)

func run() -> Dictionary:
	if not _validate_dependencies():
		return _create_error_result("Invalid dependencies")
	
	voxel_data = _generate_voxel_data()
	if not voxel_data or voxel_data.is_empty():
		return _create_error_result("Failed to generate voxel data")
	
	var padded_data = _get_padded_data(voxel_data)
	if not padded_data:
		return _create_error_result("Failed to create padded data")
	
	_generate_mesh(padded_data)
	
	# Clean up temporary data to save memory
	padded_data = null
	
	var generation_time = Time.get_ticks_msec() - generation_start_time
	
	var result = {
		"chunk_position": chunk_position,
		"voxel_data": voxel_data,
		"mesh_arrays": mesh_arrays,
		"biome_data": biome_data,
		"generation_time_ms": generation_time,
		"vertex_count": vertex_count,
		"triangle_count": triangle_count,
		"success": true
	}
	
	if debug_enabled:
		print("VoxelMesher[%s]: Generated in %dms, %d vertices, %d triangles" % [chunk_position, generation_time, vertex_count, triangle_count])
	
	return result

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
				var world_y = float(y)
				var density = 0.0
				
				if generator.is_ocean(world_x, world_z) and world_y <= int(generator.sea_level):
					# Ocean: create smooth underwater surface
					density = (generator.sea_level - world_y) * 0.3
				else:
					# Land: create smooth terrain surface with better falloff
					var surface_height = ground_h
					var distance_from_surface = surface_height - world_y
					
					if distance_from_surface > 0:
						# Below surface: solid (positive density)
						density = distance_from_surface * 0.4
					else:
						# Above surface: air (negative density)
						density = distance_from_surface * 0.4
				
				# Clamp density to prevent extreme values
				density = clamp(density, -2.0, 5.0)
				data[x][y][z] = density

	return data

func _get_padded_data(p_voxel_data):
	# Padded data needs to be CHUNK_SIZE + 1 in each dimension for marching cubes
	var size = CHUNK_WIDTH + 1
	var height = CHUNK_HEIGHT + 1
	var padded = []
	padded.resize(size)
	for x in range(size):
		padded[x] = []
		padded[x].resize(height)
		for y in range(height):
			padded[x][y] = []
			padded[x][y].resize(size)

	# Fill the padded data with proper neighbor information
	for x in range(size):
		for y in range(height):
			for z in range(size):
				if x < CHUNK_WIDTH and y < CHUNK_HEIGHT and z < CHUNK_DEPTH:
					# Use existing chunk data
					padded[x][y][z] = p_voxel_data[x][y][z]
				else:
					# Get data from neighboring chunks or generate it
					var world_x = chunk_position.x * CHUNK_WIDTH + x
					var world_y = y
					var world_z = chunk_position.y * CHUNK_DEPTH + z
					
					# Use the same density calculation as the main chunk
					if generator.is_ocean(world_x, world_z) and world_y <= int(generator.sea_level):
						padded[x][y][z] = (generator.sea_level - world_y) * 0.3
					else:
						var ground_h = generator.get_height(world_x, world_z, CHUNK_HEIGHT)
						var surface_height = ground_h
						var distance_from_surface = surface_height - world_y
						
						if distance_from_surface > 0:
							# Below surface: solid (positive density)
							padded[x][y][z] = distance_from_surface * 0.4
						else:
							# Above surface: air (negative density)
							padded[x][y][z] = distance_from_surface * 0.4
					
					# Clamp density values
					padded[x][y][z] = clamp(padded[x][y][z], -2.0, 5.0)
	
	return padded

func _generate_mesh(padded_voxel_data):
	if not padded_voxel_data or padded_voxel_data.is_empty():
		print("VoxelMesher: ERROR - Invalid padded voxel data")
		mesh_arrays = []
		return
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	triangle_count = 0
	vertex_count = 0

	for x in range(CHUNK_WIDTH):
		for y in range(CHUNK_HEIGHT):
			for z in range(CHUNK_DEPTH):
				# Bounds check for biome data
				if x >= biome_data.size() or z >= biome_data[x].size():
					continue
				
				var biome = biome_data[x][z]
				
				# Set color based on biome (using cached colors)
				var biome_color = _cached_colors.get(biome, Color(0.2, 0.8, 0.3, 1.0))
				st.set_color(biome_color)

				# Bounds check for padded data
				if x + 1 >= padded_voxel_data.size() or y + 1 >= padded_voxel_data[0].size() or z + 1 >= padded_voxel_data[0][0].size():
					continue

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

				# Bounds check for TRI_TABLE
				if cube_index >= TRI_TABLE.size():
					continue
				
				var tri_indices = TRI_TABLE[cube_index]
				if tri_indices[0] == -1:
					continue

				for i in range(0, 16, 3):
					if tri_indices[i] == -1:
						break
					
					# Bounds check for tri_indices
					if i + 2 >= tri_indices.size():
						break
					
					var a = _interpolate_edge(x, y, z, tri_indices[i+0], padded_voxel_data)
					var b = _interpolate_edge(x, y, z, tri_indices[i+1], padded_voxel_data)
					var c = _interpolate_edge(x, y, z, tri_indices[i+2], padded_voxel_data)
					
					# Only add valid, non-degenerate triangles
					if _is_valid_triangle(a, b, c, Vector3(x, y, z)):
						st.add_vertex(a)
						st.add_vertex(b)
						st.add_vertex(c)
						vertex_count += 3
						triangle_count += 1

	if debug_enabled:
		print("VoxelMesher[", chunk_position, "]: Generated ", triangle_count, " triangles")
	
	var mesh = st.commit()
	
	# Optimize the mesh to reduce patchy appearance
	if mesh.get_surface_count() > 0:
		var surface_arrays = mesh.surface_get_arrays(0)
		var optimized_mesh = ArrayMesh.new()
		
		# Only keep the mesh if we have enough vertices for a proper surface
		var vertices = surface_arrays[Mesh.ARRAY_VERTEX]
		if vertices.size() > 10:
			optimized_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
			mesh = optimized_mesh
	
	mesh_arrays = mesh.surface_get_arrays(0) if mesh.get_surface_count() > 0 else []

func _precache_biome_colors():
	"""Pre-cache biome colors for performance"""
	_cached_colors[WorldData.Biome.TUNDRA] = Color(0.95, 0.95, 1.0, 1.0)
	_cached_colors[WorldData.Biome.FOREST] = Color(0.15, 0.50, 0.20, 1.0)
	_cached_colors[WorldData.Biome.PLAINS] = Color(0.2, 0.8, 0.3, 1.0)
	_cached_colors[WorldData.Biome.DESERT] = Color(0.95, 0.85, 0.65, 1.0)
	_cached_colors[WorldData.Biome.MOUNTAINS] = Color(0.7, 0.7, 0.7, 1.0)
	_cached_colors[WorldData.Biome.JUNGLE] = Color(0.1, 0.6, 0.15, 1.0)
	_cached_colors[WorldData.Biome.SWAMP] = Color(0.15, 0.45, 0.15, 1.0)
	_cached_colors[WorldData.Biome.OCEAN] = Color(0.05, 0.3, 0.6, 1.0)

func _validate_dependencies() -> bool:
	"""Validate all required dependencies are available"""
	return generator != null and TRI_TABLE != null and EDGE_TABLE != null and \
		   TRI_TABLE.size() > 0 and EDGE_TABLE.size() > 0

func _create_error_result(error_msg: String) -> Dictionary:
	"""Create error result dictionary"""
	print("VoxelMesher[%s]: ERROR - %s" % [chunk_position, error_msg])
	return {
		"chunk_position": chunk_position,
		"voxel_data": [],
		"mesh_arrays": [],
		"biome_data": [],
		"success": false,
		"error": error_msg,
		"generation_time_ms": Time.get_ticks_msec() - generation_start_time
	}

func _is_valid_triangle(a: Vector3, b: Vector3, c: Vector3, fallback: Vector3) -> bool:
	"""Check if triangle vertices form a valid, non-degenerate triangle"""
	# Check triangle has non-zero area (simplified check)
	var edge1 = b - a
	var edge2 = c - a
	var cross = edge1.cross(edge2)
	return cross.length_squared() > 0.000001  # Very small threshold to avoid filtering valid triangles

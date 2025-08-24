# terrain_debug.gd
extends Node3D

@export var debug_chunk_size: int = 16
@export var debug_chunk_height: int = 32
@export var show_debug_info: bool = true

var generator: RefCounted
var debug_mesh_instance: MeshInstance3D

func _ready():
	# Create a simple generator for testing
	generator = preload("res://src/core/world/WorldGenerator.gd").new(1024, debug_chunk_size)
	generator.sea_level = 16.0
	generator.chunk_height = debug_chunk_height
	
	# Create debug mesh instance
	debug_mesh_instance = MeshInstance3D.new()
	add_child(debug_mesh_instance)
	
	# Generate debug terrain
	generate_debug_terrain()

func generate_debug_terrain():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate a simple heightmap for debugging
	for x in range(debug_chunk_size):
		for z in range(debug_chunk_size):
			var world_x = float(x)
			var world_z = float(z)
			
			var height = generator.get_height(world_x, world_z, debug_chunk_height)
			var biome = generator.get_biome(world_x, world_z)
			
			# Create a simple colored cube for each voxel
			var color = get_biome_color(biome)
			st.set_color(color)
			
			# Create a cube at this position
			create_cube_at(st, Vector3(x, height, z), 1.0)
	
	var mesh = st.commit()
	debug_mesh_instance.mesh = mesh
	
	if show_debug_info:
		print_debug_terrain_info()

func get_biome_color(biome: int) -> Color:
	match biome:
		WorldData.Biome.TUNDRA:
			return Color(0.8, 0.8, 1.0, 1.0)      # Light blue-white
		WorldData.Biome.PLAINS:
			return Color(0.4, 0.6, 0.2, 1.0)      # Green
		WorldData.Biome.DESERT:
			return Color(0.8, 0.7, 0.5, 1.0)      # Sand color
		WorldData.Biome.MOUNTAINS:
			return Color(0.5, 0.5, 0.5, 1.0)      # Gray
		WorldData.Biome.JUNGLE:
			return Color(0.2, 0.4, 0.1, 1.0)      # Dark green
		WorldData.Biome.SWAMP:
			return Color(0.3, 0.4, 0.2, 1.0)      # Dark green-brown
		WorldData.Biome.OCEAN:
			return Color(0.1, 0.3, 0.8, 1.0)      # Blue
		_:
			return Color(0.4, 0.6, 0.2, 1.0)      # Default green

func create_cube_at(st: SurfaceTool, pos: Vector3, size: float):
	var half_size = size * 0.5
	var vertices = [
		# Front face
		Vector3(pos.x - half_size, pos.y - half_size, pos.z + half_size),
		Vector3(pos.x + half_size, pos.y - half_size, pos.z + half_size),
		Vector3(pos.x + half_size, pos.y + half_size, pos.z + half_size),
		Vector3(pos.x - half_size, pos.y + half_size, pos.z + half_size),
		# Back face
		Vector3(pos.x - half_size, pos.y - half_size, pos.z - half_size),
		Vector3(pos.x + half_size, pos.y - half_size, pos.z - half_size),
		Vector3(pos.x + half_size, pos.y + half_size, pos.z - half_size),
		Vector3(pos.x - half_size, pos.y + half_size, pos.z - half_size)
	]
	
	# Add triangles for each face
	var faces = [
		[0, 1, 2, 0, 2, 3],  # Front
		[5, 4, 7, 5, 7, 6],  # Back
		[4, 0, 3, 4, 3, 7],  # Left
		[1, 5, 6, 1, 6, 2],  # Right
		[3, 2, 6, 3, 6, 7],  # Top
		[4, 5, 1, 4, 1, 0]   # Bottom
	]
	
	for face in faces:
		for i in range(0, 6, 3):
			st.add_vertex(vertices[face[i]])
			st.add_vertex(vertices[face[i+1]])
			st.add_vertex(vertices[face[i+2]])

func print_debug_terrain_info():
	print("=== TERRAIN DEBUG INFO ===")
	print("Chunk size: ", debug_chunk_size)
	print("Chunk height: ", debug_chunk_height)
	print("Sea level: ", generator.sea_level)
	
	# Test a few sample points
	var test_points = [Vector2(0, 0), Vector2(8, 8), Vector2(15, 15)]
	for point in test_points:
		var debug_info = generator.get_debug_info(point.x, point.y)
		print("Point (", point.x, ", ", point.y, "):")
		print("  Height: ", debug_info.height)
		print("  Biome: ", WorldData.Biome.keys()[debug_info.biome])
		print("  Temperature: ", debug_info.temperature)
		print("  Moisture: ", debug_info.moisture)
		print("  Continent value: ", debug_info.continent_value)
		print("  Is ocean: ", debug_info.is_ocean)
		print("---")

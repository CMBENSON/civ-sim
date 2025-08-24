# simple_test.gd
extends Node3D

func _ready():
	print("=== SIMPLE TERRAIN TEST ===")
	
	# Create a generator
	var generator = preload("res://src/core/world/WorldGenerator.gd").new(1024, 32)
	generator.sea_level = 16.0
	generator.chunk_height = 64
	
	# Test some basic functionality
	print("Testing basic terrain generation...")
	
	# Test a few sample points
	var test_points = [
		Vector2(0, 0),
		Vector2(100, 100),
		Vector2(200, 200),
		Vector2(300, 300),
		Vector2(400, 400)
	]
	
	for point in test_points:
		var height = generator.get_height(point.x, point.y, 64)
		var biome = generator.get_biome(point.x, point.y)
		var is_ocean = generator.is_ocean(point.x, point.y)
		var temp = generator.get_temperature_01(point.x, point.y)
		var moist = generator.get_moisture_01(point.x, point.y)
		
		print("Point (", point.x, ", ", point.y, "):")
		print("  Height: ", height)
		print("  Biome: ", WorldData.Biome.keys()[biome])
		print("  Is Ocean: ", is_ocean)
		print("  Temperature: ", temp)
		print("  Moisture: ", moist)
		print("---")
	
	# Test debug info if available
	if generator.has_method("get_debug_info"):
		print("Testing debug info...")
		var debug_info = generator.get_debug_info(100, 100)
		print("Debug info for (100, 100):")
		for key in debug_info:
			print("  ", key, ": ", debug_info[key])
	
	print("=== TEST COMPLETE ===")

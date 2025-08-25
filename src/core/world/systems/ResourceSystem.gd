# src/core/world/systems/ResourceSystem.gd
extends RefCounted
class_name ResourceSystem

signal resource_depleted(node_id: String, position: Vector3)
signal resource_discovered(node_id: String, position: Vector3, resource_type: int)

enum ResourceType {
	STONE, IRON, COPPER, GOLD, GEMS,
	WOOD, HERBS, FRUITS, SPICES,
	WATER, FISH, SALT
}

var resource_nodes: Dictionary = {}
var node_spawn_cooldowns: Dictionary = {}
var biome_resource_weights: Dictionary = {}

func _init():
	_setup_biome_resources()

func _setup_biome_resources():
	"""Define which resources spawn in which biomes"""
	biome_resource_weights = {
		WorldData.Biome.MOUNTAINS: {
			ResourceType.STONE: 0.4,
			ResourceType.IRON: 0.3,
			ResourceType.COPPER: 0.2,
			ResourceType.GEMS: 0.1
		},
		WorldData.Biome.FOREST: {
			ResourceType.WOOD: 0.5,
			ResourceType.HERBS: 0.3,
			ResourceType.FRUITS: 0.2
		},
		WorldData.Biome.DESERT: {
			ResourceType.GEMS: 0.4,
			ResourceType.SPICES: 0.3,
			ResourceType.SALT: 0.3
		},
		WorldData.Biome.OCEAN: {
			ResourceType.FISH: 0.6,
			ResourceType.SALT: 0.4
		}
		# ... more biomes
	}

func generate_resources_for_chunk(chunk_pos: Vector2i, biome_generator: BiomeGenerator) -> Array:
	"""Generate resource nodes for a newly loaded chunk"""
	var resources = []
	var chunk_size = 16
	
	# Sample a few points in the chunk to determine resources
	for i in range(3):  # 3 potential resource sites per chunk
		var local_x = randi() % chunk_size
		var local_z = randi() % chunk_size
		var world_x = chunk_pos.x * chunk_size + local_x
		var world_z = chunk_pos.y * chunk_size + local_z
		
		var height = 50.0  # Get from height generator
		var biome = biome_generator.get_biome(world_x, world_z, height)
		
		if _should_spawn_resource(biome):
			var resource = _create_resource_node(Vector3(world_x, height, world_z), biome)
			if resource:
				resources.append(resource)
	
	return resources

func _should_spawn_resource(biome: int) -> bool:
	"""Determine if a resource should spawn based on biome and scarcity"""
	return randf() < 0.3  # 30% chance per site

func _create_resource_node(position: Vector3, biome: int) -> Dictionary:
	"""Create a resource node with finite quantity"""
	var weights = biome_resource_weights.get(biome, {})
	if weights.is_empty():
		return {}
	
	var resource_type = _weighted_random_resource(weights)
	var node_id = str(position) + "_" + str(resource_type)
	
	var resource_node = {
		"id": node_id,
		"position": position,
		"type": resource_type,
		"quantity": randi_range(50, 200),
		"max_quantity": 200,
		"respawn_rate": 0.1,  # Very slow respawn
		"last_harvest": 0,
		"discoverable": true  # Hidden until first player finds it
	}
	
	resource_nodes[node_id] = resource_node
	return resource_node

func _weighted_random_resource(weights: Dictionary) -> int:
	"""Select random resource type based on weights"""
	var total_weight = 0.0
	for weight in weights.values():
		total_weight += weight
	
	var random_value = randf() * total_weight
	var current_weight = 0.0
	
	for resource_type in weights:
		current_weight += weights[resource_type]
		if random_value <= current_weight:
			return resource_type
	
	return weights.keys()[0]  # Fallback

func harvest_resource(node_id: String, amount: int = 1) -> Dictionary:
	"""Attempt to harvest from a resource node"""
	var node = resource_nodes.get(node_id, {})
	if node.is_empty():
		return {"success": false, "reason": "node_not_found"}
	
	if node.quantity <= 0:
		return {"success": false, "reason": "depleted"}
	
	var harvested = min(amount, node.quantity)
	node.quantity -= harvested
	node.last_harvest = Time.get_unix_time_from_system()
	
	if node.quantity <= 0:
		resource_depleted.emit(node_id, node.position)
		_schedule_respawn(node_id)
	
	return {
		"success": true,
		"harvested": harvested,
		"remaining": node.quantity,
		"type": node.type
	}

func _schedule_respawn(node_id: String):
	"""Schedule resource node to respawn after time"""
	var respawn_time = Time.get_unix_time_from_system() + randi_range(300, 1800)  # 5-30 minutes
	node_spawn_cooldowns[node_id] = respawn_time

func update_resource_respawn():
	"""Update resource respawn - call this periodically"""
	var current_time = Time.get_unix_time_from_system()
	
	for node_id in node_spawn_cooldowns.keys():
		if current_time >= node_spawn_cooldowns[node_id]:
			var node = resource_nodes.get(node_id)
			if node:
				node.quantity = min(node.max_quantity, node.quantity + randi_range(10, 30))
				if node.quantity > 0:
					resource_discovered.emit(node_id, node.position, node.type)
			node_spawn_cooldowns.erase(node_id)

func get_resources_in_area(center: Vector3, radius: float) -> Array:
	"""Get all resource nodes within radius of position"""
	var nearby_resources = []
	
	for node in resource_nodes.values():
		var distance = center.distance_to(node.position)
		if distance <= radius and node.quantity > 0:
			nearby_resources.append(node)
	
	return nearby_resources

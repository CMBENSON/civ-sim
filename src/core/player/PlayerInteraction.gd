# src/core/player/PlayerInteraction.gd
extends RefCounted
class_name PlayerInteraction

# Terrain editing settings (class-level static variables)
static var edit_strength: float = 2.0
static var edit_radius: int = 3
static var max_edit_distance: float = 10.0
static var edit_timer: float = 0.0

# Interaction modes
enum InteractionMode {
	NONE,
	TERRAIN_ADD,
	TERRAIN_REMOVE,
	INSPECT
}

static var current_mode: InteractionMode = InteractionMode.NONE

const EDIT_INTERVAL: float = 0.1  # Edit every 100ms

static func handle_terrain_edit(player: CharacterBody3D, world_node: Node3D, mode: InteractionMode) -> bool:
	"""Handle terrain editing interaction"""
	if not _validate_edit_inputs(player, world_node):
		return false
	
	var raycast = _get_player_raycast(player)
	if not raycast or not raycast.is_colliding():
		if world_node.verbose_logging:
			print("PlayerInteraction: No collision detected for terrain edit")
		return false
	
	var collision_point = raycast.get_collision_point()
	var collision_normal = raycast.get_collision_normal()
	
	# Validate edit distance
	var distance_to_collision = player.global_position.distance_to(collision_point)
	if distance_to_collision > max_edit_distance:
		if world_node.verbose_logging:
			print("PlayerInteraction: Edit point too far away: ", distance_to_collision)
		return false
	
	# Offset the edit point based on the mode
	var edit_point = collision_point
	var strength = edit_strength
	
	match mode:
		InteractionMode.TERRAIN_ADD:
			edit_point += collision_normal * 0.5
			strength = abs(edit_strength)
		InteractionMode.TERRAIN_REMOVE:
			edit_point -= collision_normal * 0.5
			strength = -abs(edit_strength)
		_:
			return false
	
	if world_node.verbose_logging:
		print("PlayerInteraction: Editing terrain at ", edit_point, " with strength ", strength)
	
	# Perform the terrain edit
	world_node.edit_terrain(edit_point, strength)
	return true

static func handle_inspection(player: CharacterBody3D, world_node: Node3D) -> Dictionary:
	"""Handle world inspection interaction"""
	if not _validate_edit_inputs(player, world_node):
		return {"error": "Invalid inputs for inspection"}
	
	var raycast = _get_player_raycast(player)
	if not raycast or not raycast.is_colliding():
		return {"error": "No collision detected for inspection"}
	
	var collision_point = raycast.get_collision_point()
	var world_x = collision_point.x
	var world_z = collision_point.z
	
	# Get comprehensive world information at this point
	var info = {}
	
	if world_node.generator:
		info = world_node.generator.get_debug_info(world_x, world_z) if world_node.generator.has_method("get_debug_info") else {}
	
	# Add basic information
	info.merge({
		"world_position": Vector3(world_x, collision_point.y, world_z),
		"collision_point": collision_point,
		"surface_height": world_node.get_surface_height(world_x, world_z),
		"biome": world_node.get_biome(world_x, world_z),
		"player_distance": player.global_position.distance_to(collision_point)
	})
	
	return info

static func set_edit_parameters(strength: float, radius: int = -1, max_distance: float = -1):
	"""Configure terrain editing parameters"""
	edit_strength = clamp(strength, 0.1, 10.0)
	
	if radius > 0:
		edit_radius = clamp(radius, 1, 8)
	
	if max_distance > 0:
		max_edit_distance = clamp(max_distance, 1.0, 50.0)
	
	print("PlayerInteraction: Edit parameters - strength: ", edit_strength, ", radius: ", edit_radius, ", max_distance: ", max_edit_distance)

static func get_edit_parameters() -> Dictionary:
	"""Get current editing parameters"""
	return {
		"strength": edit_strength,
		"radius": edit_radius,
		"max_distance": max_edit_distance,
		"current_mode": current_mode
	}

static func cycle_interaction_mode() -> InteractionMode:
	"""Cycle through interaction modes"""
	match current_mode:
		InteractionMode.NONE:
			current_mode = InteractionMode.TERRAIN_ADD
		InteractionMode.TERRAIN_ADD:
			current_mode = InteractionMode.TERRAIN_REMOVE
		InteractionMode.TERRAIN_REMOVE:
			current_mode = InteractionMode.INSPECT
		InteractionMode.INSPECT:
			current_mode = InteractionMode.NONE
		_:
			current_mode = InteractionMode.NONE
	
	print("PlayerInteraction: Mode changed to ", _get_mode_name(current_mode))
	return current_mode

static func set_interaction_mode(mode: InteractionMode):
	"""Set specific interaction mode"""
	current_mode = mode
	print("PlayerInteraction: Mode set to ", _get_mode_name(current_mode))

static func handle_continuous_edit(player: CharacterBody3D, world_node: Node3D, delta: float) -> bool:
	"""Handle continuous terrain editing while button is held"""
	if current_mode != InteractionMode.TERRAIN_ADD and current_mode != InteractionMode.TERRAIN_REMOVE:
		return false
	
	# Throttle continuous editing to prevent excessive operations
	edit_timer += delta
	if edit_timer < EDIT_INTERVAL:
		return false
	
	edit_timer = 0.0
	
	return handle_terrain_edit(player, world_node, current_mode)

static func _validate_edit_inputs(player: CharacterBody3D, world_node: Node3D) -> bool:
	"""Validate inputs for terrain interaction"""
	if not is_instance_valid(player):
		print("PlayerInteraction: ERROR - Invalid player reference")
		return false
	
	if not is_instance_valid(world_node):
		print("PlayerInteraction: ERROR - Invalid world_node reference")
		return false
	
	if not world_node.has_method("edit_terrain"):
		print("PlayerInteraction: ERROR - world_node missing edit_terrain method")
		return false
	
	return true

static func _get_player_raycast(player: CharacterBody3D) -> RayCast3D:
	"""Get the player's raycast node safely"""
	if not player.has_node("Head/Camera3D/RayCast3D"):
		print("PlayerInteraction: ERROR - Player missing raycast node")
		return null
	
	var raycast = player.get_node("Head/Camera3D/RayCast3D")
	if not raycast is RayCast3D:
		print("PlayerInteraction: ERROR - Raycast node is not RayCast3D type")
		return null
	
	return raycast

static func _get_mode_name(mode: InteractionMode) -> String:
	"""Get human-readable name for interaction mode"""
	match mode:
		InteractionMode.NONE:
			return "None"
		InteractionMode.TERRAIN_ADD:
			return "Terrain Add"
		InteractionMode.TERRAIN_REMOVE:
			return "Terrain Remove"
		InteractionMode.INSPECT:
			return "Inspect"
		_:
			return "Unknown"

static func get_interaction_help() -> Array:
	"""Get help text for current interaction controls"""
	var help = []
	
	match current_mode:
		InteractionMode.NONE:
			help.append("I - Cycle interaction mode")
			help.append("Current: None (no interaction)")
		InteractionMode.TERRAIN_ADD:
			help.append("Left Click - Add terrain")
			help.append("Q/E - Adjust strength")
			help.append("I - Cycle interaction mode")
		InteractionMode.TERRAIN_REMOVE:
			help.append("Left Click - Remove terrain")
			help.append("Q/E - Adjust strength") 
			help.append("I - Cycle interaction mode")
		InteractionMode.INSPECT:
			help.append("Left Click - Inspect world")
			help.append("I - Cycle interaction mode")
	
	return help
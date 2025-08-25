extends CharacterBody3D

# Import PlayerInteraction class
const PlayerInteraction = preload("res://src/core/player/PlayerInteraction.gd")

const WALK_SPEED = 8.0
const FLY_SPEED = 25.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var raycast = $Head/Camera3D/RayCast3D

var world_node = null
var is_flying = false  # Toggle between walking and flying

# Interaction system
var is_editing = false
var interaction_timer = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Ensure player has proper collision setup
	if not has_node("CollisionShape3D"):
		var collision_shape = CapsuleShape3D.new()
		collision_shape.radius = 0.8
		collision_shape.height = 1.8
		var collision_body = CollisionShape3D.new()
		collision_body.shape = collision_shape
		add_child(collision_body)
	
	# Validate node structure
	if not _validate_node_structure():
		print("Player: WARNING - Node structure validation failed")
	
	print("Controls:")
	print("  WASD/Arrow Keys - Move")
	print("  Space - Jump (walking) / Fly up (flying)")
	print("  Ctrl - Fly down (flying)")
	print("  Shift - Speed boost")
	print("  F - Toggle walking/flying mode")
	print("  Left Click - Remove terrain")
	print("  Right Click - Add terrain")
	print("  Q/E - Adjust edit strength")
	print("  ESC - Release mouse")
	print("  T - Test terrain edit (debug)")

func _unhandled_input(event):
	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
	
	# Mouse capture toggle
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	# Interaction handling
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Left click - interact based on current mode
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			is_editing = event.is_pressed()
			if event.is_pressed():
				_handle_interaction()
		
		# Right click - inspect
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			if event.is_pressed():
				_handle_inspection()
	
	# Key handling
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q:
				_adjust_edit_strength(-0.5)
			KEY_E:
				_adjust_edit_strength(0.5)
			KEY_F:
				_toggle_flight_mode()
			KEY_I:
				_cycle_interaction_mode()
			KEY_T:
				_test_terrain_edit()

func _physics_process(delta):
	if is_flying:
		PlayerMovement.handle_flying_movement(self, delta)
	else:
		PlayerMovement.handle_walking_movement(self, delta)
	
	# Handle continuous terrain editing
	if is_editing and _can_interact():
		PlayerInteraction.handle_continuous_edit(self, world_node, delta)
	elif is_editing and not _can_interact():
		print("Player: Cannot edit terrain - invalid world reference")
		is_editing = false

func _handle_interaction():
	"""Handle primary interaction (left click)"""
	if not _can_interact():
		return
	
	var current_mode = PlayerInteraction.current_mode
	if current_mode == PlayerInteraction.InteractionMode.INSPECT:
		_handle_inspection()
	else:
		PlayerInteraction.handle_terrain_edit(self, world_node, current_mode)

func _handle_inspection():
	"""Handle world inspection"""
	if not _can_interact():
		return
	
	var info = PlayerInteraction.handle_inspection(self, world_node)
	if info.has("error"):
		print("Player: Inspection failed - ", info.error)
	else:
		print("=== WORLD INSPECTION ===")
		for key in info:
			print("  ", key, ": ", info[key])
		print("========================")

func _test_terrain_edit():
	"""Debug function to test terrain editing"""
	print("=== DEBUG: Testing terrain edit ===")
	print("Player position: ", global_position)
	print("World node valid: ", _can_interact())
	print("Current interaction mode: ", PlayerInteraction.current_mode)
	print("Edit parameters: ", PlayerInteraction.get_edit_parameters())
	
	if _validate_node_structure():
		print("Camera rotation: ", camera.rotation)
		print("Raycast target: ", raycast.target_position)
		print("Raycast enabled: ", raycast.enabled)
		print("Raycast collision: ", raycast.is_colliding())
		
		if raycast.is_colliding():
			print("Raycast hit point: ", raycast.get_collision_point())
			print("Raycast hit normal: ", raycast.get_collision_normal())
			print("Raycast hit object: ", raycast.get_collider())
			
			# Test interaction
			var success = PlayerInteraction.handle_terrain_edit(self, world_node, PlayerInteraction.InteractionMode.TERRAIN_ADD)
			print("Terrain edit result: ", "SUCCESS" if success else "FAILED")
		else:
			print("Raycast not hitting anything - try looking down at terrain")
	else:
		print("Node structure validation failed")
	
	print("=== END DEBUG ===")

func _can_interact() -> bool:
	"""Check if player can interact with the world"""
	return is_instance_valid(world_node) and world_node.has_method("edit_terrain")

func _validate_node_structure() -> bool:
	"""Validate required node structure"""
	if not has_node("Head"):
		print("Player: Missing Head node")
		return false
	if not has_node("Head/Camera3D"):
		print("Player: Missing Camera3D node")
		return false
	if not has_node("Head/Camera3D/RayCast3D"):
		print("Player: Missing RayCast3D node")
		return false
	return true

func _adjust_edit_strength(delta: float):
	"""Adjust terrain editing strength"""
	var params = PlayerInteraction.get_edit_parameters()
	var new_strength = clamp(params.strength + delta, 0.5, 5.0)
	PlayerInteraction.set_edit_parameters(new_strength)

func _toggle_flight_mode():
	"""Toggle between walking and flying modes"""
	is_flying = !is_flying
	print("Player: Mode changed to ", "Flying" if is_flying else "Walking")
	if is_flying:
		velocity = Vector3.ZERO

func _cycle_interaction_mode():
	"""Cycle through interaction modes"""
	PlayerInteraction.cycle_interaction_mode()

func get_interaction_help() -> Array:
	"""Get current interaction help text"""
	return PlayerInteraction.get_interaction_help()

func _exit_tree():
	# Ensure proper cleanup
	print("Player: Cleaning up...")
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	is_editing = false
	print("Player: Cleanup complete")

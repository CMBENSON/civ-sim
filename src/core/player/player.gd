extends CharacterBody3D

const WALK_SPEED = 8.0
const FLY_SPEED = 25.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var raycast = $Head/Camera3D/RayCast3D

var world_node = null
var is_flying = false  # Toggle between walking and flying

# Terrain editing settings
var edit_strength = 2.0
var edit_mode = "remove"  # "add" or "remove"
var is_editing = false

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

	# Terrain editing
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Left click - remove terrain
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				is_editing = true
				edit_mode = "remove"
			else:
				is_editing = false
		
		# Right click - add terrain
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			if event.is_pressed():
				is_editing = true
				edit_mode = "add"
			else:
				is_editing = false
	
	# Adjust edit strength
	if event is InputEventKey:
		if event.pressed:
			if event.keycode == KEY_Q:
				edit_strength = max(0.5, edit_strength - 0.5)
				print("Edit strength: ", edit_strength)
			elif event.keycode == KEY_E:
				edit_strength = min(5.0, edit_strength + 0.5)
				print("Edit strength: ", edit_strength)
			elif event.keycode == KEY_F:
				is_flying = !is_flying
				print("Mode: ", "Flying" if is_flying else "Walking")
				if is_flying:
					# Reset velocity when switching to flying
					velocity = Vector3.ZERO
			elif event.keycode == KEY_T:
				# Debug: Test terrain editing
				test_terrain_edit()

func _physics_process(delta):
	if is_flying:
		_handle_flying_movement(delta)
	else:
		_handle_walking_movement(delta)
	
	# Handle continuous terrain editing
	if is_editing and world_node != null:
		print("Player: Performing terrain edit (mode: ", edit_mode, ", strength: ", edit_strength, ")")
		perform_terrain_edit()
	elif is_editing and world_node == null:
		print("Player: ERROR - Cannot edit terrain, world_node is null!")
		is_editing = false

func _handle_flying_movement(delta):
	# Flight movement
	var current_speed = FLY_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed = FLY_SPEED * 3.0

	# Get movement input - using both WASD and arrow keys
	var input_dir = Vector2.ZERO
	
	# WASD input
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	
	# Also check arrow keys as fallback
	if Input.is_action_pressed("ui_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("ui_down"):
		input_dir.y += 1
	if Input.is_action_pressed("ui_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("ui_right"):
		input_dir.x += 1
	
	input_dir = input_dir.normalized()
	
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply horizontal velocity
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed * delta * 3)
		velocity.z = move_toward(velocity.z, 0, current_speed * delta * 3)

	# Get vertical movement input
	var vertical_movement = 0.0
	if Input.is_key_pressed(KEY_SPACE):  # Spacebar to go up
		vertical_movement += current_speed
	if Input.is_key_pressed(KEY_CTRL):  # Ctrl to go down
		vertical_movement -= current_speed
		
	# Apply vertical velocity
	velocity.y = vertical_movement

	move_and_slide()

func _handle_walking_movement(delta):
	# Walking movement with gravity
	var current_speed = WALK_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed = WALK_SPEED * 2.0

	# Get movement input
	var input_dir = Vector2.ZERO
	
	# WASD input
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	
	# Arrow keys as fallback
	if Input.is_action_pressed("ui_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("ui_down"):
		input_dir.y += 1
	if Input.is_action_pressed("ui_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("ui_right"):
		input_dir.x += 1
	
	input_dir = input_dir.normalized()
	
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply horizontal velocity
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed * delta * 3)
		velocity.z = move_toward(velocity.z, 0, current_speed * delta * 3)

	# Handle jumping
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Apply gravity
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	move_and_slide()

func perform_terrain_edit():
	if not raycast.is_colliding():
		print("Player: Raycast not colliding - cannot edit terrain")
		return
	
	var collision_point = raycast.get_collision_point()
	var collision_normal = raycast.get_collision_normal()
	
	print("Player: Raycast hit at ", collision_point, " with normal ", collision_normal)
	
	# Offset the edit point slightly based on the mode
	if edit_mode == "add":
		collision_point += collision_normal * 0.5
		print("Player: Adding terrain at ", collision_point)
	else:  # remove
		collision_point -= collision_normal * 0.5
		print("Player: Removing terrain at ", collision_point)
	
	var strength = edit_strength if edit_mode == "add" else -edit_strength
	print("Player: Calling world.edit_terrain with strength ", strength)
	
	if world_node != null:
		world_node.edit_terrain(collision_point, strength)
	else:
		print("Player: ERROR - world_node is null!")

func test_terrain_edit():
	print("=== DEBUG: Testing terrain edit ===")
	print("Player position: ", global_position)
	print("Camera rotation: ", camera.rotation)
	print("Raycast target: ", raycast.target_position)
	print("Raycast enabled: ", raycast.enabled)
	print("Raycast collision: ", raycast.is_colliding())
	
	if raycast.is_colliding():
		print("Raycast hit point: ", raycast.get_collision_point())
		print("Raycast hit normal: ", raycast.get_collision_normal())
		print("Raycast hit object: ", raycast.get_collider())
		
		# Try to edit terrain at the hit point
		var collision_point = raycast.get_collision_point()
		if world_node != null:
			print("Calling world.edit_terrain with point ", collision_point, " and strength 2.0")
			world_node.edit_terrain(collision_point, 2.0)
		else:
			print("ERROR: world_node is null!")
	else:
		print("Raycast not hitting anything!")
		print("Try looking down at the terrain")
	print("=== END DEBUG ===")

func _exit_tree():
	# Ensure proper cleanup
	print("Player: Cleaning up...")
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("Player: Cleanup complete")

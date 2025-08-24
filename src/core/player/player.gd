extends CharacterBody3D

const WALK_SPEED = 5.0
const FLY_SPEED = 20.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var raycast = $Head/Camera3D/RayCast3D

var world_node = null

# Terrain editing settings
var edit_strength = 2.0
var edit_mode = "remove"  # "add" or "remove"
var is_editing = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("Controls:")
	print("  WASD/Arrow Keys - Move")
	print("  Space - Fly up")
	print("  Ctrl - Fly down")
	print("  Shift - Speed boost")
	print("  Left Click - Remove terrain")
	print("  Right Click - Add terrain")
	print("  Q/E - Adjust edit strength")
	print("  ESC - Release mouse")

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

func _physics_process(delta):
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
	
	# Handle continuous terrain editing
	if is_editing and world_node != null:
		perform_terrain_edit()

func perform_terrain_edit():
	if not raycast.is_colliding():
		return
	
	var collision_point = raycast.get_collision_point()
	var collision_normal = raycast.get_collision_normal()
	
	# Offset the edit point slightly based on the mode
	if edit_mode == "add":
		collision_point += collision_normal * 0.5
	else:  # remove
		collision_point -= collision_normal * 0.5
	
	var strength = edit_strength if edit_mode == "add" else -edit_strength
	world_node.edit_terrain(collision_point, strength)

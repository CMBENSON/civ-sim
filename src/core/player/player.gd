extends CharacterBody3D

const WALK_SPEED = 5.0
const FLY_SPEED = 20.0 # A faster speed for flying
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.002

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var raycast = $Head/Camera3D/RayCast3D

var world_node = null

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2, PI/2)
	
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		if raycast.is_colliding():
			var collision_point = raycast.get_collision_point()
			if world_node != null:
				world_node.edit_terrain(collision_point, -1.0)

func _physics_process(delta):
	# --- FLIGHT MODE CHANGES ---
	# We no longer apply gravity.
	# if not is_on_floor():
	# 	velocity.y -= gravity * delta

	# Get the current speed (sprint if Shift is held)
	var current_speed = FLY_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed = FLY_SPEED * 3.0

	# Get horizontal movement input
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply horizontal velocity
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	# Get vertical movement input
	var vertical_movement = 0.0
	if Input.is_action_pressed("ui_accept"): # Spacebar to go up
		vertical_movement += current_speed
	if Input.is_action_pressed("ui_page_down"): # Left Ctrl to go down
		vertical_movement -= current_speed
		
	# Apply vertical velocity
	velocity.y = vertical_movement

	move_and_slide()

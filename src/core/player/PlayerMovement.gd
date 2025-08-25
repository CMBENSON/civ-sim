# src/core/player/PlayerMovement.gd
extends RefCounted
class_name PlayerMovement

static func handle_flying_movement(player: CharacterBody3D, delta: float):
	var current_speed = player.FLY_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed = player.FLY_SPEED * 3.0

	var input_dir = _get_movement_input()
	var direction = (player.head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply horizontal velocity
	if direction:
		player.velocity.x = direction.x * current_speed
		player.velocity.z = direction.z * current_speed
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, current_speed * delta * 3)
		player.velocity.z = move_toward(player.velocity.z, 0, current_speed * delta * 3)

	# Vertical movement
	var vertical_movement = 0.0
	if Input.is_key_pressed(KEY_SPACE):
		vertical_movement += current_speed
	if Input.is_key_pressed(KEY_CTRL):
		vertical_movement -= current_speed
	
	player.velocity.y = vertical_movement
	player.move_and_slide()

static func handle_walking_movement(player: CharacterBody3D, delta: float):
	var current_speed = player.WALK_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed = player.WALK_SPEED * 2.0

	var input_dir = _get_movement_input()
	var direction = (player.head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply horizontal velocity
	if direction:
		player.velocity.x = direction.x * current_speed
		player.velocity.z = direction.z * current_speed
	else:
		player.velocity.x = move_toward(player.velocity.x, 0, current_speed * delta * 3)
		player.velocity.z = move_toward(player.velocity.z, 0, current_speed * delta * 3)

	# Handle jumping
	if Input.is_key_pressed(KEY_SPACE) and player.is_on_floor():
		player.velocity.y = player.JUMP_VELOCITY

	# Apply gravity
	if not player.is_on_floor():
		player.velocity.y -= 9.8 * delta

	player.move_and_slide()

static func _get_movement_input() -> Vector2:
	var input_dir = Vector2.ZERO
	
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	
	return input_dir.normalized()

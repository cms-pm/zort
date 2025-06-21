extends CharacterBody2D
class_name Player

@export_group("Movement")
@export var base_speed: float = 300.0
@export var acceleration: float = 1500.0
@export var friction: float = 1200.0

# Internal variables
var input_vector: Vector2
var last_direction: Vector2 = Vector2.DOWN

func _ready():
	# Add to player group for targeting
	add_to_group("player")
	if PoolManager.dev_mode:
		print("Player: Added to 'player' group for targeting")

func _physics_process(delta):
	handle_input()
	apply_movement(delta)
	update_direction()

func handle_input():
	# Get input from Input Map actions
	input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")

func apply_movement(delta):
	if input_vector != Vector2.ZERO:
		# Moving - accelerate toward target velocity
		velocity = velocity.move_toward(input_vector * base_speed, acceleration * delta)
	else:
		# Not moving - apply friction
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	
	# Apply movement
	move_and_slide()

func update_direction():
	# Store last movement direction for animations
	if input_vector != Vector2.ZERO:
		last_direction = input_vector.normalized()

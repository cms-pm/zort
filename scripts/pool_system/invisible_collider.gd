## Invisible Collider - High-performance pooled projectile 🎯
##
## A RigidBody2D projectile designed for object pooling with optimized physics
## state management and lifecycle control. Supports multiple launch modes and
## automatic collision detection with fadeout visual effects.
##
class_name InvisibleCollider
extends RigidBody2D

# Pool lifecycle signals
signal deactivation_requested(obj: Node)
signal hit_target(target: Node, collider: Node)

# Projectile configuration
@export var speed: float = 500.0
@export var lifetime: float = 3.0
@export var damage: int = 10

# Runtime state
var velocity: Vector2 = Vector2.ZERO
var target_node: Node2D = null
var current_lifetime: float = 0.0

func _ready() -> void:
	# Configure physics
	gravity_scale = 0.0
	lock_rotation = true
	
	# Set up collision detection
	contact_monitor = true
	max_contacts_reported = 10
	
	# Connect collision signal
	body_entered.connect(_on_body_entered)

## Initializes projectile for new lifecycle (called by pool manager)
func pool_activate() -> void:
	# Reset all projectile state
	current_lifetime = 0.0
	velocity = Vector2.ZERO
	target_node = null
	
	# Clear all physics properties to prevent state leakage
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	constant_force = Vector2.ZERO
	constant_torque = 0.0
	
	# Force physics server state reset for reliable behavior
	PhysicsServer2D.body_set_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY,
		Vector2.ZERO
	)
	PhysicsServer2D.body_set_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY,
		0.0
	)
	
	# Reset visual interpolation and appearance
	reset_physics_interpolation()
	modulate = Color.WHITE
	modulate.a = 1.0

func pool_deactivate() -> void:
	# CRITICAL: Stop physics movement immediately to prevent jumping
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	
	# Clean up any ongoing effects
	target_node = null
	velocity = Vector2.ZERO
	current_lifetime = 0.0
	modulate = Color.WHITE
	# DON'T set position here - let pool manager handle RigidBody2D physics properly

## Launch projectile toward a target node
func launch_at_target(start_pos: Vector2, target: Node2D, override_speed: float = -1.0) -> void:
	# Set position using PhysicsServer2D for reliable physics communication
	PhysicsServer2D.body_set_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D.IDENTITY.translated(start_pos)
	)
	reset_physics_interpolation()
	
	# Ensure physics state settles before making visible
	_make_visible_after_physics_settlement(start_pos)
	
	target_node = target
	
	var use_speed = override_speed if override_speed > 0 else speed
	
	# Calculate direction to target
	if target_node:
		var direction = (target_node.global_position - start_pos).normalized()
		velocity = direction * use_speed
		linear_velocity = velocity

func launch_at_position(start_pos: Vector2, target_pos: Vector2, override_speed: float = -1.0) -> void:
	# CRITICAL FIX: Use PhysicsServer2D instead of global_position
	PhysicsServer2D.body_set_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D.IDENTITY.translated(start_pos)
	)
	reset_physics_interpolation()  # Clear any interpolation memory
	
	# ULTRA-DEFENSIVE: Block until physics frame processes AND validate position
	_make_visible_after_physics_settlement(start_pos)
	
	var use_speed = override_speed if override_speed > 0 else speed
	
	# Calculate direction to position
	var direction = (target_pos - start_pos).normalized()
	velocity = direction * use_speed
	linear_velocity = velocity
	
	# Debug launch info available but disabled for cleaner output
	# if PoolManager.dev_mode:
	#	print("InvisibleCollider: Launched from %s to %s at speed %s" % [start_pos, target_pos, use_speed])

func launch_with_velocity(start_pos: Vector2, vel: Vector2) -> void:
	# CRITICAL FIX: Use PhysicsServer2D instead of global_position
	PhysicsServer2D.body_set_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D.IDENTITY.translated(start_pos)
	)
	reset_physics_interpolation()  # Clear any interpolation memory
	
	# ULTRA-DEFENSIVE: Block until physics frame processes AND validate position
	_make_visible_after_physics_settlement(start_pos)
	
	velocity = vel
	linear_velocity = velocity

func _physics_process(delta: float) -> void:
	# SAFETY: Only process if we're actually active in the pool
	if not get_meta("is_pooled_active", false):
		return  # Inactive objects shouldn't be processing
	
	# Update lifetime
	var old_lifetime = current_lifetime
	current_lifetime += delta
	
	# Debug: Track suspicious lifetime jumps
	if PoolManager.dev_mode and current_lifetime > 0.5 and old_lifetime < 0.1:
		print("InvisibleCollider: %s SUSPICIOUS LIFETIME JUMP from %.2f to %.2f (delta %.2f)" % [name, old_lifetime, current_lifetime, delta])
	
	# Check if expired
	if current_lifetime >= lifetime:
		if PoolManager.dev_mode:
			print("InvisibleCollider: %s expired (%.2f >= %.2f)" % [name, current_lifetime, lifetime])
		request_deactivation()
		return
	
	# Optional: Track target if we have one
	if target_node and is_instance_valid(target_node):
		# Slight homing behavior (optional)
		var direction = (target_node.global_position - global_position).normalized()
		var target_velocity = direction * speed
		velocity = velocity.lerp(target_velocity, 0.02)  # 2% homing
		linear_velocity = velocity

func request_deactivation() -> void:
	if PoolManager.dev_mode:
		var reason = "timeout" if current_lifetime >= lifetime else "collision"
		print("InvisibleCollider: %s requesting deactivation (%s: %.2f/%.2f) at position %s" % [name, reason, current_lifetime, lifetime, global_position])
	deactivation_requested.emit(self)

## Set lifetime dynamically
func set_lifetime(new_lifetime: float) -> void:
	lifetime = new_lifetime
	# If already active, adjust remaining time
	if get_meta("is_pooled_active", false):
		current_lifetime = 0.0  # Reset timer with new lifetime

## Get remaining lifetime
func get_remaining_lifetime() -> float:
	return max(0.0, lifetime - current_lifetime)

## Makes object visible immediately (legacy method)
func _make_visible() -> void:
	visible = true

## Safely reveals projectile after physics state has settled
func _make_visible_after_physics_settlement(expected_pos: Vector2) -> void:
	# Wait for physics server to process position update
	await get_tree().physics_frame
	
	# Validate position accuracy before revealing
	var actual_pos = global_position
	var distance = actual_pos.distance_to(expected_pos)
	
	# Show projectile if position is accurate (1 pixel tolerance)
	if distance < 1.0:
		visible = true
	else:
		# Wait additional frame if position hasn't settled
		await get_tree().physics_frame
		visible = true

## Extend lifetime by amount
func extend_lifetime(extra_time: float) -> void:
	lifetime += extra_time

## Set to infinite lifetime (must be manually deactivated)
func set_infinite_lifetime() -> void:
	lifetime = INF

## Collision detection
func _on_body_entered(body: Node) -> void:
	# Check if we hit our target
	if body == target_node:
		hit_target.emit(body, self)
	
	# Check if we hit something we care about
	if body.is_in_group("player") or body.is_in_group("enemies"):
		# Debug collision info available but disabled for cleaner output
		
		# Do damage logic here
		if body.has_method("take_damage"):
			body.take_damage(damage)
		
		# Return to pool after hit
		request_deactivation()

func _process(_delta: float) -> void:
	# Fade out earlier to ensure invisibility before expiration
	if current_lifetime > lifetime * 0.6:  # Start fade at 60% instead of 80%
		var fade_progress = (current_lifetime - lifetime * 0.6) / (lifetime * 0.3)  # Fade over 30% of lifetime
		modulate.a = 1.0 - fade_progress
		
		# Ensure complete invisibility at 90% lifetime (before expiration)
		if current_lifetime > lifetime * 0.9:
			modulate.a = 0.0

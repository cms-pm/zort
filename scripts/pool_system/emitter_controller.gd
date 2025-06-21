## Emitter Controller - Shoots projectiles at targets! 🔫
## Simple projectile spawner using object pools
class_name EmitterController
extends Node2D

# Pool settings
@export var pool_name: String = "invisible_colliders"
@export var fire_rate: float = 1.0
@export var projectile_speed: float = 500.0
@export var auto_fire: bool = true

# Burst fire options
@export var burst_mode: bool = true
@export var burst_count: int = 3
@export var burst_spread: float = 15.0

# Debug
@export var projectile_lifetime: float = -1  # -1 = use default
@export var debug_visual: bool = true

# Runtime stuff
var pool_manager_ref = null
var target_node: Node2D = null
var fire_timer: Timer = null
var visual_marker: Sprite2D = null

func _ready() -> void:
	if PoolManager.dev_mode:
		print("EmitterController: Starting up at ", position, " 🎯")
	
	# Find pool manager
	pool_manager_ref = get_node("/root/Main/PoolManager")
	if not pool_manager_ref:
		push_error("EmitterController: Can't find PoolManager!")
		return
	
	# Connect to pool events
	pool_manager_ref.pool_exhausted.connect(_on_pool_exhausted)
	
	# Find target (usually player)
	var players = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		target_node = players[0]
		if PoolManager.dev_mode:
			print("EmitterController: Found target! 🎮")
	
	# Setup firing timer
	fire_timer = Timer.new()
	fire_timer.wait_time = 1.0 / fire_rate
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	add_child(fire_timer)
	
	# Show debug marker
	if debug_visual:
		_create_visual_marker()
	
	# Start shooting!
	if auto_fire:
		start_auto_fire()

func _create_visual_marker() -> void:
	visual_marker = Sprite2D.new()
	visual_marker.texture = load("res://assets/sprites/crosshair016.png")
	visual_marker.modulate = Color.GREEN
	visual_marker.scale = Vector2(0.5, 0.5)
	add_child(visual_marker)
	if PoolManager.dev_mode:
		print("EmitterController: Green crosshair marker created! 💚")

## Start shooting automatically
func start_auto_fire() -> void:
	if fire_timer:
		fire_timer.start()
		if PoolManager.dev_mode:
			print("EmitterController: Auto-fire ON! 🔥")

## Stop shooting
func stop_auto_fire() -> void:
	if fire_timer:
		fire_timer.stop()
		if PoolManager.dev_mode:
			print("EmitterController: Auto-fire OFF! 🛑")

## Shoot at current target
func fire_at_target() -> bool:
	if not target_node or not is_instance_valid(target_node):
		return false
	return fire_at_position(target_node.global_position)

## Shoot at specific position
func fire_at_position(target_pos: Vector2) -> bool:
	if not pool_manager_ref:
		return false
	
	# Get a projectile from the pool
	var projectile = pool_manager_ref.get_object(pool_name)
	if not projectile:
		if PoolManager.dev_mode:
			print("EmitterController: Pool exhausted - no projectile available")
		return false  # Pool empty
	
	# Debug: Got projectile (output disabled for cleaner logs)
	
	# Launch it!
	if projectile.has_method("launch_at_position"):
		projectile.launch_at_position(global_position, target_pos, projectile_speed)
		# Debug: Launched projectile (output disabled for cleaner logs)
	else:
		if PoolManager.dev_mode:
			print("EmitterController: ERROR - projectile missing launch_at_position method!")
		return false
	
	# Custom lifetime if needed
	if projectile_lifetime > 0 and projectile.has_method("set_lifetime"):
		projectile.set_lifetime(projectile_lifetime)
	
	return true

## Timer callback for auto-fire
func _on_fire_timer_timeout() -> void:
	if burst_mode:
		fire_burst_at_target()
	else:
		fire_at_target()

## Fire a burst of projectiles
func fire_burst_at_target() -> bool:
	if not target_node or not is_instance_valid(target_node):
		return false
	
	var base_direction = (target_node.global_position - global_position).normalized()
	var base_angle = base_direction.angle()
	var spread_rad = deg_to_rad(burst_spread)
	var success_count = 0
	
	for i in burst_count:
		# Calculate spread angle
		var angle_offset = 0.0
		if burst_count > 1:
			angle_offset = lerp(-spread_rad/2, spread_rad/2, float(i) / float(burst_count - 1))
		
		var fire_angle = base_angle + angle_offset
		var fire_direction = Vector2.from_angle(fire_angle)
		var target_pos = global_position + fire_direction * 1000.0  # Far point
		
		if fire_at_position(target_pos):
			success_count += 1
	
	return success_count > 0

## Handle pool exhaustion
func _on_pool_exhausted(exhausted_pool_name: String) -> void:
	if exhausted_pool_name == pool_name:
		if PoolManager.dev_mode:
			print("⚠️ EmitterController: Pool exhausted! Consider increasing pool size or reducing fire rate.")

## Input handling for manual control
func _unhandled_input(event: InputEvent) -> void:
	# Toggle auto-fire with Enter
	if event.is_action_pressed("ui_accept"):
		if fire_timer.is_stopped():
			start_auto_fire()
		else:
			stop_auto_fire()
	
	# Emergency stop with Escape
	elif event.is_action_pressed("ui_cancel"):
		stop_auto_fire()
		if pool_manager_ref:
			pool_manager_ref.force_return_all(pool_name)
			if PoolManager.dev_mode:
				print("🛑 Emergency stop! All projectiles returned to pool.")
	
	# Manual fire with mouse click
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		fire_at_position(mouse_pos)

## Configuration helpers
func set_fire_rate(new_rate: float) -> void:
	fire_rate = new_rate
	if fire_timer:
		fire_timer.wait_time = 1.0 / fire_rate

func set_target(new_target: Node2D) -> void:
	target_node = new_target

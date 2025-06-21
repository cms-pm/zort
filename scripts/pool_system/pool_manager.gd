## Pool Manager - High-performance object pooling system 🎯
## 
## Provides efficient creation, retrieval, and recycling of pooled objects.
## Features RigidBody2D physics optimization and comprehensive state management.
##
class_name PoolManager
extends Node

# Development mode toggle - controls all pool system logging
static var dev_mode: bool = false

# Pool lifecycle events
signal pool_exhausted(pool_name: String)
signal object_activated(pool_name: String, object: Node)
signal object_deactivated(pool_name: String, object: Node)

# Core storage
var pools: Dictionary = {}
var pool_configs: Dictionary = {}

func _ready() -> void:
	if dev_mode:
		print("PoolManager: Ready")

## Creates a pool of reusable objects
func create_pool(pool_name: String, scene_path: String, pool_size: int, parent: Node = null) -> void:
	if dev_mode:
		print("Creating pool '%s' with %d objects..." % [pool_name, pool_size])
	
	# Load scene
	var packed_scene = load(scene_path)
	if not packed_scene:
		push_error("Failed to load scene: " + scene_path)
		return
	
	# Save config
	pool_configs[pool_name] = {
		"scene": packed_scene,
		"size": pool_size,
		"parent": parent if parent else self
	}
	
	# Create pool arrays
	pools[pool_name] = {
		"available": [],
		"active": []
	}
	
	# Create all objects upfront
	for i in pool_size:
		var obj = packed_scene.instantiate()
		obj.name = "%s_pooled_%03d" % [pool_name, i + 1]
		
		pool_configs[pool_name]["parent"].add_child(obj)
		_setup_pooled_object(obj, pool_name)
		
		pools[pool_name]["available"].append(obj)
		_deactivate_object(obj)
	
	if dev_mode:
		print("Pool '%s' ready with %d objects" % [pool_name, pool_size])

## Get an available object from the pool
func get_object(pool_name: String) -> Node:
	if not pools.has(pool_name):
		push_error("Pool '%s' doesn't exist!" % pool_name)
		return null
	
	var pool = pools[pool_name]
	
	# Check for available objects
	if pool["available"].is_empty():
		pool_exhausted.emit(pool_name)
		if dev_mode:
			print("Pool '%s' exhausted" % pool_name)
		return null
	
	# Move from available to active
	var obj = pool["available"].pop_back()
	pool["active"].append(obj)
	
	if dev_mode:
		print("PoolManager: Activated object %s (pool now has %d active)" % [obj.name, pool["active"].size()])
	
	# Make it live!
	_activate_object(obj)
	object_activated.emit(pool_name, obj)
	
	return obj

## Return an object back to the pool
func return_object(obj: Node) -> void:
	var pool_name = obj.get_meta("pool_name", "")
	if not pools.has(pool_name):
		push_error("Object doesn't belong to any pool!")
		return
	
	var pool = pools[pool_name]
	var idx = pool["active"].find(obj)
	
	if idx == -1:
		if dev_mode:
			print("PoolManager: WARNING - Object %s not in active pool (already returned?)" % obj.name)
		return
	
	if dev_mode:
		print("PoolManager: Returning object %s to pool" % obj.name)
	
	# Move back to available
	pool["active"].remove_at(idx)
	pool["available"].append(obj)
	
	# Put it to sleep
	_deactivate_object(obj)
	object_deactivated.emit(pool_name, obj)

## Get useful stats about a pool
func get_pool_stats(pool_name: String) -> Dictionary:
	if not pools.has(pool_name):
		return {}
	
	var pool = pools[pool_name]
	return {
		"total": pool["available"].size() + pool["active"].size(),
		"available": pool["available"].size(),
		"active": pool["active"].size(),
		"usage_percent": float(pool["active"].size()) / float(pool["available"].size() + pool["active"].size()) * 100.0
	}

## Emergency: return all active objects to pool
func force_return_all(pool_name: String) -> void:
	if not pools.has(pool_name):
		return
	
	if dev_mode:
		print("Force returning all objects in pool '%s'" % pool_name)
	var pool = pools[pool_name]
	
	while not pool["active"].is_empty():
		var obj = pool["active"][0]
		return_object(obj)

## Setup object for pooling
func _setup_pooled_object(obj: Node, pool_name: String) -> void:
	obj.set_meta("pool_name", pool_name)
	obj.set_meta("is_pooled_active", false)
	
	# Auto-return when object requests it
	if obj.has_signal("deactivation_requested"):
		obj.deactivation_requested.connect(return_object)

## Wake up a pooled object
func _activate_object(obj: Node) -> void:
	obj.set_meta("is_pooled_active", true)
	
	# CRITICAL: Keep object invisible until position is set by launch method
	obj.visible = false
	
	# Turn on processing
	obj.set_process(true)
	obj.set_physics_process(true)
	
	# Special handling for physics objects
	if obj is RigidBody2D:
		# Unfreeze immediately so object can move when launched
		obj.freeze = false
		obj.sleeping = false
		obj.reset_physics_interpolation()
	
	# Let object customize its activation
	if obj.has_method("pool_activate"):
		obj.pool_activate()

## Deactivates object and returns it to inactive state
func _deactivate_object(obj: Node) -> void:
	obj.set_meta("is_pooled_active", false)
	obj.visible = false
	
	# Disable processing to conserve CPU
	obj.set_process(false)
	obj.set_physics_process(false)
	
	# Allow object to perform custom deactivation logic
	if obj.has_method("pool_deactivate"):
		obj.pool_deactivate()
	
	# Reset physics state to prevent state leakage between lifetimes
	if obj is RigidBody2D:
		_reset_rigidbody_immediately(obj)
	else:
		obj.global_position = Vector2.ZERO

## Immediately resets RigidBody2D physics state to prevent artifacts
func _reset_rigidbody_immediately(obj: RigidBody2D) -> void:
	# Freeze body and clear all physics forces
	obj.freeze = true
	obj.linear_velocity = Vector2.ZERO
	obj.angular_velocity = 0.0
	obj.constant_force = Vector2.ZERO
	obj.constant_torque = 0.0
	
	# Use PhysicsServer2D for reliable position reset
	PhysicsServer2D.body_set_state(
		obj.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D.IDENTITY.translated(Vector2(0, 999999))
	)
	
	# Clear physics interpolation and ensure body is ready for reuse
	obj.reset_physics_interpolation()
	obj.sleeping = false

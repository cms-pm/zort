## Main Pool Integration - Sets up pools and emitters! 🎮
## Simple setup script for the main game scene
extends Node2D

# Pool configuration
const COLLIDER_POOL_SIZE = 1500
const COLLIDER_SCENE_PATH = "res://scenes/pool_system/invisible_collider.tscn"
const EMITTER_POSITION = Vector2(100, 100)

func _ready() -> void:
	if PoolManager.dev_mode:
		print("\n🚀 SETTING UP POOL SYSTEM! 🚀")
		print("=".repeat(40))
	
	# Get the existing pool manager from scene
	var pool_manager = get_node("PoolManager")
	if not pool_manager:
		push_error("No PoolManager found in scene!")
		return
	
	# Create projectile emitter
	var emitter = EmitterController.new()
	emitter.name = "EmitterController"
	emitter.position = EMITTER_POSITION
	add_child(emitter)
	
	if PoolManager.dev_mode:
		print("✅ Pool system ready!")
		print("  • %d projectiles in pool" % COLLIDER_POOL_SIZE)
		print("  • Emitter at %s" % EMITTER_POSITION)
		print("  • Auto-targeting player")
		print("\nControls:")
		print("  • Enter: Toggle auto-fire")
		print("  • Escape: Stop all projectiles")
		print("  • Click: Manual fire")
		print("=".repeat(40))
		
		
		
		

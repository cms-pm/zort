## Game Pool Setup - Creates all pools for the game! 🎯
## Extends PoolManager with game-specific configurations
class_name GamePoolSetup
extends PoolManager

# All our game's pools in one place!
const GAME_POOLS = {
	"invisible_colliders": {
		"scene_path": "res://scenes/pool_system/invisible_collider.tscn",
		"pool_size": 1500,
		"description": "Crosshair projectiles"
	}
}

func _ready() -> void:
	super._ready()
	
	if PoolManager.dev_mode:
		print("GamePoolSetup: Creating game pools... 🚀")
	
	# Create all pools defined above
	for pool_name in GAME_POOLS:
		var config = GAME_POOLS[pool_name]
		create_pool(
			pool_name,
			config["scene_path"],
			config["pool_size"]
		)
	
	if PoolManager.dev_mode:
		print("GamePoolSetup: All pools ready! 🎮")
		_print_pool_summary()

func _print_pool_summary() -> void:
	if PoolManager.dev_mode:
		print("\n📊 Pool Summary:")
		for pool_name in GAME_POOLS:
			var stats = get_pool_stats(pool_name)
			print("  • %s: %d objects" % [pool_name, stats["total"]])

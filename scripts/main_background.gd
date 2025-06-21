@tool
extends TextureRect

@export var tile_texture: Texture2D
@export var tile_size: Vector2 = Vector2(1024, 1024)
@export var world_size: Vector2 = Vector2(4096, 4096)
@export_group("Debug")
@export var force_update: bool : set = _refresh

func set_tile_texture(value: Texture2D):
	tile_texture = value
	_apply_texture()
	
func _refresh(_value: bool):
	_apply_texture()

func _apply_texture():
# Set texture and enable tiling
	if tile_texture:
		texture = tile_texture
		stretch_mode = TextureRect.STRETCH_TILE
		if world_size:
			# Size to cover expected play area
			size = world_size  # Adjust based on world size
			position = -size / 2  # Center around origin

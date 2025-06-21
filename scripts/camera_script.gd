extends Camera2D

@export var target: Node2D
@export var follow_speed: float = 5.0
@export var follow_offset: Vector2 = Vector2.ZERO

func _process(delta):
	if target:
		var target_position = target.global_position + follow_offset
		global_position = global_position.lerp(target_position, follow_speed * delta)

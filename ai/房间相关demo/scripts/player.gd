
extends CharacterBody2D

@export var speed = 200.0

func _physics_process(delta):
    var dir = Vector2(
        Input.get_axis("move_left","move_right"),
        Input.get_axis("move_up","move_down")
    )
    velocity = dir.normalized() * speed
    move_and_slide()

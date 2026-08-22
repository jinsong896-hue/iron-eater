
extends CharacterBody2D

var hp=120
var speed=50
var target

func _ready():
    target=get_parent().get_parent().get_node("Player")

func _physics_process(delta):
    if target:
        if global_position.distance_to(target.global_position)>80:
            velocity=global_position.direction_to(target.global_position)*speed
            move_and_slide()

func take_damage(value):
    hp-=value
    if hp<=0:
        queue_free()

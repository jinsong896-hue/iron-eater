
extends CharacterBody2D

var speed=220
var hp=500
var attack_power=35
var devour_count=0

func _physics_process(delta):
    velocity=Input.get_vector("ui_left","ui_right","ui_up","ui_down")*speed
    move_and_slide()

func _input(event):
    if event.is_action_pressed("attack"):
        attack()
    if event.is_action_pressed("fire_slash"):
        fire_slash()

func attack():
    hit_enemies(attack_power)

func fire_slash():
    hit_enemies(70)

func hit_enemies(dmg):
    var enemies=get_parent().get_node("Enemies").get_children()
    for e in enemies:
        if global_position.distance_to(e.global_position)<150:
            e.take_damage(dmg)

func devour(item):
    attack_power+=item.attack
    devour_count+=1

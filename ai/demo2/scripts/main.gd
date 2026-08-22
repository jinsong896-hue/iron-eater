
extends Node2D

var loot_dropped=false

func _ready():
    $HUD.text="Devourer Level1\nWASD Move  LMB Attack  Q Fire Slash"

func _process(delta):
    var count=$Enemies.get_child_count()
    $HUD.text="HP: "+str($Player.hp)+"  ATK: "+str($Player.attack_power)+"  Enemies:"+str(count)
    if count==0 and !loot_dropped:
        loot_dropped=true
        $HUD.text+="\nBroken Iron Sword dropped\nPress E to Devour"
    if loot_dropped and Input.is_action_just_pressed("pickup"):
        $Player.devour({"attack":5})

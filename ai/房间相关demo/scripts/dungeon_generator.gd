
extends Node2D

var rooms = []

var room_list = [
    "SmallCell",
    "CrossRoom",
    "Arena",
    "Storage",
    "BoneRoom",
    "BloodRoom",
    "ChainRoom"
]

func _ready():
    generate()

func generate():
    print("Fantasy Dungeon Generated")
    for i in range(10):
        var room = room_list.pick_random()
        rooms.append(room)
        print("Create Room:", room)

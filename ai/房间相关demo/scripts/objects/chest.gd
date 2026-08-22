
extends StaticBody2D

var opened=false

func interact():
    if opened:
        return
    opened=true
    print("Treasure Found")

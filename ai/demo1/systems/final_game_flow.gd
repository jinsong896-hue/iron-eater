
extends Node

enum STATE{
START,
EXPLORE,
COMBAT,
LOOT,
DEVOUR,
BOSS,
CLEAR
}

var current_state=STATE.START


func set_state(value):
    current_state=value

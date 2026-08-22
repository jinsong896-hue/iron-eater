
extends PointLight2D

func _process(delta):
    energy = 2.5 + sin(Time.get_ticks_msec()/100.0)*0.2

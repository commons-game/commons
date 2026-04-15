## Health — shared health component for mobs and players.
## Attach as a child Node; set max_hp before adding to tree.
extends Node

signal died
signal damaged(amount: int, current: int, maximum: int)

var max_hp: int = 100
var current_hp: int = 100

func _init(p_max_hp: int = 100) -> void:
	max_hp = p_max_hp
	current_hp = p_max_hp

func take_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)
	emit_signal("damaged", amount, current_hp, max_hp)
	if current_hp == 0:
		emit_signal("died")

func is_alive() -> bool:
	return current_hp > 0

func heal(amount: int) -> void:
	current_hp = min(max_hp, current_hp + amount)

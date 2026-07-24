class_name Inventory
extends Node

signal salvage_changed(total: int)

var total_salvage: int = 0


func add_salvage(amount: int) -> void:
	total_salvage += amount
	salvage_changed.emit(total_salvage)


func spend_salvage(amount: int) -> bool:
	if amount > total_salvage:
		return false
	total_salvage -= amount
	salvage_changed.emit(total_salvage)
	return true

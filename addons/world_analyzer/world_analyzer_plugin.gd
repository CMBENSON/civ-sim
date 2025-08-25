@tool
extends EditorPlugin

var analyzer_panel

func _enter_tree():
	analyzer_panel = preload("res://addons/world_analyzer/world_analyzer_panel.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, analyzer_panel)

func _exit_tree():
	remove_control_from_docks(analyzer_panel)
	analyzer_panel.free()
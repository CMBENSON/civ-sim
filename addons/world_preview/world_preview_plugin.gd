@tool
extends EditorPlugin

var preview_panel_scene = preload("res://addons/world_preview/world_preview_panel.tscn")
var preview_panel_instance

func _enter_tree():
	# Initialization of the plugin goes here.
	preview_panel_instance = preview_panel_scene.instantiate()
	# Add the panel to the editor's main dock.
	add_control_to_dock(DOCK_SLOT_LEFT_UL, preview_panel_instance)

func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_control_from_docks(preview_panel_instance)
	preview_panel_instance.free()

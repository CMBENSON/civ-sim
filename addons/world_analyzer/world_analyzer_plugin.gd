# addons/world_analyzer/plugin.gd
@tool
extends EditorPlugin

var dock_panel: Control

func _enter_tree():
	# Create the enhanced world analyzer panel
	var WorldAnalyzerPanel = preload("res://addons/world_analyzer/world_analyzer_panel.gd")
	dock_panel = WorldAnalyzerPanel.new()
	dock_panel.name = "World Analyzer"
	
	# Add to dock
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock_panel)
	
	print("World Analyzer: Enhanced plugin loaded")

func _exit_tree():
	if dock_panel:
		remove_control_from_docks(dock_panel)
		dock_panel.queue_free()
		dock_panel = null
	
	print("World Analyzer: Plugin unloaded")

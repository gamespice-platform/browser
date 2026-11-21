@tool
extends EditorPlugin

## Editor entry point for GameSpice Browser. Registers inspector types only.
##
## No autoloads. A browser is a screen's node, and a process showing two lists —
## favourites and everything else — has two of them.

const _ICON := "res://addons/gs_browser/icon_placeholder.svg"

const _TYPES := [
	["GSBrowser", "Node", "res://addons/gs_browser/runtime/gs_browser.gd"],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for entry in _TYPES:
		remove_custom_type(entry[0])

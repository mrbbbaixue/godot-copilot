@tool
extends AcceptDialog

var plugin: EditorPlugin

# UI elements - now referenced from scene
@onready var base_url_input: LineEdit = %BaseUrlInput
@onready var api_key_input: LineEdit = %ApiKeyInput
@onready var model_input: LineEdit = %ModelInput
@onready var auto_apply_mode_checkbox: CheckBox = %AutoApplyModeCheckbox
@onready var help_label: Label = %HelpLabel


func _init() -> void:
	title = "Godot Copilot Settings"


func _ready() -> void:
	# Connect signals
	confirmed.connect(_on_confirmed)
	about_to_popup.connect(_on_about_to_popup)

	# Set help label color
	help_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))


func _on_about_to_popup() -> void:
	if plugin:
		base_url_input.text = plugin.get_setting("api", "base_url")
		api_key_input.text = plugin.get_setting("api", "api_key")
		model_input.text = plugin.get_setting("api", "model")
		auto_apply_mode_checkbox.button_pressed = plugin.get_setting("mode", "auto_apply_mode")


func _on_confirmed() -> void:
	if plugin:
		plugin.set_setting("api", "base_url", base_url_input.text)
		plugin.set_setting("api", "api_key", api_key_input.text)
		plugin.set_setting("api", "model", model_input.text)
		plugin.set_setting("mode", "auto_apply_mode", auto_apply_mode_checkbox.button_pressed)

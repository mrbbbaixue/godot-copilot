@tool
extends PanelContainer

## Input box component with Claude Code style layout
## Send button at bottom-right, settings button at bottom-left
## UI is defined in the scene file, this script only handles logic

signal send_pressed(text: String)
signal settings_pressed()
signal stop_pressed()

# Node references (automatically assigned from scene)
@onready var input_field: TextEdit = $VBoxContainer/TextEdit
@onready var send_button: Button = $VBoxContainer/HBoxContainer/HBoxContainer2/SendButton
@onready var stop_button: Button = $VBoxContainer/HBoxContainer/HBoxContainer2/StopButton
@onready var settings_button: Button = $VBoxContainer/HBoxContainer/HBoxContainer/SettingsButton

# Whether streaming is in progress (controls button visibility)
var is_streaming: bool = false:
	set(value):
		is_streaming = value
		_update_button_visibility()


# Plugin reference for accessing editor interface
var _plugin: EditorPlugin = null
var plugin: EditorPlugin:
	get:
		return _plugin
	set(value):
		_plugin = value
		_apply_editor_theme()


func _ready() -> void:
	# Apply editor theme
	_apply_editor_theme()

	# Connect button signals
	settings_button.pressed.connect(_on_settings_button_pressed)
	stop_button.pressed.connect(_on_stop_button_pressed)
	send_button.pressed.connect(_on_send_button_pressed)

	# Connect keyboard input signal
	input_field.gui_input.connect(_on_input_field_gui_input)


func _apply_editor_theme() -> void:
	# Only apply editor theme if running in the editor
	if not Engine.is_editor_hint():
		return

	# Try to get editor theme through plugin
	if _plugin and _plugin.has_method("get_editor_interface"):
		var editor_iface = _plugin.get_editor_interface()
		if editor_iface and editor_iface.has_method("get_editor_theme"):
			var editor_theme = editor_iface.get_editor_theme()
			if editor_theme:
				# Try to get TextEdit stylebox from editor theme
				var textedit_stylebox = editor_theme.get_stylebox("normal", "TextEdit")
				if textedit_stylebox:
					# Apply editor theme stylebox to input field
					input_field.add_theme_stylebox_override("normal", textedit_stylebox)
					input_field.add_theme_stylebox_override("focus", textedit_stylebox)

				# Also apply panel style if available
				var panel_stylebox = editor_theme.get_stylebox("panel", "PanelContainer")
				if panel_stylebox:
					add_theme_stylebox_override("panel", panel_stylebox)

				# Buttons should use default theme (no override)
				# This will make them use the editor's button theme


func _update_button_visibility() -> void:
	stop_button.visible = is_streaming
	send_button.visible = not is_streaming


func clear_input() -> void:
	input_field.text = ""


func get_input_text() -> String:
	return input_field.text.strip_edges()


func set_input_text(text: String) -> void:
	input_field.text = text


func _on_send_button_pressed() -> void:
	var text = get_input_text()
	if not text.is_empty():
		send_pressed.emit(text)
		clear_input()


func _on_settings_button_pressed() -> void:
	settings_pressed.emit()


func _on_stop_button_pressed() -> void:
	stop_pressed.emit()


func _on_input_field_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Enter or keypad Enter
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# Shift+Enter for newline, otherwise send (including Ctrl+Enter/Cmd+Enter for backward compatibility)
			if not event.shift_pressed:
				_on_send_button_pressed()
				get_viewport().set_input_as_handled()

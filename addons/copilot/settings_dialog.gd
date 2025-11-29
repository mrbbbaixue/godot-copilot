@tool
extends AcceptDialog

var plugin: EditorPlugin

# UI elements
var base_url_input: LineEdit
var api_key_input: LineEdit
var model_input: LineEdit


func _init() -> void:
	title = "Godot Copilot Settings"
	_setup_ui()


func _setup_ui() -> void:
	var container := VBoxContainer.new()
	add_child(container)
	
	# Base URL
	var url_label := Label.new()
	url_label.text = "API Base URL:"
	container.add_child(url_label)
	
	base_url_input = LineEdit.new()
	base_url_input.placeholder_text = "https://api.openai.com/v1"
	base_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(base_url_input)
	
	container.add_child(_create_spacer())
	
	# API Key
	var key_label := Label.new()
	key_label.text = "API Key:"
	container.add_child(key_label)
	
	api_key_input = LineEdit.new()
	api_key_input.placeholder_text = "sk-..."
	api_key_input.secret = true
	api_key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(api_key_input)
	
	container.add_child(_create_spacer())
	
	# Model
	var model_label := Label.new()
	model_label.text = "Model Name:"
	container.add_child(model_label)
	
	model_input = LineEdit.new()
	model_input.placeholder_text = "gpt-4o"
	model_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(model_input)
	
	container.add_child(_create_spacer())
	
	# Help text
	var help_label := Label.new()
	help_label.text = "You can use any OpenAI-compatible API endpoint."
	help_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	container.add_child(help_label)
	
	# Connect signals
	confirmed.connect(_on_confirmed)
	about_to_popup.connect(_on_about_to_popup)


func _create_spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	return spacer


func _on_about_to_popup() -> void:
	if plugin:
		base_url_input.text = plugin.get_setting("api", "base_url")
		api_key_input.text = plugin.get_setting("api", "api_key")
		model_input.text = plugin.get_setting("api", "model")


func _on_confirmed() -> void:
	if plugin:
		plugin.set_setting("api", "base_url", base_url_input.text)
		plugin.set_setting("api", "api_key", api_key_input.text)
		plugin.set_setting("api", "model", model_input.text)

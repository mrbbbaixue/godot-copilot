@tool
extends VBoxContainer

const LLMClient = preload("llm_client.gd")
const MarkdownParser = preload("markdown_parser.gd")
const DiffUtils = preload("diff_utils.gd")

var plugin: EditorPlugin

# UI elements
var chat_display: RichTextLabel
var input_field: TextEdit
var send_button: Button
var settings_button: Button
var clear_button: Button
var apply_code_button: Button
var apply_diff_button: Button
var read_code_button: Button
var read_scene_button: Button
var stop_button: Button

# API client
var llm_client: LLMClient

# Chat history
var messages := []
var current_response := ""

# Context tracking
var current_script_path := ""


func _init() -> void:
	custom_minimum_size = Vector2(300, 400)
	_setup_ui()


func _setup_ui() -> void:
	# Header with buttons
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)
	
	var title := Label.new()
	title.text = "AI Copilot"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	settings_button = Button.new()
	settings_button.text = "⚙"
	settings_button.tooltip_text = "Settings"
	settings_button.pressed.connect(_on_settings_pressed)
	header.add_child(settings_button)
	
	clear_button = Button.new()
	clear_button.text = "🗑"
	clear_button.tooltip_text = "Clear chat"
	clear_button.pressed.connect(_on_clear_pressed)
	header.add_child(clear_button)
	
	# Code action buttons - first row
	var code_actions := HBoxContainer.new()
	code_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(code_actions)
	
	read_code_button = Button.new()
	read_code_button.text = "📖 Read Code"
	read_code_button.tooltip_text = "Read current script and add to context"
	read_code_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	read_code_button.pressed.connect(_on_read_code_pressed)
	code_actions.add_child(read_code_button)
	
	read_scene_button = Button.new()
	read_scene_button.text = "🎬 Read Scene"
	read_scene_button.tooltip_text = "Read the scene file (.tscn) that uses this script"
	read_scene_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	read_scene_button.pressed.connect(_on_read_scene_pressed)
	code_actions.add_child(read_scene_button)
	
	# Code action buttons - second row
	var apply_actions := HBoxContainer.new()
	apply_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(apply_actions)
	
	apply_code_button = Button.new()
	apply_code_button.text = "✏ Apply Code"
	apply_code_button.tooltip_text = "Replace current script with AI-generated code"
	apply_code_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_code_button.pressed.connect(_on_apply_code_pressed)
	apply_code_button.disabled = true
	apply_actions.add_child(apply_code_button)
	
	apply_diff_button = Button.new()
	apply_diff_button.text = "📝 Apply Diff"
	apply_diff_button.tooltip_text = "Apply diff changes to current script"
	apply_diff_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_diff_button.pressed.connect(_on_apply_diff_pressed)
	apply_diff_button.disabled = true
	apply_actions.add_child(apply_diff_button)
	
	# Main content area with split container
	var split_container := VSplitContainer.new()
	split_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(split_container)
	
	# Chat display area
	chat_display = RichTextLabel.new()
	chat_display.bbcode_enabled = true
	chat_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_display.custom_minimum_size = Vector2(0, 200)
	chat_display.selection_enabled = true
	chat_display.scroll_following = true
	split_container.add_child(chat_display)
	
	# Input area container
	var input_container := VBoxContainer.new()
	input_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_container.custom_minimum_size = Vector2(0, 100)
	split_container.add_child(input_container)
	
	input_field = TextEdit.new()
	input_field.placeholder_text = "Type your message..."
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input_container.add_child(input_field)
	
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	input_container.add_child(button_row)
	
	stop_button = Button.new()
	stop_button.text = "Stop"
	stop_button.pressed.connect(_on_stop_pressed)
	stop_button.visible = false
	button_row.add_child(stop_button)
	
	send_button = Button.new()
	send_button.text = "Send"
	send_button.pressed.connect(_on_send_pressed)
	# Style the send button
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.6, 1.0) # Accent color (blue-ish)
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_right = 4
	style_box.corner_radius_bottom_left = 4
	send_button.add_theme_stylebox_override("normal", style_box)
	button_row.add_child(send_button)
	
	# Initialize LLM client
	llm_client = LLMClient.new()
	llm_client.chunk_received.connect(_on_llm_chunk)
	llm_client.error_occurred.connect(_on_llm_error)
	llm_client.request_finished.connect(_on_llm_finished)
	
	# Update display
	_update_chat_display()


func _process(_delta: float) -> void:
	pass


func _exit_tree() -> void:
	if llm_client:
		llm_client.stop_stream()


func _on_stop_pressed() -> void:
	if llm_client:
		llm_client.stop_stream()


func _on_settings_pressed() -> void:
	if plugin:
		plugin.show_settings()


func _on_clear_pressed() -> void:
	messages.clear()
	current_response = ""
	current_script_path = ""
	_update_chat_display()
	apply_code_button.disabled = true
	apply_diff_button.disabled = true


func _on_read_code_pressed() -> void:
	if not plugin:
		return
	
	var code = plugin.get_current_code()
	if code.is_empty():
		_add_system_message("No script is currently open in the editor.")
		return
	
	var script = plugin.get_current_script()
	var script_name := "Unknown"
	var script_path := ""
	if script:
		script_name = script.resource_path.get_file()
		script_path = script.resource_path
	
	# Store the current script path for diff application
	current_script_path = script_path
	
	# Add code to context
	var code_message := "Current script (%s):\n```gdscript\n%s\n```" % [script_name, code]
	_add_user_message(code_message)
	_add_system_message("Code from '%s' has been added to the conversation context." % script_name)
	
	# Auto-read associated scene if exists
	if not script_path.is_empty():
		var scene_path := plugin.find_scene_for_script(script_path)
		if not scene_path.is_empty():
			_add_system_message("Found associated scene: %s (use 'Read Scene' to add to context)" % scene_path.get_file())


func _on_read_scene_pressed() -> void:
	if not plugin:
		return
	
	var script_path := plugin.get_current_script_path()
	if script_path.is_empty():
		_add_system_message("No script is currently open in the editor.")
		return
	
	# Find the scene file that uses this script
	var scene_path := plugin.find_scene_for_script(script_path)
	
	if scene_path.is_empty():
		_add_system_message("No scene file found that references this script.")
		return
	
	var scene_content := plugin.read_scene_content(scene_path)
	if scene_content.is_empty():
		_add_system_message("Failed to read scene file: %s" % scene_path)
		return
	
	# Add scene to context
	var scene_message := "Scene file (%s):\n```tscn\n%s\n```" % [scene_path.get_file(), scene_content]
	_add_user_message(scene_message)
	_add_system_message("Scene '%s' has been added to the conversation context." % scene_path.get_file())


func _on_apply_code_pressed() -> void:
	if not plugin or current_response.is_empty():
		return
	
	var code := _extract_code_from_response(current_response)
	if code.is_empty():
		_add_system_message("No code block found in the last response.")
		return
	
	plugin.set_current_code(code)
	_add_system_message("Code has been applied to the current script.")


func _on_apply_diff_pressed() -> void:
	if not plugin or current_response.is_empty():
		return
	
	var current_code := plugin.get_current_code()
	if current_code.is_empty():
		_add_system_message("No script is currently open in the editor.")
		return
	
	# Check if response contains diff format
	if not DiffUtils.contains_diff(current_response):
		_add_system_message("No diff found in the last response. Try using 'Apply Code' instead.")
		return
	
	# Apply the diff
	var result := DiffUtils.apply_diff(current_code, current_response)
	
	if result["success"]:
		plugin.set_current_code(result["code"])
		_add_system_message("Diff has been applied to the current script.")
	else:
		_add_system_message("Failed to apply diff: %s" % result["error"])


func _extract_code_from_response(response: String) -> String:
	# Look for code blocks in markdown format
	var regex := RegEx.new()
	regex.compile("```(?:gdscript|gd)?\\s*\\n([\\s\\S]*?)\\n```")
	var result := regex.search(response)
	if result:
		return result.get_string(1)
	
	# Try without language specifier
	regex.compile("```\\s*\\n([\\s\\S]*?)\\n```")
	result = regex.search(response)
	if result:
		return result.get_string(1)
	
	return ""


func _on_send_pressed() -> void:
	var user_input := input_field.text.strip_edges()
	if user_input.is_empty():
		return
	
	_add_user_message(user_input)
	input_field.text = ""
	
	_send_to_api()


func _add_user_message(content: String) -> void:
	messages.append({"role": "user", "content": content})
	_update_chat_display()


func _add_assistant_message(content: String) -> void:
	messages.append({"role": "assistant", "content": content})
	current_response = content
	_update_chat_display()
	apply_code_button.disabled = _extract_code_from_response(content).is_empty()


func _add_system_message(content: String) -> void:
	chat_display.append_text("\n[color=yellow][System] %s[/color]\n" % content)


func _update_chat_display() -> void:
	chat_display.clear()
	chat_display.append_text("[b]Chat with AI[/b]\n")
	chat_display.append_text("─".repeat(30) + "\n")
	
	for msg in messages:
		if msg["role"] == "user":
			chat_display.append_text("\n[color=cyan][b]You:[/b][/color]\n")
			chat_display.append_text(_format_message(msg["content"]) + "\n")
		elif msg["role"] == "assistant":
			chat_display.append_text("\n[color=green][b]AI:[/b][/color]\n")
			chat_display.append_text(_format_message(msg["content"]) + "\n")
	
	if llm_client and llm_client.is_streaming() and not current_response.is_empty():
		chat_display.append_text("\n[color=green][b]AI:[/b][/color]\n")
		chat_display.append_text(_format_message(current_response) + "\n")


func _format_message(content: String) -> String:
	return MarkdownParser.parse(content)


func _send_to_api() -> void:
	if not plugin:
		_add_system_message("Plugin not initialized.")
		return
	
	var base_url: String = plugin.get_setting("api", "base_url")
	var api_key: String = plugin.get_setting("api", "api_key")
	var model: String = plugin.get_setting("api", "model")
	var use_full_code_mode: bool = plugin.get_setting("mode", "full_code_mode")
	
	if api_key.is_empty():
		_add_system_message("API key not configured. Please go to Settings.")
		return
	
	# Setup UI for streaming
	send_button.visible = false
	stop_button.visible = true
	
	current_response = ""
	llm_client.start_stream(base_url, api_key, model, messages, use_full_code_mode)


func _on_llm_chunk(chunk: String) -> void:
	current_response += chunk
	_update_chat_display()


func _on_llm_error(message: String) -> void:
	send_button.visible = true
	stop_button.visible = false
	_add_system_message(message)


func _on_llm_finished(full_response: String) -> void:
	send_button.visible = true
	stop_button.visible = false
	
	if not full_response.is_empty():
		current_response = full_response
		messages.append({"role": "assistant", "content": full_response})
		
		# Update button states based on response content
		apply_code_button.disabled = _extract_code_from_response(full_response).is_empty()
		apply_diff_button.disabled = not DiffUtils.contains_diff(full_response)
		
		_update_chat_display()
	else:
		_add_system_message("Empty response from AI.")

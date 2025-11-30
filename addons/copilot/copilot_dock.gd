@tool
extends VBoxContainer

const LLMClient = preload("llm_client.gd")
const MarkdownParser = preload("markdown_parser.gd")
const DiffUtils = preload("diff_utils.gd")
const ChatMessage = preload("chat_message.gd")
const SystemPrompts = preload("system_prompts.gd")

var plugin: EditorPlugin

# UI elements
var chat_scroll: ScrollContainer
var chat_container: VBoxContainer
var input_field: TextEdit
var send_button: Button
var settings_button: Button
var clear_button: Button
var stop_button: Button

# API client
var llm_client: LLMClient

# Chat history
var messages := []
var current_response := ""

# Streaming message widget
var streaming_message: ChatMessage = null


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
	
	# Main content area with split container
	var split_container := VSplitContainer.new()
	split_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(split_container)
	
	# Chat display area with scroll container
	chat_scroll = ScrollContainer.new()
	chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_scroll.custom_minimum_size = Vector2(0, 200)
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split_container.add_child(chat_scroll)
	
	# Chat container for messages
	chat_container = VBoxContainer.new()
	chat_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_container.add_theme_constant_override("separation", 8)
	chat_scroll.add_child(chat_container)
	
	# Add header to chat container
	var chat_header := Label.new()
	chat_header.text = "💬 Chat with AI"
	chat_header.add_theme_font_size_override("font_size", 16)
	chat_header.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	chat_container.add_child(chat_header)
	
	var separator := HSeparator.new()
	chat_container.add_child(separator)
	
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
	_clear_chat_display()


func _clear_chat_display() -> void:
	# Remove all message widgets except header and separator
	for child in chat_container.get_children():
		if child is ChatMessage:
			child.queue_free()
	streaming_message = null


func _on_send_pressed() -> void:
	var user_input := input_field.text.strip_edges()
	if user_input.is_empty():
		return
	
	_add_user_message(user_input)
	input_field.text = ""
	
	_send_to_api()


func _add_user_message(content: String) -> void:
	messages.append({"role": "user", "content": content})
	_add_message_widget(ChatMessage.MessageRole.USER, content)


func _add_assistant_message(content: String) -> void:
	messages.append({"role": "assistant", "content": content})
	current_response = content
	_add_message_widget(ChatMessage.MessageRole.ASSISTANT, content)


func _add_system_message(content: String) -> void:
	_add_message_widget(ChatMessage.MessageRole.SYSTEM, content)


func _add_message_widget(role: ChatMessage.MessageRole, content: String) -> void:
	var msg_widget := ChatMessage.new()
	msg_widget.setup(role, content)
	
	# Connect apply signal for assistant messages
	if role == ChatMessage.MessageRole.ASSISTANT:
		msg_widget.apply_code_requested.connect(_on_apply_code_requested)
	
	chat_container.add_child(msg_widget)
	_scroll_to_bottom()


func _scroll_to_bottom() -> void:
	# Delay scroll to allow layout to update
	await get_tree().process_frame
	if chat_scroll:
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)


func _get_context_prompt() -> String:
	if not plugin:
		return ""
	
	# Get current scene
	var scene_path := plugin.get_current_scene_path()
	var scene_content := plugin.get_current_scene_content()
	
	# Get current script
	var script_path := plugin.get_current_script_path()
	var script_content := plugin.get_current_code()
	
	# Get file tree
	var file_tree := plugin.get_file_tree()
	
	return SystemPrompts.build_context_prompt(scene_path, scene_content, script_path, script_content, file_tree)


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
	
	# Get context prompt with current scene, script, and file tree
	var context_prompt := _get_context_prompt()
	
	# Setup UI for streaming
	send_button.visible = false
	stop_button.visible = true
	
	current_response = ""
	llm_client.start_stream(base_url, api_key, model, messages, use_full_code_mode, context_prompt)


func _on_llm_chunk(chunk: String) -> void:
	current_response += chunk
	
	# Create or update streaming message widget
	if streaming_message == null:
		streaming_message = ChatMessage.new()
		streaming_message.setup(ChatMessage.MessageRole.ASSISTANT, current_response)
		streaming_message.apply_code_requested.connect(_on_apply_code_requested)
		chat_container.add_child(streaming_message)
	else:
		streaming_message.set_streaming_content(current_response)
	
	_scroll_to_bottom()


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
		
		# Update the streaming message with final content
		if streaming_message:
			streaming_message.set_streaming_content(full_response)
	else:
		_add_system_message("Empty response from AI.")
	
	streaming_message = null


func _on_apply_code_requested(file_path: String, code: String, is_diff: bool) -> void:
	if not plugin:
		_add_system_message("Plugin not initialized.")
		return
	
	var result: Dictionary
	if is_diff:
		result = plugin.apply_diff_to_file(file_path, code)
	else:
		result = plugin.apply_code_to_file(file_path, code)
	
	if result["success"]:
		if result.get("created", false):
			_add_system_message("✅ Created new file: %s" % file_path)
		else:
			_add_system_message("✅ Applied changes to: %s" % file_path)
	else:
		_add_system_message("❌ Failed to apply changes to %s: %s" % [file_path, result["error"]])

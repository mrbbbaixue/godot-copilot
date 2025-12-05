@tool
extends VBoxContainer

const LLMClient = preload("res://addons/copilot/scripts/llm_client.gd")
const MarkdownParser = preload("res://addons/copilot/scripts/markdown_parser.gd")
const DiffUtils = preload("res://addons/copilot/scripts/diff_utils.gd")
const SystemPrompts = preload("res://addons/copilot/scripts/system_prompts.gd")
const ChatMessageScene = preload("res://addons/copilot/scenes/chat_message.tscn")
const ChatMessage = preload("res://addons/copilot/scenes/chat_message.gd")
const InputBox = preload("res://addons/copilot/scenes/input_box.tscn")

var plugin: EditorPlugin

# UI elements
var chat_scroll: ScrollContainer
var chat_container: VBoxContainer
var input_box: Control  # InputBox instance
var clear_button: Button

# API client
var llm_client: LLMClient

# Chat history
var messages := []
var current_response := ""

# Context tracking
var current_script_path := ""

# Streaming message widget
var streaming_message: ChatMessage = null


func _init() -> void:
	custom_minimum_size = Vector2(300, 400)
	_setup_ui()


func _setup_ui() -> void:
	# Set dock background color to editor theme dark variant
	var bg_color := Color(0.1, 0.1, 0.1)  # Default dark gray
	if plugin:
		var editor_settings = plugin.get_editor_interface().get_editor_settings()
		var base_color = editor_settings.get_setting("interface/theme/base_color")
		if base_color is Color:
			# Darken the base color for background
			bg_color = base_color.darkened(0.7)

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)

	# Header with clear chat button only
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)

	# Spacer to push button to the right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

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
	
	
	# Input box (using separate scene)
	input_box = InputBox.instantiate()
	input_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_box.custom_minimum_size = Vector2(0, 100)
	split_container.add_child(input_box)

	# Connect signals from input box
	input_box.send_pressed.connect(_on_send_pressed)
	input_box.settings_pressed.connect(_on_settings_pressed)
	input_box.stop_pressed.connect(_on_stop_pressed)
	
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
	current_script_path = ""
	_clear_chat_display()


func _clear_chat_display() -> void:
	# Remove all message widgets except header and separator
	for child in chat_container.get_children():
		if child is ChatMessage:
			child.queue_free()
	streaming_message = null


## Build the automatic context string with current scene, code, and file tree
func _build_auto_context() -> String:
	if not plugin:
		return ""
	
	var context_parts := []
	
	# 1. File tree structure
	var file_tree = plugin.get_file_tree()
	if not file_tree.is_empty():
		context_parts.append("## Project File Structure:\n```\n%s```" % file_tree)
	
	# 2. Current open scene
	var scene_path = plugin.get_current_scene_path()
	if not scene_path.is_empty():
		var scene_content = plugin.read_scene_content(scene_path)
		if not scene_content.is_empty():
			context_parts.append("## Currently Open Scene (%s):\n```tscn\n%s\n```" % [scene_path, scene_content])
	
	# 3. Current script in code editor
	var script = plugin.get_current_script()
	var code = plugin.get_current_code()
	if script and not code.is_empty():
		var script_path = script.resource_path
		current_script_path = script_path
		context_parts.append("## Currently Open Script (%s):\n```gdscript\n%s\n```" % [script_path, code])
	
	if context_parts.is_empty():
		return ""
	
	return "# Current Project Context\n\n" + "\n\n".join(context_parts)


func _on_send_pressed(text: String) -> void:
	var user_input := text.strip_edges()
	if user_input.is_empty():
		return

	# Build auto context for the first message or if context has changed significantly
	var full_message := user_input
	if messages.is_empty():
		var auto_context := _build_auto_context()
		if not auto_context.is_empty():
			full_message = auto_context + "\n\n---\n\n## User Request:\n" + user_input
			_add_system_message("📂 Auto-included: project file tree, current scene, and current script")

	# Add full message (with context) to API messages, but only show user input in UI
	_add_user_message(full_message, user_input)

	_send_to_api()


func _add_user_message(api_content: String, display_content: String = "") -> void:
	# api_content: full message sent to API (may include auto-context)
	# display_content: message shown in UI (just user input, no context)
	messages.append({"role": "user", "content": api_content})
	var show_content := display_content if not display_content.is_empty() else api_content
	_add_message_widget(ChatMessage.MessageRole.USER, show_content)


func _add_system_message(content: String) -> void:
	_add_message_widget(ChatMessage.MessageRole.SYSTEM, content)


func _add_message_widget(role: ChatMessage.MessageRole, content: String) -> void:
	var msg_widget := ChatMessageScene.instantiate()
	msg_widget.setup(role, content)
	
	# Connect apply signals for assistant messages
	if role == ChatMessage.MessageRole.ASSISTANT:
		msg_widget.apply_diff_requested.connect(_on_apply_diff_to_file)
		msg_widget.apply_code_requested.connect(_on_apply_code_to_file)
	
	chat_container.add_child(msg_widget)
	_scroll_to_bottom()


## Handle apply diff request from chat message
func _on_apply_diff_to_file(file_path: String, diff_text: String) -> void:
	if not plugin:
		_add_system_message("Plugin not initialized.")
		return
	
	# Read original file content
	var original_content = plugin.read_file_content(file_path)
	if original_content.is_empty() and not (diff_text.contains("--- /dev/null") or diff_text.contains("--- a/dev/null")):
		_add_system_message("Cannot read file: %s" % file_path)
		return
	
	# Apply the diff
	var result := DiffUtils.apply_diff(original_content, diff_text)
	
	if result["success"]:
		# Write the modified content back to the file
		if plugin.write_file_content(file_path, result["code"]):
			_add_system_message("✅ Diff applied to %s" % file_path)
			# If this is the current open script, also update the editor
			if file_path == current_script_path or file_path == plugin.get_current_script_path():
				plugin.set_current_code(result["code"])
		else:
			_add_system_message("❌ Failed to write to file: %s" % file_path)
	else:
		_add_system_message("❌ Failed to apply diff: %s" % result["error"])


## Handle apply code request from chat message
func _on_apply_code_to_file(file_path: String, code: String) -> void:
	if not plugin:
		_add_system_message("Plugin not initialized.")
		return
	
	# Write the code to the file
	if plugin.write_file_content(file_path, code):
		_add_system_message("✅ Code applied to %s" % file_path)
		# If this is the current open script, also update the editor
		if file_path == current_script_path or file_path == plugin.get_current_script_path():
			plugin.set_current_code(code)
	else:
		_add_system_message("❌ Failed to write to file: %s" % file_path)


func _scroll_to_bottom() -> void:
	# Delay scroll to allow layout to update
	await get_tree().process_frame
	if chat_scroll:
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)


func _send_to_api() -> void:
	if not plugin:
		_add_system_message("Plugin not initialized.")
		return
	
	var base_url: String = plugin.get_setting("api", "base_url")
	var api_key: String = plugin.get_setting("api", "api_key")
	var model: String = plugin.get_setting("api", "model")
	var system_prompt: String = SystemPrompts.get_system_prompt()
	
	if api_key.is_empty():
		_add_system_message("API key not configured. Please go to Settings.")
		return
	
	# Setup UI for streaming
	if input_box:
		input_box.is_streaming = true
	
	current_response = ""
	llm_client.start_stream(base_url, api_key, model, messages, system_prompt)


func _on_llm_chunk(chunk: String) -> void:
	current_response += chunk
	
	# Create or update streaming message widget
	if streaming_message == null:
		streaming_message = ChatMessageScene.instantiate()
		streaming_message.setup(ChatMessage.MessageRole.ASSISTANT, current_response)
		streaming_message.apply_diff_requested.connect(_on_apply_diff_to_file)
		streaming_message.apply_code_requested.connect(_on_apply_code_to_file)
		chat_container.add_child(streaming_message)
	else:
		streaming_message.set_streaming_content(current_response)
	
	_scroll_to_bottom()


func _on_llm_error(message: String) -> void:
	if input_box:
		input_box.is_streaming = false
	_add_system_message(message)


func _on_llm_finished(full_response: String) -> void:
	if input_box:
		input_box.is_streaming = false

	if not full_response.is_empty():
		current_response = full_response
		messages.append({"role": "assistant", "content": full_response})

		# Update the streaming message with final content and connect signals
		if streaming_message:
			streaming_message.set_streaming_content(full_response)
			streaming_message.apply_diff_requested.connect(_on_apply_diff_to_file)
			streaming_message.apply_code_requested.connect(_on_apply_code_to_file)

			# Auto-apply changes if enabled
			if plugin and plugin.get_setting("mode", "auto_apply_mode"):
				_auto_apply_changes(full_response)
	else:
		_add_system_message("Empty response from AI.")

	streaming_message = null


## Auto-apply changes from AI response when auto-apply mode is enabled
func _auto_apply_changes(content: String) -> void:
	if not plugin:
		return

	# Extract diffs and code blocks from the content
	var diffs := DiffUtils.extract_all_diffs(content)
	var code_blocks := DiffUtils.extract_code_blocks_with_paths(content)

	# Apply all diffs
	for diff_info: Dictionary in diffs:
		var file_path: String = diff_info["path"]
		var diff_text: String = diff_info["diff"]
		var is_new_file: bool = diff_info["is_new_file"]

		# Read original file content (if not a new file)
		var original_content := ""
		if not is_new_file:
			original_content = plugin.read_file_content(file_path)
			if original_content.is_empty():
				_add_system_message("⚠ Skipping diff for %s (cannot read file)" % file_path)
				continue

		# Apply the diff
		var result := DiffUtils.apply_diff(original_content, diff_text)

		if result["success"]:
			# Write the modified content back to the file
			if plugin.write_file_content(file_path, result["code"]):
				_add_system_message("✅ Auto-applied diff to %s" % file_path)
				# If this is the current open script, also update the editor
				if file_path == current_script_path or file_path == plugin.get_current_script_path():
					plugin.set_current_code(result["code"])
			else:
				_add_system_message("❌ Failed to write to file: %s" % file_path)
		else:
			_add_system_message("❌ Failed to auto-apply diff to %s: %s" % [file_path, result["error"]])

	# Apply all code blocks
	for block_info: Dictionary in code_blocks:
		var file_path: String = block_info["path"]
		var code: String = block_info["code"]

		# Write the code to the file
		if plugin.write_file_content(file_path, code):
			_add_system_message("✅ Auto-applied code to %s" % file_path)
			# If this is the current open script, also update the editor
			if file_path == current_script_path or file_path == plugin.get_current_script_path():
				plugin.set_current_code(code)
		else:
			_add_system_message("❌ Failed to write to file: %s" % file_path)

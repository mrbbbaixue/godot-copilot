@tool
extends VBoxContainer
## Main Copilot dock controller - orchestrates all components
##
## Responsibilities:
## - Initializes and coordinates all component managers
## - Connects signals between components
## - Handles high-level user interactions
## - Manages dock appearance and lifecycle

# Component dependencies
const ChatManager = preload("res://addons/copilot/scripts/chat_manager.gd")
const MessageManager = preload("res://addons/copilot/scripts/message_manager.gd")
const ApiManager = preload("res://addons/copilot/scripts/api_manager.gd")
const ContextBuilder = preload("res://addons/copilot/scripts/context_builder.gd")
const FileApplier = preload("res://addons/copilot/scripts/file_applier.gd")

# UI elements (scene references)
var input_box: Control  # InputBox instance from scene

# Component instances
var chat_manager: ChatManager
var message_manager: MessageManager
var api_manager: ApiManager
var context_builder: ContextBuilder
var file_applier: FileApplier

# External dependencies
var plugin: EditorPlugin

# State
var _is_initialized := false


func _init() -> void:
	## Set minimum size for the dock
	custom_minimum_size = Vector2(300, 400)


func _ready() -> void:
	## Initialize the dock when added to scene tree
	# Get scene references
	input_box = $MainSplitContainer/InputBoxInstance

	# Initialize components
	_initialize_components()

	# Connect signals between components
	_setup_signal_connections()

	# Setup visual appearance
	_setup_background()

	_is_initialized = true


func _exit_tree() -> void:
	## Clean up when dock is removed
	if api_manager:
		api_manager.stop_streaming()


#region Component Management
## Initialize all component managers
func _initialize_components() -> void:
	# Core managers (don't require plugin)
	message_manager = MessageManager.new()

	chat_manager = ChatManager.new()
	chat_manager.setup(
		$Header/ClearButton,
		$MainSplitContainer/ChatScrollContainer,
		$MainSplitContainer/ChatScrollContainer/ChatContainer
	)

	# Plugin-dependent managers
	if plugin:
		api_manager = ApiManager.new()
		api_manager.setup(plugin)

		context_builder = ContextBuilder.new()
		context_builder.setup(plugin)

		file_applier = FileApplier.new()
		file_applier.setup(plugin)


## Connect all component signals
func _setup_signal_connections() -> void:
	# Input box signals
	input_box.send_pressed.connect(_on_send_pressed)
	input_box.settings_pressed.connect(_on_settings_pressed)
	input_box.stop_pressed.connect(_on_stop_pressed)

	# Chat manager signals
	chat_manager.apply_diff_requested.connect(_on_apply_diff_requested)
	chat_manager.apply_code_requested.connect(_on_apply_code_requested)
	chat_manager.chat_cleared.connect(_on_chat_cleared)

	# API manager signals
	if api_manager:
		api_manager.chunk_received.connect(_on_api_chunk_received)
		api_manager.error_occurred.connect(_on_api_error_occurred)
		api_manager.request_finished.connect(_on_api_request_finished)
		api_manager.streaming_started.connect(_on_api_streaming_started)
		api_manager.streaming_stopped.connect(_on_api_streaming_stopped)

	# File applier signals
	if file_applier:
		file_applier.file_applied.connect(_on_file_applied)
#endregion


#region Signal Handlers
## Handle send button press from input box
func _on_send_pressed(text: String) -> void:
	var user_input := text.strip_edges()
	if user_input.is_empty():
		return

	# Build auto context for the first message
	var full_message := user_input
	if message_manager.is_empty():
		var auto_context := _build_auto_context()
		if not auto_context.is_empty():
			full_message = auto_context + "\n\n---\n\n## User Request:\n" + user_input
			_add_system_message("📂 Auto-included: project file tree, current scene, and current script")

			# Update file applier with current script path from context
			if context_builder and file_applier:
				var script_path = context_builder.get_current_script_path()
				if not script_path.is_empty():
					file_applier.set_current_script_path(script_path)

	# Add user message to history and display
	_add_user_message(full_message, user_input)

	# Send to API
	_send_to_api()


## Handle settings button press
func _on_settings_pressed() -> void:
	if plugin:
		plugin.show_settings()


## Handle stop button press
func _on_stop_pressed() -> void:
	if api_manager:
		api_manager.stop_streaming()


## Handle API chunk received
func _on_api_chunk_received(chunk: String) -> void:
	message_manager.append_to_current_response(chunk)
	chat_manager.update_streaming_content(message_manager.get_current_response())


## Handle API error
func _on_api_error_occurred(message: String) -> void:
	_add_system_message(message)


## Handle API request finished
func _on_api_request_finished(full_response: String) -> void:
	if not full_response.is_empty():
		message_manager.set_current_response(full_response)
		message_manager.add_assistant_message(full_response)
		chat_manager.finalize_streaming_message(full_response)

		# Auto-apply changes if enabled
		if plugin and plugin.get_setting("mode", "auto_apply_mode"):
			_auto_apply_changes(full_response)
	else:
		_add_system_message("Empty response from AI.")


## Handle API streaming started
func _on_api_streaming_started() -> void:
	if input_box:
		input_box.is_streaming = true


## Handle API streaming stopped
func _on_api_streaming_stopped() -> void:
	if input_box:
		input_box.is_streaming = false


## Handle apply diff request
func _on_apply_diff_requested(file_path: String, diff_text: String) -> void:
	if file_applier:
		file_applier.apply_diff(file_path, diff_text)


## Handle apply code request
func _on_apply_code_requested(file_path: String, code: String) -> void:
	if file_applier:
		file_applier.apply_code(file_path, code)


## Handle file application result
func _on_file_applied(file_path: String, success: bool, message: String) -> void:
	if not success or message:
		_add_system_message(message)


## Handle chat cleared signal
func _on_chat_cleared() -> void:
	# Clear cached script paths
	if context_builder:
		context_builder.clear_cached_path()
	if file_applier:
		file_applier.set_current_script_path("")
#endregion


#region Helper Methods
## Build automatic context from current project state
func _build_auto_context() -> String:
	if context_builder:
		return context_builder.build_auto_context()
	return ""


## Add user message to history and display
func _add_user_message(api_content: String, display_content: String = "") -> void:
	message_manager.add_user_message(api_content)
	var show_content := display_content if not display_content.is_empty() else api_content
	chat_manager.add_message(ChatManager.MessageRole.USER, show_content)


## Add system message to display
func _add_system_message(content: String) -> void:
	chat_manager.add_message(ChatManager.MessageRole.SYSTEM, content)


## Send current messages to API
func _send_to_api() -> void:
	if api_manager:
		api_manager.send_messages(message_manager.get_messages())


## Auto-apply changes from AI response
func _auto_apply_changes(content: String) -> void:
	if file_applier:
		file_applier.auto_apply_changes(content)


## Setup dock background color based on editor theme
func _setup_background() -> void:
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
#endregion
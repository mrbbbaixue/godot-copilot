@tool
class_name ChatManager
## Manages chat UI display, message widgets, and scrolling

const ChatMessageScene = preload("res://addons/copilot/scenes/chat_message.tscn")
const ChatMessage = preload("res://addons/copilot/scenes/chat_message.gd")

# Message role enum (mirrors ChatMessage.MessageRole for decoupling)
enum MessageRole { USER, ASSISTANT, SYSTEM }

signal message_added(role: MessageRole, content: String)
signal chat_cleared
signal apply_diff_requested(file_path: String, diff_text: String)
signal apply_code_requested(file_path: String, code: String)

# UI references
var chat_scroll: ScrollContainer
var chat_container: VBoxContainer
var clear_button: Button

# State
var streaming_message: ChatMessage = null
var _is_initialized := false

## Initialize with UI references
func setup(ui_clear_button: Button, ui_chat_scroll: ScrollContainer, ui_chat_container: VBoxContainer) -> void:
	clear_button = ui_clear_button
	chat_scroll = ui_chat_scroll
	chat_container = ui_chat_container

	clear_button.pressed.connect(_on_clear_pressed)
	_is_initialized = true

## Add a message widget to the chat display
func add_message(role: MessageRole, content: String, is_streaming: bool = false) -> void:
	if not _is_initialized:
		push_error("ChatManager not initialized. Call setup() first.")
		return

	if is_streaming:
		_update_streaming_message(content, role)
	else:
		_add_static_message(role, content)

	message_added.emit(role, content)
	_scroll_to_bottom()

## Update streaming message content
func update_streaming_content(content: String) -> void:
	if streaming_message:
		streaming_message.set_streaming_content(content)
		_scroll_to_bottom()

## Finalize streaming message and connect apply signals
func finalize_streaming_message(content: String) -> void:
	if streaming_message:
		streaming_message.set_streaming_content(content)
		streaming_message.apply_diff_requested.connect(_on_apply_diff_requested)
		streaming_message.apply_code_requested.connect(_on_apply_code_requested)
		streaming_message = null

## Clear all messages from the chat display
func clear_display() -> void:
	if not _is_initialized:
		return

	for child in chat_container.get_children():
		if child is ChatMessage:
			child.queue_free()
	streaming_message = null
	chat_cleared.emit()

# Private methods
func _add_static_message(role: MessageRole, content: String) -> void:
	var msg_widget := ChatMessageScene.instantiate()
	msg_widget.setup(role, content)

	# Connect apply signals for assistant messages
	if role == MessageRole.ASSISTANT:
		msg_widget.apply_diff_requested.connect(_on_apply_diff_requested)
		msg_widget.apply_code_requested.connect(_on_apply_code_requested)

	chat_container.add_child(msg_widget)

func _update_streaming_message(content: String, role: MessageRole = MessageRole.ASSISTANT) -> void:
	if streaming_message == null:
		streaming_message = ChatMessageScene.instantiate()
		streaming_message.setup(role, content)
		chat_container.add_child(streaming_message)
	else:
		streaming_message.set_streaming_content(content)

func _scroll_to_bottom() -> void:
	# Delay scroll to allow layout to update
	await get_tree().process_frame
	if chat_scroll:
		chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

func _on_clear_pressed() -> void:
	clear_display()

func _on_apply_diff_requested(file_path: String, diff_text: String) -> void:
	apply_diff_requested.emit(file_path, diff_text)

func _on_apply_code_requested(file_path: String, code: String) -> void:
	apply_code_requested.emit(file_path, code)
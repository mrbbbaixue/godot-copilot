@tool
class_name MessageManager
## Manages chat message history and state

signal messages_updated(messages: Array)
signal messages_cleared

var messages := []
var _current_response := ""

## Add a user message to history
func add_user_message(api_content: String, display_content: String = "") -> Dictionary:
	var message = {"role": "user", "content": api_content}
	messages.append(message)
	messages_updated.emit(messages)
	return message

## Add an assistant message to history
func add_assistant_message(content: String) -> Dictionary:
	var message = {"role": "assistant", "content": content}
	messages.append(message)
	messages_updated.emit(messages)
	return message

## Get all messages
func get_messages() -> Array:
	return messages.duplicate()

## Clear all messages
func clear_messages() -> void:
	messages.clear()
	_current_response = ""
	messages_cleared.emit()

## Check if messages are empty
func is_empty() -> bool:
	return messages.is_empty()

## Get current streaming response
func get_current_response() -> String:
	return _current_response

## Append to current streaming response
func append_to_current_response(chunk: String) -> void:
	_current_response += chunk

## Set current response (for finalization)
func set_current_response(response: String) -> void:
	_current_response = response

## Clear current response
func clear_current_response() -> void:
	_current_response = ""

## Get count of messages
func get_message_count() -> int:
	return messages.size()
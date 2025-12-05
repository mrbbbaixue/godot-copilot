@tool
class_name ApiManager
## Manages API communication with LLM service

const LLMClient = preload("res://addons/copilot/scripts/llm_client.gd")
const SystemPrompts = preload("res://addons/copilot/scripts/system_prompts.gd")

signal chunk_received(chunk: String)
signal error_occurred(message: String)
signal request_finished(full_response: String)
signal streaming_started
signal streaming_stopped

var _llm_client: LLMClient
var _plugin: EditorPlugin
var _is_streaming := false

## Initialize with the main plugin instance
func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_llm_client = LLMClient.new()
	_llm_client.chunk_received.connect(_on_chunk_received)
	_llm_client.error_occurred.connect(_on_error_occurred)
	_llm_client.request_finished.connect(_on_request_finished)

## Send messages to API
func send_messages(messages: Array, include_system_prompt: bool = true) -> void:
	if not _plugin:
		error_occurred.emit("Plugin not initialized.")
		return

	var base_url: String = _plugin.get_setting("api", "base_url")
	var api_key: String = _plugin.get_setting("api", "api_key")
	var model: String = _plugin.get_setting("api", "model")
	var system_prompt: String = SystemPrompts.get_system_prompt() if include_system_prompt else ""

	if api_key.is_empty():
		error_occurred.emit("API key not configured. Please go to Settings.")
		return

	_is_streaming = true
	streaming_started.emit()
	_llm_client.start_stream(base_url, api_key, model, messages, system_prompt)

## Stop current streaming request
func stop_streaming() -> void:
	if _llm_client:
		_llm_client.stop_stream()
	_is_streaming = false
	streaming_stopped.emit()

## Check if currently streaming
func is_streaming() -> bool:
	return _is_streaming

# Signal handlers
func _on_chunk_received(chunk: String) -> void:
	chunk_received.emit(chunk)

func _on_error_occurred(message: String) -> void:
	_is_streaming = false
	streaming_stopped.emit()
	error_occurred.emit(message)

func _on_request_finished(full_response: String) -> void:
	_is_streaming = false
	streaming_stopped.emit()
	request_finished.emit(full_response)

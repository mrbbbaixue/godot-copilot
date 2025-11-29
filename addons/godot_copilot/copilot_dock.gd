@tool
extends VBoxContainer

var plugin: EditorPlugin

# UI elements
var chat_display: RichTextLabel
var input_field: TextEdit
var send_button: Button
var settings_button: Button
var clear_button: Button
var apply_code_button: Button
var read_code_button: Button
var stop_button: Button

# API client for non-streaming
var http_request: HTTPRequest

# Streaming support
var stream_thread: Thread
var stream_mutex: Mutex
var is_streaming := false
var should_stop_stream := false
var stream_buffer := ""
var current_response := ""
var pending_stream_text := ""

# Chat history
var messages := []


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
	
	# Code action buttons
	var code_actions := HBoxContainer.new()
	code_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(code_actions)
	
	read_code_button = Button.new()
	read_code_button.text = "📖 Read Current Code"
	read_code_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	read_code_button.pressed.connect(_on_read_code_pressed)
	code_actions.add_child(read_code_button)
	
	apply_code_button = Button.new()
	apply_code_button.text = "✏ Apply Code"
	apply_code_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_code_button.pressed.connect(_on_apply_code_pressed)
	apply_code_button.disabled = true
	code_actions.add_child(apply_code_button)
	
	# Chat display area
	chat_display = RichTextLabel.new()
	chat_display.bbcode_enabled = true
	chat_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_display.custom_minimum_size = Vector2(0, 200)
	chat_display.selection_enabled = true
	chat_display.scroll_following = true
	add_child(chat_display)
	
	# Input area
	var input_container := HBoxContainer.new()
	input_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(input_container)
	
	input_field = TextEdit.new()
	input_field.placeholder_text = "Type your message..."
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.custom_minimum_size = Vector2(0, 60)
	input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input_container.add_child(input_field)
	
	send_button = Button.new()
	send_button.text = "Send"
	send_button.pressed.connect(_on_send_pressed)
	input_container.add_child(send_button)
	
	stop_button = Button.new()
	stop_button.text = "Stop"
	stop_button.pressed.connect(_on_stop_pressed)
	stop_button.visible = false
	input_container.add_child(stop_button)
	
	# HTTP request for API calls
	http_request = HTTPRequest.new()
	http_request.request_completed.connect(_on_request_completed)
	add_child(http_request)
	
	# Initialize mutex for thread safety
	stream_mutex = Mutex.new()
	
	# Update display
	_update_chat_display()


func _process(_delta: float) -> void:
	# Process pending stream text on the main thread
	if not pending_stream_text.is_empty():
		stream_mutex.lock()
		var text_to_add := pending_stream_text
		pending_stream_text = ""
		stream_mutex.unlock()
		
		if not text_to_add.is_empty():
			_append_to_current_response(text_to_add)


func _exit_tree() -> void:
	# Stop streaming thread before cleanup
	if is_streaming:
		should_stop_stream = true
		if stream_thread and stream_thread.is_started():
			stream_thread.wait_to_finish()
		is_streaming = false


func _on_stop_pressed() -> void:
	_stop_streaming()


func _stop_streaming() -> void:
	if is_streaming:
		should_stop_stream = true
		if stream_thread and stream_thread.is_started():
			stream_thread.wait_to_finish()
		is_streaming = false
		should_stop_stream = false
		if send_button:
			send_button.visible = true
			send_button.disabled = false
		if stop_button:
			stop_button.visible = false


func _on_settings_pressed() -> void:
	if plugin:
		plugin.show_settings()


func _on_clear_pressed() -> void:
	messages.clear()
	current_response = ""
	_update_chat_display()
	apply_code_button.disabled = true


func _on_read_code_pressed() -> void:
	if not plugin:
		return
	
	var code := plugin.get_current_code()
	if code.is_empty():
		_add_system_message("No script is currently open in the editor.")
		return
	
	var script := plugin.get_current_script()
	var script_name := "Unknown"
	if script:
		script_name = script.resource_path.get_file()
	
	# Add code to context
	var code_message := "Current script (%s):\n```gdscript\n%s\n```" % [script_name, code]
	_add_user_message(code_message)
	_add_system_message("Code from '%s' has been added to the conversation context." % script_name)


func _on_apply_code_pressed() -> void:
	if not plugin or current_response.is_empty():
		return
	
	var code := _extract_code_from_response(current_response)
	if code.is_empty():
		_add_system_message("No code block found in the last response.")
		return
	
	plugin.set_current_code(code)
	_add_system_message("Code has been applied to the current script.")


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


func _format_message(content: String) -> String:
	# Simple formatting for code blocks
	var formatted := content
	# Escape BBCode characters first
	formatted = formatted.replace("[", "[lb]")
	formatted = formatted.replace("]", "[rb]")
	return formatted


func _send_to_api() -> void:
	if not plugin:
		_add_system_message("Plugin not initialized.")
		return
	
	var base_url: String = plugin.get_setting("api", "base_url")
	var api_key: String = plugin.get_setting("api", "api_key")
	var model: String = plugin.get_setting("api", "model")
	
	if api_key.is_empty():
		_add_system_message("API key not configured. Please go to Settings.")
		return
	
	# Start streaming response
	_start_streaming_request(base_url, api_key, model)


func _start_streaming_request(base_url: String, api_key: String, model: String) -> void:
	if is_streaming:
		return
	
	is_streaming = true
	should_stop_stream = false
	
	# Setup UI for streaming
	send_button.visible = false
	stop_button.visible = true
	
	# Prepare message for streaming display
	current_response = ""
	_update_chat_display()
	chat_display.append_text("\n[color=green][b]AI:[/b][/color]\n")
	
	# Start stream in thread
	var request_data := {
		"base_url": base_url,
		"api_key": api_key,
		"model": model,
		"messages": messages.duplicate(true)
	}
	
	stream_thread = Thread.new()
	stream_thread.start(_stream_request_thread.bind(request_data))


func _stream_request_thread(request_data: Dictionary) -> void:
	var base_url: String = request_data["base_url"]
	var api_key: String = request_data["api_key"]
	var model: String = request_data["model"]
	var chat_messages: Array = request_data["messages"]
	
	# Parse URL
	var url := base_url.trim_suffix("/") + "/chat/completions"
	var url_parts := url.split("://")
	var use_ssl := url_parts[0] == "https"
	var host_path := url_parts[1] if url_parts.size() > 1 else url_parts[0]
	var slash_pos := host_path.find("/")
	var host := host_path.substr(0, slash_pos) if slash_pos > 0 else host_path
	var path := host_path.substr(slash_pos) if slash_pos > 0 else "/chat/completions"
	
	# Handle port
	var port := 443 if use_ssl else 80
	var colon_pos := host.find(":")
	if colon_pos > 0:
		port = int(host.substr(colon_pos + 1))
		host = host.substr(0, colon_pos)
	
	# Create HTTP client
	var http := HTTPClient.new()
	var err := http.connect_to_host(host, port)
	if err != OK:
		call_deferred("_on_stream_error", "Failed to connect to host")
		return
	
	# Wait for connection
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		if should_stop_stream:
			http.close()
			call_deferred("_on_stream_finished")
			return
		http.poll()
		OS.delay_msec(50)
	
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		call_deferred("_on_stream_error", "Connection failed: " + str(http.get_status()))
		return
	
	# Prepare request
	var system_message := {
		"role": "system",
		"content": "You are an AI assistant helping with Godot game development. When providing code, always wrap it in ```gdscript code blocks. Be concise and helpful."
	}
	
	var request_messages := [system_message]
	for msg in chat_messages:
		request_messages.append({"role": msg["role"], "content": msg["content"]})
	
	var body := {
		"model": model,
		"messages": request_messages,
		"stream": true
	}
	
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
		"Accept: text/event-stream"
	])
	
	err = http.request(HTTPClient.METHOD_POST, path, headers, JSON.stringify(body))
	if err != OK:
		call_deferred("_on_stream_error", "Request failed")
		return
	
	# Wait for response headers
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		if should_stop_stream:
			http.close()
			call_deferred("_on_stream_finished")
			return
		http.poll()
		OS.delay_msec(50)
	
	if http.get_status() != HTTPClient.STATUS_BODY and http.get_status() != HTTPClient.STATUS_CONNECTED:
		call_deferred("_on_stream_error", "Request error: " + str(http.get_status()))
		return
	
	if http.get_response_code() != 200:
		var response_body := PackedByteArray()
		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk := http.read_response_body_chunk()
			if chunk.size() > 0:
				response_body.append_array(chunk)
			OS.delay_msec(10)
		call_deferred("_on_stream_error", "API error (%d): %s" % [http.get_response_code(), response_body.get_string_from_utf8()])
		return
	
	# Read streaming response
	var buffer := ""
	var full_response := ""
	
	while http.get_status() == HTTPClient.STATUS_BODY:
		if should_stop_stream:
			http.close()
			break
		
		http.poll()
		var chunk := http.read_response_body_chunk()
		
		if chunk.size() > 0:
			buffer += chunk.get_string_from_utf8()
			
			# Process complete SSE events
			while "\n" in buffer:
				var newline_pos := buffer.find("\n")
				var line := buffer.substr(0, newline_pos).strip_edges()
				buffer = buffer.substr(newline_pos + 1)
				
				if line.begins_with("data: "):
					var data := line.substr(6)
					if data == "[DONE]":
						continue
					
					var json := JSON.new()
					if json.parse(data) == OK:
						var response = json.data
						if response is Dictionary and response.has("choices"):
							var choices: Array = response["choices"]
							if choices.size() > 0:
								var delta: Dictionary = choices[0].get("delta", {})
								var content: String = delta.get("content", "")
								if not content.is_empty():
									full_response += content
									# Queue text update for main thread
									stream_mutex.lock()
									pending_stream_text += content
									stream_mutex.unlock()
		
		OS.delay_msec(10)
	
	http.close()
	call_deferred("_on_stream_complete", full_response)


func _append_to_current_response(text: String) -> void:
	current_response += text
	chat_display.append_text(_format_message(text))


func _on_stream_error(error_msg: String) -> void:
	is_streaming = false
	send_button.visible = true
	stop_button.visible = false
	_add_system_message(error_msg)


func _on_stream_finished() -> void:
	is_streaming = false
	send_button.visible = true
	stop_button.visible = false
	if not current_response.is_empty():
		messages.append({"role": "assistant", "content": current_response})
		apply_code_button.disabled = _extract_code_from_response(current_response).is_empty()


func _on_stream_complete(full_response: String) -> void:
	is_streaming = false
	send_button.visible = true
	stop_button.visible = false
	
	if not full_response.is_empty():
		current_response = full_response
		messages.append({"role": "assistant", "content": full_response})
		apply_code_button.disabled = _extract_code_from_response(full_response).is_empty()
	else:
		_add_system_message("Empty response from AI.")


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	send_button.disabled = false
	send_button.text = "Send"
	
	if result != HTTPRequest.RESULT_SUCCESS:
		_add_system_message("Request failed with result: " + str(result))
		return
	
	if response_code != 200:
		var error_text := body.get_string_from_utf8()
		_add_system_message("API error (%d): %s" % [response_code, error_text])
		return
	
	var json := JSON.new()
	var parse_result := json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		_add_system_message("Failed to parse response.")
		return
	
	var response_data = json.data
	if response_data is Dictionary and response_data.has("choices"):
		var choices: Array = response_data["choices"]
		if choices.size() > 0:
			var message: Dictionary = choices[0].get("message", {})
			var content: String = message.get("content", "")
			if not content.is_empty():
				_add_assistant_message(content)
			else:
				_add_system_message("Empty response from AI.")
	else:
		_add_system_message("Unexpected response format.")

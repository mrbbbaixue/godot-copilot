@tool
extends RefCounted

signal chunk_received(chunk: String)
signal error_occurred(message: String)
signal request_finished(full_response: String)

var _thread: Thread
var _mutex: Mutex
var _should_stop := false
var _is_streaming := false

func _init() -> void:
	_mutex = Mutex.new()

func start_stream(base_url: String, api_key: String, model: String, messages: Array, use_diff_mode: bool = false) -> void:
	if _is_streaming:
		return
	
	_is_streaming = true
	_should_stop = false
	
	var request_data := {
		"base_url": base_url,
		"api_key": api_key,
		"model": model,
		"messages": messages.duplicate(true),
		"use_diff_mode": use_diff_mode
	}
	
	_thread = Thread.new()
	_thread.start(_stream_request_thread.bind(request_data))

func stop_stream() -> void:
	if _is_streaming:
		_should_stop = true
		if _thread and _thread.is_started():
			_thread.wait_to_finish()
		_is_streaming = false

func is_streaming() -> bool:
	return _is_streaming

func _stream_request_thread(request_data: Dictionary) -> void:
	var base_url: String = request_data["base_url"]
	var api_key: String = request_data["api_key"]
	var model: String = request_data["model"]
	var chat_messages: Array = request_data["messages"]
	var use_diff_mode: bool = request_data.get("use_diff_mode", false)
	
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
	var err: int
	if use_ssl:
		err = http.connect_to_host(host, port, TLSOptions.client())
	else:
		err = http.connect_to_host(host, port)
	if err != OK:
		call_deferred("_emit_error", "Failed to connect to host")
		return
	
	# Wait for connection
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		if _should_stop:
			http.close()
			call_deferred("_emit_finished", "")
			return
		http.poll()
		OS.delay_msec(50)
	
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		call_deferred("_emit_error", "Connection failed: " + str(http.get_status()))
		return
	
	# Prepare request
	var system_content: String
	if use_diff_mode:
		system_content = """You are an AI assistant helping with Godot game development. 
When providing code modifications, use unified diff format to show changes. Format your diffs like this:

```diff
--- original
+++ modified
@@ -line_number,count +line_number,count @@
 context line (unchanged)
-removed line
+added line
 context line (unchanged)
```

Only show the lines that change, with 2-3 lines of context around each change. This saves output time and makes changes clearer.
For new files or complete rewrites, you may still use ```gdscript code blocks.
Be concise and helpful."""
	else:
		system_content = "You are an AI assistant helping with Godot game development. When providing code, always wrap it in ```gdscript code blocks. Be concise and helpful."
	
	var system_message := {
		"role": "system",
		"content": system_content
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
		"Host: " + host,
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
		"Accept: text/event-stream"
	])
	
	err = http.request(HTTPClient.METHOD_POST, path, headers, JSON.stringify(body))
	if err != OK:
		call_deferred("_emit_error", "Request failed")
		return
	
	# Wait for response headers
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		if _should_stop:
			http.close()
			call_deferred("_emit_finished", "")
			return
		http.poll()
		OS.delay_msec(50)
	
	if http.get_status() != HTTPClient.STATUS_BODY and http.get_status() != HTTPClient.STATUS_CONNECTED:
		call_deferred("_emit_error", "Request error: " + str(http.get_status()))
		return
	
	if http.get_response_code() != 200:
		var response_body := PackedByteArray()
		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk := http.read_response_body_chunk()
			if chunk.size() > 0:
				response_body.append_array(chunk)
			OS.delay_msec(10)
		call_deferred("_emit_error", "API error (%d): %s" % [http.get_response_code(), response_body.get_string_from_utf8()])
		return
	
	# Read streaming response
	var buffer := ""
	var full_response := ""
	
	while http.get_status() == HTTPClient.STATUS_BODY:
		if _should_stop:
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
									call_deferred("emit_signal", "chunk_received", content)
		
		OS.delay_msec(10)
	
	http.close()
	call_deferred("_emit_finished", full_response)

func _emit_error(msg: String) -> void:
	_is_streaming = false
	error_occurred.emit(msg)

func _emit_finished(full_response: String) -> void:
	_is_streaming = false
	request_finished.emit(full_response)

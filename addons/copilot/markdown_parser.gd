@tool
extends RefCounted

static func parse(text: String) -> String:
	var parts = []
	var current_pos = 0
	var code_block_regex = RegEx.new()
	# Match ```language ... ```
	code_block_regex.compile("```(?:\\w+)?\\s*\\n([\\s\\S]*?)\\n```")
	
	var matches = code_block_regex.search_all(text)
	
	for m in matches:
		var start = m.get_start()
		var end = m.get_end()
		
		# Process text before code block
		var pre_text = text.substr(current_pos, start - current_pos)
		parts.append(_process_markdown(pre_text))
		
		# Process code block
		var code_content = m.get_string(1)
		parts.append(_format_code_block(code_content))
		
		current_pos = end
	
	# Process remaining text
	var remaining = text.substr(current_pos)
	parts.append(_process_markdown(remaining))
	
	return "".join(parts)

static func _process_markdown(text: String) -> String:
	var result = text
	# Escape BBCode tags
	result = result.replace("[", "[lb]")
	result = result.replace("]", "[rb]")
	
	# Bold **text**
	var bold = RegEx.new()
	bold.compile("\\*\\*(.*?)\\*\\*")
	result = bold.sub(result, "[b]$1[/b]", true)
	
	# Italic *text*
	var italic = RegEx.new()
	italic.compile("\\*(.*?)\\*")
	result = italic.sub(result, "[i]$1[/i]", true)
	
	# Inline code `text`
	var inline_code = RegEx.new()
	inline_code.compile("`([^`]+)`")
	result = inline_code.sub(result, "[code]$1[/code]", true)
	
	return result

static func _format_code_block(code: String) -> String:
	var escaped = code.replace("[", "[lb]").replace("]", "[rb]")
	# Add some color or styling if desired, for now just [code]
	return "[code]" + escaped + "[/code]"

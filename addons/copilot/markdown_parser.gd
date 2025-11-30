@tool
extends RefCounted

## Enhanced Markdown parser with support for syntax highlighting and diff blocks

# Color constants for syntax highlighting
const COLOR_KEYWORD := "#ff7085"       # Pink for keywords
const COLOR_STRING := "#a5d6a7"        # Light green for strings
const COLOR_COMMENT := "#6b7280"       # Gray for comments
const COLOR_NUMBER := "#82aaff"        # Light blue for numbers
const COLOR_FUNCTION := "#ffd54f"      # Yellow for functions
const COLOR_TYPE := "#c792ea"          # Purple for types

# Diff colors
const COLOR_DIFF_ADD := "#4caf50"      # Green for additions
const COLOR_DIFF_REMOVE := "#f44336"   # Red for deletions
const COLOR_DIFF_HUNK := "#64b5f6"     # Blue for hunk headers
const COLOR_DIFF_META := "#9e9e9e"     # Gray for metadata

# Code block background
const COLOR_CODE_BG := "#1e1e2e"       # Dark background for code


static func parse(text: String) -> String:
	var parts = []
	var current_pos = 0
	var code_block_regex = RegEx.new()
	# Match ```language ... ``` and capture the language
	code_block_regex.compile("```(\\w*)\\s*\\n([\\s\\S]*?)\\n```")
	
	var matches = code_block_regex.search_all(text)
	
	for m in matches:
		var start = m.get_start()
		var end = m.get_end()
		
		# Process text before code block
		var pre_text = text.substr(current_pos, start - current_pos)
		parts.append(_process_markdown(pre_text))
		
		# Get language and code content
		var language = m.get_string(1).to_lower()
		var code_content = m.get_string(2)
		
		# Process code block based on language
		if language == "diff":
			parts.append(_format_diff_block(code_content))
		elif language == "gdscript" or language == "gd":
			parts.append(_format_gdscript_block(code_content))
		else:
			parts.append(_format_code_block(code_content, language))
		
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
	italic.compile("(?<!\\*)\\*(?!\\*)([^*]+)(?<!\\*)\\*(?!\\*)")
	result = italic.sub(result, "[i]$1[/i]", true)
	
	# Inline code `text`
	var inline_code = RegEx.new()
	inline_code.compile("`([^`]+)`")
	result = inline_code.sub(result, "[bgcolor=#2d2d3d][code]$1[/code][/bgcolor]", true)
	
	# Headers
	var h3 = RegEx.new()
	h3.compile("^### (.+)$")
	result = h3.sub(result, "[b][color=#82aaff]$1[/color][/b]", true)
	
	var h2 = RegEx.new()
	h2.compile("^## (.+)$")
	result = h2.sub(result, "[b][font_size=18][color=#82aaff]$1[/color][/font_size][/b]", true)
	
	var h1 = RegEx.new()
	h1.compile("^# (.+)$")
	result = h1.sub(result, "[b][font_size=20][color=#82aaff]$1[/color][/font_size][/b]", true)
	
	return result


static func _format_code_block(code: String, language: String = "") -> String:
	var escaped = code.replace("[", "[lb]").replace("]", "[rb]")
	var lang_label = ""
	if not language.is_empty():
		lang_label = "[color=#6b7280][i]" + language + "[/i][/color]\n"
	return "\n[bgcolor=#1e1e2e]" + lang_label + "[code]" + escaped + "[/code][/bgcolor]\n"


static func _format_gdscript_block(code: String) -> String:
	var lines = code.split("\n")
	var result_lines = []
	
	for line in lines:
		result_lines.append(_highlight_gdscript_line(line))
	
	var highlighted = "\n".join(result_lines)
	return "\n[bgcolor=#1e1e2e][color=#6b7280][i]gdscript[/i][/color]\n" + highlighted + "[/bgcolor]\n"


static func _highlight_gdscript_line(line: String) -> String:
	var result = line
	# Escape BBCode tags first
	result = result.replace("[", "[lb]")
	result = result.replace("]", "[rb]")
	
	# Comment highlighting (must be done first to avoid other replacements in comments)
	var comment_regex = RegEx.new()
	comment_regex.compile("(#.*)$")
	result = comment_regex.sub(result, "[color=" + COLOR_COMMENT + "]$1[/color]", true)
	
	# String highlighting (double and single quotes)
	var string_regex = RegEx.new()
	string_regex.compile("(\"[^\"]*\"|'[^']*')")
	result = string_regex.sub(result, "[color=" + COLOR_STRING + "]$1[/color]", true)
	
	# Keywords - use a single regex for all keywords
	var keywords = ["func", "var", "const", "class", "extends", "if", "elif", "else", 
					"for", "while", "match", "return", "pass", "break", "continue",
					"class_name", "signal", "enum", "static",
					"preload", "load", "self", "super", "true", "false", "null",
					"and", "or", "not", "in", "is", "as", "await", "@tool", "@export",
					"@onready"]
	var kw_pattern = "\\b(" + "|".join(keywords) + ")\\b"
	var kw_regex = RegEx.new()
	kw_regex.compile(kw_pattern)
	result = kw_regex.sub(result, "[color=" + COLOR_KEYWORD + "]$1[/color]", true)
	
	# Types - use a single regex for all types
	var types = ["int", "float", "bool", "String", "Vector2", "Vector3", "Array",
				 "Dictionary", "Node", "Node2D", "Node3D", "Control", "Sprite2D",
				 "void", "Variant"]
	var type_pattern = "\\b(" + "|".join(types) + ")\\b"
	var type_regex = RegEx.new()
	type_regex.compile(type_pattern)
	result = type_regex.sub(result, "[color=" + COLOR_TYPE + "]$1[/color]", true)
	
	# Numbers
	var num_regex = RegEx.new()
	num_regex.compile("\\b(\\d+\\.?\\d*)\\b")
	result = num_regex.sub(result, "[color=" + COLOR_NUMBER + "]$1[/color]", true)
	
	# Function calls
	var func_regex = RegEx.new()
	func_regex.compile("\\b([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(")
	result = func_regex.sub(result, "[color=" + COLOR_FUNCTION + "]$1[/color](", true)
	
	return result


static func _format_diff_block(diff_text: String) -> String:
	var lines = diff_text.split("\n")
	var result_lines = []
	
	result_lines.append("[color=#6b7280][i]diff[/i][/color]")
	
	for line in lines:
		var escaped = line.replace("[", "[lb]").replace("]", "[rb]")
		
		if line.begins_with("@@"):
			# Hunk header
			result_lines.append("[color=" + COLOR_DIFF_HUNK + "]" + escaped + "[/color]")
		elif line.begins_with("---") or line.begins_with("+++"):
			# File headers
			result_lines.append("[color=" + COLOR_DIFF_META + "]" + escaped + "[/color]")
		elif line.begins_with("-"):
			# Removed line
			result_lines.append("[bgcolor=#3d1f1f][color=" + COLOR_DIFF_REMOVE + "]" + escaped + "[/color][/bgcolor]")
		elif line.begins_with("+"):
			# Added line
			result_lines.append("[bgcolor=#1f3d1f][color=" + COLOR_DIFF_ADD + "]" + escaped + "[/color][/bgcolor]")
		else:
			# Context line
			result_lines.append("[color=#b0bec5]" + escaped + "[/color]")
	
	return "\n[bgcolor=#1e1e2e]" + "\n".join(result_lines) + "[/bgcolor]\n"

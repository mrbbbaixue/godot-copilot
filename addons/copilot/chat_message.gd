@tool
extends PanelContainer

## A reusable chat message component with improved visual styling

const MarkdownParser = preload("markdown_parser.gd")
const DiffUtils = preload("diff_utils.gd")

enum MessageRole { USER, ASSISTANT, SYSTEM }

# Signals for code block actions
signal apply_code_requested(file_path: String, code: String, is_diff: bool)

# Message properties
var role: MessageRole = MessageRole.USER
var content: String = ""

# UI elements
var avatar_label: Label
var role_label: Label
var content_container: VBoxContainer
var header_container: HBoxContainer
var main_container: VBoxContainer

# Style colors
const USER_BG_COLOR := Color(0.15, 0.25, 0.35, 0.8)       # Blue-ish for user
const ASSISTANT_BG_COLOR := Color(0.15, 0.30, 0.20, 0.8)  # Green-ish for assistant
const SYSTEM_BG_COLOR := Color(0.30, 0.25, 0.15, 0.8)     # Yellow-ish for system

const USER_ACCENT_COLOR := Color(0.4, 0.7, 1.0)           # Cyan
const ASSISTANT_ACCENT_COLOR := Color(0.4, 0.8, 0.5)      # Green
const SYSTEM_ACCENT_COLOR := Color(1.0, 0.85, 0.4)        # Yellow

const USER_AVATAR := "👤"
const ASSISTANT_AVATAR := "🤖"
const SYSTEM_AVATAR := "⚙️"


func _init() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# Configure panel container
	custom_minimum_size = Vector2(0, 40)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Create main vertical container
	main_container = VBoxContainer.new()
	main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(main_container)
	
	# Header with avatar and role
	header_container = HBoxContainer.new()
	header_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.add_child(header_container)
	
	# Avatar
	avatar_label = Label.new()
	avatar_label.text = USER_AVATAR
	avatar_label.add_theme_font_size_override("font_size", 18)
	header_container.add_child(avatar_label)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(8, 0)
	header_container.add_child(spacer)
	
	# Role label
	role_label = Label.new()
	role_label.text = "You"
	role_label.add_theme_font_size_override("font_size", 14)
	header_container.add_child(role_label)
	
	# Separator line
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 2)
	main_container.add_child(separator)
	
	# Content container for text and code blocks
	content_container = VBoxContainer.new()
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.add_child(content_container)
	
	# Apply default style
	_apply_style()


func setup(message_role: MessageRole, message_content: String) -> void:
	role = message_role
	content = message_content
	_apply_style()
	_update_content()


func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	
	var accent_color: Color
	
	match role:
		MessageRole.USER:
			style.bg_color = USER_BG_COLOR
			accent_color = USER_ACCENT_COLOR
			avatar_label.text = USER_AVATAR
			role_label.text = "You"
		MessageRole.ASSISTANT:
			style.bg_color = ASSISTANT_BG_COLOR
			accent_color = ASSISTANT_ACCENT_COLOR
			avatar_label.text = ASSISTANT_AVATAR
			role_label.text = "AI Assistant"
		MessageRole.SYSTEM:
			style.bg_color = SYSTEM_BG_COLOR
			accent_color = SYSTEM_ACCENT_COLOR
			avatar_label.text = SYSTEM_AVATAR
			role_label.text = "System"
	
	# Apply border on left side for visual distinction
	style.border_width_left = 3
	style.border_color = accent_color
	
	add_theme_stylebox_override("panel", style)
	
	# Style the role label
	role_label.add_theme_color_override("font_color", accent_color)


func _update_content() -> void:
	# Clear existing content
	for child in content_container.get_children():
		child.queue_free()
	
	# Parse content into segments (text and code blocks)
	var segments := _parse_content_segments(content)
	
	for segment in segments:
		if segment["type"] == "text":
			_add_text_segment(segment["content"])
		elif segment["type"] == "code":
			_add_code_segment(segment["content"], segment["language"], segment["file_path"], segment["is_diff"])


func _parse_content_segments(text: String) -> Array:
	var segments := []
	var current_pos := 0
	
	# Match code blocks with optional file path: ```language:filepath or ```language
	var code_block_regex := RegEx.new()
	code_block_regex.compile("```(\\w*)(?::([^\\s\\n]+))?\\s*\\n([\\s\\S]*?)\\n```")
	
	var matches := code_block_regex.search_all(text)
	
	for m in matches:
		var start := m.get_start()
		var end := m.get_end()
		
		# Add text before this code block
		if start > current_pos:
			var pre_text := text.substr(current_pos, start - current_pos)
			if not pre_text.strip_edges().is_empty():
				segments.append({
					"type": "text",
					"content": pre_text
				})
		
		# Add code block
		var language := m.get_string(1).to_lower()
		var file_path := m.get_string(2) if m.get_string(2) else ""
		var code_content := m.get_string(3)
		var is_diff := language == "diff"
		
		segments.append({
			"type": "code",
			"content": code_content,
			"language": language,
			"file_path": file_path,
			"is_diff": is_diff
		})
		
		current_pos = end
	
	# Add remaining text
	if current_pos < text.length():
		var remaining := text.substr(current_pos)
		if not remaining.strip_edges().is_empty():
			segments.append({
				"type": "text",
				"content": remaining
			})
	
	return segments


func _add_text_segment(text: String) -> void:
	var text_label := RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.fit_content = true
	text_label.selection_enabled = true
	text_label.scroll_active = false
	
	var formatted := MarkdownParser.parse(text)
	text_label.append_text(formatted)
	
	content_container.add_child(text_label)


func _add_code_segment(code: String, language: String, file_path: String, is_diff: bool) -> void:
	var code_container := VBoxContainer.new()
	code_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Code block header with file path
	if not file_path.is_empty():
		var header := HBoxContainer.new()
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var path_label := Label.new()
		path_label.text = "📄 " + file_path
		path_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		path_label.add_theme_font_size_override("font_size", 12)
		path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(path_label)
		
		code_container.add_child(header)
	
	# Code content
	var code_label := RichTextLabel.new()
	code_label.bbcode_enabled = true
	code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_label.fit_content = true
	code_label.selection_enabled = true
	code_label.scroll_active = false
	
	# Format code based on type
	var formatted_code := ""
	if is_diff:
		formatted_code = MarkdownParser.format_diff_block(code)
	elif language == "gdscript" or language == "gd":
		formatted_code = MarkdownParser.format_gdscript_block(code)
	elif language == "tscn":
		formatted_code = MarkdownParser.format_code_block(code, "tscn")
	else:
		formatted_code = MarkdownParser.format_code_block(code, language)
	
	code_label.append_text(formatted_code)
	code_container.add_child(code_label)
	
	# Apply button (only for assistant messages with file paths)
	if role == MessageRole.ASSISTANT and not file_path.is_empty():
		var button_container := HBoxContainer.new()
		button_container.alignment = BoxContainer.ALIGNMENT_END
		
		var apply_button := Button.new()
		if is_diff:
			apply_button.text = "📝 Apply Diff"
			apply_button.tooltip_text = "Apply this diff to %s" % file_path
		else:
			apply_button.text = "✏️ Apply Code"
			apply_button.tooltip_text = "Apply this code to %s" % file_path
		
		# Style the button
		var style_box := StyleBoxFlat.new()
		style_box.bg_color = Color(0.2, 0.5, 0.3)
		style_box.corner_radius_top_left = 4
		style_box.corner_radius_top_right = 4
		style_box.corner_radius_bottom_left = 4
		style_box.corner_radius_bottom_right = 4
		apply_button.add_theme_stylebox_override("normal", style_box)
		
		# Connect button with code data
		apply_button.pressed.connect(_on_apply_pressed.bind(file_path, code, is_diff))
		
		button_container.add_child(apply_button)
		code_container.add_child(button_container)
	
	content_container.add_child(code_container)


func _on_apply_pressed(file_path: String, code: String, is_diff: bool) -> void:
	apply_code_requested.emit(file_path, code, is_diff)


func set_streaming_content(partial_content: String) -> void:
	content = partial_content
	_update_content()

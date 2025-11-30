@tool
extends PanelContainer

## A reusable chat message component with improved visual styling

const MarkdownParser = preload("markdown_parser.gd")
const DiffUtils = preload("diff_utils.gd")

signal apply_diff_requested(file_path: String, diff_text: String)
signal apply_code_requested(file_path: String, code: String)

enum MessageRole { USER, ASSISTANT, SYSTEM }

# Message properties
var role: MessageRole = MessageRole.USER
var content: String = ""

# UI elements
var avatar_label: Label
var role_label: Label
var content_label: RichTextLabel
var header_container: HBoxContainer
var main_container: VBoxContainer
var apply_buttons_container: VBoxContainer

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
	
	# Content
	content_label = RichTextLabel.new()
	content_label.bbcode_enabled = true
	content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_label.fit_content = true
	content_label.selection_enabled = true
	content_label.scroll_active = false
	main_container.add_child(content_label)
	
	# Container for apply buttons (will be populated when content is set)
	apply_buttons_container = VBoxContainer.new()
	apply_buttons_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.add_child(apply_buttons_container)
	
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
	if content_label:
		var formatted_content = MarkdownParser.parse(content)
		content_label.clear()
		content_label.append_text(formatted_content)
	
	# Update apply buttons for assistant messages
	_update_apply_buttons()


func _update_apply_buttons() -> void:
	# Clear existing buttons
	for child in apply_buttons_container.get_children():
		child.queue_free()
	
	# Only show apply buttons for assistant messages
	if role != MessageRole.ASSISTANT:
		return
	
	# Extract diffs and code blocks from the content
	var diffs := DiffUtils.extract_all_diffs(content)
	var code_blocks := DiffUtils.extract_code_blocks_with_paths(content)
	
	# Add apply buttons for each diff
	for diff_info in diffs:
		var btn := _create_apply_button(
			"📝 Apply Diff to %s" % diff_info["path"].get_file(),
			diff_info["path"],
			true
		)
		btn.set_meta("diff_text", diff_info["diff"])
		btn.set_meta("is_new_file", diff_info["is_new_file"])
		apply_buttons_container.add_child(btn)
	
	# Add apply buttons for code blocks with file paths
	for block_info in code_blocks:
		var btn := _create_apply_button(
			"✏ Apply Code to %s" % block_info["path"].get_file(),
			block_info["path"],
			false
		)
		btn.set_meta("code", block_info["code"])
		apply_buttons_container.add_child(btn)


func _create_apply_button(text: String, file_path: String, is_diff: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = file_path
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Style the button
	var style_box := StyleBoxFlat.new()
	if is_diff:
		style_box.bg_color = Color(0.2, 0.5, 0.3, 0.8)  # Green for diff
	else:
		style_box.bg_color = Color(0.2, 0.4, 0.6, 0.8)  # Blue for code
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_right = 4
	style_box.corner_radius_bottom_left = 4
	btn.add_theme_stylebox_override("normal", style_box)
	
	btn.set_meta("file_path", file_path)
	btn.set_meta("is_diff", is_diff)
	btn.pressed.connect(_on_apply_button_pressed.bind(btn))
	
	return btn


func _on_apply_button_pressed(btn: Button) -> void:
	var file_path: String = btn.get_meta("file_path")
	var is_diff: bool = btn.get_meta("is_diff")
	
	if is_diff:
		var diff_text: String = btn.get_meta("diff_text")
		apply_diff_requested.emit(file_path, diff_text)
	else:
		var code: String = btn.get_meta("code")
		apply_code_requested.emit(file_path, code)


func set_streaming_content(partial_content: String) -> void:
	content = partial_content
	_update_content()

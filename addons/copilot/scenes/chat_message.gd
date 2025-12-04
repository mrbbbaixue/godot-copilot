@tool
extends PanelContainer

## A reusable chat message component with improved visual styling

const MarkdownParser = preload("res://addons/copilot/scripts/markdown_parser.gd")
const DiffUtils = preload("res://addons/copilot/scripts/diff_utils.gd")
const DiffButtonTemplate = preload("res://addons/copilot/scenes/diff_button_template.tscn")
const CodeButtonTemplate = preload("res://addons/copilot/scenes/code_button_template.tscn")

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

# State tracking
var nodes_ready := false
var pending_role: MessageRole = MessageRole.USER
var pending_content := ""

# Style colors - using editor theme colors
const USER_BORDER_COLOR := Color(0.25, 0.55, 0.95)        # Blue accent for user
const ASSISTANT_BORDER_COLOR := Color(0.25, 0.65, 0.4)    # Green accent for assistant
const SYSTEM_BORDER_COLOR := Color(0.9, 0.7, 0.2)         # Orange accent for system

const USER_BG_COLOR := Color(0.25, 0.55, 0.95, 0.15)      # Blue background for user (light with transparency)
const USER_ACCENT_COLOR := Color(0.25, 0.55, 0.95)        # Blue accent (for role label)
const ASSISTANT_ACCENT_COLOR := Color(0.25, 0.65, 0.4)    # Green accent (for role label)
const SYSTEM_ACCENT_COLOR := Color(0.9, 0.7, 0.2)         # Orange accent (for role label)

const USER_AVATAR := ""  # No emoji
const ASSISTANT_AVATAR := ""  # No emoji
const SYSTEM_AVATAR := ""  # No emoji


func _ready() -> void:
	# Get references to scene nodes
	main_container = $MainContainer
	header_container = $MainContainer/HeaderContainer
	avatar_label = $MainContainer/HeaderContainer/AvatarLabel
	role_label = $MainContainer/HeaderContainer/RoleLabel
	content_label = $MainContainer/ContentLabel
	apply_buttons_container = $MainContainer/ApplyButtonsContainer

	nodes_ready = true

	# Apply default style
	_apply_style()

	# Apply pending setup if any
	if pending_content != "":
		role = pending_role
		content = pending_content
		_apply_style()
		_update_content()
		pending_content = ""


func setup(message_role: MessageRole, message_content: String) -> void:
	if not nodes_ready:
		# Store for when nodes are ready
		pending_role = message_role
		pending_content = message_content
		return

	role = message_role
	content = message_content
	_apply_style()
	_update_content()


func _apply_style() -> void:
	# Get existing style from theme or create new one
	var existing_style = get_theme_stylebox("panel")
	var style: StyleBoxFlat
	if existing_style is StyleBoxFlat:
		style = existing_style.duplicate() as StyleBoxFlat
	else:
		style = StyleBoxFlat.new()
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8

	var accent_color: Color
	var border_color: Color

	match role:
		MessageRole.USER:
			accent_color = USER_ACCENT_COLOR
			border_color = USER_BORDER_COLOR
			avatar_label.text = USER_AVATAR
			role_label.text = "You"
			# User messages have left border and background color
			style.bg_color = USER_BG_COLOR
			style.border_width_left = 3
			style.border_color = border_color
		MessageRole.ASSISTANT:
			accent_color = ASSISTANT_ACCENT_COLOR
			border_color = ASSISTANT_BORDER_COLOR
			avatar_label.text = ASSISTANT_AVATAR
			role_label.text = "AI Assistant"
			# Assistant messages have no border and transparent background
			style.bg_color = Color.TRANSPARENT
			style.border_width_left = 0
		MessageRole.SYSTEM:
			accent_color = SYSTEM_ACCENT_COLOR
			border_color = SYSTEM_BORDER_COLOR
			avatar_label.text = SYSTEM_AVATAR
			role_label.text = "System"
			# System messages have no border and transparent background
			style.bg_color = Color.TRANSPARENT
			style.border_width_left = 0

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

	# Hide container by default
	apply_buttons_container.visible = false

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

	# Show container if we added any buttons
	if diffs.size() > 0 or code_blocks.size() > 0:
		apply_buttons_container.visible = true


func _create_apply_button(text: String, file_path: String, is_diff: bool) -> Button:
	var btn: Button
	if is_diff:
		btn = DiffButtonTemplate.instantiate()
	else:
		btn = CodeButtonTemplate.instantiate()

	btn.text = text
	btn.tooltip_text = file_path

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

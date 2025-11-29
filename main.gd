@tool
extends Node2D

# 色块大小
@export var block_size: Vector2 = Vector2(50, 50)
# 色块间距
@export var spacing: int = 5
# 网格行列数
@export var grid_size: Vector2 = Vector2(8, 6)
# 是否在编辑器中显示
@export var show_in_editor: bool = true : set = set_show_in_editor

func _ready():
	if Engine.is_editor_hint() and show_in_editor:
		generate_color_blocks()
	elif not Engine.is_editor_hint():
		generate_color_blocks()

func set_show_in_editor(value: bool) -> void:
	show_in_editor = value
	if Engine.is_editor_hint():
		# 清除现有色块
		for child in get_children():
			if child is ColorRect:
				child.queue_free()
		# 如果需要显示，重新生成
		if show_in_editor:
			generate_color_blocks()

func generate_color_blocks():
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			# 创建色块
			var block = ColorRect.new()
			block.size = block_size
			block.position = Vector2(x * (block_size.x + spacing), y * (block_size.y + spacing))
			
			# 生成随机颜色
			var random_color = Color(randf(), randf(), randf())
			block.color = random_color
			
			add_child(block)

# 按空格键重新生成色块
func _input(event):
	if event.is_action_pressed("ui_accept") and not Engine.is_editor_hint():
		# 清除现有色块
		for child in get_children():
			if child is ColorRect:
				child.queue_free()
		# 生成新色块
		generate_color_blocks()

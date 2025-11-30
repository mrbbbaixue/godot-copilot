@tool
extends Node2D
@export var block_size: Vector2 = Vector2(50, 50)
@export var spacing: int = 5
@export var block_count: int = 8
@export var show_in_editor: bool = true : set = set_show_in_editor
@export var wave_speed: float = 2.0
@export var wave_amplitude: float = 100.0
@export var wave_frequency: float = 0.5

var is_paused: bool = false
var time: float = 0.0
var blocks: Array = []

func _ready():
	if Engine.is_editor_hint() and show_in_editor:
		generate_color_blocks()
	elif not Engine.is_editor_hint():
		generate_color_blocks()

func set_show_in_editor(value: bool) -> void:
	show_in_editor = value
	if Engine.is_editor_hint():
		for child in get_children():
			if child is ColorRect:
				child.queue_free()
		if show_in_editor:
			generate_color_blocks()

func generate_color_blocks():
	blocks.clear()
	# 计算总宽度和起始位置，使色块居中
	var total_width = block_count * block_size.x + (block_count - 1) * spacing
	var start_x = (get_viewport_rect().size.x - total_width) / 2
	
	for i in range(block_count):
		var block = ColorRect.new()
		block.size = block_size
		block.position = Vector2(start_x + i * (block_size.x + spacing), get_viewport_rect().size.y / 2)
		var random_color = generate_vibrant_color()
		block.color = random_color
		add_child(block)
		blocks.append(block)

func _process(delta):
	if Engine.is_editor_hint() or is_paused:
		return
	
	time += delta * wave_speed
	for i in range(blocks.size()):
		var block = blocks[i]
		var wave_offset = sin(time + i * wave_frequency) * wave_amplitude
		block.position.y = get_viewport_rect().size.y / 2 + wave_offset

func _input(event):
	if event.is_action_pressed("ui_accept") and not Engine.is_editor_hint():
		is_paused = !is_paused

func generate_vibrant_color() -> Color:
	# 生成鲜艳颜色的方法：保持高饱和度和亮度
	var hue = randf()  # 随机色相
	var saturation = randf_range(0.7, 1.0)  # 高饱和度
	var value = randf_range(0.8, 1.0)  # 高亮度
	
	# 或者使用另一种方法：固定一个通道为0或1，随机其他两个通道
	# var method = randi() % 3
	# match method:
	# 	0: return Color(randf_range(0.8, 1.0), randf_range(0.8, 1.0), 0.0)  # 黄色系
	# 	1: return Color(randf_range(0.8, 1.0), 0.0, randf_range(0.8, 1.0))  # 紫色系
	# 	2: return Color(0.0, randf_range(0.8, 1.0), randf_range(0.8, 1.0))  # 青色系
	
	return Color.from_hsv(hue, saturation, value)

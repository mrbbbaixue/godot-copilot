@tool
extends Node2D
# 基础设置
@export var block_size: Vector2 = Vector2(20, 20)
@export var spacing: int = 5
@export var block_count: int = 8
@export var show_in_editor: bool = true : set = set_show_in_editor
# 波浪效果
@export var wave_speed: float = 2.0
@export var wave_amplitude: float = 100.0
@export var wave_frequency: float = 0.5
# 炫酷效果
@export var pulse_enabled: bool = true
@export var pulse_speed: float = 3.0
@export var mouse_interaction: bool = true
var is_paused: bool = false
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
		
		# 创建渐变材质
		var material = ShaderMaterial.new()
		material.shader = create_gradient_shader()
		block.material = material
		
		# 设置初始颜色
		var base_color = generate_vibrant_color()
		material.set_shader_parameter("color1", base_color)
		material.set_shader_parameter("color2", base_color.darkened(0.3))
		material.set_shader_parameter("gradient_offset", 0.0)
		
		add_child(block)
		blocks.append({
			"node": block,
			"material": material,
			"base_color": base_color,
			"target_color": base_color,
			"color_t": 0.0,
			"pulse_phase": randf() * PI * 2,
			"original_y": get_viewport_rect().size.y / 2,
			"mouse_influence": 0.0
		})
func _process(delta):
	if Engine.is_editor_hint() or is_paused:
		return
	
	var time = Time.get_ticks_msec() / 1000.0
	var mouse_pos = get_global_mouse_position()
	
	for i in range(blocks.size()):
		var block_data = blocks[i]
		var block = block_data["node"]
		var material = block_data["material"]
		
		# 波浪运动
		var wave_offset = sin(time * wave_speed + i * wave_frequency) * wave_amplitude
		var wave_offset2 = cos(time * wave_speed * 0.7 + i * wave_frequency * 1.3) * wave_amplitude * 0.3
		
		# 鼠标交互
		if mouse_interaction:
			var distance = block.global_position.distance_to(mouse_pos)
			var influence = clamp(1.0 - distance / 300.0, 0.0, 1.0)
			block_data["mouse_influence"] = lerp(block_data["mouse_influence"], influence, delta * 10.0)
			wave_offset += sin(time * 5.0) * wave_amplitude * 0.5 * block_data["mouse_influence"]
		else:
			block_data["mouse_influence"] = 0.0
		
		# 更新位置
		block.position.y = block_data["original_y"] + wave_offset + wave_offset2
		
		# 脉冲效果
		if pulse_enabled:
			var pulse = sin(time * pulse_speed + block_data["pulse_phase"]) * 0.5 + 0.5
			material.set_shader_parameter("gradient_offset", pulse * 0.3)
			
			# 颜色渐变
			block_data["color_t"] += delta * 0.5
			if block_data["color_t"] >= 1.0:
				block_data["color_t"] = 0.0
				block_data["base_color"] = block_data["target_color"]
				block_data["target_color"] = generate_vibrant_color()
			
			var current_color = block_data["base_color"].lerp(block_data["target_color"], block_data["color_t"])
			material.set_shader_parameter("color1", current_color)
			material.set_shader_parameter("color2", current_color.darkened(0.3))
		
		# 鼠标悬停效果
		var target_scale = Vector2.ONE
		if block_data["mouse_influence"] > 0.1:
			target_scale = Vector2.ONE * (1.0 + block_data["mouse_influence"] * 0.8)
		
		# 记录缩放前的中心点
		var current_center = Vector2(
			block.position.x + block_size.x * block.scale.x / 2,
			block.position.y + block_size.y * block.scale.y / 2
		)
		
		# 应用缩放
		block.scale = block.scale.lerp(target_scale, delta * 10.0)
		
		# 调整位置以保持中心点不变
		block.position.x = current_center.x - block_size.x * block.scale.x / 2
		block.position.y = current_center.y - block_size.y * block.scale.y / 2
		blocks[i] = block_data
func _input(event):
	if event.is_action_pressed("ui_accept"):
		is_paused = !is_paused
func generate_vibrant_color() -> Color:
	# 生成鲜艳颜色的方法：保持高饱和度和亮度
	var hue = randf()  # 随机色相
	var saturation = randf_range(0.7, 1.0)  # 高饱和度
	var value = randf_range(0.8, 1.0)  # 高亮度
	
	return Color.from_hsv(hue, saturation, value)
func create_gradient_shader() -> Shader:
	var shader_code = """
	shader_type canvas_item;
	
	uniform vec4 color1 : source_color = vec4(1.0, 0.0, 0.0, 1.0);
	uniform vec4 color2 : source_color = vec4(0.0, 0.0, 1.0, 1.0);
	uniform float gradient_offset : hint_range(0.0, 1.0) = 0.0;
	
	void fragment() {
		// 创建渐变
		float gradient = UV.y + gradient_offset;
		gradient = fract(gradient);
		
		// 混合颜色
		vec4 gradient_color = mix(color1, color2, gradient);
		
		// 添加边缘发光
		float edge = smoothstep(0.0, 0.1, UV.x) * 
					smoothstep(1.0, 0.9, UV.x) *
					smoothstep(0.0, 0.1, UV.y) *
					smoothstep(1.0, 0.9, UV.y);
		
		// 最终颜色
		COLOR = gradient_color;
		COLOR.rgb += edge * 0.3;  // 边缘发光
	}
	"""
	
	var shader = Shader.new()
	shader.code = shader_code
	return shader

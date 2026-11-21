@tool
extends EditorPlugin

const DualGridMapScript = preload("res://addons/dual_grid_editor/runtime/dual_grid_map.gd")
const CUSTOM_TYPE_NAME := "DualGridMap"
const FloodFill = preload("res://addons/dual_grid_editor/core/dual_grid_flood_fill.gd")
enum ToolMode { BRUSH, RECTANGLE, BUCKET }
var bucket_bounds := Rect2i(-16, -16, 32, 32)
var bounds_button: Button
var bounds_dialog: ConfirmationDialog
var bounds_inputs: Array[SpinBox] = []

var current_map: Variant = null
var toolbar: HBoxContainer
var edit_button: Button
var tool_choice: OptionButton
var edit_mode := false
var tool_mode: int = ToolMode.BRUSH
var is_painting := false
var paint_grass := true
var stroke_before: Array[Vector2i] = []
var hovered_cell := Vector2i.ZERO
var last_painted_cell := Vector2i.ZERO
var has_hover := false
var rectangle_start := Vector2i.ZERO
var stroke_button: int = MOUSE_BUTTON_NONE

func _enter_tree() -> void:
	add_custom_type(CUSTOM_TYPE_NAME, "Node2D", DualGridMapScript, null)
	_create_toolbar()
	print("[DualGrid Editor] v0.5 油漆桶工具已启用")

func _exit_tree() -> void:
	_end_for_context_change()
	if toolbar != null:
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, toolbar)
		toolbar.queue_free()
		toolbar = null
	if is_instance_valid(bounds_dialog):
		bounds_dialog.queue_free()
	remove_custom_type(CUSTOM_TYPE_NAME)
	current_map = null

func _create_toolbar() -> void:
	toolbar = HBoxContainer.new()
	toolbar.name = "DualGridToolbar"
	var title_label := Label.new()
	title_label.text = "DualGrid"
	toolbar.add_child(title_label)
	edit_button = Button.new()
	edit_button.text = "地形编辑：关闭"
	edit_button.toggle_mode = true
	edit_button.tooltip_text = "左键绘制，右键擦除；矩形拖动后松开提交；油漆桶点击松开生效；Esc取消"
	toolbar.add_child(edit_button)
	edit_button.toggled.connect(_on_edit_mode_toggled)
	tool_choice = OptionButton.new()
	tool_choice.add_item("画笔", ToolMode.BRUSH)
	tool_choice.add_item("矩形", ToolMode.RECTANGLE)
	tool_choice.add_item("油漆桶", ToolMode.BUCKET)
	tool_choice.disabled = true
	tool_choice.item_selected.connect(_on_tool_selected)
	toolbar.add_child(tool_choice)
	bounds_button = Button.new()
	bounds_button.text = "填充范围…"
	bounds_button.tooltip_text = "设置油漆桶生效的逻辑格范围；蓝框内有效"
	bounds_button.visible = false
	bounds_button.pressed.connect(_show_bucket_bounds)
	toolbar.add_child(bounds_button)
	_create_bounds_dialog()
	toolbar.visible = false
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, toolbar)

func _on_edit_mode_toggled(enabled: bool) -> void:
	if not enabled:
		_end_for_context_change()
	edit_mode = enabled
	has_hover = false
	edit_button.text = "地形编辑：开启" if enabled else "地形编辑：关闭"
	tool_choice.disabled = not enabled
	bounds_button.disabled = not enabled
	update_overlays()

func _on_tool_selected(index: int) -> void:
	_end_for_context_change()
	tool_mode = tool_choice.get_item_id(index)
	bounds_button.visible = tool_mode == ToolMode.BUCKET
	update_overlays()

func _handles(object: Object) -> bool:
	return object is Node2D and object.get_script() == DualGridMapScript

func _edit(object: Object) -> void:
	_end_for_context_change()
	current_map = object if is_instance_valid(object) else null
	has_hover = false
	update_overlays()

func _make_visible(visible: bool) -> void:
	if toolbar != null:
		toolbar.visible = visible
	if not visible:
		_end_for_context_change()
		current_map = null
		has_hover = false
		if edit_button != null:
			edit_button.button_pressed = false
	update_overlays()

func _apply_changes() -> void:
	# Saving finishes a brush stroke; other uncommitted gestures are cancelled.
	_end_for_context_change()

func _get_map_view_transform() -> Transform2D:
	var viewport := EditorInterface.get_editor_viewport_2d()
	return viewport.global_canvas_transform * current_map.global_transform

func _event_to_cell(view_pos: Vector2) -> Vector2i:
	var transform := _get_map_view_transform()
	var local_pos: Vector2 = transform.affine_inverse() * view_pos
	return current_map.local_to_logic_cell(local_pos)

func _begin_stroke(grass: bool, cell: Vector2i, button: int) -> void:
	is_painting = true
	paint_grass = grass
	stroke_button = button
	stroke_before = current_map.grass_cells.duplicate()
	last_painted_cell = cell
	rectangle_start = cell
	hovered_cell = cell
	has_hover = true
	if tool_mode == ToolMode.BRUSH:
		_paint_cell(cell)

func _paint_cell(pos: Vector2i) -> void:
	if is_instance_valid(current_map) and current_map.has_grass(pos) != paint_grass:
		current_map.set_grass(pos, paint_grass)

func _paint_line(from_cell: Vector2i, to_cell: Vector2i) -> void:
	var steps: int = maxi(absi(to_cell.x - from_cell.x), absi(to_cell.y - from_cell.y))
	if steps == 0:
		_paint_cell(to_cell)
		return
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		_paint_cell(Vector2i(roundi(lerpf(float(from_cell.x), float(to_cell.x), t)), roundi(lerpf(float(from_cell.y), float(to_cell.y), t))))

func _rectangle_bounds() -> Rect2i:
	var first := Vector2i(mini(rectangle_start.x, hovered_cell.x), mini(rectangle_start.y, hovered_cell.y))
	var last := Vector2i(maxi(rectangle_start.x, hovered_cell.x), maxi(rectangle_start.y, hovered_cell.y))
	return Rect2i(first, last - first + Vector2i.ONE)

func _apply_rectangle() -> void:
	# Build once and assign once, rather than invoking a map redraw per cell.
	var bounds := _rectangle_bounds()
	var updated: Array[Vector2i] = []
	if paint_grass:
		updated = current_map.grass_cells.duplicate()
		var occupied: Dictionary = {}
		for p in updated:
			occupied[p] = true
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var p := Vector2i(x, y)
				if not occupied.has(p):
					updated.append(p)
					occupied[p] = true
	else:
		for p in current_map.grass_cells:
			if not bounds.has_point(p):
				updated.append(p)
	current_map.grass_cells = updated

func _finish_stroke() -> void:
	if not is_painting:
		return
	is_painting = false
	stroke_button = MOUSE_BUTTON_NONE
	if not is_instance_valid(current_map):
		stroke_before.clear()
		return
	if tool_mode == ToolMode.RECTANGLE:
		_apply_rectangle()
	if tool_mode == ToolMode.BUCKET:
		var result: Dictionary = FloodFill.apply(stroke_before, rectangle_start, paint_grass, bucket_bounds)
		if not result["ok"]:
			push_warning("DualGrid: " + str(result["reason"]))
			stroke_before.clear()
			update_overlays()
			return
		current_map.grass_cells = result["cells"]
	var stroke_after: Array[Vector2i] = current_map.grass_cells.duplicate()
	if stroke_after != stroke_before:
		var undo_redo := get_undo_redo()
		var action_name := "DualGrid 矩形填充" if tool_mode == ToolMode.RECTANGLE else "DualGrid 绘制地形"
		if tool_mode == ToolMode.RECTANGLE and not paint_grass:
			action_name = "DualGrid 矩形擦除"
		if tool_mode == ToolMode.BUCKET:
			action_name = "DualGrid 油漆桶填充" if paint_grass else "DualGrid 油漆桶擦除"
		undo_redo.create_action(action_name, UndoRedo.MERGE_DISABLE, current_map)
		undo_redo.add_do_property(current_map, "grass_cells", stroke_after)
		undo_redo.add_undo_property(current_map, "grass_cells", stroke_before.duplicate())
		undo_redo.commit_action(false)
	stroke_before.clear()
	update_overlays()

func _cancel_stroke() -> void:
	if not is_painting:
		return
	if tool_mode == ToolMode.BRUSH and is_instance_valid(current_map):
		current_map.grass_cells = stroke_before.duplicate()
	is_painting = false
	stroke_button = MOUSE_BUTTON_NONE
	stroke_before.clear()
	update_overlays()

func _end_for_context_change() -> void:
	if tool_mode != ToolMode.BRUSH:
		_cancel_stroke()
	else:
		_finish_stroke()

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not edit_mode or not is_instance_valid(current_map):
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_painting:
			_cancel_stroke()
			return true
		return false
	# Settle a gesture before undo/redo or save shortcuts are forwarded.
	if event is InputEventKey and event.pressed and (event.ctrl_pressed or event.meta_pressed):
		if event.keycode in [KEY_Z, KEY_Y, KEY_S]:
			_end_for_context_change()
		return false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		var button: int = mouse_event.button_index
		if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
			return false
		if mouse_event.pressed:
			if is_painting:
				return true
			if mouse_event.alt_pressed or mouse_event.ctrl_pressed or mouse_event.meta_pressed:
				return false
			_begin_stroke(button == MOUSE_BUTTON_LEFT, _event_to_cell(mouse_event.position), button)
		else:
			if not is_painting:
				return false
			if button != stroke_button:
				return true
			hovered_cell = _event_to_cell(mouse_event.position)
			if tool_mode == ToolMode.BRUSH:
				_paint_line(last_painted_cell, hovered_cell)
			_finish_stroke()
		update_overlays()
		return true
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		# Release outside the viewport: cancel uncommitted rectangle/bucket on re-entry.
		if is_painting:
			var expected_mask: int = MOUSE_BUTTON_MASK_LEFT if stroke_button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
			if (motion.button_mask & expected_mask) == 0:
				_end_for_context_change()
		hovered_cell = _event_to_cell(motion.position)
		has_hover = true
		if is_painting and tool_mode == ToolMode.BRUSH:
			_paint_line(last_painted_cell, hovered_cell)
			last_painted_cell = hovered_cell
		update_overlays()
		return is_painting
	return false

func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not edit_mode or not is_instance_valid(current_map):
		return
	if tool_mode == ToolMode.BUCKET:
		var first: Rect2 = current_map.get_logic_cell_rect(bucket_bounds.position)
		var last: Rect2 = current_map.get_logic_cell_rect(bucket_bounds.end - Vector2i.ONE)
		var bounds_rect := Rect2(first.position, last.end - first.position)
		var view_transform := _get_map_view_transform()
		var border := PackedVector2Array([
			view_transform * bounds_rect.position,
			view_transform * Vector2(bounds_rect.end.x, bounds_rect.position.y),
			view_transform * bounds_rect.end,
			view_transform * Vector2(bounds_rect.position.x, bounds_rect.end.y),
			view_transform * bounds_rect.position
		])
		overlay.draw_polyline(border, Color(0.3, 0.7, 1.0, 0.9), 2.0)
	if not has_hover:
		return
	var rect: Rect2 = current_map.get_logic_cell_rect(hovered_cell)
	if is_painting and tool_mode == ToolMode.RECTANGLE:
		var bounds := _rectangle_bounds()
		var first: Rect2 = current_map.get_logic_cell_rect(bounds.position)
		var last: Rect2 = current_map.get_logic_cell_rect(bounds.end - Vector2i.ONE)
		rect = Rect2(first.position, last.end - first.position)
	var transform := _get_map_view_transform()
	var points := PackedVector2Array([
		transform * rect.position,
		transform * Vector2(rect.end.x, rect.position.y),
		transform * rect.end,
		transform * Vector2(rect.position.x, rect.end.y)
	])
	var color := Color(0.2, 0.9, 0.3, 0.22)
	if is_painting and not paint_grass:
		color = Color(0.95, 0.3, 0.2, 0.22)
	overlay.draw_colored_polygon(points, color)
	points.append(points[0])
	overlay.draw_polyline(points, Color.WHITE, 1.5)

func _create_bounds_dialog() -> void:
	bounds_dialog = ConfirmationDialog.new()
	bounds_dialog.title = "油漆桶填充范围（逻辑格）"
	bounds_dialog.min_size = Vector2i(360, 240)
	EditorInterface.get_base_control().add_child(bounds_dialog)
	var layout := VBoxContainer.new()
	bounds_dialog.add_child(layout)
	var hint := Label.new()
	hint.text = "填充和擦除都只作用于蓝框内。\n默认：(-16,-16) 起，32×32格。"
	layout.add_child(hint)
	var names := ["起点 X", "起点 Y", "宽度", "高度"]
	for i in range(4):
		var row := HBoxContainer.new()
		layout.add_child(row)
		var label := Label.new()
		label.text = names[i]
		label.custom_minimum_size.x = 100
		row.add_child(label)
		var input := SpinBox.new()
		input.min_value = -1000000 if i < 2 else 1
		input.max_value = 1000000 if i < 2 else 256
		input.step = 1
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(input)
		bounds_inputs.append(input)
	bounds_dialog.confirmed.connect(_confirm_bucket_bounds)

func _show_bucket_bounds() -> void:
	_end_for_context_change()
	var values := [bucket_bounds.position.x, bucket_bounds.position.y, bucket_bounds.size.x, bucket_bounds.size.y]
	for i in range(4):
		bounds_inputs[i].value = values[i]
	bounds_dialog.popup_centered()

func _confirm_bucket_bounds() -> void:
	# Read pending text edits too, including a value typed just before Enter.
	for input in bounds_inputs:
		input.apply()
	bucket_bounds = Rect2i(int(bounds_inputs[0].value), int(bounds_inputs[1].value), int(bounds_inputs[2].value), int(bounds_inputs[3].value))
	update_overlays()

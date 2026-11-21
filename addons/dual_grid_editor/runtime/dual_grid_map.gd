@tool
extends Node2D

const Solver = preload("res://addons/dual_grid_editor/core/dual_grid_solver.gd")

@export_range(16, 128, 8)
var cell_size: int = 64:
	set(value):
		cell_size = value
		queue_redraw()

@export var grass_color: Color = Color("#70AD70"):
	set(value):
		grass_color = value
		queue_redraw()

@export var dirt_color: Color = Color("#C8A77B"):
	set(value):
		dirt_color = value
		queue_redraw()

@export var show_grid: bool = true:
	set(value):
		show_grid = value
		queue_redraw()

@export var grass_cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
	set(value):
		grass_cells = value
		queue_redraw()

# v0.3: Canonical atlas bits: TL=1, TR=2, BL=4, BR=8.
@export_group("Dual Grid Atlas")
# Reference image layout, with TL=1, TR=2, BL=4, BR=8.
const STANDARD_MASK_TO_INDEX = [12, 15, 8, 9, 0, 11, 14, 7, 13, 4, 1, 10, 3, 2, 5, 6]
@export_enum("Reference 4x4", "Mask Order 4x4", "Custom")
var atlas_layout: int = 0:
	set(value):
		atlas_layout = value
		queue_redraw()

@export var terrain_atlas: Texture2D:
	set(value):
		if terrain_atlas != null and terrain_atlas.changed.is_connected(queue_redraw):
			terrain_atlas.changed.disconnect(queue_redraw)
		terrain_atlas = value
		if terrain_atlas != null and not terrain_atlas.changed.is_connected(queue_redraw):
			terrain_atlas.changed.connect(queue_redraw)
		queue_redraw()

@export var atlas_tile_size: Vector2i = Vector2i(32, 32):
	set(value):
		atlas_tile_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		queue_redraw()

# Index of each mask's tile, counted left-to-right then top-to-bottom.
@export var mask_to_atlas_index: PackedInt32Array = PackedInt32Array([
	0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
]):
	set(value):
		mask_to_atlas_index = value
		queue_redraw()

func _draw() -> void:
	var cells: Dictionary = {}
	var display_cells: Dictionary = {}
	for pos in grass_cells:
		cells[pos] = true
		for affected in Solver.get_affected_cells(pos):
			display_cells[affected] = true
	for pos in display_cells:
		var mask: int = Solver.get_display_mask(cells, pos)
		_draw_display_cell(pos, mask)

func _draw_display_cell(pos: Vector2i, mask: int) -> void:
	var size := float(cell_size)
	var half := size / 2.0
	var origin := Vector2((pos.x + 0.5) * size, (pos.y + 0.5) * size)
	var rect := Rect2(origin, Vector2(size, size))
	# Preserve v0.2 dirt background beneath transparent atlas pixels.
	draw_rect(rect, dirt_color)
	var flags := [Solver.TOP_LEFT, Solver.TOP_RIGHT, Solver.BOTTOM_LEFT, Solver.BOTTOM_RIGHT]
	var atlas_mask: int = 0
	for i in range(4):
		if (mask & flags[i]) != 0:
			atlas_mask |= 1 << i
	var drew_atlas: bool = _draw_atlas_cell(rect, atlas_mask)
	if not drew_atlas:
		var offsets := [Vector2.ZERO, Vector2(half, 0), Vector2(0, half), Vector2(half, half)]
		for i in range(4):
			if (mask & flags[i]) != 0:
				draw_rect(Rect2(origin + offsets[i], Vector2(half, half)), grass_color)
	if show_grid:
		draw_rect(rect, Color(0.2, 0.2, 0.2, 0.5), false, 1.0)

func _draw_atlas_cell(rect: Rect2, mask: int) -> bool:
	# Zero contributes no grass texture. Background was already drawn.
	if mask == 0:
		return true
	if terrain_atlas == null:
		return false
	var width: int = terrain_atlas.get_width()
	var height: int = terrain_atlas.get_height()
	if width % atlas_tile_size.x != 0 or height % atlas_tile_size.y != 0:
		return false
	var columns: int = floori(float(width) / float(atlas_tile_size.x))
	var rows: int = floori(float(height) / float(atlas_tile_size.y))
	if columns < 1 or rows < 1:
		return false
	var index: int = -1
	match atlas_layout:
		0:
			if columns != 4 or rows != 4:
				return false
			index = STANDARD_MASK_TO_INDEX[mask]
		1:
			if columns != 4 or rows != 4:
				return false
			index = mask
		2:
			if mask_to_atlas_index.size() != 16:
				return false
			index = mask_to_atlas_index[mask]
		_:
			return false
	if index < 0 or index >= columns * rows:
		return false
	var source_pos := Vector2(index % columns, floori(float(index) / float(columns))) * Vector2(atlas_tile_size)
	# Set texture_filter=Nearest on the map in Inspector for pixel art.
	draw_texture_rect_region(terrain_atlas, rect, Rect2(source_pos, Vector2(atlas_tile_size)))
	return true

func set_grass(pos: Vector2i, enabled: bool) -> void:
	var updated := grass_cells.duplicate()
	if enabled and not updated.has(pos):
		updated.append(pos)
	elif not enabled:
		updated.erase(pos)
	grass_cells = updated

func has_grass(pos: Vector2i) -> bool:
	return grass_cells.has(pos)

func local_to_logic_cell(local_pos: Vector2) -> Vector2i:
	return Vector2i(floori(local_pos.x / float(cell_size)), floori(local_pos.y / float(cell_size)))

func get_logic_cell_rect(pos: Vector2i) -> Rect2:
	return Rect2(Vector2(pos) * float(cell_size), Vector2.ONE * float(cell_size))

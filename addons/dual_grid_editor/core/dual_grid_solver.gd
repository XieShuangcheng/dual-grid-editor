
@tool
extends RefCounted

# 四个角的位标记
const TOP_LEFT := 1
const TOP_RIGHT := 2
const BOTTOM_LEFT := 4
const BOTTOM_RIGHT := 8


# 计算四角组合
static func calculate_mask(
	top_left: bool,
	top_right: bool,
	bottom_left: bool,
	bottom_right: bool
) -> int:
	var mask := 0

	if top_left:
		mask |= TOP_LEFT

	if top_right:
		mask |= TOP_RIGHT

	if bottom_left:
		mask |= BOTTOM_LEFT

	if bottom_right:
		mask |= BOTTOM_RIGHT

	return mask


# 根据逻辑网格数据计算显示网格状态
static func get_display_mask(
	cells: Dictionary,
	display_pos: Vector2i
) -> int:
	var x := display_pos.x
	var y := display_pos.y

	var tl := bool(cells.get(Vector2i(x, y), false))
	var tr := bool(cells.get(Vector2i(x + 1, y), false))
	var bl := bool(cells.get(Vector2i(x, y + 1), false))
	var br := bool(cells.get(Vector2i(x + 1, y + 1), false))

	return calculate_mask(tl, tr, bl, br)


# 逻辑格子发生改变后，需要更新的显示格子
static func get_affected_cells(
	logic_pos: Vector2i
) -> Array[Vector2i]:
	return [
		logic_pos,
		logic_pos + Vector2i(-1, 0),
		logic_pos + Vector2i(0, -1),
		logic_pos + Vector2i(-1, -1)
	]

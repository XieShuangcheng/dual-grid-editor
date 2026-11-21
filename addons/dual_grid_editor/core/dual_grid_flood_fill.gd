@tool
extends RefCounted

const LIMIT: int = 65536
const DIRECTIONS = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

# Pure operation: caller's array is never mutated. Rect2i excludes end.
static func apply(before: Array[Vector2i], seed: Vector2i, paint: bool, bounds: Rect2i) -> Dictionary:
	if bounds.size.x <= 0 or bounds.size.y <= 0 or bounds.size.x > 256 or bounds.size.y > 256:
		return {"ok": false, "cells": before.duplicate(), "reason": "填充范围宽高必须为1到256格"}
	if not bounds.has_point(seed):
		return {"ok": false, "cells": before.duplicate(), "reason": "点击位置在填充范围之外"}
	var occupied: Dictionary = {}
	for p in before:
		occupied[p] = true
	var source_grass: bool = occupied.has(seed)
	if source_grass == paint:
		return {"ok": true, "cells": before.duplicate(), "reason": ""}
	var queue: Array[Vector2i] = [seed]
	var visited: Dictionary = {seed: true}
	var head: int = 0
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		for direction in DIRECTIONS:
			var neighbor: Vector2i = p + direction
			if not bounds.has_point(neighbor) or visited.has(neighbor):
				continue
			if occupied.has(neighbor) != source_grass:
				continue
			if queue.size() >= LIMIT:
				return {"ok": false, "cells": before.duplicate(), "reason": "区域超过65536格，本次操作已取消"}
			visited[neighbor] = true
			queue.append(neighbor)
	var updated: Array[Vector2i] = []
	if paint:
		updated = before.duplicate()
		updated.append_array(queue)
	else:
		for p in before:
			if not visited.has(p):
				updated.append(p)
	return {"ok": true, "cells": updated, "reason": ""}

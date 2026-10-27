extends Node

# ============================================================
# SURVIVAL GAME - 8 FIXED BEACH SPAWN POINTS
# Loaded via preload (not an autoload).
# ============================================================

const EDGE: float = 180.0

const POINTS: Array[Vector3] = [
	Vector3(0.0, 1.0, EDGE),
	Vector3(EDGE * 0.7, 1.0, EDGE * 0.7),
	Vector3(EDGE, 1.0, 0.0),
	Vector3(EDGE * 0.7, 1.0, -EDGE * 0.7),
	Vector3(0.0, 1.0, -EDGE),
	Vector3(-EDGE * 0.7, 1.0, -EDGE * 0.7),
	Vector3(-EDGE, 1.0, 0.0),
	Vector3(-EDGE * 0.7, 1.0, EDGE * 0.7),
]

static func get_random_point() -> Vector3:
	return POINTS[randi() % POINTS.size()]

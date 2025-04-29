extends Resource
class_name PointList

@export var points: Array[Vector2]

var _optimal_size: Vector2i = Vector2i(0, 0)
var _optimal_size_hash: int = ~0

func _init(p_points: Array[Vector2] = []) -> void:
  points = p_points

func to_byte_array() -> PackedByteArray:
  var floats := PackedFloat32Array()
  floats.resize(len(points) * 2)
  for i in len(points):
    floats[i * 2] = points[i].x
    floats[i * 2 + 1] = points[i].y
  return floats.to_byte_array()

func count() -> int:
  return len(points)

func get_point(index: int) -> Vector2:
  return points.get(index)

func get_optimal_size() -> Vector2i:
  if _optimal_size_hash == points.hash():
    return _optimal_size
  var size := Vector2i(0, 0)
  for p in points:
    size.x = max(p.x, size.x)
    size.y = max(p.y, size.y)
  var a := ceilf(log(size.x) / log(2))
  var b := ceilf(log(size.y) / log(2))
  var final_size: int = 2 ** max(a, b)
  _optimal_size = Vector2i(final_size, final_size)
  _optimal_size_hash = points.hash()
  return _optimal_size

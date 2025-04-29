extends DTImplementation
class_name BowyerWatson

func execute() -> void:
  var super_triangle := Vector3i(-1, -2, -3)
  triangles = [super_triangle]

  for i in points.count():
    new_phase_title.emit("Point %d of %d" % [i, points.count()])
    var p := _get_point(i)
    var bad: Array[Vector3i] = []
    for t in triangles:
      if CGUtil.in_circumcircle(_get_point(t.x), _get_point(t.y), _get_point(t.z), p):
        bad.push_back(t)
    var polygon := []
    for t in bad:
      for edge in _get_edges(t):
        if !_is_bad_edge(bad, edge):
          polygon.push_back(edge)
    for t in bad:
      triangles.erase(t)
    for edge in polygon:
      triangles.push_back(Vector3i(edge[0], edge[1], i))
    queue_redraw.call_deferred()
    await _execution_breakpoint()
    
  new_phase_title.emit("Removed triangles connected to super triangle")
  triangles = triangles.filter(_filter_super_triangle)
  queue_redraw.call_deferred()
  await _execution_breakpoint()

  new_phase_title.emit("Done!")

func _get_point(idx: int) -> Vector2:
  if idx == -1:
    return Vector2(-_texture_size.x * 10, -_texture_size.y * 10)
  if idx == -2:
    return Vector2(_texture_size.x * 10, -_texture_size.y * 10)
  if idx == -3:
    return Vector2(0, _texture_size.y * 10)
  return points.get_point(idx)

func _filter_super_triangle(tri: Vector3i) -> bool:
  for i in tri:
    if i < 0:
      return false
  return true

func _is_bad_edge(bad: Array[Vector3i], edge: Array) -> bool:
  for b in bad:
    for bad_edge in _get_edges(b):
      if edge == [bad_edge[1], bad_edge[0]]:
        return true
  return false

func _get_edges(t: Vector3i) -> Array:
  return [[t.x, t.y], [t.y, t.z], [t.z, t.x]]

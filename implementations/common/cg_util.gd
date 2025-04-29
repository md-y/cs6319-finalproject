class_name CGUtil

static func in_circumcircle(a: Vector2, b: Vector2, c: Vector2, p: Vector2) -> bool:
  var ax = a.x - p.x
  var ay = a.y - p.y
  var bx = b.x - p.x
  var by = b.y - p.y
  var cx = c.x - p.x
  var cy = c.y - p.y

  var det = (ax * ax + ay * ay) * (bx * cy - cx * by) - (bx * bx + by * by) * (ax * cy - cx * ay) + (cx * cx + cy * cy) * (ax * by - bx * ay)
  var orient = (b - a).cross(c - a)
  return (orient * det) > 0

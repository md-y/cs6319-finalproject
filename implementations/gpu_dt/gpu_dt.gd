extends DTImplementation
class_name GPU_DT

var _voronoi_shader: RID = _init_shader(load("res://implementations/gpu_dt/compute_shaders/gpu_dt_voronoi.glsl"));
const _VORONOI_LOCAL_SIZE = 16
var _postprocess_shader: RID = _init_shader(load("res://implementations/gpu_dt/compute_shaders/gpu_dt_postprocess.glsl"));
const _POSTPROCESS_LOCAL_SIZE = 16

var _gpu_dt_display_material: ShaderMaterial = load("res://implementations/gpu_dt/resources/gpu_dt_display_material.tres")

func _ready() -> void:
  material = _gpu_dt_display_material

func execute() -> void:
  var tx := _create_texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT)
  var display_texture: Texture2DRD = material.get_shader_parameter("input_texture")
  display_texture.texture_rd_rid = tx

  var points_array := points.to_byte_array()
  var points_buffer := _rd.storage_buffer_create(points_array.size(), points_array)

  if len(triangles) > 0:
    triangles.resize(0)

  new_phase_title.emit("Ready")
  await _execution_breakpoint()
  await _execute_voronoi(tx, points_buffer)
  var border_pixels := await _execute_postprocess(tx, points_buffer)

  material = null

  await _fix_hull(border_pixels)
  queue_redraw.call_deferred()

  await _flip_edges()
  queue_redraw.call_deferred()

  new_phase_title.emit("Done!")

  _rd.free_rid(points_buffer)

func _execute_voronoi(tx: RID, points_buffer: RID) -> void:
  var image_set := _create_uniform_set(RenderingDevice.UNIFORM_TYPE_IMAGE, tx, _voronoi_shader, 0)
  var points_set := _create_uniform_set(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, points_buffer, _voronoi_shader, 1)

  var x_groups_all_pixels = ceili(_texture_size.x / float(_VORONOI_LOCAL_SIZE))
  var y_groups_all_pixels = ceili(_texture_size.y / float(_VORONOI_LOCAL_SIZE))
  var jfa_iteration_count = ceili(log(max(_texture_size.x, _texture_size.y)) / log(2)) + 1
  
  var phases := [
  [
    "Initialization",
    1, # Iterations
    ceili(points.count() / float(_VORONOI_LOCAL_SIZE * _VORONOI_LOCAL_SIZE)), # X group
    1 # Y Group
  ],
  [
    "1+JFA",
    jfa_iteration_count,
    x_groups_all_pixels,
    y_groups_all_pixels
  ],
  [
    "Island Removal",
    4,
    x_groups_all_pixels,
    y_groups_all_pixels
  ],
  [
    "Find Voronoi Vertices",
    1,
    x_groups_all_pixels,
    y_groups_all_pixels
  ]
  ]

  for p in len(phases):
    var x_groups = phases[p][2]
    var y_groups = phases[p][3]
    for i in phases[p][1]:
      if phases[p][1] == 1:
        new_phase_title.emit(phases[p][0])
      else:
        new_phase_title.emit("%s (Iteration %d)" % [phases[p][0], i + 1])

      var pipeline := _rd.compute_pipeline_create(_voronoi_shader)
      var compute_list := _rd.compute_list_begin()
      _rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
      _rd.compute_list_bind_uniform_set(compute_list, image_set, 0)
      _rd.compute_list_bind_uniform_set(compute_list, points_set, 1)

      var push_constants := PackedInt32Array([p, i, 0, 0]).to_byte_array()
      _rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())

      _rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
      _rd.compute_list_end()
      _rd.free_rid(pipeline)
      await _execution_breakpoint()

  _rd.free_rid(points_set)
  _rd.free_rid(image_set)

func _execute_postprocess(tx: RID, points_buffer: RID) -> Array[Vector4]:
  var image_set := _create_uniform_set(RenderingDevice.UNIFORM_TYPE_IMAGE, tx, _postprocess_shader, 0)
  var points_set := _create_uniform_set(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, points_buffer, _postprocess_shader, 1)

  var border_pixels_values := PackedFloat32Array()
  border_pixels_values.resize((_texture_size.x + _texture_size.y - 2) * 8)
  var border_pixels_array := border_pixels_values.to_byte_array()
  var border_pixels_buffer = _rd.storage_buffer_create(border_pixels_array.size(), border_pixels_array)
  var border_pixels_set = _create_uniform_set(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, border_pixels_buffer, _postprocess_shader, 2)

  var triangle_array := PackedInt32Array([0]).to_byte_array()
  var triangle_buffer := _rd.storage_buffer_create(triangle_array.size(), triangle_array)
  var triangles_set := _create_uniform_set(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, triangle_buffer, _postprocess_shader, 3)

  var x_groups = ceili(_texture_size.x / float(_POSTPROCESS_LOCAL_SIZE))
  var y_groups = ceili(_texture_size.y / float(_POSTPROCESS_LOCAL_SIZE))

  for p in 2:
    if p == 0:
      new_phase_title.emit("Count Triangles and Gather Border Pixels")
    if p == 1:
      new_phase_title.emit("Generate Triangles")

    var pipeline := _rd.compute_pipeline_create(_postprocess_shader)
    var compute_list := _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
    _rd.compute_list_bind_uniform_set(compute_list, image_set, 0)
    _rd.compute_list_bind_uniform_set(compute_list, points_set, 1)
    _rd.compute_list_bind_uniform_set(compute_list, border_pixels_set, 2)
    _rd.compute_list_bind_uniform_set(compute_list, triangles_set, 3)

    var push_constants := PackedInt32Array([p, 0, 0, 0]).to_byte_array()
    _rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())

    _rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
    _rd.compute_list_end()
    _rd.free_rid(pipeline)

    # Actually setup triangle buffer using count
    if p == 0:
      triangle_array = _rd.buffer_get_data(triangle_buffer)
      var triangle_count = triangle_array.decode_s32(0)
      var empty_triangles = PackedInt32Array()
      empty_triangles.resize(triangle_count * 3)
      triangle_array.append_array(empty_triangles.to_byte_array())
      triangle_buffer = _rd.storage_buffer_create(triangle_array.size(), triangle_array)
      triangles_set = _create_uniform_set(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, triangle_buffer, _postprocess_shader, 1)

      border_pixels_array = _rd.buffer_get_data(border_pixels_buffer)
      border_pixels_values = border_pixels_array.to_float32_array()
      await _execution_breakpoint()

    # Get triangles
    if p == 1:
      triangle_array = _rd.buffer_get_data(triangle_buffer)
      await _execution_breakpoint()

  _rd.free_rid(image_set)

  var triangle_sites := triangle_array.slice(4).to_int32_array()
  assert(len(triangle_sites) % 3 == 0)
  @warning_ignore("integer_division")
  triangles.resize(len(triangle_sites) / 3)
  for i in len(triangles):
    var ti = i * 3
    triangles[i] = Vector3i(triangle_sites.get(ti), triangle_sites.get(ti + 1), triangle_sites.get(ti + 2))

  var border_pixels: Array[Vector4] = []
  assert(len(border_pixels_values) % 4 == 0)
  @warning_ignore("integer_division")
  border_pixels.resize(len(border_pixels_values) / 4)
  for i in len(border_pixels):
    var pi = i * 4
    border_pixels[i] = Vector4(border_pixels_values.get(pi), border_pixels_values.get(pi + 1), border_pixels_values.get(pi + 2), border_pixels_values.get(pi + 3))

  return border_pixels

func _fix_hull(pixels: Array[Vector4]) -> void:
  var stack: Array[int] = []
  stack.push_back(int(pixels[0].x))
  for p in pixels:
    if int(p.x) == stack[-1]:
      continue
    stack.push_back(int(p.x))
    while len(stack) >= 3 && !_is_clockwise(stack[-1], stack[-2], stack[-3]):
      triangles.push_back(Vector3i(stack[-1], stack[-2], stack[-3]))
      queue_redraw.call_deferred()

      new_phase_title.emit("Fixed Hull for triangles %d, %d, and %d" % [stack[-1], stack[-2], stack[-3]])
      await _execution_breakpoint()
      stack.pop_at(-2)

func _flip_edges() -> void:
  var triangle_edges: Dictionary = {}

  for i in len(triangles):
    _update_incident_triangles(triangle_edges, i)

  var did_flip := true
  while did_flip:
    did_flip = false
    for tri_idx in len(triangles):
      var tri := triangles[tri_idx]
      var a := tri.x
      var b := tri.y
      var c := tri.z
      var inc_edge := [b, a]
      if inc_edge not in triangle_edges:
        continue
      for j in len(triangle_edges[inc_edge]):
        var inc_idx: int = triangle_edges[inc_edge][j]
        var inc = triangles[inc_idx]
        if tri == inc || inc.x != a || inc.z != b:
          continue
        var d: int = inc.y
        if _in_circle(tri, d):
          did_flip = true
          _update_incident_triangles(triangle_edges, tri_idx, false)
          _update_incident_triangles(triangle_edges, inc_idx, false)
          triangles[tri_idx] = Vector3i(a, d, c)
          triangles[inc_idx] = Vector3i(c, b, d)
          _update_incident_triangles(triangle_edges, tri_idx)
          _update_incident_triangles(triangle_edges, inc_idx)

          queue_redraw.call_deferred()
          new_phase_title.emit("Flipped Edge for triangles %d and %d" % [tri_idx, inc_idx])
          await _execution_breakpoint()

func _update_incident_triangles(triangle_edges: Dictionary, tri_idx: int, add = true) -> void:
  var tri := triangles[tri_idx]
  for e in [[tri.x, tri.y], [tri.y, tri.z], [tri.z, tri.x]]:
    if e not in triangle_edges:
      triangle_edges[e] = []
    if add:
      if tri not in triangle_edges[e]:
        triangle_edges[e].push_back(tri_idx)
    else:
      triangle_edges[e].erase(tri_idx)
      
func _is_clockwise(i1: int, i2: int, i3: int) -> bool:
  var p1 := points.get_point(i1)
  var p2 := points.get_point(i2)
  var p3 := points.get_point(i3)
  var cross := (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
  return cross < 0

func _in_circle(tri: Vector3i, other_site: int) -> bool:
  var a := points.get_point(tri.x)
  var b := points.get_point(tri.y)
  var c := points.get_point(tri.z)
  var p := points.get_point(other_site)
  return CGUtil.in_circumcircle(a, b, c, p)

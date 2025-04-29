extends DTImplementation
class_name GDel2D

var _shader: RID = _init_shader(load("res://implementations/gdel2d/compute_shaders/gdel2d.glsl"));
const _SHADER_LOCAL_SIZE = 16

var _gdel2d_display_material: ShaderMaterial = load("res://implementations/gdel2d/resources/gdel2d_display_material.tres")

func _ready() -> void:
  material = _gdel2d_display_material

func execute() -> void:
  await _execute_gpu()
  
  triangles = triangles.filter(_filter_super_triangle)
  new_phase_title.emit("Removed points connected to super triangle")
  queue_redraw.call_deferred()
  await _execution_breakpoint()

  new_phase_title.emit("Done!")

func _execute_gpu() -> void:
  #### Points Buffer
  var points_float_array := PackedFloat32Array([0, 0, 0, 0])
  points_float_array.resize(4 + points.count() * 4)  
  for i in points.count():
    var idx := 4 + i * 4
    points_float_array[idx] = points.get_point(i).x
    points_float_array[idx + 1] = points.get_point(i).y
    points_float_array[idx + 2] = 0 # Metadata
  var points_byte_array := points_float_array.to_byte_array()
  var points_buffer := _rd.storage_buffer_create(points_byte_array.size(), points_byte_array)
  var points_set := _create_uniform_set(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, points_buffer, _shader, 0)

  #### Triangle Buffer
  var triangle_int_array := PackedInt32Array()
  var triangle_count := points.count() * 2
  triangles.resize(triangle_count)
  var triangle_prefix_size = 4;
  triangle_int_array.resize(triangle_prefix_size + triangle_count * 4)

  triangle_int_array[1] = 1; # Next index should start at 1
  triangle_int_array[triangle_prefix_size] = -1
  triangle_int_array[triangle_prefix_size + 1] = -2
  triangle_int_array[triangle_prefix_size + 2] = -3

  var triangle_byte_array := triangle_int_array.to_byte_array()
  var triangle_buffer := _rd.storage_buffer_create(triangle_byte_array.size(), triangle_byte_array)
  var triangles_set := _create_uniform_set(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, triangle_buffer, _shader, 1)

  #### Insertion Buffer
  var insertion_int_array := PackedInt32Array()
  insertion_int_array.resize(triangle_count)
  insertion_int_array.fill(-1)
  var insertion_byte_array := insertion_int_array.to_byte_array()
  var insertion_buffer := _rd.storage_buffer_create(insertion_byte_array.size(), insertion_byte_array)
  var insertion_set := _create_uniform_set(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, insertion_buffer, _shader, 2)

  var iteration: int = 0
  var phase: int = 0

  var phases := [
    ["Update insertion array", points.count()],
    ["Split triangles", triangle_count],
    ["Fix bad edges", triangle_count],
  ]

  var inserted_count := 0;
  while inserted_count < points.count():
    phase = 0
    while phase < len(phases):
      new_phase_title.emit("%s (%d of %d points inserted)" % [phases[phase][0], inserted_count, points.count()])

      if phase == 2:
        var bad_edge_flag := _rd.buffer_get_data(triangle_buffer).decode_s32(0)
        if bad_edge_flag == 0:
          phase += 1
          iteration = 0
          continue

      var pipeline := _rd.compute_pipeline_create(_shader)
      var compute_list := _rd.compute_list_begin()
      _rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
      _rd.compute_list_bind_uniform_set(compute_list, points_set, 0)
      _rd.compute_list_bind_uniform_set(compute_list, triangles_set, 1)
      _rd.compute_list_bind_uniform_set(compute_list, insertion_set, 2)

      var push_constants := PackedInt32Array([phase, iteration, 0, 0]).to_byte_array()
      _rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())

      var x_groups := ceili(phases[phase][1] / float(_SHADER_LOCAL_SIZE * _SHADER_LOCAL_SIZE))
      _rd.compute_list_dispatch(compute_list, x_groups, 1, 1)
      _rd.compute_list_end()
      _rd.free_rid(pipeline)
      await _execution_breakpoint()

      var new_triangle_data := _rd.buffer_get_data(triangle_buffer).to_int32_array().slice(triangle_prefix_size)
      assert(len(new_triangle_data) >> 2 == triangle_count)
      for i in len(triangles):
        triangles[i] = Vector3i(new_triangle_data[i * 4], new_triangle_data[i * 4 + 1], new_triangle_data[i * 4 + 2])
      queue_redraw.call_deferred()

      if phase != 2:
        phase += 1
        iteration = 0
      iteration += 1
    inserted_count = _rd.buffer_get_data(points_buffer).decode_s32(0)

  _rd.free_rid(points_set)
  _rd.free_rid(triangles_set)
  _rd.free_rid(insertion_set)

func _filter_super_triangle(tri: Vector3i) -> bool:
  for i in 3:
    if tri[i] < 0:
      return false
  return true

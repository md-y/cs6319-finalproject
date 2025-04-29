extends Control
class_name DTImplementation

@export var points: PointList
@export var triangles: Array[Vector3i] = []

var breakpoints_enabled = true

var _texture_size: Vector2i:
  get:
    return points.get_optimal_size()

signal new_phase_title(title: String)

var _rd := RenderingServer.get_rendering_device()

signal breakpoint_continue()

func _init_shader(shader: RDShaderFile) -> RID:
  var spirv: RDShaderSPIRV = shader.get_spirv()
  return _rd.shader_create_from_spirv(spirv)

func _create_texture(format: RenderingDevice.DataFormat, no_data_color = Color(0, 0, 0, 0)) -> RID:
  # Only these formats are supported: https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/storage_rd/texture_storage.cpp#L2276
  var tf: RDTextureFormat = RDTextureFormat.new()
  tf.format = format
  tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
  tf.width = _texture_size.x
  tf.height = _texture_size.y
  tf.depth = 1
  tf.array_layers = 1
  tf.mipmaps = 1
  tf.usage_bits = (
      RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
      RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
      RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
      RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
      RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT |
      RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
  )

  var tx := _rd.texture_create(tf, RDTextureView.new(), [])
  _rd.texture_clear(tx, no_data_color, 0, 1, 0, 1)
  return tx

func _create_uniform_set(type: RenderingDevice.UniformType, value: RID, shader: RID, set_num: int, binding = 0) -> RID:
  var uniform := RDUniform.new()
  uniform.uniform_type = type
  uniform.binding = binding
  uniform.add_id(value)
  return _rd.uniform_set_create([uniform], shader, set_num)

func execute() -> void:
  pass

func continue_execution() -> void:
  RenderingServer.call_on_render_thread(breakpoint_continue.emit)

func _execution_breakpoint() -> void:
  if breakpoints_enabled:
    await breakpoint_continue

func _draw() -> void:
  draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
  for tri in triangles:
    if min(tri.x, tri.y, tri.z) < 0 || max(tri.x, tri.y, tri.z) >= points.count():
      continue
    var a := _remap_point(tri.x)
    var b := _remap_point(tri.y)
    var c := _remap_point(tri.z)
    draw_line(a, b, Color.CYAN, 2.0)
    draw_line(b, c, Color.CYAN, 2.0)
    draw_line(c, a, Color.CYAN, 2.0)

func _remap_point(point_idx: int) -> Vector2:
  var p := Vector2(points.get_point(point_idx))
  p.x = remap(p.x, 0, _texture_size.x, 0, size.x)
  p.y = remap(p.y, 0, _texture_size.y, 0, size.y)
  return p

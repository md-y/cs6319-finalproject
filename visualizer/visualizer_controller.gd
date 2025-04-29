extends Node
class_name VisualizerController

@export var points: PointList
@export var dt_implementation: DTImplementation
@export var run_info_label: Label

var _current_index = 1

func _ready() -> void:
  setup_implementation()

func skip_to_end() -> void:
  dt_implementation.breakpoints_enabled = false
  dt_implementation.continue_execution()

func step_execution() -> void:
  dt_implementation.breakpoints_enabled = true
  dt_implementation.continue_execution()

func setup_implementation() -> void:
  dt_implementation.points = points
  dt_implementation.new_phase_title.connect(update_label)
  RenderingServer.call_on_render_thread(dt_implementation.execute)

func reset_implementation() -> void:
  change_implementation(_current_index)

func update_label(text: String) -> void:
  run_info_label.text = text

func change_implementation(idx: int) -> void:
  var parent := dt_implementation.get_parent()
  parent.remove_child(dt_implementation)
  dt_implementation.queue_free()

  _current_index = idx
  
  match idx:
    0:
      dt_implementation = BowyerWatson.new()
    1:
      dt_implementation = GPU_DT.new()
    _:
      dt_implementation = BowyerWatson.new()
  
  parent.add_child(dt_implementation)
  setup_implementation()

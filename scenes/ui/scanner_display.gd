extends Control

## Scan progress bar + resulting nearby-object list — the "clear progress
## feedback" and "readable result" halves of the scanner spec. Deliberately
## separate from RadarDisplay: radar never shows this level of detail.
##
## Requires a Scanner hardpoint (see ModuleCatalog.SCANNER_HARDPOINT_TYPE_ID)
## — this whole display hides itself whenever the player's ship has none
## mounted/intact, checked live every frame same as RadarDisplay.
@export var result_display_duration: float = 5.0

var _ship: Ship
var _scanner: Scanner
var _progress_bar: ProgressBar
var _status_label: Label
var _results_container: VBoxContainer
var _result_timer: float = 0.0


func _ready() -> void:
	_ship = PlayerContext.get_ship()
	if _ship == null:
		return

	_scanner = _ship.get_scanner()
	_scanner.scan_started.connect(_on_scan_started)
	_scanner.scan_progress_updated.connect(_on_scan_progress)
	_scanner.scan_completed.connect(_on_scan_completed)
	_scanner.scan_cancelled.connect(_on_scan_cancelled)

	_build_ui()


## Top-right, opposite RadarDisplay (bottom-right) so the two never overlap.
const RIGHT_MARGIN: float = 10.0
const TOP_MARGIN: float = 10.0


func _build_ui() -> void:
	_status_label = Label.new()
	_status_label.text = "Scanning..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status_label.position = Vector2(-(240.0 + RIGHT_MARGIN), TOP_MARGIN)
	_status_label.size = Vector2(240, 20)
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 5)
	_status_label.visible = false
	add_child(_status_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(240, 18)
	_progress_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_progress_bar.position = Vector2(-(240.0 + RIGHT_MARGIN), TOP_MARGIN + 22.0)
	_progress_bar.visible = false
	add_child(_progress_bar)

	_results_container = VBoxContainer.new()
	_results_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_results_container.position = Vector2(-(280.0 + RIGHT_MARGIN), TOP_MARGIN)
	_results_container.size = Vector2(280, 140)
	_results_container.visible = false
	add_child(_results_container)


func _process(delta: float) -> void:
	if _ship == null:
		return

	if not _ship.has_scanner():
		_progress_bar.visible = false
		_status_label.visible = false
		_results_container.visible = false
		return

	if not _results_container.visible:
		return
	_result_timer -= delta
	if _result_timer <= 0.0:
		_results_container.visible = false


func _on_scan_started() -> void:
	_results_container.visible = false
	_progress_bar.value = 0.0
	_progress_bar.visible = true
	_status_label.visible = true


func _on_scan_progress(fraction: float) -> void:
	_progress_bar.value = fraction


func _on_scan_completed(results: Array[Dictionary]) -> void:
	_progress_bar.visible = false
	_status_label.visible = false

	for child in _results_container.get_children():
		child.queue_free()

	if results.is_empty():
		_results_container.add_child(_make_result_label("No objects in range."))
	else:
		for entry in results:
			var suffix: String = " (known)" if entry["already_known"] else ""
			var line: String = "%s — %d%s" % [entry["category"], int(entry["distance"]), suffix]
			_results_container.add_child(_make_result_label(line))

	_results_container.visible = true
	_result_timer = result_display_duration


func _on_scan_cancelled() -> void:
	_progress_bar.visible = false
	_status_label.visible = false


func _make_result_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	return label

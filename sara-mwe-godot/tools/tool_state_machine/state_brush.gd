extends RefCounted

class_name StateBrush

var canvas: MaCanvas
# The brush owns its own shader
var compute: MaCompute

var radius: float = 25.0
## Global opacity of the brush (0.0 to 1.0)
var opacity: float = 0.9
var color: Color = Color(1.0, 0.0, 0.0, 1.0)

## Automatically detects if user is using a tablet to stop mice from drawing tiny dots
var is_tablet: bool = true
## Curve for pressure sensitivity (1.0 is linear, > 1.0 makes light touches more precise)
var pressure_gamma: float = 0.5

var last_mouse_pos: Vector2 = -Vector2.ONE
var last_pressure: float = 1.0
var is_drawing: bool = false


func _init() -> void:
    # The tool loads its own shader when created
    compute = MaCompute.new("paint")


## Resets stroke interpolation and state
func reset() -> void:
    last_mouse_pos = -Vector2.ONE
    last_pressure = 1.0
    is_drawing = false


## Converts raw hardware screen coordinates directly to texture pixels (bypasses 60Hz UI cache)
func _get_event_local_pos(event: InputEvent) -> Vector2:
    return canvas.get_global_transform().affine_inverse() * event.global_position


## Dispatches paint commands via Canvas wrapper using exact hardware polling
func handle_input(event: InputEvent) -> void:
    assert(canvas != null and canvas.document != null, "Canvas/Document missing")
    assert(radius > 0.0, "Brush radius must be positive")

    # Pre-calculate the color with alpha for opacity
    var stroke_color = color
    stroke_color.a = opacity

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            is_drawing = true
            last_mouse_pos = _get_event_local_pos(event)

            var actual_radius = max(0.1, radius * (last_pressure * 2.0))
            _dispatch_brush(last_mouse_pos, actual_radius, stroke_color)
        else:
            reset()

    elif event is InputEventMouseMotion and is_drawing:
        var tex_pos = _get_event_local_pos(event)

        # Detect tablet vs mouse
        var raw_pressure = event.pressure
        if raw_pressure > 0.0:
            is_tablet = true

        # Apply pressure and gamma curve
        var current_pressure = raw_pressure if is_tablet else 0.5 # middle default pressure?
        current_pressure = pow(current_pressure, pressure_gamma)

        # Calculate dynamic spacing based on the ACTUAL current radius
        var current_actual_radius = max(0.1, radius * (current_pressure * 2.0))
        var step_size = max(current_actual_radius * 0.1, 1.0)

        # Linear interpolation (Lerp) between the last hardware point and the current one
        if last_mouse_pos != -Vector2.ONE and last_mouse_pos.distance_to(tex_pos) > step_size:
            var dist = last_mouse_pos.distance_to(tex_pos)
            var steps = max(int(dist / step_size), 1)

            for i in range(steps + 1):
                var t = float(i) / steps
                var interp_pos = last_mouse_pos.lerp(tex_pos, t)
                var interp_pressure = lerpf(last_pressure, current_pressure, t)
                var interp_radius = max(0.1, radius * (interp_pressure * 2.0))
                _dispatch_brush(interp_pos, interp_radius, stroke_color)
        else:
            _dispatch_brush(tex_pos, current_actual_radius, stroke_color)

        last_mouse_pos = tex_pos
        last_pressure = current_pressure


## The brush calculates its own bounding box and writes directly to the active layer!
func _dispatch_brush(pos: Vector2, actual_radius: float, stroke_color: Color) -> void:
    var doc = canvas.document
    var r = actual_radius + 2.0
    var rect = Rect2(pos.x - r, pos.y - r, r * 2, r * 2)

    var start_x = max(0, floor(rect.position.x / 8.0) * 8.0)
    var start_y = max(0, floor(rect.position.y / 8.0) * 8.0)
    var end_x = min(doc.canvas_size.x, ceil(rect.end.x / 8.0) * 8.0)
    var end_y = min(doc.canvas_size.y, ceil(rect.end.y / 8.0) * 8.0)

    var width = end_x - start_x
    var height = end_y - start_y
    if width <= 0 or height <= 0:
        return

    var data = PackedFloat32Array(
        [
            pos.x,
            pos.y,
            start_x,
            start_y,
            stroke_color.r,
            stroke_color.g,
            stroke_color.b,
            stroke_color.a,
            actual_radius,
            0.0,
            0.0,
            0.0,
        ],
    )

    compute.set_texture(0, doc.active_layer.texture.rid)
    compute.set_push_constant_float_array(data)
    compute.dispatch(0, int(width / 8.0), int(height / 8.0), 1)

    # Tell the rest of the application that the VRAM has changed
    EventBus.canvas_needs_composite.emit()


## Safely clear VRAM references before Godot destroys the RenderingDevice
func _exit_tree() -> void:
    compute = null

extends RefCounted

class_name StateBrush

var canvas: MaCanvas
var radius: float = 25.0
## Global opacity of the brush (0.0 to 1.0)
var opacity: float = 0.75
var color: Color = Color(1.0, 0.0, 0.0, 1.0)

## Automatically detects if user is using a tablet to stop mice from drawing tiny dots
var is_tablet: bool = true
## Curve for pressure sensitivity (1.0 is linear, > 1.0 makes light touches more precise)
var pressure_gamma: float = 0.5

var last_mouse_pos: Vector2 = -Vector2.ONE
var last_pressure: float = 1.0
var is_drawing: bool = false


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
    assert(canvas != null, "Canvas missing in StateBrush")
    assert(radius > 0.0, "Brush radius must be positive")

    # Pre-calculate the color with alpha for opacity
    var stroke_color = color
    stroke_color.a = opacity

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            is_drawing = true
            last_mouse_pos = _get_event_local_pos(event)

            var actual_radius = max(0.1, radius * (last_pressure * 2.0))
            canvas.dispatch_brush(last_mouse_pos, actual_radius, stroke_color)
        else:
            reset()

    elif event is InputEventMouseMotion and is_drawing:
        var tex_pos = _get_event_local_pos(event)

        # 1. Detect tablet vs mouse
        var raw_pressure = event.pressure
        if raw_pressure > 0.0:
            is_tablet = true

        # 2. Apply pressure and gamma curve
        var current_pressure = raw_pressure if is_tablet else 1.0
        current_pressure = pow(current_pressure, pressure_gamma)

        # 3. Calculate dynamic spacing based on the ACTUAL current radius
        var current_actual_radius = max(0.1, radius * (current_pressure * 2.0))
        var step_size = max(current_actual_radius * 0.1, 1.0)

        # 4. Linear interpolation (Lerp) between the last hardware point and the current one
        if last_mouse_pos != -Vector2.ONE and last_mouse_pos.distance_to(tex_pos) > step_size:
            var dist = last_mouse_pos.distance_to(tex_pos)
            var steps = max(int(dist / step_size), 1)

            for i in range(steps + 1):
                var t = float(i) / steps
                var interp_pos = last_mouse_pos.lerp(tex_pos, t)
                var interp_pressure = lerpf(last_pressure, current_pressure, t)
                var interp_radius = max(0.1, radius * (interp_pressure * 2.0))
                canvas.dispatch_brush(interp_pos, interp_radius, stroke_color)
        else:
            canvas.dispatch_brush(tex_pos, current_actual_radius, stroke_color)

        last_mouse_pos = tex_pos
        last_pressure = current_pressure

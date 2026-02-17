extends RefCounted

class_name StateBrush

var canvas: MaCanvas
# The brush owns its own shader
var compute: MaCompute

# --- BRUSH SETTINGS ---
var radius: float = 25 # 2x radius is diameter (px)
var hardness: GammaFloat = GammaFloat.new(.0, 1.) # hard/soft edge
var opacity: float = 1. # maximum opacity per stroke
var flow: GammaFloat = GammaFloat.new(1., 2.4) # strength per dab/stamp
var spacing: float = .18 # % of the brush diameter

var size_by_pressure: bool = false
var size_pressure_gamma: GammaFloat = GammaFloat.new(0.0, 2.0)
var opacity_by_pressure: bool = true
var opacity_pressure_gamma: GammaFloat = GammaFloat.new(0.0, .5)
var color: Color = Color(1.0, 1.0, 1.0, 1.0)

# --- HARDWARE STATE ---
## State flag indicating if a pen is currently being used
var is_tablet: bool = true
## Define your maximum easily reachable physical pressure based on your graph
var max_tablet_pressure = 0.73
## Curve for pressure sensitivity (1.0 is linear, > 1.0 makes light touches more precise)
var pressure_gamma: float = 2.4

var last_mouse_pos: Vector2 = -Vector2.ONE
var last_pressure: float = 0.0
## Accumulator for perfect sub-pixel spacing intervals
var leftover_distance: float = 0.0
var is_drawing: bool = false

## Counter to detect when the user switches to a physical mouse
var _mouse_motion_streak: int = 0


func _init() -> void:
    # The tool loads its own shader when created
    compute = MaCompute.new("paint")


## Main entry point for all input events.
func handle_input(event: InputEvent) -> void:
    assert(canvas != null and canvas.document != null, "Canvas/Document missing")
    assert(radius > 0.0, "Brush radius must be positive")

    _analyze_pointer_type(event)

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        _handle_stroke_state(event)
    elif event is InputEventMouseMotion and is_drawing:
        _handle_stroke_motion(event)


## Resets stroke interpolation and state
func reset() -> void:
    last_mouse_pos = -Vector2.ONE
    last_pressure = 0.0
    leftover_distance = 0.0
    is_drawing = false


## Converts raw hardware screen coordinates directly to texture pixels
func _get_event_local_pos(event: InputEvent) -> Vector2:
    return canvas.get_global_transform().affine_inverse() * event.global_position


## Heuristics to bypass the Wayland "device 0" bug by analyzing raw telemetry
func _analyze_pointer_type(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        # A physical pen will almost always report one of these
        if event.pressure > 0.0 or event.tilt != Vector2.ZERO or event.pen_inverted:
            is_tablet = true
            _mouse_motion_streak = 0

            # Catch hover pressure: If the driver sends a motion event with pressure
            # *just before* the click event: save it to avoid a 0.0 pressure start
            if not is_drawing and event.pressure > 0.0:
                last_pressure = event.pressure
        else:
            # If streak of pure (0,0) tilt and 0.0 pressure, it's a mouse
            _mouse_motion_streak += 1
            if _mouse_motion_streak > 10:
                is_tablet = false


func _handle_stroke_state(event: InputEventMouseButton) -> void:
    if event.pressed:
        is_drawing = true
        last_mouse_pos = _get_event_local_pos(event)
        leftover_distance = 0.0
        canvas.document.stroke_opacity = opacity

        # Use already encoded last_pressure from hover, or default to 1.0 if mouse
        var raw_pressure = (last_pressure if last_pressure > 0.0 else 0.0) if is_tablet else 1.0
        last_pressure = raw_pressure

        var current_pressure = _get_normalized_pressure(raw_pressure)
        _stamp_brush(last_mouse_pos, current_pressure)

    elif is_drawing:
        canvas.document.commit_stroke()
        reset()


func _handle_stroke_motion(event: InputEventMouseMotion) -> void:
    var tex_pos = _get_event_local_pos(event)

    # Read raw pressure (force 1.0 if using mouse)
    var raw_pressure = event.pressure if is_tablet else 1.0
    var current_pressure = _get_normalized_pressure(raw_pressure)

    _process_stroke_interpolation(tex_pos, current_pressure)


## Consolidates the math for max pressure
func _get_normalized_pressure(raw_pressure: float) -> float:
    # Map the 0.0 - local_max range to a full 0.0 - 1.0 range
    var normalized = clamp(raw_pressure / max_tablet_pressure, 0.0, 1.0)
    # Apply user-defined gamma curve for sensitivity
    return pow(normalized, pressure_gamma)


# Handles the complex distance and stepping logic
func _process_stroke_interpolation(tex_pos: Vector2, current_pressure: float) -> void:
    var current_actual_radius = max(0.1, radius * (current_pressure if size_by_pressure else 1.0))
    var step_size = max(current_actual_radius * 2.0 * spacing, 1.0)

    if last_mouse_pos != -Vector2.ONE:
        var dist = last_mouse_pos.distance_to(tex_pos)
        var total_dist = leftover_distance + dist

        if total_dist >= step_size:
            var steps = int(total_dist / step_size)

            for i in range(1, steps + 1):
                var t = (step_size * i - leftover_distance) / dist
                var interp_pos = last_mouse_pos.lerp(tex_pos, t)

                # Both are now gamma-encoded, safe to lerp
                var interp_pressure = lerpf(last_pressure, current_pressure, t)

                _stamp_brush(interp_pos, interp_pressure)

            leftover_distance = total_dist - (steps * step_size)
        else:
            leftover_distance = total_dist

    last_mouse_pos = tex_pos
    # Store the gamma-encoded pressure for the next frame
    last_pressure = current_pressure


## Calculates dynamic pressure modifiers and dispatches a single dab to the GPU
func _stamp_brush(pos: Vector2, pressure: float) -> void:
    var actual_radius = max(0.1, radius * (pressure if size_by_pressure else 1.0))
    var stroke_color = color
    stroke_color.a = flow.transf() * (pressure if opacity_by_pressure else 1.0)

    _dispatch_brush(pos, actual_radius, stroke_color)


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

    # Pack the payload into std430 alignment (chunks of 4)
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
            hardness.raw(),
            hardness.gamma_inv(),
            flow.transf(),
        ],
    )

    compute.set_texture(0, doc.stroke_layer.texture.rid)
    compute.set_push_constant_float_array(data)
    compute.dispatch(0, int(width / 8.0), int(height / 8.0), 1)

    # Tell the rest of the application that the VRAM has changed
    EventBus.canvas_needs_composite.emit()

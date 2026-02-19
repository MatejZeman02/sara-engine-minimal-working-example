## Navigation logic for scaling the canvas view.
##
## Implements smooth vertical-drag zooming centered on the cursor position.
extends RefCounted

class_name StateZoom

var canvas: MaCanvas
var is_zooming: bool = false
var zoom_start_y: float = 0.0
var zoom_start_scale: Vector2 = Vector2.ONE
var zoom_start_pos: Vector2 = Vector2.ZERO


## Resets internal zoom state
func reset() -> void:
    is_zooming = false


## Handles vertical drag to zoom into the absolute screen center
func handle_input(event: InputEvent) -> void:
    assert(canvas != null, "Canvas missing in StateZoom")

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            is_zooming = true
            zoom_start_y = event.global_position.y
            zoom_start_scale = canvas.scale
            zoom_start_pos = canvas.position
        else:
            reset()

    elif event is InputEventMouseMotion and is_zooming:
        var drag_dist = zoom_start_y - event.global_position.y
        var zoom_factor = max(0.05, 1.0 + (drag_dist * 0.005))

        var new_scale = zoom_start_scale * zoom_factor

        # find window center in screen coordinates
        var screen_center = canvas.get_viewport_rect().size / 2.0
        # which pixel is currently at the center in canvas local coordinates?
        var local_center = (screen_center - zoom_start_pos) / zoom_start_scale
        # recalculate position
        var new_pos = screen_center - (local_center * new_scale)

        canvas.scale = new_scale
        canvas.position = new_pos

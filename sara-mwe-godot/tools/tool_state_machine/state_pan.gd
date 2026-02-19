## Navigation logic for moving the canvas view.
##
## Translates mouse relative movement into MaCanvas position offsets.
extends RefCounted

class_name StatePan

var canvas: MaCanvas
var is_panning: bool = false


## Resets internal pan state
func reset() -> void:
    is_panning = false


## Pushes the canvas position relatively to the mouse movement
func handle_input(event: InputEvent) -> void:
    assert(canvas != null, "Canvas missing in StatePan")

    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        is_panning = event.pressed

    elif event is InputEventMouseMotion and is_panning:
        canvas.position += event.relative

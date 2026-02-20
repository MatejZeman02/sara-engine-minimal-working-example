## Central input router and tool state controller.
##
## Switches between Brush, Pan, and Zoom states based on user input.
## Manages the shared state of the cursor and tablet telemetry.
extends Node

class_name ToolMachine

enum ToolType { BRUSH, PAN, ZOOM }
var current_tool: ToolType = ToolType.BRUSH

var canvas: MaCanvas
var brush_state: StateBrush = StateBrush.new()
var pan_state: StatePan = StatePan.new()
var zoom_state: StateZoom = StateZoom.new()

## Blocks brush drawing if we returned to brush mode while mouse is still pressed
var block_brush_until_release: bool = false


func _ready() -> void:
    # Forces Godot to process every single hardware mouse movement immediately,
    # preventing straight lines during fast curved strokes.
    Input.set_use_accumulated_input(false)
    canvas = get_parent()
    assert(canvas is MaCanvas, "ToolMachine must be a child of MaCanvas")

    brush_state.canvas = canvas
    pan_state.canvas = canvas
    zoom_state.canvas = canvas

    _update_cursor()


## Called by MaDocument whenever layers change to update the caches for the visible area.
func _input(event: InputEvent) -> void:
    assert(canvas != null and canvas.document != null, "Canvas document missing")
    var is_space = Input.is_key_pressed(KEY_SPACE)
    var is_ctrl = Input.is_key_pressed(KEY_CTRL)
    var is_mouse_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

    var target_tool = ToolType.BRUSH
    if is_space and is_ctrl:
        target_tool = ToolType.ZOOM
    elif is_space:
        target_tool = ToolType.PAN

    # detect tool changes and reset states accordingly
    if target_tool != current_tool:
        # Safety mechanism: If we switch to brush tool while still holding mouse from previous panning
        if target_tool == ToolType.BRUSH and is_mouse_down:
            block_brush_until_release = true

        current_tool = target_tool
        _update_cursor()
        brush_state.reset()
        zoom_state.reset()
        pan_state.reset()

    # unblock brush input once the mouse button is released
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
        block_brush_until_release = false

    # stops event propagation to prevent accidental drawing when switching tools mid-stroke
    if current_tool == ToolType.BRUSH and block_brush_until_release:
        return

    # Send input to the active tool state
    match current_tool:
        ToolType.BRUSH:
            brush_state.handle_input(event)
        ToolType.PAN:
            pan_state.handle_input(event)
        ToolType.ZOOM:
            zoom_state.handle_input(event)

    # Global undo/redo listeners:
    # arg 2 (allow_echo): true allows holding down the key to repeat
    # arg 3 (exact_match): true prevents ctrl+shift+z from triggering ctrl+z
    if event.is_action_pressed("ui_undo", true, true):
        if canvas.document.undo_redo.has_undo():
            canvas.document.undo_redo.undo()
    elif event.is_action_pressed("ui_redo", true, true):
        if canvas.document.undo_redo.has_redo():
            canvas.document.undo_redo.redo()


## Dynamically changes the cursor of the canvas node itself
func _update_cursor() -> void:
    assert(canvas != null, "Canvas must be initialized before setting cursor")
    match current_tool:
        ToolType.BRUSH:
            canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
        ToolType.PAN:
            canvas.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        ToolType.ZOOM:
            canvas.mouse_default_cursor_shape = Control.CURSOR_VSIZE
        _:
            canvas.mouse_default_cursor_shape = Control.CURSOR_ARROW

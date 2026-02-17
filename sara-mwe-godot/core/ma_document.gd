@tool
extends Node

class_name MaDocument

var canvas_size: Vector2i
var active_layer: MaLayer

# --- STROKE BUFFER ---
var stroke_layer: MaLayer
var stroke_opacity: float = 1.0


# TODO: let user configure.
## Creates a default new file: A solid gray background and an empty transparent paint layer
func setup_default_document(size: Vector2i) -> void:
    canvas_size = size

    # Background Layer (Solid Gray)
    var bg_layer = MaLayer.new()
    bg_layer.name = "Background"
    add_child(bg_layer)
    bg_layer.setup(canvas_size)
    # 0.5 in Linear space is quite bright. For perceptual mid-gray, we might prefer .5^3
    bg_layer.fill(Color(0.5, 0.5, 0.5, 1.0))

    # Paint Layer (Fully Transparent)
    var paint_layer = MaLayer.new()
    paint_layer.name = "Layer-1"
    add_child(paint_layer)
    paint_layer.setup(canvas_size)
    paint_layer.fill(Color.TRANSPARENT)

    # Stroke Buffer (Temporary scratchpad, explicitly NOT added as a child)
    stroke_layer = MaLayer.new()
    stroke_layer.name = "StrokeBuffer"
    stroke_layer.setup(canvas_size)
    stroke_layer.fill(Color.TRANSPARENT)

    # Set the target for the brush
    active_layer = paint_layer


## Bakes the temporary stroke into the active layer and clears the scratchpad
func commit_stroke() -> void:
    if stroke_layer == null or active_layer == null:
        return

    var compositor = MaCompute.new("composite")

    # Bindings: Active Layer is background/output (0). Stroke Layer is foreground (1).
    compositor.set_texture(0, active_layer.texture.rid)
    compositor.set_texture(1, stroke_layer.texture.rid)

    # Apply the global opacity limit for the entire stroke
    var push_data = PackedFloat32Array([stroke_opacity, 0.0, 0.0, 0.0])
    compositor.set_push_constant_float_array(push_data)

    var groups_x = int(ceil(canvas_size.x / 8.0))
    var groups_y = int(ceil(canvas_size.y / 8.0))

    compositor.dispatch(0, groups_x, groups_y, 1)

    # Clear the scratchpad for the next stroke
    stroke_layer.fill(Color.TRANSPARENT)

    # Force the display to update with the newly baked layer
    EventBus.canvas_needs_composite.emit()


## Cleanup
func _exit_tree() -> void:
    # Nodes, that are not in the tree needs to be manually freed
    if is_instance_valid(stroke_layer):
        stroke_layer.free()

    stroke_layer = null

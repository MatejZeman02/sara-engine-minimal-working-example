@tool
extends Node

class_name MaDocument

var canvas_size: Vector2i
var active_layer: MaLayer

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

    # Set the target for the brush
    active_layer = paint_layer

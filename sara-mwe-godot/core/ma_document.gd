## High-level container for canvas data and layer management.
##
## Manages the overall canvas dimensions, the stack of MaLayer objects,
## and coordinates the temporary stroke buffer for active drawing operations.
@tool
extends Node

class_name MaDocument

var canvas_size: Vector2i
var active_layer: MaLayer

# --- STROKE BUFFER ---
var stroke_layer: MaLayer
var stroke_opacity: float = 1.0


## Creates a default new file: A solid gray background and an empty transparent paint layer
func setup_default_document(size: Vector2i) -> void:
    canvas_size = size

    # Background Layer (Solid Gray)
    var bg_layer = MaLayer.new()
    bg_layer.name = "Background"
    add_child(bg_layer)
    bg_layer.setup(canvas_size)
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
    # Note: intentionally DO NOT call setup() on the stroke layer.
    # We want it to be completely empty and only allocate chunks exactly where the brush touches!

    # Set the target for the brush
    active_layer = paint_layer


## Bakes the temporary stroke chunks into the active layer chunks and clears the scratchpad
func commit_stroke() -> void:
    if stroke_layer == null or active_layer == null:
        return

    var compositor = MaCompute.new("composite")

    # Iterate only through the chunks that were drawn on during the stroke
    for grid_pos in stroke_layer.chunks:
        var stroke_chunk = stroke_layer.chunks[grid_pos]

        # Ensure the active layer has a chunk at this exact position (allows drawing out of bounds!)
        var target_chunk = active_layer.get_or_create_chunk(grid_pos)

        # Bindings: Active Layer's chunk is background (0). Stroke Layer's chunk is foreground (1).
        compositor.set_texture(0, target_chunk.rid)
        compositor.set_texture(1, stroke_chunk.rid)

        # Apply the global opacity limit for the entire stroke.
        # Offset is (0, 0) because we are compositing a 256x256 chunk exactly onto another 256x256 chunk.
        # var push_data = PackedFloat32Array([stroke_opacity, 0.0, 0.0, 0.0])
        
        # Offset je (0, 0), protože zapékáme 256x256 chunk přesně na jiný 256x256 chunk.
        # Pořadí je: Offset X, Offset Y, Opacity, Pad
        var push_data = PackedFloat32Array([0.0, 0.0, stroke_opacity, 0.0])
        compositor.set_push_constant_float_array(push_data)

        # Dispatch for the 256x256 chunk (256 / 8 = 32 groups)
        compositor.dispatch(0, 32, 32, 1)

    # Clear the scratchpad chunks for the next stroke, automatically freeing VRAM
    stroke_layer.chunks.clear()

    # Force the display to update with the newly baked layer
    EventBus.canvas_needs_composite.emit()


## Cleanup
func _exit_tree() -> void:
    if is_instance_valid(stroke_layer):
        stroke_layer.free()

    stroke_layer = null

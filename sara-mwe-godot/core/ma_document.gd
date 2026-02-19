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

# --- CACHES ---
var bottom_cache: MaLayer
var top_cache: MaLayer


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
    # We want it to be completely empty and only allocate chunks exactly where the brush touches

    # Initialize Caches
    bottom_cache = MaLayer.new()
    bottom_cache.name = "BottomCache"

    top_cache = MaLayer.new()
    top_cache.name = "TopCache"

    # Set the target for the brush
    active_layer = paint_layer

    # Force initial cache build for the starting screen resolution
    var visible_rect = Rect2(0, 0, size.x, size.y)
    update_caches(visible_rect)


## Rebuilds the Bottom and Top caches for the specific canvas area.
## This should only be called when layers change (visibility, opacity, ordering, etc.).
func update_caches(visible_rect: Rect2) -> void:
    assert(bottom_cache != null, "bottom_cache must be initialized")
    assert(top_cache != null, "top_cache must be initialized")
    assert(active_layer != null, "active_layer must be set")
    assert(visible_rect != Rect2(), "visible_rect isn't valid")
    if bottom_cache == null or top_cache == null or active_layer == null:
        return

    var rd = RenderingServer.get_rendering_device()
    var compositor = MaCompute.new("composite")
    var chunk_size = float(MaLayer.CHUNK_SIZE)
    var groups = int(ceil(chunk_size / 8.0))

    # Determine which grid coordinates intersect the visible rectangle
    var start_x = int(floor(visible_rect.position.x / chunk_size))
    var start_y = int(floor(visible_rect.position.y / chunk_size))
    var end_x = int(floor(visible_rect.end.x / chunk_size))
    var end_y = int(floor(visible_rect.end.y / chunk_size))

    var visible_grid_positions: Array[Vector2i] = []
    for cx in range(start_x, end_x + 1):
        for cy in range(start_y, end_y + 1):
            visible_grid_positions.append(Vector2i(cx, cy))

    # Clear ONLY the visible chunks in both caches
    for grid_pos in visible_grid_positions:
        var bottom_chunk = bottom_cache.get_or_create_chunk(grid_pos)
        rd.texture_clear(bottom_chunk.rid, Color.TRANSPARENT, 0, 1, 0, 1)

        var top_chunk = top_cache.get_or_create_chunk(grid_pos)
        rd.texture_clear(top_chunk.rid, Color.TRANSPARENT, 0, 1, 0, 1)

    # Iterate through all children and bake them into the appropriate cache
    var is_above_active = false

    for child in get_children():
        if not child is MaLayer or child == active_layer or not child.visible:
            # Skip the active/hidden layer
            continue

        # Determine target cache based on the layer's position relative to the active layer
        var target_cache = top_cache if is_above_active else bottom_cache

        # Composite this layer's chunks into the target cache
        for grid_pos in visible_grid_positions:
            if not child.chunks.has(grid_pos):
                continue # Layer has no data in this chunk, skip it

            var source_chunk = child.chunks[grid_pos]
            var dest_chunk = target_cache.get_or_create_chunk(grid_pos)

            compositor.set_texture(0, dest_chunk.rid)
            compositor.set_texture(1, source_chunk.rid)

            # Offset is (0,0) because we are rendering a 256x256 chunk directly onto another 256x256 chunk
            # The structure remains: vec2 offset, float opacity, float pad
            var push_data = PackedFloat32Array([0.0, 0.0, child.opacity, 0.0])
            compositor.set_push_constant_float_array(push_data)

            compositor.dispatch(0, groups, groups, 1)


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
    if is_instance_valid(bottom_cache):
        bottom_cache.free()
    if is_instance_valid(top_cache):
        top_cache.free()

    stroke_layer = null
    bottom_cache = null
    top_cache = null

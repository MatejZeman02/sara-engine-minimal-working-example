## Main UI display node and compositor.
##
## A TextureRect that triggers the composite compute shader to flatten
## all document layers into a single viewable texture on every update signal.
extends TextureRect

class_name MaCanvas

# --- CONFIGURATION ---
var canvas_size = Vector2i(1920, 1080)

# --- VARIABLES ---
var canvas: MaTexture
var document: MaDocument
@export var checkerboard_shader: Shader = preload("res://shaders/canvas/checkerboard.gdshader")

# Flag to prevent compositor spam during fast brush strokes
var _needs_composite: bool = false


## runs once on start
func _ready() -> void:
    stretch_mode = TextureRect.STRETCH_KEEP
    size = canvas_size
    pivot_offset = Vector2.ZERO
    expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    mouse_filter = Control.MOUSE_FILTER_PASS

    _center_canvas()

    canvas = MaTexture.new(canvas_size)
    var output_texture = Texture2DRD.new()
    output_texture.texture_rd_rid = canvas.rid
    self.texture = output_texture

    # --- CHECKERBOARD SETUP ---
    var bg = ColorRect.new()
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.show_behind_parent = true
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var bg_mat = ShaderMaterial.new()
    bg_mat.shader = checkerboard_shader
    bg_mat.set_shader_parameter("canvas_size", Vector2(canvas_size))
    bg.material = bg_mat

    add_child(bg)

    # --- DOCUMENT SETUP ---
    document = MaDocument.new()
    add_child(document)
    document.setup_default_document(canvas_size)

    # Connect the signal to the new, lightweight function
    EventBus.canvas_needs_composite.connect(_request_composite)


## Centers the canvas in the viewport and applies an initial scale to fit it on screen.
func _center_canvas() -> void:
    var window_size = get_viewport_rect().size
    var scale_factor = min(window_size.x / float(canvas_size.x), window_size.y / float(canvas_size.y))
    scale = Vector2(scale_factor, scale_factor)
    position = (window_size - (Vector2(canvas_size) * scale_factor)) / 2.0


## raise flag to composite
func _request_composite() -> void:
    _needs_composite = true


func _process(_delta: float) -> void:
    if _needs_composite:
        composite_all_layers()
        _needs_composite = false


## Flattens all visible layers and the active stroke buffer into the canvas texture.
func composite_all_layers() -> void:
    var rd = RenderingServer.get_rendering_device()
    rd.texture_clear(canvas.rid, Color.TRANSPARENT, 0, 1, 0, 1)

    var compositor = MaCompute.new("composite")
    var chunk_size = float(MaLayer.CHUNK_SIZE)
    var groups = int(ceil(chunk_size / 8.0))

    # viewport culling math:
    # Determine the rectangle currently visible to the user (in local canvas pixels)
    var screen_rect = get_viewport_rect()
    var visible_rect = get_global_transform().affine_inverse() * screen_rect

    # start batch
    compositor.list_begin(0)

    # Iterate through the Document's standard layers
    for child in document.get_children():
        if not child is MaLayer or not child.visible:
            continue

        for grid_pos in child.chunks:
            var offset_x = grid_pos.x * chunk_size
            var offset_y = grid_pos.y * chunk_size

            # viewport culling
            var chunk_rect = Rect2(offset_x, offset_y, chunk_size, chunk_size)
            if not visible_rect.intersects(chunk_rect):
                continue # chunk off-screen

            var chunk = child.chunks[grid_pos]
            compositor.set_texture(0, canvas.rid)
            compositor.set_texture(1, chunk.rid)

            var push_data = PackedFloat32Array([offset_x, offset_y, child.opacity, 0.0])
            compositor.set_push_constant_float_array(push_data)

            # Add to the queue (batching)
            compositor.list_dispatch(groups, groups, 1)

    # Add the active Stroke Buffer on top
    if document.stroke_layer != null:
        for grid_pos in document.stroke_layer.chunks:
            var offset_x = grid_pos.x * chunk_size
            var offset_y = grid_pos.y * chunk_size

            var chunk_rect = Rect2(offset_x, offset_y, chunk_size, chunk_size)
            if not visible_rect.intersects(chunk_rect):
                continue

            var chunk = document.stroke_layer.chunks[grid_pos]
            compositor.set_texture(0, canvas.rid)
            compositor.set_texture(1, chunk.rid)

            var push_data = PackedFloat32Array([offset_x, offset_y, document.stroke_opacity, 0.0])
            compositor.set_push_constant_float_array(push_data)

            compositor.list_dispatch(groups, groups, 1)

    # fire the entire batch at once
    compositor.list_end()

    queue_redraw()


## Safely clear VRAM references before Godot destroys the RenderingDevice
func _exit_tree() -> void:
    canvas = null
    document = null

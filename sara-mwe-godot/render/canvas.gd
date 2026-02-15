extends TextureRect

class_name MaCanvas

# --- CONFIGURATION ---
var canvas_size = Vector2i(1920, 1080)

# --- VARIABLES ---
var compute: MaCompute
var canvas: MaTexture
var document: MaDocument


func _ready() -> void:
    Engine.max_fps = 100

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
    bg_mat.shader = load("res://scripts/shaders/checkerboard.gdshader")
    bg_mat.set_shader_parameter("canvas_size", Vector2(canvas_size))
    bg.material = bg_mat

    add_child(bg)

    # --- DOCUMENT SETUP ---
    document = MaDocument.new()
    add_child(document)
    document.setup_default_document(canvas_size)

    compute = MaCompute.new("paint")


func _center_canvas() -> void:
    var window_size = get_viewport_rect().size
    var scale_factor = min(window_size.x / float(canvas_size.x), window_size.y / float(canvas_size.y))
    scale = Vector2(scale_factor, scale_factor)
    position = (window_size - (Vector2(canvas_size) * scale_factor)) / 2.0


## Sends drawing instructions to the GPU.
## 'actual_radius' is the pre-calculated, pressure-applied final size.
func dispatch_brush(pos: Vector2, actual_radius: float, color: Color) -> void:
    assert(actual_radius > 0.0, "Brush radius must be positive")
    assert(document != null and document.active_layer != null, "No active layer selected!")

    # Bounding box scales with the pressure-adjusted radius
    var r = actual_radius + 2.0
    var rect = Rect2(pos.x - r, pos.y - r, r * 2, r * 2)

    var start_x = max(0, floor(rect.position.x / 8.0) * 8.0)
    var start_y = max(0, floor(rect.position.y / 8.0) * 8.0)
    var end_x = min(canvas_size.x, ceil(rect.end.x / 8.0) * 8.0)
    var end_y = min(canvas_size.y, ceil(rect.end.y / 8.0) * 8.0)

    var width = end_x - start_x
    var height = end_y - start_y
    if width <= 0 or height <= 0:
        return

    # Pack the payload. 'pressure' is replaced by standard 0.0 padding.
    var data = PackedFloat32Array(
        [
            pos.x,
            pos.y,
            start_x,
            start_y,
            color.r,
            color.g,
            color.b,
            color.a,
            actual_radius,
            0.0,
            0.0,
            0.0,
        ],
    )

    # Draw strictly to the document's active layer
    compute.set_texture(0, document.active_layer.texture.rid)
    compute.set_push_constant_float_array(data)
    compute.dispatch(0, int(width / 8.0), int(height / 8.0), 1)

    composite_all_layers()


func composite_all_layers() -> void:
    var rd = RenderingServer.get_rendering_device()
    rd.texture_clear(canvas.rid, Color.TRANSPARENT, 0, 1, 0, 1)

    var compositor = MaCompute.new("composite")

    # Iterate through the Document's layers, not the Canvas's children
    for child in document.get_children():
        if child is MaLayer:
            if not child.is_visible:
                continue

            compositor.set_texture(0, canvas.rid)
            compositor.set_texture(1, child.texture.rid)

            var push_data = PackedFloat32Array([child.opacity, 0.0, 0.0, 0.0])
            compositor.set_push_constant_float_array(push_data)

            var groups_x = int(ceil(canvas_size.x / 8.0))
            var groups_y = int(ceil(canvas_size.y / 8.0))

            compositor.dispatch(0, groups_x, groups_y, 1)

    queue_redraw()


func _exit_tree() -> void:
    # Safely clear VRAM references before Godot destroys the RenderingDevice
    compute = null
    canvas = null
    document = null

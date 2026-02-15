extends TextureRect

class_name MaCanvas

# --- CONFIGURATION ---
var canvas_size = Vector2i(1920, 1080)

# --- VARIABLES ---
var canvas: MaTexture
var document: MaDocument
@export var checkerboard_shader: Shader = preload("res://shaders/canvas/checkerboard.gdshader")


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
    bg_mat.shader = checkerboard_shader
    bg_mat.set_shader_parameter("canvas_size", Vector2(canvas_size))
    bg.material = bg_mat

    add_child(bg)

    # --- DOCUMENT SETUP ---
    document = MaDocument.new()
    add_child(document)
    document.setup_default_document(canvas_size)

    EventBus.canvas_needs_composite.connect(composite_all_layers)


func _center_canvas() -> void:
    var window_size = get_viewport_rect().size
    var scale_factor = min(window_size.x / float(canvas_size.x), window_size.y / float(canvas_size.y))
    scale = Vector2(scale_factor, scale_factor)
    position = (window_size - (Vector2(canvas_size) * scale_factor)) / 2.0


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


## Safely clear VRAM references before Godot destroys the RenderingDevice
func _exit_tree() -> void:
    canvas = null
    document = null

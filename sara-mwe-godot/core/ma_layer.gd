@tool
extends Node

class_name MaLayer

## The texture for this layer
var texture: MaTexture

## Whether the layer is visible
@export var is_visible: bool = true

## The opacity of the layer
@export_range(0.0, 1.0) var opacity: float = 1.0

## The blend mode for the layer
enum BlendMode {
    NORMAL,
}
@export var blend_mode: BlendMode = BlendMode.NORMAL


## Fills the entire VRAM texture with a solid color instantly
func fill(color: Color) -> void:
    assert(texture != null and texture.rid.is_valid(), "Texture not initialized")
    var rd = RenderingServer.get_rendering_device()
    # texture_clear is a highly optimized native Vulkan command
    rd.texture_clear(texture.rid, color, 0, 1, 0, 1)


## Initialize the VRAM texture manually after adding the node
func setup(canvas_size: Vector2i) -> void:
    assert(canvas_size.x > 0 and canvas_size.y > 0, "Canvas size must be positive")
    texture = MaTexture.new(canvas_size)
    assert(texture != null and texture.rid.is_valid(), "Failed to create MaTexture for layer")


## Automatic cleanup (Destructor)
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # MaTexture is RefCounted. NEVER call .free() on it!
        # Setting it to null drops the reference count to 0, safely triggering its own deletion.
        texture = null

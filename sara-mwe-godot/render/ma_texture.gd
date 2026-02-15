@tool
extends RefCounted

# smart pointer counter
class_name MaTexture

var rid: RID
var size: Vector2i
var rd: RenderingDevice

## _size: Vector2i - dimensions of the texture
## format_bits: int - optional, specify the data format (default is RGBA32F)
func _init(_size: Vector2i, format_bits: int = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT):
    assert(_size.x > 0 and _size.y > 0, "Texture size must be positive")

    rd = RenderingServer.get_rendering_device()
    assert(rd != null, "Failed to get RenderingDevice")

    size = _size

    var fmt = RDTextureFormat.new()
    fmt.width = size.x
    fmt.height = size.y
    fmt.format = format_bits

    # Set all common usage flags required for compute shaders and drawing
    fmt.usage_bits = \
    RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
    RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
    RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | \
    RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | \
    RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT

    # Create the texture on the GPU
    rid = rd.texture_create(fmt, RDTextureView.new(), [])
    assert(rid.is_valid(), "Failed to create texture")

    # Clear to gray by default
    rd.texture_clear(rid, Color(0.5, 0.5, 0.5, 1), 0, 1, 0, 1)


## Automatic cleanup (Destructor)
func _notification(what):
    if what == NOTIFICATION_PREDELETE:
        # Simply free the RID when the object is destroyed
        if rid.is_valid() and rd != null:
            rd.free_rid(rid)
            rid = RID() # Reset the RID to an invalid state after freeing it

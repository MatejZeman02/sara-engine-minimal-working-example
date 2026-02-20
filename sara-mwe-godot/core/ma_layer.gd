## Chunk-based texture management for an individual canvas layer.
##
## Uses a sparse dictionary of 256x256 MaTexture chunks to represent
## large drawing areas efficiently in VRAM. Handles per-layer opacity and blending.
@tool
extends Node

class_name MaLayer

const CHUNK_SIZE: int = 256

## Dictionary mapping chunk grid coordinates (Vector2i) to MaTexture
var chunks: Dictionary = { }

## Whether the layer is visible
@export var visible: bool = true

## The opacity of the layer
@export_range(0.0, 1.0) var opacity: float = 1.0

## The blend mode for the layer
enum BlendMode {
    NORMAL,
}
@export var blend_mode: BlendMode = BlendMode.NORMAL


## Initialize the VRAM textures to cover the starting canvas area
func setup(canvas_size: Vector2i) -> void:
    assert(canvas_size.x > 0 and canvas_size.y > 0, "Canvas size must be positive")

    # Calculate how many chunks are needed to cover the initial canvas
    var chunks_x = int(ceil(canvas_size.x / float(CHUNK_SIZE)))
    var chunks_y = int(ceil(canvas_size.y / float(CHUNK_SIZE)))

    # Pre-allocate the initial grid
    for x in range(chunks_x):
        for y in range(chunks_y):
            get_or_create_chunk(Vector2i(x, y))


## Returns an existing chunk or creates a new one on the fly
func get_or_create_chunk(grid_pos: Vector2i) -> MaTexture:
    if chunks.has(grid_pos):
        return chunks[grid_pos]

    # Allocate new 256x256 texture in VRAM
    var new_chunk = MaTexture.new(Vector2i(CHUNK_SIZE, CHUNK_SIZE))
    assert(new_chunk != null and new_chunk.rid.is_valid(), "Failed to create MaTexture for chunk")

    # Initialize with transparent pixels
    var rd = RenderingServer.get_rendering_device()
    rd.texture_clear(new_chunk.rid, Color.TRANSPARENT, 0, 1, 0, 1)

    chunks[grid_pos] = new_chunk
    return new_chunk


## Fills all currently allocated chunks with a solid color instantly
func fill(color: Color) -> void:
    var rd = RenderingServer.get_rendering_device()
    for chunk in chunks.values():
        assert(chunk.rid.is_valid(), "Invalid chunk RID during fill")
        rd.texture_clear(chunk.rid, color, 0, 1, 0, 1)


## Automatic cleanup (Destructor)
func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        # MaTextures are RefCounted. Clearing the dictionary drops their reference counts to 0,
        # safely triggering their own deletion.
        chunks.clear()


## Creates VRAM copy of an existing chunk for Undo/Redo backups.
## Returns null if the chunk doesn't exist yet (meaning the undo state is empty).
func duplicate_chunk(grid_pos: Vector2i) -> MaTexture:
    if not chunks.has(grid_pos):
        return null
    return create_texture_copy(chunks[grid_pos])


## Replaces a specific chunk with provided texture data (used by UndoRedo).
## If new_chunk is null, it removes the chunk completely.
func set_chunk(grid_pos: Vector2i, new_chunk: MaTexture) -> void:
    if new_chunk == null:
        chunks.erase(grid_pos)
    else:
        chunks[grid_pos] = new_chunk


## Creates a VRAM copy of a provided MaTexture (for undo history)
func create_texture_copy(original: MaTexture) -> MaTexture:
    if original == null:
        return null

    var copy_chunk = MaTexture.new(Vector2i(CHUNK_SIZE, CHUNK_SIZE))
    var rd = RenderingServer.get_rendering_device()

    rd.texture_copy(
        original.rid,
        copy_chunk.rid,
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(CHUNK_SIZE, CHUNK_SIZE, 1),
        0,
        0,
        0,
        0,
    )
    return copy_chunk

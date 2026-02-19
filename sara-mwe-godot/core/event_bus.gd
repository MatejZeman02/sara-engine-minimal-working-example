## Global signal dispatcher for cross-node communication.
##
## Acts as a central hub for decoupled components to communicate without
## direct references. Primarily handles rendering triggers and UI state updates.
extends Node

## Emitted by tools (like StateBrush) when they modify a layer in VRAM.
## MaCanvas listens to this so it knows when to run the compositor.
@warning_ignore("unused_signal")
signal canvas_needs_composite()

@warning_ignore("unused_signal")
signal active_layer_changed(layer: MaLayer)

@warning_ignore("unused_signal")
signal document_created(doc: MaDocument)

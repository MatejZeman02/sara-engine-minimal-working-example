# TODO:
- the minimal working example of a painting software:

## Features
### Pareto principle (80/20 core) features:
- [x] Paint brush
- [x] Pressure Sensitivity (tablet/pen features)
- [ ] UI sliders/buttons
- [ ] Eraser mode
- [ ] Eyedropper/color picker
- [x] Pan and Zoom
- [ ] Undo / Redo:
- [ ] Clear Canvas / Fill Canvas
- [x] layers (opacity, hide)
  - [ ] layer lock (alpha, painting)
  - [ ] blending modes (normal, multiply, overlay, color dodge, erase, hue, saturation, lightness (value))

### Others:
- [ ] selection tool
- [ ] Transform Mesh & Perspective Warping
- [ ] Color Matching & Correction (Ctrl U/B)
- [ ] document menu/resize/crop
- [ ] liquify tool
- [ ] Symmetry/Mirror
- [ ] Canvas rotation
- [ ] Brush Stabilizers

### Long-term:
- color spaces on gpu
- export/import (jpg/png/exr/sad - custom sara document file)
- unlimited canvas shape and size
- UI buttons/sliders
- blending modes/locking layers
- make brush parameters editable by user
- noise textures to brush shape
- mask layer (or just layer on erase mode?)

### Possibly:
- Possible 3rd party libraries: OpenCV, LittleCMS, ...?
- To integrate c++:
  - Create a C++ wrapper that uses godot-cpp bindings.
  - Link OpenCV in it.
  - Write conversion functions between Godot::Image (or Texture) and cv::Mat.
  - Compile it as a shared library (.so). Godot will then see it as a native Node or Resource.
  - Also compile to .dll for windows.

## Bugs:
- icons not showing when pointer not on canvas, but outside.


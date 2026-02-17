# TODO:
- the minimal working example of a painting software:

## Pareto principle (80/20 core) features:
- [x] Paint brush
- [x] Pressure Sensitivity (tablet/pen features)
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
- [ ] liquify tool
- [ ] Symmetry/Mirror
- [ ] Canvas rotation
- [ ] Brush Stabilizers

### Long-term:
- color spaces on gpu
- export/import (class Image)
- unlimited canvas shape and size
- UI buttons/sliders
- blending modes/locking layers
- make brush parameters editable by user
- noise textures to brush shape

## Possibly:
- Possible 3rd party libraries: OpenCV, LittleCMS, ...?
- To integrate c++:
  - Create a C++ wrapper that uses godot-cpp bindings.
  - Link OpenCV in it.
  - Write conversion functions between Godot::Image (or Texture) and cv::Mat.
  - Compile it as a shared library (.so). Godot will then see it as a native Node or Resource.
  - Also compile to .dll for windows.

# TODO:
- the minimal working example
- find out the mem cpu-gpu bottleneck.
- classes inside compute shaders

## Long-term:
- Undo/Redo
- Dirty area
- color spaces on gpu
- export/import (trida Image)
- unlimited canvas shape and size
- UI buttons/sliders
- layers
- blending modes
- make brush parameters editable by user
- noise textures to brush shape
- export to linux/windows (SConstruct?)

## Possibly:
- integrate OpenCV/c++ 3rd party library (also to .dll for windows)
  - Vytvořím C++ wrapper, který používá godot-cpp bindings.
  - V něm nalinkuji OpenCV.
  - Napíši konverzní funkce mezi Godot::Image (nebo Texture) a cv::Mat.
  - Zkompiluji to jako sdílenou knihovnu (.so). Godot ji pak vidí jako nativní Node nebo Resource.

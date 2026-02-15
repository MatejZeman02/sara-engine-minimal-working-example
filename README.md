# SARA Brush Engine (Minimal Working Example)

Welcome to the Minimal Working Example (MWE) of **Sara**, a custom, high-performance raster brush engine built from scratch in **Godot 4.6 (Stable)**.

This repository serves as a proof-of-concept for migrating traditional, CPU-heavy drawing operations (like those found in Krita or Photoshop) into a pure GPU-first pipeline using Vulkan Compute Shaders. By keeping the active canvas entirely in VRAM and calculating brush interpolation, pressure, and blending on the GPU, we achieve massive performance gains for large canvases and complex brushes.

### Installation & Setup

2. Open the project folder using **Godot 4.6** (or newer).
3. The project is pre-configured to use the **Forward+** renderer (Vulkan).
4. **Linux Users (Wayland/Fedora):** If you are using a laptop with hybrid graphics (Optimus), ensure you launch Godot using your discrete GPU to avoid compatibility fallbacks.
5. run in godot or export the project for your platform.

I will create builds later, when there is a real release version with some features.

### Technical Architecture & Wrappers

To abstract the verbose Vulkan `RenderingDevice` API and maintain clean Model-View-Controller (MVC) separation, the engine uses a custom wrapper and state-machine system:

* **Core Logic (GPU Hybrid):** All drawing mathematics (Porter-Duff alpha blending, interpolation) happen on the GPU via Compute Shaders. The CPU is strictly reserved for input handling, state routing, and calculating bounding boxes.
* **Rendering & Memory:** The active canvas layer is kept in VRAM using `rgba32f` (32-bit float) precision. The result is displayed via `Texture2DRD` to avoid expensive GPU-to-CPU memory transfers.
* **State Machine Controller:** A `ToolMachine` node routes raw hardware inputs into isolated, stateless tools (`StateBrush`, `StatePan`, `StateZoom`).
* **`GlobalShaderCompiler` (Autoload):** A singleton that parses custom `.ma-compute` files. It uses robust Regular Expressions (Regex) to strip comments and extract `#kernel` directives and `[numthreads]` attributes, surviving code formatters like `clang-format`. It compiles SPIR-V shaders automatically and handles hot-reloading.
* **`MaCompute` & `MaTexture` Classes:** Custom RAII wrappers that manage compute pipelines, uniform sets, and texture formats.
* **`*.ma-compute` Format:** A custom shader file format (based on Acerola: https://github.com/GarrettGunnell/Acerola-Compute/tree/main) allowing multiple kernels in one file. Godot's `#version 450` is injected automatically.

### Input & Performance Optimizations

* **Tile-Based Dispatch (Dirty Rect):** Instead of dispatching the compute shader over the entire 4K canvas per mouse movement, the CPU calculates an 8x8 pixel-aligned bounding box strictly around the pressure-adjusted brush radius.
* **Push Constants:** The bounding box `offset` (top-left corner) is sent to the GPU via push constants. This reduces thread dispatches by over 99.5%.
* **Uncapped Hardware Polling:** Godot's default `Input Accumulation` is disabled. The engine processes every micro-tick of the mouse/tablet hardware directly, preventing straight-line artifacts on fast, curved strokes.
* **60Hz UI Cache Bypass:** Standard Godot UI functions like `get_local_mouse_position()` update only at the monitor's refresh rate. Sara bypasses this by multiplying the raw `InputEvent` global position by the canvas's `affine_inverse()` transform, unlocking true 1000Hz+ tablet polling.

### Memory Management

The godot agressive deleting of RenderDevice did not use to be memory-leak free.
Right now it holds thanks to a strict implementation of the RAII (Resource Acquisition Is Initialization) pattern:

* **RAII Lifecycle:** GPU wrappers like `MaTexture` and `MaCompute` extend Godot's `RefCounted` class.
* **Automatic Cleanup:** When an object (like a tool state or a texture) goes out of scope and its reference count hits zero, Godot triggers the `_notification(NOTIFICATION_PREDELETE)` function. Inside this function, the engine safely frees all raw Vulkan RIDs (`rd.free_rid()`) from the `RenderingDevice`.
* **The Exit Race Condition:** When closing the application, Godot's C++ backend aggressively destroys the global `RenderingDevice` before GDScript can finish its final garbage collection pass. Attempting manual cleanup during this split-second window causes C++ crashes. Therefore, the engine intentionally lets Godot's internal garbage collector handle the final teardown.

### Known Bugs

* **Harmless Exit Warning:** Due to the teardown race condition mentioned above, the console may print `WARNING: 1 RID of type "Compute" was leaked` when exiting the app. This is expected behavior and does not impact stability or leak memory during runtime.

### Future Roadmap

* **GPU Compositor Layer Architecture:** Implementing an MVC layer system where `MaLayer` Godot nodes serve purely as data structures, while a master `composite.ma-compute` shader mathematically flattens visible VRAM textures into a single display output.
* **"Sample Merged" Brush Logic:** Allowing the brush shader to read from a flattened canvas snapshot to enable smudging, watercolor, and turpentine washing effects non-destructively.
* **Split Color Management:** Ensuring all physics/opacity blending strictly occurs in **Linear Rec.709** space on the GPU, while color interpolation and smudging occur in the perceptually uniform **OK-HSL** space.

### Credits & Acknowledgements

This software is developed by Matěj Zeman as a bachelor thesis on FIT CTU (CZ) and released under the **GPLv3 License**.

This project was made possible by the following open-source software and libraries:

* **Godot Engine:** (c) 2014-present Godot Engine contributors. (MIT License)
* **A-Compute:** Compute shader wrapper infrastructure inspiration by Acerola / Garrett Gunnell. (MIT License)
* **Oklab Color Space:** Color math by Björn Ottosson. (MIT License)

*See the `THIRDPARTY.txt` and `LICENSE` files for full copyright details and license texts.*

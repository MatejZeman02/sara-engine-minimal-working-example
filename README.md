# SARA Brush engine in godot

This is the first iteration of the project of creating a custom brush engine inside Godot called Sara.

### Project Context: GPU Brush Engine in Godot

**Goal:**
I am building a custom, high-performance raster brush engine from scratch using **Godot 4.6 (Stable)** on Linux (Fedora/Wayland). The goal is to replace CPU-heavy operations (like in Krita) with a GPU-first approach using Vulkan Compute Shaders.

**Technical Architecture & Wrappers:**
To abstract the verbose Vulkan `RenderingDevice` API, the engine uses a custom wrapper system:

* **Core Logic:** Hybrid pipeline. All drawing mathematics (blending, interpolation, color space handling) happen on the GPU via Compute Shaders. CPU is only used for input handling (tablet pressure/tilt), Undo/Redo history, and saving.
* **Rendering & Memory:** The active canvas layer is kept in VRAM (Texture) using `rgba32f` (32-bit float) precision. The result is displayed via `Texture2DRD` to avoid expensive GPU-to-CPU memory transfers during the draw loop.
* **`GlobalShaderCompiler` (Autoload):** A singleton that parses `.acompute` files, extracts custom `#kernel` directives and `[numthreads]` attributes, and compiles SPIR-V shaders automatically. It also handles hot-reloading in the editor.
* **`ACompute` Class:** A `RefCounted` wrapper that manages pipelines, uniform sets, and dispatches. It eliminates boilerplate from the main script.
* **`ATexture` Class:** A custom RAII wrapper for handling GPU texture creation (`RDTextureFormat`, usage bits) and automatic cleanup via reference counting.
* **`*.acompute` Format:** A custom shader file format that allows defining multiple kernels in one file. Godot's `#version 450` is injected automatically by the compiler.

### Memory Management & "Leak" Warnings
* **RAII Lifecycle:** Resources like `ATexture` and `ACompute` extend `RefCounted`. They automatically clear their `RenderingDevice` RIDs (textures, pipelines, buffers) via `NOTIFICATION_PREDELETE` when they go out of scope during runtime.
* **Exit Warnings (DO NOT FIX):** On app exit, the Godot console prints `WARNING: 1 RID of type "Compute" was leaked` (or "Shader"). **This is expected and harmless.** * **The Race Condition:** Godot's C++ core aggressively destroys the `RenderingDevice` on shutdown before GDScript's `NOTIFICATION_PREDELETE` can run. Attempting manual cleanup during a close request leads to C++ crashes (`Attempted to free invalid ID`). Therefore, the architecture intentionally leaves the final exit cleanup to the engine's internal garbage collector to maintain stability.

### Optimizations
* **Tile-Based Dispatch (Dirty Rect):** Instead of dispatching the compute shader over the entire 1920x1080 canvas per mouse movement (which processes ~2 million threads and causes unnecessary GPU load), the engine calculates an 8x8 pixel aligned bounding box around the brush radius.
* **Push Constants:** The bounding box `offset` (top-left corner) is sent via push constants. The compute shader calculates global invocation coordinates as `gl_GlobalInvocationID.xy + p.offset`. This reduces thread dispatches by over 99.5%.

### Current Status (Minimal Working Example)
I have a basic "Hello World" brush engine setup consisting of:
1. **`paint.acompute`:** A compute shader that draws a circle based on mouse position.
2. **`Paint.gd`:** A GDScript attached to a `TextureRect` that handles the `RenderingDevice` setup, uniform sets, and push constants.
* **Hardware:** 4K Monitor, target canvas 1920x1080.

- code is live tested via asserts inside the scripts.
- comments are in english.
- double hash: ## is docstring. 

### Resolved Issues (History)
* **Export Failure for Custom Shaders:** Godot's export process strips unrecognized file extensions. `*.acompute` must be explicitly added to **Filters to export non-resource files** in the export preset.
* **Compiler Parsing Errors:** The compiler expects the `[numthreads(X, Y, Z)]` directive to be placed *immediately* above the `void KernelName()` function definition.
* **Fedora/Wayland Hybrid Graphics:** Running the exported binary via terminal on Optimus laptops defaults to the integrated Intel GPU. Fixed by explicitly setting **Device Type** to **Discrete** in `Project Settings -> General -> Rendering -> Rendering Device`.
* **Coordinate Mapping:** Mouse input was offset due to 4K monitor vs. 1080p texture mismatch. Solved by implementing coordinate remapping from Visual Rect space to Texture space.
* **Texture Usage Flags:** `texture_clear` failed due to missing flags. Solved by adding `TEXTURE_USAGE_CAN_COPY_TO_BIT` (and `COPY_FROM` / `STORAGE` / `SAMPLING`).
* **Vulkan Sync Crash:** Encountered `Only local devices can submit and sync` when calling `rd.submit()` on the main `RenderingDevice`. Solved by removing `rd.submit()` (Godot's main RD handles submission automatically).
* **Barrier Warnings:** `rd.barrier()` triggered "Barriers are automatically inserted" warnings. Solved by removing explicit barriers.

### Future Context
* I plan to implement custom interpolation spaces later.
* I want to avoid "stamping" artifacts using procedural noise (UV perturbation) in the shader, rather than AI.
* I may eventually implement a parser to allow C++ style structs/methods in GLSL for better code organization.
# -------------------------------------------------------------------------
# Sara Brush Engine
# Copyright (c) 2026 [Matej Zeman]
#
# Portions of this compute shader infrastructure are based on the
# Acerola Compute Wrapper by Acerola (Garrett Gunnell).
# https://github.com/GarrettGunnell/Acerola-Compute/tree/main
#
# This software is released under the MIT License.
# The license file is in this folder.
# https://opensource.org/licenses/MIT
# -------------------------------------------------------------------------

@tool
extends Node

var shader_files: Array = Array()
var compute_shader_file_paths: Array = Array()

var rd: RenderingDevice

## Dictionaries to store RIDs and plain text code for hot-reloading comparison
var shader_compilations = { }
var shader_code_cache = { }
var compute_shader_kernel_compilations = { }

## Check for changes every 30 frames (adjust as needed)
var frame_counter = 0
const CHECK_EVERY_X_FPS = 30
# custom and normal shaders
const COMPUTE_SHADER_EXTENSION = "ma-compute"
# const COMPUTE_SHADER_EXTENSION = "acompute"
const SHADER_EXTENSIONS = ["glsl", "shader", COMPUTE_SHADER_EXTENSION]


func _init() -> void:
    rd = RenderingServer.get_rendering_device()
    # Abort initialization silently during headless export/project scanning
    if rd == null:
        return
    find_files("res://")

    # Compile standard shaders (if any)
    for shader_file in shader_files:
        compile_shader(shader_file)

    # Compile custom compute shaders
    for file_path in compute_shader_file_paths:
        compile_compute_shader(file_path)


## Recursively scan the project directory for shader files
func find_files(dir_name) -> void:
    assert(dir_name != "", "Directory name must not be empty")
    var dir = DirAccess.open(dir_name)
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if dir.current_is_dir():
                find_files(dir_name.path_join(file_name))
            else:
                var ext = file_name.get_extension()
                if ext in SHADER_EXTENSIONS:
                    if ext == COMPUTE_SHADER_EXTENSION:
                        compute_shader_file_paths.push_back(dir_name.path_join(file_name))
                    else:
                        shader_files.push_back(dir_name.path_join(file_name))
            file_name = dir.get_next()


## Extract filename without extension
func get_shader_name(file_path: String) -> String:
    assert(file_path != "", "File path must not be empty")
    return file_path.get_file().split(".")[0]


## Placeholder for standard .glsl vertex/fragment shaders
func compile_shader(_shader_file_path) -> void:
    assert(false, "TODO: Standard shader compilation is currently not implemented. ERROR: " + _shader_file_path)


## Main compilation logic for .ma-compute files
func compile_compute_shader(compute_shader_file_path: String) -> void:
    var compute_shader_name = get_shader_name(compute_shader_file_path)

    var file = FileAccess.open(compute_shader_file_path, FileAccess.READ)
    assert(file != null, "Failed to open: " + compute_shader_file_path + " editing the file?")

    var raw_text = file.get_as_text()
    shader_code_cache[compute_shader_file_path] = raw_text

    # 0. Odstranění všech komentářů (line i block), aby se neparsovaly zakomentované tagy
    var comment_regex = RegEx.new()
    comment_regex.compile("/\\*[\\s\\S]*?\\*/|//.*")
    var clean_text = comment_regex.sub(raw_text, "", true)

    # 1. Získání všech kernelů
    var kernel_regex = RegEx.new()
    kernel_regex.compile("#kernel\\s+(\\w+)")
    var kernels = []
    for result in kernel_regex.search_all(clean_text):
        kernels.append(result.get_string(1))

    assert(!kernels.is_empty(), "No kernels found in: " + compute_shader_file_path)

    # Příprava RIDs (čištění)
    if not compute_shader_kernel_compilations.has(compute_shader_name):
        compute_shader_kernel_compilations[compute_shader_name] = []
    else:
        for rid in compute_shader_kernel_compilations[compute_shader_name]:
            if rid.is_valid():
                rd.free_rid(rid)
        compute_shader_kernel_compilations[compute_shader_name].clear()

    # 2. Zpracování každého kernelu zvlášť
    for k_name in kernels:
        var code = clean_text

        # Hledáme přesnou vazbu: [numthreads(x,y,z)] void nazev_kernelu(
        var func_sig_regex = RegEx.new()
        func_sig_regex.compile(
            "\\[numthreads\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)\\]\\s*void\\s+" +
            k_name + "\\s*\\(",
        )

        var match_sig = func_sig_regex.search(code)
        assert(
            match_sig != null,
            "Missing [numthreads] or valid signature for kernel: " + k_name,
        )

        var x = match_sig.get_string(1)
        var y = match_sig.get_string(2)
        var z = match_sig.get_string(3)

        # Nahradíme celý nalezený blok rovnou za "void main("
        code = func_sig_regex.sub(code, "void main(")

        # Odstraníme zbylé #kernel direktivy
        code = kernel_regex.sub(code, "", true)

        # 3. Složení validního GLSL
        var final_source = "#version 450\n"
        final_source += "layout(local_size_x = %s, local_size_y = %s, local_size_z = %s) in;\n" % [x, y, z]
        final_source += code

        # print(final_source) # Debug: Output the final shader source to the console for verification

        # Kompilace SPIR-V
        var shader_source = RDShaderSource.new()
        shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
        shader_source.source_compute = final_source
        var shader_spirv = rd.shader_compile_spirv_from_source(shader_source)

        assert(
            shader_spirv.compile_error_compute == "",
            "Error in " + k_name + ":\n" + shader_spirv.compile_error_compute,
        )

        var rid = rd.shader_create_from_spirv(shader_spirv)
        assert(rid.is_valid(), "Failed to create shader RID for kernel: " + k_name)

        compute_shader_kernel_compilations[compute_shader_name].append(rid)
        if k_name == compute_shader_name:
            print("Compiled Kernel: " + k_name)
        else:
            print("Compiled Kernel: " + k_name + " (" + compute_shader_name + ")")


## Hot-Reload logic
func _process(_delta: float) -> void:
    frame_counter += 1
    if frame_counter % CHECK_EVERY_X_FPS != 0:
        return

    for file_path in compute_shader_file_paths:
        # Check if file content has changed since last cache update
        if FileAccess.open(file_path, FileAccess.READ) == null:
            # someone is currently editing the file
            continue
        var current_code = FileAccess.open(file_path, FileAccess.READ).get_as_text()
        assert(shader_code_cache.has(file_path), "File path must exist in shader code cache")

        if shader_code_cache[file_path] != current_code:
            var shader_name = get_shader_name(file_path)
            assert(compute_shader_kernel_compilations.has(shader_name), "Shader name must exist in compilations")

            # Clear old RIDs
            for kernel in compute_shader_kernel_compilations[shader_name]:
                if kernel.is_valid():
                    rd.free_rid(kernel)
            compute_shader_kernel_compilations[shader_name].clear()

            # Recompile
            compile_compute_shader(file_path)


## Resource cleanup during runtime destruction
func _notification(what):
    if what == NOTIFICATION_PREDELETE:
        if rd == null:
            return

        for shader_name in shader_compilations:
            var shader = shader_compilations[shader_name]
            if shader.is_valid():
                rd.free_rid(shader)

        for compute_shader in compute_shader_kernel_compilations:
            for kernel in compute_shader_kernel_compilations[compute_shader]:
                if kernel.is_valid():
                    rd.free_rid(kernel)


## Getter to retrieve compiled kernel RIDs for other scripts
func get_compute_kernel_compilations(shader_name):
    assert(shader_name != "", "Shader name must not be empty")
    if compute_shader_kernel_compilations.has(shader_name):
        return compute_shader_kernel_compilations[shader_name]
    return []

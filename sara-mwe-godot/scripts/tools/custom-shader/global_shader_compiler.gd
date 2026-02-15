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

    var raw_text = _load_shader_file(compute_shader_file_path)
    var clean_text = _remove_comments(raw_text)
    clean_text = _process_includes(clean_text, compute_shader_file_path)

    var kernels = _extract_kernels(clean_text)
    assert(!kernels.is_empty(), "No kernels found in: " + compute_shader_file_path)

    _prepare_kernel_rids(compute_shader_name)

    for k_name in kernels:
        _compile_kernel(k_name, clean_text, compute_shader_name)


## Load shader file and cache its content
func _load_shader_file(file_path: String) -> String:
    var file = FileAccess.open(file_path, FileAccess.READ)
    assert(file != null, "Failed to open: " + file_path + " editing the file?")
    var raw_text = file.get_as_text()
    shader_code_cache[file_path] = raw_text
    return raw_text


## Remove all comments (line and block) to prevent parsing commented tags
func _remove_comments(raw_text: String) -> String:
    var comment_regex = RegEx.new()
    comment_regex.compile("/\\*[\\s\\S]*?\\*/|//.*")
    return comment_regex.sub(raw_text, "", true)


## Process #include directives and replace with file content
func _process_includes(clean_text: String, compute_shader_file_path: String) -> String:
    var include_regex = RegEx.new()
    include_regex.compile("#include\\s+\"([^\"]+)\"")

    var include_match = include_regex.search(clean_text)
    while include_match != null:
        var include_filename = include_match.get_string(1)
        var include_path = _find_include_file(include_filename, compute_shader_file_path)

        var include_file = FileAccess.open(include_path, FileAccess.READ)
        assert(include_file != null, "Failed to include file: " + include_path)
        var include_content = include_file.get_as_text()

        clean_text = clean_text.replace(include_match.get_string(0), include_content)
        include_match = include_regex.search(clean_text)

    return clean_text


## Find include file in same directory or subdirectories
func _find_include_file(include_filename: String, compute_shader_file_path: String) -> String:
    var search_dir = compute_shader_file_path.get_base_dir()

    var same_dir_path = search_dir.path_join(include_filename)
    if ResourceLoader.exists(same_dir_path):
        return same_dir_path

    var dir = DirAccess.open(search_dir)
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if dir.current_is_dir() and not file_name.begins_with("."):
                var subdir_path = search_dir.path_join(file_name).path_join(include_filename)
                if ResourceLoader.exists(subdir_path):
                    return subdir_path
            file_name = dir.get_next()

    assert(false, "Include file not found: " + include_filename)
    return ""


## Extract all kernel names from shader code
func _extract_kernels(clean_text: String) -> Array:
    var kernel_regex = RegEx.new()
    kernel_regex.compile("#kernel\\s+(\\w+)")
    var kernels = []
    for result in kernel_regex.search_all(clean_text):
        kernels.append(result.get_string(1))
    return kernels


## Prepare kernel RIDs for compilation (cleanup old ones)
func _prepare_kernel_rids(compute_shader_name: String) -> void:
    if not compute_shader_kernel_compilations.has(compute_shader_name):
        compute_shader_kernel_compilations[compute_shader_name] = []
    else:
        for rid in compute_shader_kernel_compilations[compute_shader_name]:
            if rid.is_valid():
                rd.free_rid(rid)
        compute_shader_kernel_compilations[compute_shader_name].clear()


## Compile a single kernel from the shader code
func _compile_kernel(k_name: String, clean_text: String, compute_shader_name: String) -> void:
    var code = clean_text
    var numthreads = _extract_numthreads(k_name, code)
    code = _replace_kernel_signature(k_name, code)

    var final_source = _assemble_glsl(numthreads, code)
    var rid = _compile_spirv(final_source, k_name)

    compute_shader_kernel_compilations[compute_shader_name].append(rid)
    _print_kernel_compiled(k_name, compute_shader_name)


## Extract numthreads values from kernel signature
func _extract_numthreads(k_name: String, code: String) -> Array:
    var func_sig_regex = RegEx.new()
    func_sig_regex.compile(
        "\\[numthreads\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)\\]\\s*void\\s+" +
        k_name + "\\s*\\(",
    )

    var match_sig = func_sig_regex.search(code)
    assert(match_sig != null, "Missing [numthreads] or valid signature for kernel: " + k_name)

    return [match_sig.get_string(1), match_sig.get_string(2), match_sig.get_string(3)]


## Replace kernel signature with standard main function
func _replace_kernel_signature(k_name: String, code: String) -> String:
    var func_sig_regex = RegEx.new()
    func_sig_regex.compile(
        "\\[numthreads\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)\\]\\s*void\\s+" +
        k_name + "\\s*\\(",
    )
    code = func_sig_regex.sub(code, "void main(")

    var kernel_regex = RegEx.new()
    kernel_regex.compile("#kernel\\s+(\\w+)")
    code = kernel_regex.sub(code, "", true)

    return code


## Assemble final GLSL source with version and layout directives
func _assemble_glsl(numthreads: Array, code: String) -> String:
    var final_source = "#version 450\n"
    final_source += "layout(local_size_x = %s, local_size_y = %s, local_size_z = %s) in;\n" % numthreads
    final_source += code
    return final_source


## Compile GLSL to SPIR-V
func _compile_spirv(final_source: String, k_name: String) -> RID:
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
    return rid


## Print kernel compilation status
func _print_kernel_compiled(k_name: String, compute_shader_name: String) -> void:
    if k_name == compute_shader_name:
        print("Compiled Kernel: " + k_name)
    else:
        print("Compiled Kernel: " + k_name + " (" + compute_shader_name + ")")


## Hot-reload logic
func _process(_delta: float) -> void:
    frame_counter += 1
    if frame_counter % CHECK_EVERY_X_FPS != 0:
        return

    for file_path in compute_shader_file_paths:
        # Check if file content has changed since last cache update
        if FileAccess.open(file_path, FileAccess.READ) == null:
            # Someone is currently editing the file
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

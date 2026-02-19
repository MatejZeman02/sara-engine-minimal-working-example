## -------------------------------------------------------------------------
## Sara Brush Engine
## Copyright (c) 2026 [Matej Zeman]
##
## Portions of this compute shader infrastructure are based on the
## Acerola Compute Wrapper by Acerola (Garrett Gunnell).
## https://github.com/GarrettGunnell/Acerola-Compute/tree/main
##
## This software is released under the MIT License.
## The license file is in this folder.
## https://opensource.org/licenses/MIT
## -------------------------------------------------------------------------
##
## Abstraction layer for dispatching Vulkan compute workloads.
##
## Simplifies the process of setting push constants, binding textures,
## and executing shader kernels via the RenderingDevice.

@tool
extends RefCounted

## .gmacs: Godot Matej-Acerola Compute-Shader
class_name MaCompute

var kernels = []
var rd: RenderingDevice
var shader_name: String
var shader_id: RID
var push_constant: PackedByteArray = PackedByteArray()

# Uniform Management
var uniform_set_gpu_id: RID
var uniform_set_cache: Array[RDUniform] = []
var uniform_buffer_cache = { }
var uniform_buffer_id_cache = { }

var refresh_uniforms = true
var _active_compute_list: int = -1


func _init(_shader_name: String) -> void:
    assert(not _shader_name.is_empty(), "Shader name cannot be empty")
    rd = RenderingServer.get_rendering_device()
    assert(rd != null, "RenderingDevice is null")
    shader_name = _shader_name
    _load_kernels()


# Sets push constants from a float array with padding to ensure 16-byte alignment
func set_push_constant_float_array(data: PackedFloat32Array) -> void:
    assert(not data.is_empty(), "Float array cannot be empty")
    # Vulkan (std430) aligns blocks according to vec4 (16 bytes = 4 floats)
    var floats_count = data.size()
    var remainder = floats_count % 4

    var aligned_data = data
    #  if the data size is not a multiple of 4, pad with zeros
    if remainder != 0:
        aligned_data = data.duplicate()
        aligned_data.resize(floats_count + (4 - remainder))

    push_constant = aligned_data.to_byte_array()


# Sets push constants from a raw byte array
func set_push_constant(data: PackedByteArray) -> void:
    assert(not data.is_empty(), "Byte array cannot be empty")
    push_constant = data


# Binds a texture to a specific uniform binding slot
func set_texture(binding: int, texture_rid: RID) -> void:
    assert(binding >= 0, "Binding index cannot be negative")
    assert(texture_rid.is_valid(), "Texture RID is not valid")
    var u = RDUniform.new()
    u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    u.binding = binding
    u.add_id(texture_rid)
    _cache_uniform(u)

# --- BATCHING API ---

## Opens the communication queue with the GPU
func list_begin(kernel_index: int = 0) -> void:
    assert(kernel_index >= 0 and kernel_index < kernels.size(), "Invalid kernel index")

    # Check for hot-reloads
    var global_shader_list = GlobalShaderCompiler.get_compute_kernel_compilations(shader_name)
    if not global_shader_list.is_empty() and shader_id != global_shader_list[0]:
        _load_kernels()
        refresh_uniforms = true

    _active_compute_list = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(_active_compute_list, kernels[kernel_index])


## Adds work to the open queue
func list_dispatch(x_groups: int, y_groups: int, z_groups: int) -> void:
    assert(_active_compute_list != -1, "You must call list_begin() before list_dispatch()")

    # Rebuild Uniform Set only if necessary (textures changed)
    if refresh_uniforms:
        if uniform_set_gpu_id.is_valid():
            rd.free_rid(uniform_set_gpu_id)
        var valid_uniforms = uniform_set_cache.filter(func(u): return u != null)
        if shader_id.is_valid():
            uniform_set_gpu_id = rd.uniform_set_create(valid_uniforms, shader_id, 0)
            refresh_uniforms = false

    if uniform_set_gpu_id.is_valid():
        rd.compute_list_bind_uniform_set(_active_compute_list, uniform_set_gpu_id, 0)

    if not push_constant.is_empty():
        rd.compute_list_set_push_constant(_active_compute_list, push_constant, push_constant.size())

    rd.compute_list_dispatch(_active_compute_list, x_groups, y_groups, z_groups)


## Closes the queue and submits the entire batch to the GPU
func list_end() -> void:
    assert(_active_compute_list != -1, "No active compute list to end")
    rd.compute_list_end()
    _active_compute_list = -1


## brush calls of dispatch
func dispatch(kernel_index: int, x_groups: int, y_groups: int, z_groups: int) -> void:
    list_begin(kernel_index)
    list_dispatch(x_groups, y_groups, z_groups)
    list_end()

# --- Internal Methods ---


## Loads and creates compute pipelines for each kernel in the shader
func _load_kernels() -> void:
    assert(rd != null, "RenderingDevice is null")
    for k in kernels:
        if k.is_valid():
            rd.free_rid(k)
    kernels.clear()

    var compiled_shaders = GlobalShaderCompiler.get_compute_kernel_compilations(shader_name)
    if compiled_shaders.is_empty():
        return

    shader_id = compiled_shaders[0]
    assert(shader_id.is_valid(), "Compiled shader RID is not valid")

    for shader_rid in compiled_shaders:
        if shader_rid.is_valid():
            var pipeline = rd.compute_pipeline_create(shader_rid)
            assert(pipeline.is_valid(), "Compute pipeline creation failed")
            kernels.append(pipeline)


## Caches uniform settings to avoid unnecessary rebuilds
func _cache_uniform(u: RDUniform) -> void:
    assert(u != null, "RDUniform cannot be null")
    assert(u.binding >= 0, "Binding index cannot be negative")
    if uniform_set_cache.size() <= u.binding:
        uniform_set_cache.resize(u.binding + 1)

    var old_u = uniform_set_cache[u.binding]
    if old_u == null or _has_uniform_changed(old_u, u):
        uniform_set_cache[u.binding] = u
        refresh_uniforms = true


## Compares old and new uniforms to detect changes
func _has_uniform_changed(old_u: RDUniform, new_u: RDUniform) -> bool:
    assert(old_u != null, "Old RDUniform cannot be null")
    assert(new_u != null, "New RDUniform cannot be null")
    if old_u.get_ids().size() != new_u.get_ids().size():
        return true
    for i in range(old_u.get_ids().size()):
        if old_u.get_ids()[i] != new_u.get_ids()[i]:
            return true
    return false


## RAII cleanup during runtime destruction
func _notification(what):
    if what == NOTIFICATION_PREDELETE:
        # user clicked the window close button
        if rd == null:
            return
        for k in kernels:
            if k.is_valid():
                rd.free_rid(k)
        for rid in uniform_buffer_id_cache.values():
            if rid.is_valid():
                rd.free_rid(rid)
        # if uniform_set_gpu_id.is_valid(): # throws error otherwise
        #     rd.free_rid(uniform_set_gpu_id)

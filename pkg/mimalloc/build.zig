const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const mimalloc_dep = b.dependency("mimalloc", .{});
    const mimalloc_module = b.addTranslateC(.{
        .root_source_file = mimalloc_dep.path("include/mimalloc.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }).createModule();

    const mimalloc_lib = build_library(b, "mimalloc", mimalloc_module, .static);

    mimalloc_lib.addCSourceFiles(.{
        .root = mimalloc_dep.path("src"),
        .files = &.{"static.c"},
        .flags = &.{
            "-std=c11",
            "-O3",
            "-march=native",
            "-ffunction-sections",
            "-fdata-sections",
            "-fvisibility=hidden",
            "-Wstrict-prototypes",
            "-ftls-model=initial-exec",
            "-DMI_SECURE=0", // 0 || 1 for debug
            if (optimize == .ReleaseSafe or optimize == .Debug) "-DMI_SECURE=4" else "-DMI_SECURE=0",
            "-DMI_DEBUG=0", // 0  || 3 for debug
            "-DMI_STAT=0", // 0   || 1 for debug
            "-DMI_LIBC_MUSL=1",
            "-DMI_NO_PTHREADS=1",

            "-DMI_NO_VERSION=1",
            "-DMI_OVERRIDE=0",
            "-DMI_TRACK_ASAN=0",
            "-ffast-math",
            "-fomit-frame-pointer",
        },
    });

    mimalloc_lib.addIncludePath(mimalloc_dep.path("include"));
    mimalloc_lib.installHeadersDirectory(mimalloc_dep.path("include"), ".", .{});

    const mimalloc_zig = b.addModule("mimalloc", .{
        .root_source_file = b.path("mimalloc.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mimalloc", .module = mimalloc_module },
        },
        .link_libc = true,
    });

    mimalloc_zig.linkLibrary(mimalloc_lib);
}

fn build_library(
    b: *std.Build,
    name: []const u8,
    module: *std.Build.Module,
    linkage: std.builtin.LinkMode,
) *std.Build.Step.Compile {
    const l = b.addLibrary(.{
        .name = name,
        .root_module = module,
        .linkage = linkage,
    });
    strip_step(l);

    return l;
}

fn strip_step(step: *std.Build.Step.Compile) void {
    if (step.root_module.optimize != .Debug and step.root_module.optimize != .ReleaseSafe) {
        step.use_llvm = true;
        step.link_eh_frame_hdr = false;
        step.link_emit_relocs = false;
        step.lto = .full;
        step.bundle_compiler_rt = true;
        step.pie = false;
        step.bundle_ubsan_rt = false;
        step.link_gc_sections = true;
        step.link_function_sections = true;
        step.link_data_sections = true;
        step.discard_local_symbols = true;
        step.compress_debug_sections = .none;
    } else {
        step.use_llvm = true;
    }
    if (@hasField(std.meta.Child(@TypeOf(step)), "llvm_codegen_threads"))
        step.llvm_codegen_threads = step.llvm_codegen_threads orelse 0;
}

fn build_module(
    b: *std.Build,
    options: std.Build.Module.CreateOptions,
) *std.Build.Module {
    const m = b.createModule(options);
    strip(m);
    return m;
}

fn strip(root_module: *std.Build.Module) void {
    if (root_module.optimize != .Debug and root_module.optimize != .ReleaseSafe) {
        // root_module.strip = true;
        root_module.omit_frame_pointer = true;
        root_module.unwind_tables = .none;
        root_module.sanitize_c = .off;
    } else {
        root_module.strip = false;
        root_module.omit_frame_pointer = false;
        root_module.unwind_tables = .sync;
        root_module.sanitize_c = .full;
    }
}

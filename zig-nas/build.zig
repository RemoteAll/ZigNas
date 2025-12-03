const std = @import("std");

/// 平台配置结构（用于跨平台优化）
const PlatformConfig = struct {
    name: []const u8,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    strip: bool,
};

/// 检测平台类型并返回优化配置
fn detectPlatformConfig(target_query: std.Target.Query, optimize: std.builtin.OptimizeMode) PlatformConfig {
    const cpu_arch = target_query.cpu_arch orelse @import("builtin").cpu.arch;

    // 检测是否是嵌入式 ARM 设备（如 Synology NAS）
    const is_embedded_arm = blk: {
        if (cpu_arch != .arm) break :blk false;

        // 检测 musl libc 或 gnueabi/gnueabihf
        if (target_query.abi) |abi| {
            if (abi == .musleabi or abi == .musleabihf or
                abi == .gnueabi or abi == .gnueabihf)
            {
                break :blk true;
            }
        }
        break :blk false;
    };

    // 检测是否是高性能服务器平台
    const is_high_perf = blk: {
        if (is_embedded_arm) break :blk false;

        // x86_64 或 aarch64 → 高性能服务器
        if (cpu_arch == .x86_64 or cpu_arch == .aarch64) {
            break :blk true;
        }
        break :blk false;
    };

    // 根据平台返回优化配置
    if (is_embedded_arm) {
        return PlatformConfig{
            .name = "embedded_arm",
            .optimize = .ReleaseSmall, // NAS: 体积优先（存储空间有限）
            .linkage = .static, // 静态链接提高兼容性（避免依赖问题）
            .strip = true, // 减小二进制体积
        };
    } else if (is_high_perf) {
        return PlatformConfig{
            .name = "high_perf",
            .optimize = switch (optimize) {
                .Debug => .Debug,
                else => .ReleaseFast, // 高性能：速度第一
            },
            .linkage = .dynamic, // 动态链接使用系统优化库
            .strip = false, // 保留符号便于性能分析
        };
    } else {
        return PlatformConfig{
            .name = "generic",
            .optimize = optimize,
            .linkage = .dynamic,
            .strip = false,
        };
    }
}

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // ========== 平台检测与配置 ==========
    const platform_config = detectPlatformConfig(target.query, optimize);

    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("zig_nas", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.

    // 根据目标平台生成带平台标识的文件名
    const target_query = target.query;
    const platform_suffix = blk: {
        const os_tag = target_query.os_tag orelse @import("builtin").os.tag;
        const cpu_arch = target_query.cpu_arch orelse @import("builtin").cpu.arch;

        const os_name = switch (os_tag) {
            .windows => "windows",
            .linux => "linux",
            .macos => "macos",
            else => @tagName(os_tag),
        };

        const arch_name = switch (cpu_arch) {
            .x86_64 => "x86_64",
            .aarch64 => "aarch64",
            .arm => "armv7", // ARM 32位标识为 armv7
            else => @tagName(cpu_arch),
        };

        break :blk b.fmt("-{s}-{s}", .{ os_name, arch_name });
    };

    const exe = b.addExecutable(.{
        .name = b.fmt("zig_nas{s}", .{platform_suffix}),
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = platform_config.optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "zig_nas" is the name you will use in your source code to
                // import this module (e.g. `@import("zig_nas")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "zig_nas", .module = mod },
            },
        }),
    });

    // 应用平台特定配置
    exe.linkage = platform_config.linkage;
    exe.root_module.strip = platform_config.strip;

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // ========== 交叉编译目标（针对不同平台和架构）==========
    const cross_targets = [_]struct {
        query: std.Target.Query,
        name: []const u8,
        force_high_perf: bool, // 是否强制高性能模式（覆盖默认配置）
    }{
        // ========== ARMv7 目标（Synology NAS 等）==========
        // ARMv7 高性能版本 - ReleaseFast + 动态链接
        .{
            .query = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .gnueabihf, // 硬浮点，适配 Synology ARMv7l
            },
            .name = "linux-armv7-fast",
            .force_high_perf = true, // 强制高性能模式
        },
        // ARMv7 体积优化版本 - ReleaseSmall + 静态链接（默认）
        .{
            .query = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .gnueabihf,
            },
            .name = "linux-armv7-small",
            .force_high_perf = false,
        },
        // 嵌入式 ARM (OpenWrt) - musl + 硬浮点
        .{
            .query = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
            .name = "linux-arm-musl",
            .force_high_perf = false,
        },
        // ========== ARM64 目标 ==========
        // Linux ARM64 服务器
        .{
            .query = .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .name = "linux-aarch64",
            .force_high_perf = true,
        },
        // ========== x86_64 目标 ==========
        // Linux x86_64 服务器
        .{
            .query = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .name = "linux-x86_64",
            .force_high_perf = true,
        },
        // Windows x86_64
        .{
            .query = .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .gnu,
            },
            .name = "windows-x86_64",
            .force_high_perf = true,
        },
    };

    // 为每个目标创建交叉编译步骤
    for (cross_targets) |cross_target| {
        const cross_target_resolved = b.resolveTargetQuery(cross_target.query);

        // 根据 force_high_perf 决定配置
        const cross_platform_config = if (cross_target.force_high_perf)
            PlatformConfig{
                .name = "high_perf",
                .optimize = .ReleaseFast,
                .linkage = .static, // ARMv7 即使高性能也用静态链接保证兼容性
                .strip = false, // 保留符号便于性能分析
            }
        else
            detectPlatformConfig(cross_target.query, .ReleaseFast);

        // 交叉编译可执行文件
        const cross_exe = b.addExecutable(.{
            .name = b.fmt("zig_nas-{s}", .{cross_target.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = cross_target_resolved,
                .optimize = cross_platform_config.optimize,
                .imports = &.{
                    .{ .name = "zig_nas", .module = mod },
                },
            }),
        });
        cross_exe.linkage = cross_platform_config.linkage;
        cross_exe.root_module.strip = cross_platform_config.strip;
        b.installArtifact(cross_exe);
    }

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}

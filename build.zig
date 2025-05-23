const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/telegram.zig"),
        .target = target,
        .optimize = optimize,
    });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    exe_mod.addImport("zigtgshka_lib", lib_mod);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addStaticLibrary(.{
        .name = "telegram-bot-api",
        .root_source_file = b.path("src/telegram.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "zigtgshka",
        .root_module = exe_mod,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/telegram.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_tests.linkLibC();

    const run_main_tests = b.addRunArtifact(main_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);

    // Helper function to add example executables
    const Example = struct {
        name: []const u8,
        file: []const u8,
        description: []const u8,
    };

    const examples = [_]Example{
        .{ .name = "echo_bot", .file = "examples/echo_bot.zig", .description = "Run the echo bot example" },
        .{ .name = "bot_info", .file = "examples/bot_info.zig", .description = "Get bot information" },
        .{ .name = "simple_sender", .file = "examples/simple_sender.zig", .description = "Send a simple message" },
        .{ .name = "polling_bot", .file = "examples/polling_bot.zig", .description = "Run the polling bot with commands" },
        .{ .name = "webhook_manager", .file = "examples/webhook_manager.zig", .description = "Manage webhooks and check bot status" },
        .{ .name = "advanced_bot", .file = "examples/advanced_bot.zig", .description = "Run the advanced bot with state management" },
    };

    // Add all example executables
    for (examples) |example| {
        const exe_example = b.addExecutable(.{
            .name = example.name,
            .root_source_file = b.path(example.file),
            .target = target,
            .optimize = optimize,
        });
        exe_example.root_module.addImport("telegram", lib_mod);
        exe_example.linkLibC();
        b.installArtifact(exe_example);

        // Add run step for each example
        const run_example = b.addRunArtifact(exe_example);
        if (b.args) |args| {
            run_example.addArgs(args);
        }

        const step_name = std.fmt.allocPrint(b.allocator, "run-{s}", .{example.name}) catch @panic("OOM");
        const run_example_step = b.step(step_name, example.description);
        run_example_step.dependOn(&run_example.step);
    }

    // Add a convenience step to run the echo bot (backward compatibility)
    const run_echo_step = b.step("run-example", "Run the echo bot example (alias for run-echo_bot)");
    const echo_exe = b.addExecutable(.{
        .name = "echo-bot-compat",
        .root_source_file = b.path("examples/echo_bot.zig"),
        .target = target,
        .optimize = optimize,
    });
    echo_exe.root_module.addImport("telegram", lib_mod);
    echo_exe.linkLibC();

    const run_echo_compat = b.addRunArtifact(echo_exe);
    if (b.args) |args| {
        run_echo_compat.addArgs(args);
    }
    run_echo_step.dependOn(&run_echo_compat.step);

    // Module exports for external dependency usage
    const telegram_module = b.addModule("telegram", .{
        .root_source_file = b.path("src/telegram.zig"),
        .target = target,
        .optimize = optimize,
    });
    telegram_module.linkLibrary(lib);
}

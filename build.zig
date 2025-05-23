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

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/telegram.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_tests.linkLibC();

    const run_main_tests = b.addRunArtifact(main_tests);

    // Add tests for json.zig module
    const json_tests = b.addTest(.{
        .root_source_file = b.path("src/json.zig"),
        .target = target,
        .optimize = optimize,
    });
    json_tests.linkLibC();

    const run_json_tests = b.addRunArtifact(json_tests);

    // Add tests for utils.zig module (if it has tests)
    const utils_tests = b.addTest(.{
        .root_source_file = b.path("src/utils.zig"),
        .target = target,
        .optimize = optimize,
    });
    utils_tests.linkLibC();

    const run_utils_tests = b.addRunArtifact(utils_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run all library tests");
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(&run_json_tests.step);
    test_step.dependOn(&run_utils_tests.step);

    // Individual test steps for granular testing
    const test_main_step = b.step("test-main", "Run tests for telegram.zig");
    test_main_step.dependOn(&run_main_tests.step);

    const test_json_step = b.step("test-json", "Run tests for json.zig");
    test_json_step.dependOn(&run_json_tests.step);

    const test_utils_step = b.step("test-utils", "Run tests for utils.zig");
    test_utils_step.dependOn(&run_utils_tests.step);

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

// Standard library
const std = @import("std");

// Constants
// Project settings
const PROJECT_NAME = "MonOS";
const PROJECT_ZIG_DEPENDENCIES = .{
    .{ .name = "limine_zig", .src = "git+https://github.com/48cf/limine-zig#trunk" },
};

// A list of architectures supported by the kernel
const Arch = enum {
    x86_64,
    aarch64,
    riscv64,
    loongarch64,

    /// Convert the architecture to `std.Target.Cpu.Arch`
    fn toStd(self: @This()) std.Target.Cpu.Arch {
        return switch (self) {
            .x86_64 => .x86_64,
            .aarch64 => .aarch64,
            .riscv64 => .riscv64,
            .loongarch64 => .loongarch64,
        };
    }
};

// Create a target query for the given architecture
fn targetQueryForArch(arch: Arch) std.Target.Query {
    // Create a target query
    var targetQuery: std.Target.Query = .{
        .cpu_arch = arch.toStd(),
        .os_tag = .freestanding,
        .abi = .none,
    };

    // The target needs to disable some features that are unsupported in a bare-metal environment
    switch (arch) {
        .x86_64 => {
            const target = std.Target.x86;
            targetQuery.cpu_features_add = target.featureSet(&.{ .popcnt, .soft_float });
            targetQuery.cpu_features_sub = target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx });
        },
        .aarch64 => {
            const target = std.Target.aarch64;
            targetQuery.cpu_features_add = target.featureSet(&.{});
            targetQuery.cpu_features_sub = target.featureSet(&.{ .fp_armv8, .crypto, .neon });
        },
        .riscv64 => {
            const target = std.Target.riscv;
            targetQuery.cpu_features_add = target.featureSet(&.{});
            targetQuery.cpu_features_sub = target.featureSet(&.{.d});
        },
        .loongarch64 => {},
    }

    // Return the target query
    return targetQuery;
}

// Declaratively construct a build graph to be executed by an external runner
pub fn build(b: *std.Build) void {
    // Options
    const architecture = b.option(Arch, "arch", "Architecture to build MonOS for") orelse .x86_64;

    // Resolve which target/architecture to build for
    // Allow optimization mode to be specified when running `zig build`
    const target = b.resolveTargetQuery(targetQueryForArch(architecture));
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const limineDep = b.dependency("limine_zig", .{
        .api_revision = 3,
        .allow_deprecated = false,
        .no_pointers = false,
    });

    // Modules
    const kernelMod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "limine", .module = limineDep.module("limine") },
        },
    });

    // Specify the code model and other target-specific options
    switch (architecture) {
        .x86_64 => {
            kernelMod.red_zone = false;
            kernelMod.code_model = .kernel;
        },
        .aarch64, .riscv64, .loongarch64 => {},
    }

    // A build step to build an executable
    const kernel = b.addExecutable(.{
        .name = PROJECT_NAME,
        .root_module = kernelMod,
    });

    // Set the linker script for the kernel based on the architecture
    kernel.setLinkerScript(b.path(b.fmt("./linker-{s}.ld", .{@tagName(architecture)})));

    // Install the executable into the standard location when `install` step is invoked
    // The `install` step is the default step when running `zig build`
    b.resolveInstallPrefix(null, .{ .exe_dir = b.fmt("bin-{s}", .{@tagName(architecture)}) });
    b.installArtifact(kernel);

    // Add manually invoked build steps
    fetchDeps(b);

    // Run step
    const runCmd = b.addSystemCommand(&.{
        "qemu-system-x86_64",
    });
    runCmd.step.dependOn(b.getInstallStep());
    const runStep = b.step("run", "Run program");
    runStep.dependOn(&runCmd.step);

    // Unit testing step - Builds the program without running it
    const kernelUnitTests = b.addTest(.{ .root_module = kernelMod });
    const runKernelUnitTests = b.addRunArtifact(kernelUnitTests);
    const testStep = b.step("test", "Run unit tests");
    testStep.dependOn(&runKernelUnitTests.step);
}

// Fetch/Update project dependencies
fn fetchDeps(b: *std.Build) void {
    // Fetch/Update all Zig dependencies
    const fetchDepsStep = b.step("fetchDeps", "Fetch all dependencies");
    inline for (PROJECT_ZIG_DEPENDENCIES) |dependency| {
        const cmd = b.addSystemCommand(&.{ "zig", "fetch", "--save=" ++ dependency.name, dependency.src });
        fetchDepsStep.dependOn(&cmd.step);
    }

    // Fetch the latest binary release of Limine 9.x
    const fetchLimineCmd = b.addSystemCommand(&.{ "git", "clone", "https://github.com/limine-bootloader/limine.git", "--branch=v9.x-binary", "--depth=1", "limine" });
    fetchDepsStep.dependOn(&fetchLimineCmd.step);
}

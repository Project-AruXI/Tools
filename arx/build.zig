// zig fmt: off

const std = @import("std");


pub fn build(b: *std.Build) void {
  const target = b.standardTargetOptions(.{});

  const optimize = b.standardOptimizeOption(.{});

  const exe = b.addExecutable(.{
    .name = "arx",
    .root_module = b.createModule(.{
      .root_source_file = b.path("arx.zig"),
      .target = target,
      .optimize = optimize,
    }),
    .use_llvm = true // use it to be able to use debugger
  });

  const options = b.addOptions();
  options.addOption(bool, "dprint", b.option(bool, "dprint", "Enable debug printing") orelse false);
  exe.root_module.addOptions("build_options", options);

  const cliargs = b.dependency("yazap", .{});
  exe.root_module.addImport("args", cliargs.module("yazap"));

  const cham = b.dependency("chameleon", .{});
  exe.root_module.addImport("chameleon", cham.module("chameleon"));

  const ziggy = b.dependency("ziggy", .{});
  exe.root_module.addImport("ziggy", ziggy.module("ziggy"));

  const installExe = b.addInstallArtifact(exe, .{
    .dest_dir = .{
      .override = .{ .custom = "../../out" },
    },
  });
  
  b.getInstallStep().dependOn(&installExe.step);

  const runStep = b.step("run", "Run the app");

  const runCmd = b.addRunArtifact(exe);
  runStep.dependOn(&runCmd.step);

  runCmd.step.dependOn(b.getInstallStep());

  if (b.args) |args| {
    runCmd.addArgs(args);
  }

  const exeTests = b.addTest(.{
    .root_module = exe.root_module,
  });

  const runExeTests = b.addRunArtifact(exeTests);
  const testStep = b.step("test", "Run tests");
  testStep.dependOn(&runExeTests.step);
}
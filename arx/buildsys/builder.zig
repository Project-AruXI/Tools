// zig fmt: off

const std = @import("std");
const Chameleon = @import("chameleon");
const buildopts = @import("build_options");
const ziggy = @import("ziggy");

const buildTypes = @import("buildStruct.zig");

var stdoutBuffer: [1024]u8 = undefined;
var stdinBuffer: [1024]u8 = undefined;
var w = std.fs.File.stdout().writer(&stdoutBuffer);
const stdout = &w.interface;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

var clr:Chameleon.RuntimeChameleon = undefined;


const DbgLvl = enum {
DBG_BASIC,
DBG_DETAIL,
DBG_TRACE
};


fn debug(lvl: DbgLvl, comptime fmt: []const u8, fmtargs: anytype) void {
  if (buildopts.dprint) {
  var colorstr: []const u8 = undefined;
  switch (lvl) {
    DbgLvl.DBG_BASIC => { 
      colorstr = clr.cyan().fmt(fmt, fmtargs) catch "";
    },
    DbgLvl.DBG_DETAIL => { 
      colorstr = clr.blue().fmt(fmt, fmtargs) catch "";
    },
    DbgLvl.DBG_TRACE => { 
      colorstr = clr.magenta().fmt(fmt, fmtargs) catch "";
    },
  }
  std.debug.print("{s}", .{colorstr});
  }
}


fn runCompiler() !void {

}

// Process of compiling a target:
// 1. Gather source files from sourceDirs and sources
// 2. Apply compilerOptions, assemblerOptions, linkerOptions to the arxc command
//   2.a Inject libraryDirs and libraries as needed to be linker options
//   2.b If type is library, inject -d as a linker option
//   2.c If type is kernel, inject -k as a linker option
// 3. Execute the arxc command to compile the target

fn gatherFiles(sourceDirs: []const []const u8, sources: ?[]const []const u8) !std.ArrayList([]const u8) {
  var fileList = try std.ArrayList([]const u8).initCapacity(allocator, 6);
  // Gather files from sourceDirs
  // If sources is provided, only include those files found in sourceDirs
  // Others, get all files in sourceDirs (only get .ru, .s, .as, .asm files)
  for (sourceDirs) |dir| {
    const dirPath = std.fs.path.join(allocator, &.{ dir }) catch continue;
    debug(DbgLvl.DBG_TRACE, "Processing source directory: {s}\n", .{dirPath});
    var dirHandle = std.fs.cwd().openDir(dirPath, .{.iterate = true}) catch continue;
    defer dirHandle.close();

    var it = dirHandle.iterate();
    while (try it.next()) |entry| {
      if (entry.kind != .file) continue;

      const fileName = entry.name;
      debug(DbgLvl.DBG_TRACE, "Found file: {s}\n", .{fileName});
      const fileExt = std.fs.path.extension(fileName);
      debug(DbgLvl.DBG_TRACE, "File extension: {s}\n", .{fileExt});

      if (std.mem.eql(u8, fileExt, ".ru") or
          std.mem.eql(u8, fileExt, ".s") or
          std.mem.eql(u8, fileExt, ".as") or
          std.mem.eql(u8, fileExt, ".asm")) {

        // If sources is provided, check if fileName is in sources
        debug(DbgLvl.DBG_TRACE, "Considering file: {s}\n", .{fileName});
        if (sources) |srcs| if (srcs.len != 0) {
          var found = false;
          for (srcs) |src| {
            if (std.mem.eql(u8, src, fileName)) {
              found = true;
              break;
            }
          }
          if (!found) continue;
        };

        // Add to fileList
        const fullPath = std.fs.path.join(allocator, &.{ dirPath, fileName }) catch continue;
        try fileList.append(allocator, fullPath);
        debug(DbgLvl.DBG_TRACE, "Added file: {s}\n", .{fullPath});
      }
    }
    allocator.free(dirPath);
  }

  return fileList;
}

fn buildAssemblerArgs() !void {

}

fn executableProgram(target: buildTypes.Target, outbin: []const u8) !void {
  debug(DbgLvl.DBG_DETAIL, "Compiling executable program: {s}.arx\n", .{target.name.?});

  var files = try gatherFiles(target.sourceDirs.?, target.sources);
  defer files.deinit(allocator);

  debug(DbgLvl.DBG_TRACE, "Source files to compile:\n", .{});
  for (files.items) |file| {
    debug(DbgLvl.DBG_TRACE, " - {s}\n", .{file});
  }

  // var compilerOptsStr: []u8 = &[_]u8{};
  // var assemblerOptsStr: []u8 = &[_]u8{};
  // var linkerOptsStr: []u8 = &[_]u8{};

  // debug(DbgLvl.DBG_TRACE, "Compiler options: {s}\n", .{compilerOptsStr});
  // debug(DbgLvl.DBG_TRACE, "Assembler options: {s}\n", .{assemblerOptsStr});
  // debug(DbgLvl.DBG_TRACE, "Linker options: {s}\n", .{linkerOptsStr});

  // arxc ...files -o outbin ...compiler-options --assembler=f,p --linker=no-stdlib,k

  var cmdList = try std.ArrayList([]const u8).initCapacity(allocator, 8);
  defer cmdList.deinit(allocator);

  try cmdList.append(allocator, "arxc");

  // Add source files
  for (files.items) |file| {
    try cmdList.append(allocator, file);
  }

  // Add output binary
  // Output binary is [outbin]/[target].arx
  var outputPathBuf = try allocator.alloc(u8, outbin.len + 1 + target.name.?.len + 4);
  defer allocator.free(outputPathBuf);
  outputPathBuf = std.fs.path.join(allocator, &.{ outbin, "/" }) catch outputPathBuf;
  outputPathBuf = std.mem.concat(allocator, u8, &.{target.name.?, ".arx"}) catch outputPathBuf;
  const output = outputPathBuf;
  try cmdList.append(allocator, "-o");
  try cmdList.append(allocator, output);

  // Execute the process and wait for it to finish
  const argv = cmdList.items;

  // var cmfBuf: [1024]u8 = undefined;
  var proc = std.process.Child.init(argv, allocator);
  proc.spawn() catch |err| {
    debug(DbgLvl.DBG_BASIC, "Failed to spawn compiler process: {}\n", .{err});
    return;
  };
  const status = proc.wait() catch |err| {
    debug(DbgLvl.DBG_BASIC, "Failed to wait for compiler process: {}\n", .{err});
    return;
  };

  if (status.Exited != 0) {
    debug(DbgLvl.DBG_BASIC, "Compiler process exited with code: {d}\n", .{status.Exited});
    return;
  }
}

fn libraryProgram(target: buildTypes.Target, outbin: []const u8) !void {
  debug(DbgLvl.DBG_DETAIL, "Compiling library program: {s}.adlib\n", .{target.name.?});
  // Implement compilation logic here
  _ = outbin;
}

fn kernelProgram(target: buildTypes.Target, outbin: []const u8) !void {
  debug(DbgLvl.DBG_DETAIL, "Compiling kernel program: {s}.ark\n", .{target.name.?});
  // Implement compilation logic here
  _ = outbin;
}


pub fn build(targetName: []const u8) !void {
  clr = Chameleon.initRuntime(.{ .allocator = allocator });

  var arenaAllocator = std.heap.ArenaAllocator.init(allocator);
  defer arenaAllocator.deinit();
  var arena = arenaAllocator.allocator();
  arena = arena;

  debug(DbgLvl.DBG_BASIC, "Starting build process...\n", .{});

  // Read build.ziggy file (needs to be in cwd), alternative name is build.zgy
  // Try build.ziggy first, then build.zgy
  const buildFilePath = "build.zgy";

  const file = std.fs.cwd().openFile(buildFilePath, .{ .mode = .read_only }) catch |err| {
    if (err != error.FileNotFound) return err;
    
    try stdout.print("Build file '{s}' not found.\n", .{buildFilePath});
    try stdout.flush();
    return;
  };

  defer file.close();
  const fileInfo = try file.stat();
  const maxSize:usize = @intCast(fileInfo.size);
  var buildFileData = try std.fs.cwd().readFileAlloc(allocator, buildFilePath, maxSize);
  defer allocator.free(buildFileData);
  const buildFile: []const u8 = buildFileData[0..];

  // Create a zero-terminated copy required by ziggy.parseLeaky (expects [:0]const u8)
  var zbuf = try allocator.alloc(u8, buildFile.len + 1);
  defer allocator.free(zbuf);
  @memmove(zbuf[0..buildFile.len], buildFile);
  zbuf[buildFile.len] = 0;
  const buildFileZ: [:0]const u8 = zbuf[0..buildFile.len:0];

  // Parse build.ziggy
  const buildDoc = ziggy.parseLeaky(buildTypes.Document, arena, buildFileZ, .{}) catch |err| {
    switch (err) {
      ziggy.Parser.Error.Syntax => |syntaxErr| {
        try stdout.print("Syntax error in {s}: {}\n", .{buildFilePath, syntaxErr});
        try stdout.flush();
      },
      else => { return err; }
    }

    try stdout.print("Error parsing {s}: {}\n", .{buildFilePath, err});
    try stdout.flush();
    return err;
  };

  // Check that name and targets are present
  if (buildDoc.name == null) {
    try stdout.print("Project name is not specified in {s}.\n", .{buildFilePath});
    try stdout.flush();
    return;
    // return error.MissingProjectName;
  }
  if (buildDoc.targets == null) {
    try stdout.print("No targets defined in {s}.\n", .{buildFilePath});
    try stdout.flush();
    return;
    // return error.NoTargetsDefined;
  }
  const targets = buildDoc.targets.?;

  // const projName = buildDoc.name;
  // const projVersion = buildDoc.version;
  // debug(DbgLvl.DBG_BASIC, "Building project: {s} v{s}\n", .{projName, projVersion});
  // debug(DbgLvl.DBG_BASIC, "Target to build: {s}\n", .{targetName});

  const outbin = buildDoc.outbin orelse ".";
  debug(DbgLvl.DBG_DETAIL, "Output binary location: {s}\n", .{outbin});

  // Given the target name `targetName`, find the target in buildDoc.targets
  var targetToBuild:?buildTypes.Target = null;
  for (targets) |target| {
    // Ensure target has name, type, and sourceDirs at the very least
    if (target.name == null) {
      try stdout.print("A target is missing a name in {s}.\n", .{buildFilePath});
      try stdout.flush();
      return;
      // return error.MissingTargetName;
    }
    if (target.type == null) {
      try stdout.print("Target '{s}' is missing a type in {s}.\n", .{target.name.?, buildFilePath});
      try stdout.flush();
      return;
      // return error.MissingTargetType;
    }
    if (target.sourceDirs == null) {
      try stdout.print("Target '{s}' is missing sourceDirs in {s}.\n", .{target.name.?, buildFilePath});
      try stdout.flush();
      return;
      // return error.MissingTargetSourceDirs;
    }

    if (std.mem.eql(u8, target.name.?, targetName)) {
      targetToBuild = target;
      break;
    }
  }
  // If no target found, default to the first target
  if (targetToBuild == null) {
    if (targets.len > 0) {
      targetToBuild = targets[0];
    } else {
      debug(DbgLvl.DBG_BASIC, "No targets defined in build.ziggy.\n", .{});
      return;
      // return error.NoTargetsDefined;
    }
  }


  const target = targetToBuild.?;

  debug(DbgLvl.DBG_BASIC, "Building target: {s}\n", .{targetName});

  if (std.mem.eql(u8, target.type.?, "executable")) {
    debug(DbgLvl.DBG_DETAIL, "Target is an executable.\n", .{});
    try executableProgram(target, outbin);
  } else if (std.mem.eql(u8, target.type.?, "library")) {
    debug(DbgLvl.DBG_DETAIL, "Target is a library.\n", .{});
    try libraryProgram(target, outbin);
  } else if (std.mem.eql(u8, target.type.?, "kernel")) {
    debug(DbgLvl.DBG_DETAIL, "Target is a kernel.\n", .{});
    try kernelProgram(target, outbin);
  } else {
    debug(DbgLvl.DBG_BASIC, "Unknown target type: {s}\n", .{target.type.?});
    return;
    // return error.UnknownTargetType;
  }

  debug(DbgLvl.DBG_BASIC, "Build process completed.\n", .{});
}
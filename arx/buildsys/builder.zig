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

const TargetType = enum {
  Executable,
  Library,
  Kernel,
};

fn buildCompilerArgs(target: buildTypes.Target) ![]const u8 {
  if (target.compilerOptions == null) {
    return &[_]u8{};
  }
  if (target.compilerOptions.?.len == 0) {
    return &[_]u8{};
  }

  const compilerOptions = target.compilerOptions.?;

  var argsList = try std.ArrayList([]const u8).initCapacity(allocator, 4);
  defer argsList.deinit(allocator);

  for (compilerOptions) |opt| {
    if (std.mem.eql(u8, opt, "g")) {
      try argsList.append(allocator, "-g");
    } else if (std.mem.eql(u8, opt, "W") or std.mem.eql(u8, opt, "no-warn")) {
      try argsList.append(allocator, "--no-warn");
    } else if (std.mem.eql(u8, opt, "F") or std.mem.eql(u8, opt, "fatal-warning")) {
      try argsList.append(allocator, "--fatal-warning");
    } else {
      debug(DbgLvl.DBG_BASIC, "Invalid compiler option: {s}\n", .{opt});
      continue;
    }
  }

  return try std.mem.join(allocator, " ", argsList.items);
}

fn buildAssemblerArgs(target: buildTypes.Target) ![]const u8 {
  if (target.assemblerOptions == null) {
    return &[_]u8{};
  }
  if (target.assemblerOptions.?.len == 0) {
    return &[_]u8{};
  }

  const assemblerOptions = target.assemblerOptions.?;

  var argsList = try std.ArrayList([]const u8).initCapacity(allocator, 4);
  defer argsList.deinit(allocator);

  for (assemblerOptions) |opt| {
    if (!(std.mem.eql(u8, opt, "t") or
          std.mem.eql(u8, opt, "m") or
          std.mem.eql(u8, opt, "p") or
          std.mem.eql(u8, opt, "f"))) {
      debug(DbgLvl.DBG_BASIC, "Invalid assembler option: {s}\n", .{opt});
      continue;
    }
    try argsList.append(allocator, opt);
  }

  const joined = try std.mem.join(allocator, ",", argsList.items);
  defer allocator.free(joined);

  return std.fmt.allocPrint(allocator, "--assembler={s}", .{joined});
}

fn buildLinkerArgs(target: buildTypes.Target, targetType: TargetType) ![]const u8 {
  if (target.linkerOptions == null) {
    return &[_]u8{};
  }
  if (target.linkerOptions.?.len == 0) {
    return &[_]u8{};
  }

  const linkerOptions = target.linkerOptions.?;

  var argsList = try std.ArrayList([]const u8).initCapacity(allocator, 4);
  defer argsList.deinit(allocator);

  var hasK = false;
  var hasD = false;
  var hasNoStdlib = false;

  for (linkerOptions) |opt| {
    // Exes only allow no-stdlib
    // Libs only allow no-stdlib and d
    // Kernels only allow no-stdlib and k

    switch (targetType) {
      .Executable => {
        if (std.mem.eql(u8, opt, "k") or std.mem.eql(u8, opt, "d")) {
          debug(DbgLvl.DBG_BASIC, "Linker option '{s}' is invalid for executable targets.\n", .{opt});
          continue;
        }
      },
      .Library => {
        if (std.mem.eql(u8, opt, "k")) {
          debug(DbgLvl.DBG_BASIC, "Linker option 'k' is invalid for library targets.\n", .{});
          continue;
        }
        hasD = if (std.mem.eql(u8, opt, "d")) true else hasD;
      },
      .Kernel => {
        if (std.mem.eql(u8, opt, "d")) {
          debug(DbgLvl.DBG_BASIC, "Linker option 'd' is invalid for kernel targets.\n", .{});
          continue;
        }
        hasK = if (std.mem.eql(u8, opt, "k")) true else hasK;
        hasNoStdlib = if (std.mem.eql(u8, opt, "no-stdlib")) true else hasNoStdlib;
      },
    }

    try argsList.append(allocator, opt);
  }

  // Inject options based on target type
  if (targetType == .Library) {
    if (!hasD) {
      try argsList.append(allocator, "d");
    }
  } else if (targetType == .Kernel) {
    if (!hasK) {
      try argsList.append(allocator, "k");
    }
    if (!hasNoStdlib) {
      try argsList.append(allocator, "no-stdlib");
    }
  }

  const joined = try std.mem.join(allocator, ",", argsList.items);
  defer allocator.free(joined);

  return std.fmt.allocPrint(allocator, "--linker={s}", .{joined});
}

fn buildLibDirArgs(target: buildTypes.Target) ![]const u8 {
  // Build the libdir args
  // The form will be "-Llibdir0,libdir1,libdir2,..."

  if (target.libraryDirs == null) {
    return &[_]u8{};
  }
  if (target.libraryDirs.?.len == 0) {
    return &[_]u8{};
  }

  const libraryDirs = target.libraryDirs.?;

  const joined = try std.mem.join(allocator, ",", libraryDirs);
  defer allocator.free(joined);

  return std.fmt.allocPrint(allocator, "-L{s}", .{joined});
}

fn buildLibArgs(target: buildTypes.Target) ![]const u8 {
  // Build the lib args
  // The form will be "-llib0,lib1,lib2,..."

  if (target.libraries == null) {
    return &[_]u8{};
  }
  if (target.libraries.?.len == 0) {
    return &[_]u8{};
  }

  const libraries = target.libraries.?;

  const joined = try std.mem.join(allocator, ",", libraries);
  defer allocator.free(joined);

  return std.fmt.allocPrint(allocator, "-l{s}", .{joined});
}

fn buildProgram(target: buildTypes.Target, outbin: []const u8, targetType: TargetType) !void {
var files = try gatherFiles(target.sourceDirs.?, target.sources);
  defer files.deinit(allocator);

  debug(DbgLvl.DBG_TRACE, "Source files to compile:\n", .{});
  for (files.items) |file| {
    debug(DbgLvl.DBG_TRACE, " - {s}\n", .{file});
  }

  // Format of the command:
  // arxc ...files -o outbin ...compiler-options --assembler=f,p,.. --linker=no-stdlib,k,.. -Llibdir0,libdir1,... -llib0,lib1,...

  var cmdList = try std.ArrayList([]const u8).initCapacity(allocator, 8);
  defer cmdList.deinit(allocator);

  try cmdList.append(allocator, "arxc");

  // Add source files
  for (files.items) |file| {
    try cmdList.append(allocator, file);
  }

  // Add output binary
  var outputPathBuf = try allocator.alloc(u8, outbin.len + 1 + target.name.?.len + 6);
  defer allocator.free(outputPathBuf);
  outputPathBuf = try std.fs.path.join(allocator, &.{ outbin, "/" }); // catch outputPathBuf;
  debug(DbgLvl.DBG_TRACE, "Output binary base path: {s}\n", .{outputPathBuf});
  outputPathBuf = std.mem.concat(
    allocator, u8, &.{
      outputPathBuf,
      target.bin.?,
      if (targetType == .Executable) ".arx" else if (targetType == .Library) ".adlib" else ".ark"
    }
  ) catch outputPathBuf;
  const output = outputPathBuf;
  debug(DbgLvl.DBG_TRACE, "Output binary path: {s}\n", .{output});
  try cmdList.append(allocator, "-o");
  try cmdList.append(allocator, output);

  const compilerArgs = try buildCompilerArgs(target);
  try cmdList.append(allocator, compilerArgs);

  const assemblerArgs = try buildAssemblerArgs(target);
  try cmdList.append(allocator, assemblerArgs);

  const linkerArgs = try buildLinkerArgs(target, targetType);
  try cmdList.append(allocator, linkerArgs);

  const libdirArgs = try buildLibDirArgs(target);
  try cmdList.append(allocator, libdirArgs);

  const libArgs = try buildLibArgs(target);
  try cmdList.append(allocator, libArgs);

  // Execute the process and wait for it to finish
  const argv = cmdList.items;

  // View argv for debugging
  debug(DbgLvl.DBG_TRACE, "Compiler command:\n", .{});
  for (argv) |arg| {
    debug(DbgLvl.DBG_TRACE, " {s}", .{arg});
  }
  debug(DbgLvl.DBG_TRACE, "\n", .{});

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

pub fn build(targetName: []const u8) !void {
  clr = Chameleon.initRuntime(.{ .allocator = allocator });

  var arenaAllocator = std.heap.ArenaAllocator.init(allocator);
  defer arenaAllocator.deinit();
  var arena = arenaAllocator.allocator();
  arena = arena;

  debug(DbgLvl.DBG_BASIC, "Starting build process...\n", .{});

  // Read build.zgy file (needs to be in cwd)
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

  // Parse build.zgy
  var diagnostic = ziggy.Diagnostic{.path = null };
  const buildDoc = ziggy.parseLeaky(buildTypes.Document, arena, buildFileZ, .{.diagnostic = &diagnostic}) catch |err| {
    switch (err) {
      ziggy.Parser.Error.Syntax => |_| {
        try stdout.print("Syntax error in {s}: {f}\n", .{buildFilePath, diagnostic.fmt(buildFileZ)});
        try stdout.flush();
        return;
      },
      else => { return err; }
    }

    try stdout.print("Error parsing {s}: {}\n", .{buildFilePath, err});
    try stdout.flush();
    return;
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
    debug(DbgLvl.DBG_DETAIL, "Compiling executable program: {s}.arx\n", .{target.name.?});
    try buildProgram(target, outbin, .Executable);
  } else if (std.mem.eql(u8, target.type.?, "library")) {
    debug(DbgLvl.DBG_DETAIL, "Target is a library.\n", .{});
    debug(DbgLvl.DBG_DETAIL, "Compiling library program: {s}.adlib\n", .{target.name.?});
    try buildProgram(target, outbin, .Library);
  } else if (std.mem.eql(u8, target.type.?, "kernel")) {
    debug(DbgLvl.DBG_DETAIL, "Target is a kernel.\n", .{});
    debug(DbgLvl.DBG_DETAIL, "Compiling kernel program: {s}.ark\n", .{target.name.?});
    try buildProgram(target, outbin, .Kernel);
  } else {
    debug(DbgLvl.DBG_BASIC, "Unknown target type: {s}\n", .{target.type.?});
    return;
    // return error.UnknownTargetType;
  }

  debug(DbgLvl.DBG_BASIC, "Build process completed.\n", .{});
}
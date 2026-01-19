// zig fmt: off

const std = @import("std");
const buildopts = @import("build_options");
const args = @import("args");
const App = args.App;
const Arg = args.Arg;
const Command = args.Command;
const Chameleon = @import("chameleon");

const builder = @import("buildsys/builder.zig");

const MAJOR_VERSION = 0;
const MINOR_VERSION = 1;
const PATCH_VERSION = 0;

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


fn writeBuildFile(projectName: []const u8, description: []const u8, author: []const u8, version: []const u8) !void {
  const buildFileFormat = 
\\{{
\\  .name = "{s}",
\\  .version = "{s}",
\\  .author = "{s}",
\\  .description = "{s}",
\\  .dependencies = {{}}
\\}}
;

  var buildFileBuffer: [1024]u8 = undefined;
  var buildFileBufferStream = std.io.fixedBufferStream(&buildFileBuffer);
  var buildFileWriter = buildFileBufferStream.writer();
  try buildFileWriter.print(buildFileFormat, .{projectName, version, author, description});

  var buildFile = try std.fs.cwd().createFile("build.ziggy", .{ .truncate = true });
  defer buildFile.close();

  try buildFile.writeAll(buildFileBuffer[0..buildFileBufferStream.pos]);
}

fn initProject() !void {
  var stdinWriter = std.fs.File.stdin().reader(&stdinBuffer);
  const stdin = &stdinWriter.interface;

  var outBuffer: [128]u8 = undefined;
  const cwd = try std.fs.cwd().realpath(".", &outBuffer);
  const cwdName = std.fs.path.basename(cwd);

  try stdout.print("Project Name [{s}]: ", .{cwdName});
  try stdout.flush();
  const projectNamePre = try stdin.takeDelimiter('\n') orelse cwdName;
  const projectNameSlice = if (projectNamePre.len == 0) cwdName else projectNamePre;
  const projectName =  std.mem.Allocator.dupe(allocator, u8, projectNameSlice) catch cwdName;
  debug(DbgLvl.DBG_BASIC, "Creating project '{s}'...\n", .{projectName});

  const descriptionPrompt = "Description []: ";
  try stdout.print("{s}", .{descriptionPrompt});
  try stdout.flush();
  const descriptionSlice = try stdin.takeDelimiter('\n') orelse "";
  const description = std.mem.Allocator.dupe(allocator, u8, descriptionSlice) catch "";
  debug(DbgLvl.DBG_DETAIL, "Description: '{s}'\n", .{description});

  const authorPrompt = "Author []: ";
  try stdout.print("{s}", .{authorPrompt});
  try stdout.flush();
  const authorSlice = try stdin.takeDelimiter('\n') orelse "";
  const author = std.mem.Allocator.dupe(allocator, u8, authorSlice) catch "";
  debug(DbgLvl.DBG_DETAIL, "Author: '{s}'\n", .{author});

  const versionPrompt = "Version [0.1.0]: ";
  try stdout.print("{s}", .{versionPrompt});
  try stdout.flush();
  const versionPre = try stdin.takeDelimiter('\n') orelse "0.1.0";
  const versionSlice = if (versionPre.len == 0) "0.1.0" else versionPre;
  const version = std.mem.Allocator.dupe(allocator, u8, versionSlice) catch "0.1.0";
  debug(DbgLvl.DBG_DETAIL, "Version: '{s}'\n", .{version});

  try writeBuildFile(projectName, description, author, version);
  debug(DbgLvl.DBG_BASIC, "Created build.ziggy file.\n", .{});

  var mainRuFile = try std.fs.cwd().createFile("main.ru", .{ .truncate = true });
  defer mainRuFile.close();
  const mainRuContent = "module main;\n\n@import \"std\";";
  try mainRuFile.writeAll(mainRuContent);
  debug(DbgLvl.DBG_BASIC, "Created main.ru file.\n", .{});
}


fn parseArgs() !void {
  var cliargs = App.init(std.heap.page_allocator, "arxc", "Desc");
  defer cliargs.deinit();

  var cli = cliargs.rootCommand();
  cli.setProperty(.help_on_empty_args);

  try cli.addSubcommands(&[_]Command{
    cliargs.createCommand("init", "Initialize a new project"),
    cliargs.createCommand("build", "Build the project in the current directory"),
  });

  try cli.subcommands.items[1].addArg(Arg.positional("TARGET", "Target to build", null));

  try cli.addArgs(&[_]Arg{
    Arg.booleanOption("version", 'v', "Show version and exit"),
  });

  const matches = try cliargs.parseProcess();

  if (matches.containsArg("version")) {
    try stdout.print("Aru Build version {}.{}.{}\n", .{ MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION });
    try stdout.flush();
    std.process.exit(0);
  }

  if (matches.subcommandMatches("init")) |_| {
    debug(DbgLvl.DBG_BASIC, "Initializing new project...\n", .{});
    initProject() catch |err| {
      try stdout.print("Error initializing project: {}\n", .{err});
      return err;
    };
  }

  if (matches.subcommandMatches("build")) |buildMatch| {
    const targetName = buildMatch.getSingleValue("TARGET") orelse "default";

    debug(DbgLvl.DBG_BASIC, "Building project...\n", .{});
    builder.build(targetName) catch |err| {
      try stdout.print("Error building project: {}\n", .{err});
      return err;
    };
  }
}


pub fn main() !void {
  clr = Chameleon.initRuntime(.{ .allocator = allocator });

  parseArgs() catch |err| {
    try stdout.print("Error parsing arguments: {}\n", .{err});
    return err;
  };
}
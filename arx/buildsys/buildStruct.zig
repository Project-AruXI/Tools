// zig fmt: off

pub const Target = struct {
  name:?[]const u8 = null, // The name of the target
  bin:?[]const u8 = null, // The output binary name
  type:?[]const u8 = null, // The type of binary: executable, library, etc.
  sourceDirs:?[]const []const u8 = null, // Source directories
  sources:?[]const []const u8 = null, // Source files
  compilerOptions:?[]const []const u8 = null, // Compiler options
  assemblerOptions:?[]const []const u8 = null, // Assembler options
  linkerOptions:?[]const []const u8 = null, // Linker options
  libraries:?[]const []const u8 = null, // Linked libraries
  libraryDirs:?[]const []const u8 = null, // Library directories
};

pub const Document = struct {
  name:?[]const u8 = null,
  version:?[]const u8 = null,
  author:?[]const u8 = null,
  description:?[]const u8 = null,
  outbin:?[]const u8 = null,
  targets:?[]Target = null,
};
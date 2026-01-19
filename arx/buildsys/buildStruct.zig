// zig fmt: off

const Map = @import("ziggy").dynamic.Map;

pub const Target = struct {
  name:?[]const u8, // The name of the target
  bin:?[]const u8, // The output binary name
  type:?[]const u8, // The type of binary: executable, library, etc.
  sourceDirs:?[]const []const u8, // Source directories
  sources:?[]const []const u8, // Source files
  compilerOptions:?[]const []const u8, // Compiler options
  assemblerOptions:?[]const []const u8, // Assembler options
  linkerOptions:?[]const []const u8, // Linker options
  libraries:?[]const []const u8, // Linked libraries
  libraryDirs:?[]const []const u8, // Library directories
};

pub const Document = struct {
  name:?[]const u8,
  version:?[]const u8,
  author:?[]const u8,
  description:?[]const u8,
  outbin:?[]const u8,
  targets:?[]Target,
};
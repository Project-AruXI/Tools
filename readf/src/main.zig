// zig fmt: off

const std = @import("std");
const stdout = std.io.getStdOut();
const simargs = @import("simargs");

const print = std.debug.print;

// const c = @cImport({
//     @cInclude("aeoff.h");
// });
const c = @import("aoef.zig");


fn showFileHeader(allocator:std.mem.Allocator, hdr:*c.AOEFFheader) void {
  _ = allocator;

  print("AOEFF Header:\n", .{});
  print("    ID: {s:23}{x:2} {x:2} {x:2} {x:2}\n", .{"", hdr.hID[0], hdr.hID[1], hdr.hID[2], hdr.hID[3]});

  var typeStr:[]const u8 = undefined;
  if (hdr.hType == c.AHT_EXEC) { typeStr = "Executable"; }
  else if (hdr.hType == c.AHT_KERN) { typeStr = "Kernel"; }
  else if (hdr.hType == c.AHT_SLIB) { typeStr = "Library"; }
  else typeStr = "UNKNOWN_TYPE";
  print("    Type: {s}\n", .{typeStr});

  print("    Entry point: {s: >14}0x{x}\n", .{"", hdr.hEntry});
  print("    Section Headers start: {d: >6} bytes into file\n", .{hdr.hSectOff});
  print("    Number of Section Headers: {d}\n", .{hdr.hSectSize});
  print("    Symbol Table start: {d: >10} bytes into file\n", .{hdr.hSymbOff});
  print("    Number of Symbols: {d: >12}\n", .{hdr.hSymbSize});
  print("    String Table start: {d: >10} bytes into file\n", .{hdr.hStrTabOff});
  print("    String Table size: {d: >12} bytes\n\n", .{hdr.hStrTabSize});
}

fn showSectionHeaders(allocator:std.mem.Allocator, ptr:[*]u8, hdr:*c.AOEFFheader) void {
  _ = allocator;

  var secthdr:[*]c.AOEFFSectHeader = @alignCast(@ptrCast(ptr + hdr.hSectOff));
  const secthdrSize = hdr.hSectSize;
  
  print("Section Headers ({d} entries):\n", .{secthdrSize});
  print("    [NM] {s: <8} {s: <8} {s: <8}\n", .{"Name", "Size", "Offset"});
  for (0..secthdrSize) |i| {
    print("Start of current secthdr: {*}\n", .{secthdr});
    print("    [{d:0>2}] {s: <8} {x:0>8} {x:0>8}\n", .{i, secthdr[i].shSectName, secthdr[i].shSectSize, secthdr[i].shSectOff});
    secthdr += 1;
  }
}

fn showStringTable(allocator:std.mem.Allocator, ptr:[*]u8, hdr:*c.AOEFFheader) void {
  _ = allocator;
  _ = ptr;
  _ = hdr;
}

fn showSymbolTable(allocator:std.mem.Allocator, ptr:[*]u8, hdr:*c.AOEFFheader) void {
  _ = allocator;

  var symbtab:[*]c.AOEFFSymbEntry = @alignCast(@ptrCast(ptr + hdr.hSymbOff));
  const symbtabSize = hdr.hSymbSize; // number of entries

  for (0..symbtabSize) |i| {
    print("Symbol name index: {d}\n", .{symbtab[i].seSymbName});

    print("Value for symbol entry {d}: 0x{x}\n", .{i, symbtab[i].seSymbVal});
    // symbtab[i].seSymbInfo
    const symbloc:c_int = c.SE_GET_LOC(symbtab[i].seSymbInfo);
    if (symbloc == c.SE_LOCAL) {
      print("Local\n", .{});
    } else if (symbloc == c.SE_GLOBL) {
      print("Global\n", .{});
    } else {
      print("INVALID\n", .{});
    }

    const symbtype:c_int = c.SE_GET_TYPE(symbtab[i].seSymbInfo);
    if (symbtype == c.SE_FUNC_T) {
      print("Address type\n", .{});
    } else if (symbtype == c.SE_ABSV_T) {
      print("Absolute type\n", .{});
    } else if (symbtype == c.SE_NONE_T) {
      print("None type\n", .{});
    } else {
      print("INVALID TYPE\n", .{});
    }

    // print("Symbol locality::type: {d}::{d}\n", .{symbloc, symbtype});
    print("Section index: {d}\n\n", .{symbtab[i].seSymbSect});
    symbtab += 1;
  }
}

pub fn main() !void {
  var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
  defer arena.deinit();
  const allocator = arena.allocator();

// - -s: view symbol table
// - -t: view string table
// - -h: view section headers
// - -a: view everything
// - -H: view file header

  var opts = try simargs.parse(allocator, struct {
    viewSymbs:bool = false,
    viewStrTab:bool = false,
    viewSectHdrs:bool = false,
    viewAll:bool = false,
    viewHeader:bool = false,

    pub const __shorts__ = .{
      .viewSymbs = .s,
      .viewStrTab = .t,
      .viewSectHdrs = .h,
      .viewAll = .a,
      .viewHeader = .H
    };

    pub const __messages__ = .{
      .viewSymbs = "Display the symbol table",
      .viewStrTab = "Display the string table",
      .viewSectHdrs = "Display the section header table",
      .viewAll = "Equivalent to -s -t -h -H",
      .viewHeader = "Display the file header"
    };
  }, "[file]", "0.0.1");
  defer opts.deinit();


    // print("Printing raw args:\n", .{});
    // for (opts.raw_args, 0..) |a,i| {
    //   print("{d}: {s}\n", .{i+1,a});
    // }

    if (opts.raw_args.len < 2) {
      try opts.printHelp(stdout.writer());
      return;
    }


    // Make sure a flag is present before checking file prescence
    if (!opts.args.viewAll and !opts.args.viewHeader and !opts.args.viewSectHdrs and !opts.args.viewStrTab and !opts.args.viewSymbs) {
      try opts.printHelp(stdout.writer());
      return;
    }


    // print("Printing positional args:\n", .{});
    // for (opts.positional_args, 0..) |a,i| {
    //   print("{d}: {s}\n", .{i+1,a});
    // }

    if (opts.positional_args.len == 0) {
      try opts.printHelp(stdout.writer());
      return;
    }

    const binary = opts.positional_args[0];

    const file = std.fs.cwd().openFile(binary, .{}) catch {
      print("Error. Could not open file {s}!\n", .{binary});
      return;
    };
    defer file.close();

    const fileSize = try file.getEndPos();

    const buff = try allocator.alloc(u8, fileSize);
    defer allocator.free(buff);

    _ = try file.readAll(buff);

    const hdr:*c.AOEFFheader = @alignCast(@ptrCast(buff.ptr));
    print("hdr ptr {*}\n", .{hdr});

    if (opts.args.viewAll) {
      opts.args.viewHeader = true;
      opts.args.viewSectHdrs = true;
      opts.args.viewStrTab = true;
      opts.args.viewSymbs = true;
    }

    if (opts.args.viewHeader) showFileHeader(allocator, hdr);
    if (opts.args.viewSectHdrs) showSectionHeaders(allocator, buff.ptr, hdr);
    if (opts.args.viewSymbs) showSymbolTable(allocator, buff.ptr, hdr);
    if (opts.args.viewStrTab) showStringTable(allocator, buff.ptr, hdr);



    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();

    // try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // try bw.flush(); // Don't forget to flush!
}
module main

import flag
import os
import term


fn showFileHeader(hdr &AOEFFheader) {
	println("AOEFF Header:")
	println("    ID: ${hdr.hID[0]:x} ${hdr.hID[1]:x} ${hdr.hID[2]:x} ${hdr.hID[3]:x}")
	
	typeStr := match hdr.hType {
		0 { "Executable" }
		1 { "Kernel" }
		2 { "Dynamic Library" }
		3 { "Object" }
		4 { "Static Library" }
		else { "${hdr.hType}" }
	}

	println("    Type: ${typeStr} (${hdr.hType})")
	println("    Entry Point: 0x${hdr.hEntry:x}")
	println("    Section Header Offset: 0x${hdr.hSectOff:x}")
	println("    Section Header Size: ${hdr.hSectSize} entries")
	println("    Symbol Table Offset: 0x${hdr.hSymbOff:x}")
	println("    Symbol Table Size: ${hdr.hSymbSize} entries")
	println("    String Table Offset: 0x${hdr.hStrTabOff:x}")
	println("    String Table Size: ${hdr.hStrTabSize} bytes")
	println("    Relocation Directory Offset: 0x${hdr.hRelDirOff:x}")
	println("    Relocation Directory Size: ${hdr.hRelDirSize} entries")
}
fn showSectionHeaders(buff &u8, hdr &AOEFFheader) {
	println("Section Headers:")

	sectHeaderStart := hdr.hSectOff
	sectHeaderSize := hdr.hSectSize // The size is the number of entries
	
	println("    Num   Name     Size     Offset   RIndex")
	for i in 0 .. sectHeaderSize-1 {
		sectEntryOffset := sectHeaderStart + u32(i * sizeof(AOEFFSectHeader))
		sectEntry := unsafe { &AOEFFSectHeader(&u8(buff) + int(sectEntryOffset)) }
		// Convert name to string
		mut nameBytes := []u8{}
		for b in sectEntry.shSectName {
			if b == 0 {
				break
			}
			nameBytes << u8(b)
		}
		name := nameBytes.bytestr()

		// relocIndex may be 0xffffffff (undefined)
		// Convert that to -1, else leave as is
		mut relocIndex := i32(sectEntry.shSectRel)
		if relocIndex == 0xFFFFFFFF {
			relocIndex = -1
		}

		println("    [${i}] ${name:-8} ${sectEntry.shSectSize:08} 0x${sectEntry.shSectOff:08x} ${relocIndex:4}")
	}

}
fn showSymbolTable(buff &u8, hdr &AOEFFheader) {
	println("Symbol Table:")

	symbTableStart := hdr.hSymbOff
	symbTableSize := hdr.hSymbSize // The size is the number of entries

	println("    Num    Value      Size Type  Loc   Section Name")
	for i in 0 .. symbTableSize-1 {
		symbEntryOffset := symbTableStart + u32(i * sizeof(AOEFFSymbEntry))
		symbEntry := unsafe { &AOEFFSymbEntry(&u8(buff) + int(symbEntryOffset)) }

		// Get the name from the string table
		strTabStart := hdr.hStrTabOff
		nameOffset := strTabStart + symbEntry.seSymbName
		mut nameBytes := []u8{}
		mut idx := u32(0)
		for {
			b := unsafe { *(&u8(buff) + int(nameOffset + idx)) }
			if b == 0 {
				break
			}
			nameBytes << b
			idx++
		}
		name := nameBytes.bytestr()

		symbType := se_get_type(symbEntry.seSymbInfo)
		symbLoc := se_get_loc(symbEntry.seSymbInfo)

		sectStr := match symbEntry.seSymbSect {
			0 { "DATA" }
			1 { "CONST" }
			2 { "BSS" }
			3 { "TEXT" }
			4 { "EVT" }
			5 { "IVT" }
			0xFFFFFFFF { "UNDEF" }
			else { "${symbEntry.seSymbSect}" }
		}

		symbTypeStr := match symbType {
			0 { "NOTYPE" }
			1 { "ABS" }
			2 { "FUNC" }
			3 { "OBJECT" }
			else { "${symbType}" }
		}

		symbLocStr := match symbLoc {
			0 { "LOCAL" }
			1 { "GLOBAL" }
			else { "${symbLoc}" }
		}

		println("    [${i}] 0x${symbEntry.seSymbVal:08x} ${symbEntry.seSymbSize:6} ${symbTypeStr} ${symbLocStr:6} ${sectStr:6}   ${name:-12}")
	}
}
fn showStringTable(buff &u8, hdr &AOEFFheader) {
	println("String Table:")

	strTabStart := hdr.hStrTabOff
	strTabSize := hdr.hStrTabSize // The size is the number of bytes in total there are

	mut index := u32(0)
	mut lineCount := 0
	for index < strTabSize {
		mut strStart := strTabStart + index
		mut strEnd := strStart

		// Find the end of the string (null terminator)
		for unsafe { *(&u8(buff) + int(strEnd)) } != 0 {
			strEnd++
		}

		// Extract the string
		strLen := strEnd - strStart
		mut strBytes := []u8{len: int(strLen)}
		for i in 0 .. strLen {
			strBytes[i] = unsafe { *(&u8(buff) + int(strStart + i)) }
		}
		str := strBytes.bytestr()

		// Print the string with its index
		// Do not print if `str` is empty (aka arrived at the end)
		if str.len > 0 {
			print("    [${index}] ${str} ")
		}

		lineCount++
		if lineCount % 4 == 0 {
			println("")
		}

		// Move to the next string (skip null terminator)
		index += strLen + 1
	}
	println("")
	
}


fn main() {
	mut fp := flag.new_flag_parser(os.args)
	fp.application("readf-v")
	fp.version("0.0.1")
	fp.description("Description of the application")
	fp.arguments_description("file")
	fp.skip_executable()

	mut viewSymbolTable := fp.bool("view-symbol-table", `s`, false, "Display the symbol table")
	mut viewStrTable := fp.bool("view-string-table", `t`, false, "Display the string table")
	mut viewSectHeader := fp.bool("view-section-header", `h`, false, "Display the section header table")
	mut viewHeader := fp.bool("view-header", `H`, false, "Display the file header")
	viewAll := fp.bool("view-all", `a`, false, "Equivalent to -s -t -h -H")

	args := fp.finalize() or {
		eprintln(err)
		println(fp.usage())
		return
	}

	if args.len == 0 {
		println(fp.usage())
		return
	}

	// Make sure a flag is present before checking file prescence
	if !viewSymbolTable && !viewStrTable && !viewSectHeader && !viewHeader && !viewAll {
		println(term.red("No flag is present"))
		println(fp.usage())
		return
	}

	binary := args[0]

	// open the file and place it in memory
	//
	mut file := os.open(binary) or {
		eprintln(err)
		return
	}
	defer {
		file.close()
	}

	buff := vcalloc(os.file_size(binary))
	defer {
		unsafe { free(buff) }
	}

	_ := file.read_into_ptr(buff, int(os.file_size(binary))) or {
		eprintln(err)
		return
	}

	// View the pointer as AOEFFheader
	hdr := unsafe { &AOEFFheader(buff) }

	if viewAll {
		viewSymbolTable = true
		viewStrTable = true
		viewSectHeader = true
		viewHeader = true
	}
	
	if viewHeader { showFileHeader(hdr); }
	if viewSectHeader { showSectionHeaders(buff, hdr); }
	if viewSymbolTable { showSymbolTable(buff, hdr); }
	if viewStrTable { showStringTable(buff, hdr); }
}
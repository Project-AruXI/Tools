module main

import flag
import os
import term

import aoefv { 
	AOEFFheader, AOEFFSectHeader, AOEFFSymbEntry, AOEFFTRelTable, AOEFFDRelTable,
	AOEFFStrTab, AOEFFRelStrTab, AOEFFTRelEntry,
	se_get_type, se_get_loc 
}




fn getString(buff &u8, nameOffset u32) string {
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

	return name
}



fn showFileHeader(hdr &AOEFFheader) {
	println("AOEFF Header:")
	println("    ID: ${hdr.hID[0]:x} ${hdr.hID[1]:x} ${hdr.hID[2]:x} ${hdr.hID[3]:x}")
	
	typeStr := match hdr.hType {
		aoefv.aht_exec { "Executable" }
		aoefv.aht_kern { "Kernel" }
		aoefv.aht_dlib { "Dynamic Library" }
		aoefv.aht_aobj { "Object" }
		aoefv.aht_slib { "Static Library" }
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
	println("    Relocation String Table Offset: 0x${hdr.hRelStrTabOff:x}")
	println("    Relocation String Table Size: ${hdr.hRelStrTabSize} bytes")
	println("    Static Relocation Table Offset: 0x${hdr.hTRelTabOff:x}")
	println("    Static Relocation Table Size: ${hdr.hTRelTabSize} entries")
	println("    Dynamic Relocation Table Offset: 0x${hdr.hDRelTabOff:x}")
	println("    Dynamic Relocation Table Size: ${hdr.hDRelTabSize} entries")
	println("    Dynamic Library Table Offset: 0x${hdr.hDyLibTabOff:x}")
	println("    Dynamic Library Table Size: ${hdr.hDyLibTabSize} entries")
	println("    Dynamic Library String Table Offset: 0x${hdr.hDyLibStrTabOff:x}")
	println("    Dynamic Library String Table Size: ${hdr.hDyLibStrTabSize} bytes")
	println("    Import Table Offset: 0x${hdr.hImportTabOff:x}")
	println("    Import Table Size: ${hdr.hImportTabSize} entries")
}
fn showSectionHeaders(buff &u8, hdr &AOEFFheader) {
	println("Section Headers:")

	sectHeaderStart := hdr.hSectOff
	sectHeaderSize := hdr.hSectSize // The size is the number of entries
	
	println("    Num   Name     Size     Offset")
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

		println("    [${i}] ${name:-8} ${sectEntry.shSectSize:08} 0x${sectEntry.shSectOff:08x}")
	}

}
fn showSymbolTable(buff &u8, hdr &AOEFFheader) {
	println("Symbol Table:")

	symbTableStart := hdr.hSymbOff
	symbTableSize := hdr.hSymbSize // The size is the number of entries

	println("    Num    Value      Size Type  Loc   Section   Name")
	for i in 0 .. symbTableSize-1 {
		symbEntryOffset := symbTableStart + u32(i * sizeof(AOEFFSymbEntry))
		symbEntry := unsafe { &AOEFFSymbEntry(&u8(buff) + int(symbEntryOffset)) }

		// Get the name from the string table
		strTabStart := hdr.hStrTabOff
		nameOffset := strTabStart + symbEntry.seSymbName
		name := getString(buff, nameOffset)

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
			aoefv.se_none_t { "NOTYPE" }
			aoefv.se_absv_t { "ABS" }
			aoefv.se_func_t { "FUNC" }
			aoefv.se_obj_t { "OBJECT" }
			else { "${symbType}" }
		}

		symbLocStr := match symbLoc {
			aoefv.se_local { "LOCAL" }
			aoefv.se_globl { "GLOBAL" }
			else { "${symbLoc}" }
		}

		println("    [${i}] 0x${symbEntry.seSymbVal:08x} ${symbEntry.seSymbSize:6} ${symbTypeStr:-6} ${symbLocStr:-6} ${sectStr:6}   ${name:-12}")
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
fn showDynSymbolTable(buff &u8, hdr &AOEFFheader) {
	// Not implemented yet
}
fn showTRelocationTable(buff &u8, hdr &AOEFFheader) {
	trelTabStart := hdr.hTRelTabOff
	trelTabSize := hdr.hTRelTabSize // The size is the number of tables

	if trelTabSize == 0 {
		return
	}

	println("Static Relocation Table:")

	// The following C code is to be done in V
	// AOEFFTRelTab* tRelTables = (AOEFFTRelTab*) (_obj + objHeader->hTRelTabOff);
	// uint32_t currTRelTabOffset = 0x0;
	// for (uint32_t i = 0; i < objHeader->hTRelTabSize; i++) {
	// 	uint8_t* temp = (uint8_t*) tRelTables;
	// 	AOEFFTRelTab* trelTab = (AOEFFTRelTab*)(temp + currTRelTabOffset);
	// 	currTRelTabOffset += (sizeof(AOEFFTRelTab) - 8) + (sizeof(AOEFFTRelEnt) * (trelTab->relCount));
	// 	// The above is needed because the relocation entries are variable-length arrays at the end of the relocation table struct
	// 	// Also, the entries start where, per the struct definition, relEntries is located at
	// 	// Since `sizeof(AOEFFTRelTab)` includes the 8 bytes for the pointer to relEntries, we need to subtract that out and add the actual size of the entries

	mut currTRelTabOffset := u32(0)
	tRelTables := unsafe { &AOEFFTRelTable(&u8(buff) + int(trelTabStart)) }
	for _ in 0 .. trelTabSize {
		temp := unsafe { &u8(tRelTables) }
		trelTab := unsafe { &AOEFFTRelTable(&u8(temp) + currTRelTabOffset) }
		currTRelTabOffset += (sizeof(AOEFFTRelTable) - 8) + (sizeof(AOEFFTRelEntry) * trelTab.relCount)

		// Get name from relocation string table
		relStrTabStart := hdr.hRelStrTabOff
		relStrOffset := relStrTabStart + trelTab.relTabName
		relStr := getString(buff, relStrOffset)

		relTableEntryCount := trelTab.relCount
		suffix := if relTableEntryCount > 1 { "ies" } else { "y" }

		println("  Relocation of '${relStr}' containing ${relTableEntryCount} entr${suffix}:")
		println("    Offset     Type            Symbol Value + Addend   Symbol Name")
		// The entries start where AOEFFTRelTable.relEntries is at
		// As in it is not the value at that location but rather that location (the address of .relEntries)
		relEntries := &trelTab.relEntries
		for j in 0 .. relTableEntryCount {
			relEntry := unsafe { &AOEFFTRelEntry(&u8(relEntries) + int(j * sizeof(AOEFFTRelEntry))) }

			// Get symbol name from symbol table
			symbEntryOffset := hdr.hSymbOff + u32(relEntry.reSymb * sizeof(AOEFFSymbEntry))
			symbEntry := unsafe { &AOEFFSymbEntry(&u8(buff) + int(symbEntryOffset)) }
			strTabStart := hdr.hStrTabOff
			nameOffset := strTabStart + symbEntry.seSymbName
			symbName := getString(buff, nameOffset)

			// println("symbEntryOffset: 0x${symbEntryOffset-hdr.hSymbOff:x}\n symbEntry: ${symbEntry}\n strTabStart: 0x${strTabStart:x}\n nameOffset: 0x${nameOffset:x}\n symbName: ${symbName}")

			relTypeStr := match relEntry.reType {
				aoefv.re_aru32_abs14 { "RE_ARU32_ABS14" }
				aoefv.re_aru32_mem9 { "RE_ARU32_MEM9" }
				aoefv.re_aru32_ir24 { "RE_ARU32_IR24" }
				aoefv.re_aru32_ir19 { "RE_ARU32_IR19" }
				aoefv.re_aru32_decomp { "RE_ARU32_DECOMP" }
				aoefv.re_aru32_abs8 { "RE_ARU32_ABS8" }
				aoefv.re_aru32_abs16 { "RE_ARU32_ABS16" }
				aoefv.re_aru32_abs32 { "RE_ARU32_ABS32" }
				else { "${relEntry.reType}" }
			}

			println("    0x${relEntry.reOff:08x} ${relTypeStr:-10} 0x${symbEntry.seSymbVal:08x} + 0x${relEntry.reAddend:04x}   ${symbName:-12}")
		}
	}
}
fn showDRelocationTable(buff &u8, hdr &AOEFFheader) {
	// Not implemented yet
}


fn main() {
	mut fp := flag.new_flag_parser(os.args)
	fp.application("readf")
	fp.version("0.0.1")
	fp.description("Read the AOEFF binary file format.")
	fp.arguments_description("file")
	fp.skip_executable()

	mut viewSymbolTable := fp.bool("symbol-table", `y`, false, "Display the symbol table")
	mut viewDynSymbTable := fp.bool("dyn-symbol-table", `d`, false, "Display the dynamic symbol table (Not implemented)")
	mut viewStrTable := fp.bool("string-table", `t`, false, "Display the string table")
	mut viewSectHeader := fp.bool("section-header", `s`, false, "Display the section header table")
	mut viewTRelocTable := fp.bool("relocation-table", `r`, false, "Display the static relocation table")
	mut viewDRelocTable := fp.bool("dyn-relocation-table", `R`, false, "Display the dynamic relocation table")
	mut viewHeader := fp.bool("header", `H`, false, "Display the file header")
	viewAll := fp.bool("all", `a`, false, "Equivalent to -y -d -t -s -r -R -H")

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
	if !viewSymbolTable && !viewDynSymbTable && !viewStrTable && !viewSectHeader && !viewTRelocTable && !viewDRelocTable && !viewHeader && !viewAll {
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
		viewDynSymbTable = true
		viewStrTable = true
		viewSectHeader = true
		viewTRelocTable = true
		viewDRelocTable = true
		viewHeader = true
	}

	if viewHeader { showFileHeader(hdr); }
	if viewSectHeader { showSectionHeaders(buff, hdr); }
	if viewSymbolTable { showSymbolTable(buff, hdr); }
	if viewDynSymbTable {
		println(term.yellow("Dynamic Symbol Table viewing not implemented yet"))
	}
	if viewTRelocTable { showTRelocationTable(buff, hdr) }
	if viewDRelocTable {
		println(term.yellow("Dynamic Relocation Table viewing not implemented yet"))
	}
	if viewStrTable { showStringTable(buff, hdr); }
}
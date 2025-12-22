module disassembler

import term

import aoefv
import decoder


pub struct DisassemblerOptions {
pub:
	useColor bool
pub mut:
	showText bool
	showAll  bool
}


@[inline]
fn debug(msg string) {
	println(term.yellow("${msg}"))
}


fn printInstr(addr u32, instrbits u32, lp u32, useColor bool, symbolTableMap decoder.SymbTableType) {
	byte0 := u8((instrbits >> 24) & 0xFF)
	byte1 := u8((instrbits >> 16) & 0xFF)
	byte2 := u8((instrbits >> 8) & 0xFF)
	byte3 := u8((instrbits >> 0) & 0xFF)

	instr := string(decoder.decode(instrbits, useColor, lp, symbolTableMap))

	mut instrStr := ""
	if useColor {
		instrStr = "${addr:08x}: " +
			term.cyan("${byte0:02x} ${byte1:02x} ${byte2:02x} ${byte3:02x}") + "    " + instr
	} else {
		instrStr = "${addr:08x}: ${byte0:02x} ${byte1:02x} ${byte2:02x} ${byte3:02x}    ${instr}"
	}
	println(instrStr)
}


fn textDisassemble(buff &u8, hdr &aoefv.AOEFFheader, options &DisassemblerOptions, symbolTableMap decoder.SymbTableType) {
	println("\nDisassembly of section .text:")

	// From the symbol table, extract all symbols that has its .seSymbSect in the text section
	// Then, disassemble the code in the .text section, showing the symbols as labels using the string table as well

	// Store all relevant symbols in a map
	// key: address (seSymbVal)
	// value: symbol name (from string table)
	mut textSymbMap := map[u32]string{}
	
	// Go through the symbol table
	symbTableStart := u32(hdr.hSymbOff)
	symbTableSize := u32(hdr.hSymbSize)

	for i in 0 .. symbTableSize-1 {
		symbEntryOffset := symbTableStart + u32(i * sizeof(aoefv.AOEFFSymbEntry))
		symbEntry := unsafe { &aoefv.AOEFFSymbEntry(buff + int(symbEntryOffset)) }

		// Check if the symbol is in the .text section (usually index 3)
		if symbEntry.seSymbSect == 3 {
			// Get the name from the string table
			strTabStart := u32(hdr.hStrTabOff)
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

			textSymbMap[symbEntry.seSymbVal] = name

			// debug("Found symbol in .text: ${name} at address 0x${symbEntry.seSymbVal:08x}")
		}
	}

	// Get the size of the text section
	sectHeaderStart := u32(hdr.hSectOff)
	sectHeaderSize := u32(hdr.hSectSize)

	mut textSectOff := u32(0)
	mut textSectSize := u32(0)

	for i in 0 .. sectHeaderSize-1 {
		sectEntryOffset := sectHeaderStart + u32(i * sizeof(aoefv.AOEFFSectHeader))
		sectEntry := unsafe { &aoefv.AOEFFSectHeader(buff + int(sectEntryOffset)) }

		sectName := unsafe { tos(&u8(&sectEntry.shSectName[0]), 8) }.trim_right('\0')

		if sectName == ".text" {
			textSectOff = sectEntry.shSectOff
			textSectSize = sectEntry.shSectSize
			break
		}
	}

	// debug("Text section offset: 0x${textSectOff:08x}, size: ${textSectSize} bytes")

	// Disassemble the code in .text
	mut textSectStartPtr := unsafe { &u8(buff) + int(textSectOff) }
	textSectEndPtr := unsafe { &u8(textSectStartPtr) + int(textSectSize) }

	mut lp := textSectStartPtr
	for lp < textSectEndPtr {
		// Check if there is a symbol at this address
		addr := u32(unsafe { lp  - textSectStartPtr })
		// debug("Checking symbol at address 0x${addr:08x}")
		if addr in textSymbMap {
			symbName := textSymbMap[addr]
			println("\n${addr:08x} <${symbName}>:")
		}

		// instrbits := unsafe { (u32(*(&u8(lp))) << 24) | (u32(*(&u8(lp + 1))) << 16) | (u32(*(&u8(lp + 2))) << 8) | (u32(*(&u8(lp + 3))) << 0) }
		instrbits := unsafe { (u32(*(&u8(lp + 3))) << 24) | (u32(*(&u8(lp + 2))) << 16) | (u32(*(&u8(lp + 1))) << 8) |  (u32(*(&u8(lp))) << 0) }

		// debug("Disassembling instruction at 0x${addr:08x}, bits=0x${instrbits:08x}")

		printInstr(addr, instrbits, addr, options.useColor, symbolTableMap)

		unsafe { lp += 4 } // Assuming each instruction is 4 bytes
	}
}

fn dataDisassemble(buff &u8, hdr &aoefv.AOEFFheader, options &DisassemblerOptions) {
	println("\nData Sections Disassembly Not Implemented")
}

fn constDisassemble(buff &u8, hdr &aoefv.AOEFFheader, options &DisassemblerOptions) {
	println("\nConstant Sections Disassembly Not Implemented")
}


pub fn disassemble(buff &u8, hdr &aoefv.AOEFFheader, options &DisassemblerOptions, filename string) {
	symbolTableMap := decoder.buildSymbolTableMap(buff, hdr)

	debug("Disassembler options: useColor=${options.useColor}, showText=${options.showText}, showAll=${options.showAll}")

	println("${filename}:\n")

	if options.showText { textDisassemble(buff, hdr, options, symbolTableMap) }

	if options.showAll {
		dataDisassemble(buff, hdr, options)
		constDisassemble(buff, hdr, options)
	}
}
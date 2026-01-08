module decoder

import aoefv
import term


@[if debug ?]
@[inline]
fn debug(msg string) {
	println(term.yellow("${msg}"))
}

/*
	Color mappings
	instruction => underline green
	register => blue
	immediate => bold red
	cond => underline magenta
	other => mix
*/
@[inline]
fn applyInstrColor(instr string) string {
	return term.underline(term.green(instr))
}
@[inline]
fn applyCondColor(cond string) string {
	return term.underline(term.magenta(cond))
}
@[inline]
fn applyRegisterColor(reg string) string {
	return term.blue(reg)
}
@[inline]
fn applyImmColor(imm string) string {
	return term.bold(term.red(imm))
}
@[inline]
fn applyOtherColor(other string) string {
	return term.rgb(100, 100, 150, other)
}

pub type SymbTableType = map[u32]map[u32]string

// To make things easier, convert the symbol table into a map
// key: address (seSymbVal)
// value: map:
// 				key: section number (seSymbSect)
//				value: symbol name (from string table)
// An address can have multiple symbols if they are in different sections
// For example, address 0x0 can have a label for .text and another for .data
pub fn buildSymbolTableMap(buff &u8, hdr &aoefv.AOEFFheader) SymbTableType {
	mut symbolTableMap := map[u32]map[u32]string{}

	symbTableStart := u32(hdr.hSymbOff)
	symbTableSize := u32(hdr.hSymbSize)

	for i in 0 .. symbTableSize-1 {
		symbEntryOffset := symbTableStart + u32(i * sizeof(aoefv.AOEFFSymbEntry))
		symbEntry := unsafe { &aoefv.AOEFFSymbEntry(buff + int(symbEntryOffset)) }

		symbNameOffset := u32(hdr.hStrTabOff) + u32(symbEntry.seSymbName)
		symbName := unsafe { tos2(&u8(buff + int(symbNameOffset))) }

		sectNum := u32(symbEntry.seSymbSect)
		addr := u32(symbEntry.seSymbVal)

		if addr !in symbolTableMap {
			symbolTableMap[addr] = map[u32]string{}
		}
		symbolTableMap[addr][sectNum] = symbName
		// debug("Added symbol '${symbName}' at address 0x${addr:08x} in section ${sectNum}")
	}

	return symbolTableMap	
}

enum InstrType {
	i_type
	r_type
	m_type
	bi_type
	bu_type
	bc_type
	s_type
	unknown
}

struct OpcodeType {
	opcodeName string
	instrType  InstrType
}

fn opcodeMap() map[u8]OpcodeType {
	return {
		u8(0b10000000): OpcodeType{"add", InstrType.i_type} // add immediate
		u8(0b10000001): OpcodeType{"add", InstrType.r_type} // add register
		u8(0b10001000): OpcodeType{"adds", InstrType.i_type} // adds immediate
		u8(0b10001001): OpcodeType{"adds", InstrType.r_type} // adds register
		u8(0b10010000): OpcodeType{"sub", InstrType.i_type} // sub immediate
		u8(0b10010001): OpcodeType{"sub", InstrType.r_type} // sub register
		u8(0b10011000): OpcodeType{"subs", InstrType.i_type} // subs immediate
		u8(0b10011001): OpcodeType{"subs", InstrType.r_type} // subs register
		u8(0b10100000): OpcodeType{"mul", InstrType.r_type} // mul (register)
		u8(0b10100010): OpcodeType{"smul", InstrType.r_type} // smul (signed)
		u8(0b10101000): OpcodeType{"div", InstrType.r_type} // div (register)
		u8(0b10101010): OpcodeType{"sdiv", InstrType.r_type} // sdiv (signed)
		u8(0b01000000): OpcodeType{"or", InstrType.i_type} // or immediate
		u8(0b01000001): OpcodeType{"or", InstrType.r_type} // or register
		u8(0b01000010): OpcodeType{"and", InstrType.i_type} // and immediate
		u8(0b01000011): OpcodeType{"and", InstrType.r_type} // and register
		u8(0b01000100): OpcodeType{"xor", InstrType.i_type} // xor immediate
		u8(0b01000101): OpcodeType{"xor", InstrType.r_type} // xor register
		u8(0b01000110): OpcodeType{"not", InstrType.i_type} // not immediate
		u8(0b01000111): OpcodeType{"not", InstrType.r_type} // not register
		u8(0b01001000): OpcodeType{"lsl", InstrType.i_type} // lsl immediate
		u8(0b01001001): OpcodeType{"lsl", InstrType.r_type} // lsl register
		u8(0b01001010): OpcodeType{"lsr", InstrType.i_type} // lsr immediate
		u8(0b01001011): OpcodeType{"lsr", InstrType.r_type} // lsr register
		u8(0b01001100): OpcodeType{"asr", InstrType.i_type} // asr immediate
		u8(0b01001101): OpcodeType{"asr", InstrType.r_type} // asr register
		// u8(0b10011000): "cmp" // cmp immediate (alias of subs imm)
		// u8(0b10011001): "cmp" // cmp register (alias of subs reg)
		u8(0b10000100): OpcodeType{"mv", InstrType.i_type} // mv immediate
		// u8(0b10000001): "mv" // mv register (alias of or reg)
		// u8(0b10010000): "mvn" // mvn immediate (alias of sub imm)
		// u8(0b10010001): "mvn" // mvn register (alias of sub reg)
		u8(0b00010100): OpcodeType{"ld", InstrType.m_type}
		u8(0b00110100): OpcodeType{"ldb", InstrType.m_type}
		u8(0b01010100): OpcodeType{"ldbs", InstrType.m_type}
		u8(0b01110100): OpcodeType{"ldbz", InstrType.m_type}
		u8(0b10010100): OpcodeType{"ldh", InstrType.m_type}
		u8(0b10110100): OpcodeType{"ldhs", InstrType.m_type}
		u8(0b11010100): OpcodeType{"ldhz", InstrType.m_type}
		u8(0b00011100): OpcodeType{"str", InstrType.m_type}
		u8(0b00111100): OpcodeType{"strb", InstrType.m_type}
		u8(0b01011100): OpcodeType{"strh", InstrType.m_type}
		u8(0b11000000): OpcodeType{"ub", InstrType.bi_type}
		u8(0b11000010): OpcodeType{"ubr", InstrType.bu_type}
		u8(0b11000100): OpcodeType{"b", InstrType.bc_type}
		u8(0b11000110): OpcodeType{"call", InstrType.bi_type}
		u8(0b11001000): OpcodeType{"ret", InstrType.bu_type}
		// u8(0b10000000): "nop" // alias of add imm
		u8(0b10111110): OpcodeType{"SYS", InstrType.s_type} // system instructions
	}
}

fn subOpcodeMap() map[u8]string {
	return {
		u8(0b00010): "syscall"
		u8(0b00110): "hlt"
		u8(0b01010): "si"
		u8(0b01110): "di"
		u8(0b10010): "eret"
		u8(0b10110): "ldir"
		u8(0b11010): "mvcstr"
		u8(0b11110): "ldcstr"
		u8(0b11111): "resr"
	}
}

fn condCodeMap() map[u8]string {
	return {
		u8(0b0000): "eq"
		u8(0b0001): "ne"
		u8(0b0010): "ov"
		u8(0b0011): "nv"
		u8(0b0100): "mi"
		u8(0b0101): "pz"
		u8(0b0110): "cc"
		u8(0b0111): "cs"
		u8(0b1000): "gt"
		u8(0b1001): "ge"
		u8(0b1010): "lt"
		u8(0b1011): "le"
	}
}


fn getInstrOp (instrbits u32) (string, InstrType) {
	opcode := u8((instrbits >> 24) & 0xFF)

	opcodeType := opcodeMap()[opcode] or {
		return "bad", InstrType.unknown
	}

	return opcodeType.opcodeName, opcodeType.instrType
}

fn fixSysInstr(instr string, instrbits u32) string {
	if instr == "SYS" {
		subopcode := u8((instrbits >> 19) & 0x1f)

		subopcodeName := subOpcodeMap()[subopcode] or {
			return "bad"
		}

		return subopcodeName
	} else {
		return instr
	}
}

fn getRegister(regNum u8, useColor bool) string {
	regStr := "x${regNum}"
	return if useColor { applyRegisterColor(regStr) } else { regStr }
}

fn getITypeOperands(instrbits u32, useColor bool) string {
	rd := u8((instrbits) & 0x1F)
	rs := u8((instrbits >> 5) & 0x1F)
	imm := u16((instrbits >> 10) & 0x3FFF)

	rdStr := getRegister(rd, useColor)
	rsStr := getRegister(rs, useColor)

	add := if useColor {
		" " + applyOtherColor("<") + applyImmColor(imm.str()) + applyOtherColor(">")
	} else {
		" <${imm}>"
	}
	mut immStr := if useColor {
		applyImmColor("0x${imm:x}")
	} else {
		"0x${imm:x}"
	}

	if imm > 0x8 {
		immStr += add
	}

	instr, _ := getInstrOp(instrbits)

	if instr == "mv" {
		// mv uses only rd and immediate
		return " ${rdStr},${immStr}"
	}

	if instr == "add" && rd == 30 && rs == 30 && imm == 0 {
		return "nop"
	}

	return " ${rdStr},${rsStr},${immStr}"
}

fn getRTypeOperands(instrbits u32, useColor bool) string {
	rd := u8((instrbits) & 0x1F)
	rr := u8((instrbits >> 5) & 0x1F)
	rs := u8((instrbits >> 10) & 0x1F)

	rdStr := getRegister(rd, useColor)
	rrStr := getRegister(rr, useColor)
	rsStr := getRegister(rs, useColor)

	return " ${rdStr},${rsStr},${rrStr}"
}

fn getMTypeOperands(instrbits u32, useColor bool) string {
	rd := u8((instrbits) & 0x1F)
	rr := u8((instrbits >> 5) & 0x1F)
	rs := u8((instrbits >> 10) & 0x1F)
	mut imm := i16((instrbits >> 15) & 0x1FF)
	if imm & 0x100 != 0 {
		imm = imm | 0xFE00 // sign extend
	}

	rdStr := getRegister(rd, useColor)
	rsStr := getRegister(rs, useColor)
	rrStr := getRegister(rr, useColor)

	immStr := if useColor {
		applyImmColor(imm.str())
	} else {
		imm.str()
	}

	lbracket := if useColor {
		applyOtherColor("[")
	} else {
		"["
	}
	rbracket := if useColor {
		applyOtherColor("]")
	} else {
		"]"
	}

	if rr == 30 && imm == 0 {
		// rd,[rs]
		return " ${rdStr},${lbracket}${rsStr}${rbracket}"
	} else if rr == 30 {
		// rd,[rs,imm]
		return " ${rdStr},${lbracket}${rsStr},${immStr}${rbracket}"
	} else if imm == 0 {
		// rd,[rs],rr
		return " ${rdStr},${lbracket}${rsStr}${rbracket},${rrStr}"
	}

	// rd,[rs,imm],rr
	return " ${rdStr},${lbracket}${rsStr},${immStr}${rbracket},${rrStr}"
}

fn getBiTypeOperands(instrbits u32, useColor bool, lp u32, symbolTableMap SymbTableType) string {
	mut imm := u32((instrbits) & 0xFFFFFF)
	// debug("Extracted imm = 0x${imm:x}")

	// Sign extend if needed
	if imm & 0x80000 != 0 {
		imm = imm | 0xFFF80000
		// debug("Sign extended imm = 0x${imm:x}")
	}


	// Format is `instr num <symb>`
	// Where num is the immediate value shifted right by 2, added by lp
	// And symb is the symbol at that address
	// For example, if imm is 0x10, then 0x10 > 2 = 0x4
	// If lp is 0x4, then the final address is 0x8
	// Search through the symbol table to find the symbol at that address
	// For example, the symbol at 0x8 is `_fn`
	// So it would be `instr 0x8 <_fn>`

	num0 := i32(imm) >> 2
	// debug("Imm shifted right by 2 = 0x${num0:x}")

	addr := u32(num0 + i32(lp))
	// debug("Final address to lookup = 0x${addr:x}")

	// Get the symbol name at that address in the text section
	temp := (symbolTableMap[addr] or { map[u32]string{} }).clone()
	symbName := temp[3] or {
		"unknown"
	}

	// debug("Symbol ${symbName} found at address 0x${addr:x}")

	addrStr := if useColor {
		applyImmColor("0x${addr:x}")
	} else {
		"0x${addr:x}"
	}

	symbNameStr := if useColor {
		applyOtherColor("<") + applyOtherColor(symbName) + applyOtherColor(">")
	} else {
		"<${symbName}>"
	}

	return " ${addrStr} ${symbNameStr}"
}

fn getBuTypeOperands(instrbits u32, instr string, useColor bool) string {
	if instr == "ret" {
		// Ret doesn't have operands
		return ""
	}

	rd := u8((instrbits) & 0x1F)

	rdStr := getRegister(rd, useColor)

	return " ${rdStr}"
}

fn getBcTypeOperands(instrbits u32, useColor bool, lp u32, symbolTableMap SymbTableType) string {
	condCode := u8((instrbits) & 0x0F)
	rawCondStr := condCodeMap()[condCode] or {
		"unknown"
	}
	condStr := if useColor {
		applyCondColor(rawCondStr)
	} else {
		rawCondStr
	}

	mut imm := u32((instrbits >> 5) & 0x7FFFF)
	// debug("Extracted imm = 0x${imm:x}")

	// Sign extend if needed
	if imm & 0x40000 != 0 {
		imm = imm | 0xFFF80000
		// debug("Sign extended imm = 0x${imm:x}")
	}

	// Same process as Bi
	num0 := i32(imm) >> 2
	// debug("Imm shifted right by 2 = 0x${num0:x}")

	addr := u32(num0 + i32(lp))
	// debug("Final address to lookup = 0x${addr:x}")

	temp := (symbolTableMap[addr] or { map[u32]string{} }).clone()
	symbName := temp[3] or {
		"unknown"
	}

	// debug("Symbol ${symbName} found at address 0x${addr:x}")

	addrStr := if useColor {
		applyImmColor("0x${addr:x}")
	} else {
		"0x${addr:x}"
	}

	symbNameStr := if useColor {
		applyOtherColor("<") + applyOtherColor(symbName) + applyOtherColor(">")
	} else {
		"<${symbName}>"
	}

	return "${condStr} ${addrStr} ${symbNameStr}"
}

fn getSTypeOperands(instrbits u32, subinstr string, useColor bool) string {
	// only ldir and ldcst have rd (low 5 bits)
	// only mvcstr has rs (next 5 bits)

	rd := u8((instrbits) & 0x1F)
	rs := u8((instrbits >> 5) & 0x1F)

	if subinstr == "ldir" || subinstr == "ldcstr" {
		rdStr := getRegister(rd, useColor)
		return " ${rdStr}"
	} else if subinstr == "mvcstr" {
		rdStr := getRegister(rd, useColor)
		rsStr := getRegister(rs, useColor)
		return " ${rdStr},${rsStr}"
	}

	return ""
}

pub fn decode(instrbits u32, useColor bool, lp u32, symbolTableMap SymbTableType) string {
	rawInstr, instrType := getInstrOp(instrbits)

	if instrType == .unknown {
		return if useColor { applyInstrColor(rawInstr) } else { rawInstr }
	}

	rInstr := fixSysInstr(rawInstr, instrbits)

	if rInstr == "bad" {
		return if useColor { applyInstrColor(rInstr) } else { rInstr }
	}

	instr := if useColor { applyInstrColor(rInstr) } else { rInstr }

	mut decodedInstr := "${instr}"

	// The rest of the format depends on the instruction
	match instrType {
		.i_type {
			operands := getITypeOperands(instrbits, useColor)

			if operands == "nop" {
				decodedInstr = if useColor { applyInstrColor("nop") } else { "nop" }
				return decodedInstr
			}

			decodedInstr += operands
		}
		.r_type {
			operands := getRTypeOperands(instrbits, useColor)
			decodedInstr += operands
		}
		.m_type {
			operands := getMTypeOperands(instrbits, useColor)
			decodedInstr += operands
		}
		.bi_type {
			operands := getBiTypeOperands(instrbits, useColor, lp, symbolTableMap)
			decodedInstr += operands
		}
		.bu_type {
			operands := getBuTypeOperands(instrbits, rawInstr, useColor)
			decodedInstr += operands
		}
		.bc_type {
			operands := getBcTypeOperands(instrbits, useColor, lp, symbolTableMap)
			decodedInstr += operands
		}
		.s_type {
			operands := getSTypeOperands(instrbits, rInstr, useColor)
			decodedInstr += operands
		}
		else {
			eprintln("Unsupported instruction type.")
			exit(1)
		}
	}

	return decodedInstr
}
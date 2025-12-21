module disassembler

import term

import aoefv


pub struct DisassemblerOptions {
pub:
	useColor bool
pub mut:
	showText bool
}

pub fn disassemble(buff &u8, hdr &aoefv.AOEFFheader, options &DisassemblerOptions) {
	println(term.green("Dissassembly functionality is not yet implemented."))
}
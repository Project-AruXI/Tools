module aoefv

pub struct AOEFFheader {
pub:
	hID [4]u8
	hType u32
	hEntry u32
	hSectOff u32 // offset of the section header table
	hSectSize u32 // number of section header entries
	hSymbOff u32 // offset of the symbol table
	hSymbSize u32 // number of symbol entries
	hStrTabOff u32 // offset of the string table
	hStrTabSize u32 // size (in bytes) of the string table
	hRelStrTabOff u32 // offset of the relocation string table
	hRelStrTabSize u32 // size (in bytes) of the relocation string table
	hTRelTabOff u32 // offset of the static relocation tables
	hTRelTabSize u32 // number of static relocation tables entries (how many reloc tables)
	hDRelTabOff u32 // offset of the dynamic relocation tables
	hDRelTabSize u32 // number of dynamic relocation tables entries (how many reloc tables)
	hDyLibTabOff u32 // offset of the dynamic library table
	hDyLibTabSize u32 // number of dynamic library entries
	hDyLibStrTabOff u32 // offset of the dynamic library string table
	hDyLibStrTabSize u32 // size (in bytes) of the dynamic library string table
	hImportTabOff u32 // offset of the import table
	hImportTabSize u32 // number of import entries
}

// Header ID and file type constants (converted from C macros)
pub const	ah_id0 = u8(0xAE)
pub const	ah_id1 = u8(0x41) // 'A'
pub const	ah_id2 = u8(0x45) // 'E'
pub const	ah_id3 = u8(0x46) // 'F'

pub const	ahid_0 = 0
pub const	ahid_1 = 1
pub const	ahid_2 = 2
pub const	ahid_3 = 3

pub const	aht_exec = 0 // Executable
pub const	aht_kern = 1 // Kernel
pub const	aht_dlib = 2 // Dynamic library
pub const	aht_aobj = 3 // Object file
pub const	aht_slib = 4 // Static library

pub struct AOEFFSectHeader {
pub:
	shSectName [8]i8 // name of the section
	shSectOff u32 // offset of the section
	shSectSize u32 // size of the section
}

pub struct AOEFFSymbEntry {
pub:
	seSymbName u32 // index of the symbol name in the string table
	seSymbSize u32 // size of the data that the symbol is referring to
	seSymbVal u32 // value of the symbol
	seSymbInfo u8 // symbol information ([symbol type, symbol locality])
	seSymbSect u32 // section index the symbol is in, undefined if external
}

pub const se_sect_undef  = u32(0xFFFFFFFF) // For external symbols

@[inline]
pub fn se_get_type(i u8) u8 {
	return i >> 4
}

@[inline]
pub fn se_get_loc(i u8) u8 {
	return i & 0xf
}

@[inline]
pub fn se_set_info(t u8, l u8) u8 {
	return (t << 4) | (l & 0xf)
}

pub const	se_none_t = 0
pub const	se_absv_t = 1
pub const	se_func_t = 2
pub const	se_obj_t = 3
// Extra object types, not necessary
pub const	se_obj_arr_t = 4
pub const	se_obj_struct_t = 5
pub const	se_obj_union_t = 6
pub const	se_obj_ptr_t = 7

pub const	se_local = 0
pub const	se_globl = 1


pub struct AOEFFStrTab {
pub:
	stStrs &i8
}

pub struct AOEFFRelStrTab {
pub:
	rstStrs &i8
}

pub struct AOEFFTRelEntry {
pub:
	reOff u32 // offset from the start of the section
	reSymb u8 // index of the symbol in symbol table
	reType u8 // type of relocation (RE_ARU32_*)
	reAddend i32 // addend to be added to the symbol value
}

pub struct AOEFFTRelTable {
pub:
	relSect u8 // which section this relocation table is for
	relTabName u32 // index of relocation table name in relocation string table
	relCount u32 // number of relocation entries
	relEntries &AOEFFTRelEntry
}

pub struct AOEFFDRelEntry {
pub:
	reOff u32 // offset from the start of the section
	reSymb u32 // index of the symbol in symbol table
	reType u8 // type of relocation (RE_ARU32_*)
	reAddend i32 // addend to be added to the symbol value
}

pub struct AOEFFDRelTable {
pub:
	relSect u8 // which section this relocation table is for
	relTabName u32 // index of relocation table name in relocation string table
	relEntries &AOEFFDRelEntry
	relCount u32 // number of relocation entries
}

// Relocation type constants
pub const	re_aru32_abs14 = 0
pub const	re_aru32_mem9 = 1
pub const	re_aru32_ir24 = 2
pub const	re_aru32_ir19 = 3
pub const re_aru32_decomp = 4
pub const re_aru32_abs8 = 5
pub const re_aru32_abs16 = 6
pub const re_aru32_abs32 = 7

pub struct AOEFFDyLibEntry {
pub:
	dlName u32 // index of the dynamic library name in dynamic string table
	dlVersion u32 // version of the dynamic library
}

pub struct AOEFFDyStrTable {
pub:
	dlstStrs &u8
}

pub struct AOEFFImportEntry {
pub:
	ieName u32 // index of the imported symbol name in the string table
	ieDyLib u32 // index of the dynamic library this symbol is imported from in the dynamic library table
}


pub enum AOEFBinFormatType {
	aoef_ft_aobj
	aoef_ft_exec
	aoef_ft_dlib
	aoef_ft_slib
	aoef_ft_kern
}

pub struct AOEFbin {
pub:
	binarytype       AOEFBinFormatType

	header           AOEFFheader

	sectHdrTable     &AOEFFSectHeader

	symbEntTable     &AOEFFSymbEntry
	symbStringTable  AOEFFStrTab

	relStringTable   AOEFFRelStrTab
	tRelTables       &AOEFFTRelTable
	dRelTables       &AOEFFDRelTable

	dyLibTable       &AOEFFDyLibEntry
	dyLibStringTable AOEFFDyStrTable

	importTable      &AOEFFImportEntry

	data_            &u8
	const_           &u8
	text_            &u32
	text_init_       &u32
	text_deinit_     &u32
	text_fjt_        &u32

	evt_             &u8
	ivt_             &u8
}
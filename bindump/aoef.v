module main

struct AOEFFheader {
	hID      [4]u8
	hType    u32
	hEntry   u32
	hSectOff u32 // offset of the section header table
	hSectSize u32 // number of section header entries
	hSymbOff u32 // offset of the symbol table
	hSymbSize u32 // number of symbol entries
	hStrTabOff u32 // offset of the string table
	hStrTabSize u32 // size (in bytes) of the string table
	hRelDirOff u32 // offset of the relocation tables directory
	hRelDirSize u32 // number of relocation tables entries (how many reloc tables)
}

// Header ID and file type constants (converted from C macros)
const	ah_id0 = u8(0xAE)
const	ah_id1 = u8(0x41) // 'A'
const	ah_id2 = u8(0x45) // 'E'
const	ah_id3 = u8(0x46) // 'F'

const	ahid_0 = 0
const	ahid_1 = 1
const	ahid_2 = 2
const	ahid_3 = 3

const	aht_exec = 0 // Executable
const	aht_kern = 1 // Kernel
const	aht_dlib = 2 // Dynamic library
const	aht_aobj = 3 // Object file
const	aht_slib = 4 // Static library

struct AOEFFSectHeader {
	shSectName [8]i8 // name of the section
	shSectOff u32 // offset of the section
	shSectSize u32 // size of the section
	shSectRel u32 // index of the relocation table tied to this section
}

struct AOEFFSymbEntry {
	seSymbName u32 // index of the symbol name in the string table
	seSymbSize u32 // size of the data that the symbol is referring to
	seSymbVal u32 // value of the symbol
	seSymbInfo u8 // symbol information ([symbol type, symbol locality])
	seSymbSect u32 // section index the symbol is in, undefined if external
}

// Symbol table helper constants and inline functions (converted from C macros)
const se_sect_undef  = u32(0xFFFFFFFF)

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

const	se_none_t = 0
const	se_absv_t = 1
const	se_func_t = 2
const	se_obj_t = 3
const	se_obj_arr_t = 4
const	se_obj_struct_t = 5
const	se_obj_union_t = 6
const	se_obj_ptr_t = 7

const	se_local = 0
const	se_globl = 1

// For external symbols
// Extra object types, not necessary
struct AOEFFStrTab {
	stStrs &i8
}

struct AOEFFRelStrTab {
	rstStrs &i8
}

struct AOEFFRelEnt {
	reOff u32 // offset from the start of the section
	reSymb u32 // index of the symbol in symbol table
	reType u8 // type of relocation (RE_ARU32_*)
}

struct AOEFFRelTab {
	relSect u8 // which section this relocation table is for
	relTabName u32 // index of relocation table name
	relEntries &&AOEFFRelEnt
	relCount   u32 // number of relocation entries
}

struct AOEFFRelTableDir {
	reldTables &AOEFFRelTab
	reldCount  u8 // number of relocation tables
}

// Relocation type constants
const	re_aru32_abs14 = 0
const	re_aru32_mem9 = 1
const	re_aru32_ir24 = 2
const	re_aru32_ir19 = 3

struct AOEFFDyLibEnt {
	dlName u32 // index of the dynamic library name in dynamic string table
	dlVersion u32 // version of the dynamic library
}

struct AOEFFDyLibTab {
	dlEntries &AOEFFDyLibEnt
	dlCount   u32 // number of dynamic library entries
}

struct AOEFFDyStrTab {
	dlstStrs &i8
}

struct AOEFFImportEnt {
	ieName u32 // index of the imported symbol name in the string table
	ieDyLib u32 // index of the dynamic library this symbol is imported from in the dynamic library table
}

struct AOEFFImportTab {
	imEntries &AOEFFImportEnt
	imCount   u32 // number of import entries
}

enum AOEFbin_ft {
	aoef_ft_aobj
	aoef_ft_exec
	aoef_ft_dlib
	aoef_ft_slib
	aoef_ft_kern
}

struct AOEFbin {
	binarytype       AOEFbin_ft
	header           AOEFFheader
	sectHdrTable     &AOEFFSectHeader
	symbEntTable     &AOEFFSymbEntry
	symbStringTable  AOEFFStrTab
	reltabDir        AOEFFRelTableDir
	dyLibTable       AOEFFDyLibTab
	dyLibStringTable AOEFFDyStrTab
	importTable      AOEFFImportTab
	data_            &u8
	const_           &u8
	text_            &u32
	text_init_       &u32
	text_deinit_     &u32
	text_fjt_        &u32
	evt_             &u8
	ivt_             &u8
}
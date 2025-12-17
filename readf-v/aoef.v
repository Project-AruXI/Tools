module main

struct AOEFFheader {
	hID      [4]u8
	hType    u32
	hEntry   u32
	hSectOff u32
	// offset of the section header table
	hSectSize u32
	// number of section header entries
	hSymbOff u32
	// offset of the symbol table
	hSymbSize u32
	// number of symbol entries
	hStrTabOff u32
	// offset of the string table
	hStrTabSize u32
	// size (in bytes) of the string table
	hRelDirOff u32
	// offset of the relocation tables directory
	hRelDirSize u32
	// number of relocation tables entries (how many reloc tables)
}

// Header ID and file type constants (converted from C macros)
const (
	AH_ID0 = u8(0xAE)
	AH_ID1 = u8(0x41) // 'A'
	AH_ID2 = u8(0x45) // 'E'
	AH_ID3 = u8(0x46) // 'F'

	AHID_0 = 0
	AHID_1 = 1
	AHID_2 = 2
	AHID_3 = 3

	AHT_EXEC = 0 // Executable
	AHT_KERN = 1 // Kernel
	AHT_DLIB = 2 // Dynamic library
	AHT_AOBJ = 3 // Object file
	AHT_SLIB = 4 // Static library
)

struct AOEFFSectHeader {
	shSectName [8]i8
	// name of the section
	shSectOff u32
	// offset of the section
	shSectSize u32
	// size of the section
	shSectRel u32
	// index of the relocation table tied to this section
}

struct AOEFFSymbEntry {
	seSymbName u32
	// index of the symbol name in the string table
	seSymbSize u32
	// size of the data that the symbol is referring to
	seSymbVal u32
	// value of the symbol
	seSymbInfo u8
	// symbol information ([symbol type, symbol locality])
	seSymbSect u32
	// section index the symbol is in, undefined if external
}

// Symbol table helper constants and inline functions (converted from C macros)
const SE_SECT_UNDEF  = u32(0xFFFFFFFF)

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

const (
	SE_NONE_T = 0
	SE_ABSV_T = 1
	SE_FUNC_T = 2
	SE_OBJ_T = 3
	SE_OBJ_ARR_T = 4
	SE_OBJ_STRUCT_T = 5
	SE_OBJ_UNION_T = 6
	SE_OBJ_PTR_T = 7

	SE_LOCAL = 0
	SE_GLOBL = 1
)

// For external symbols
// Extra object types, not necessary
struct AOEFFStrTab {
	stStrs &i8
}

struct AOEFFRelStrTab {
	rstStrs &i8
}

struct AOEFFRelEnt {
	reOff u32
	// offset from the start of the section
	reSymb u32
	// index of the symbol in symbol table
	reType u8
	// type of relocation (RE_ARU32_*)
}

struct AOEFFRelTab {
	relSect u8
	// which section this relocation table is for
	relTabName u32
	// index of relocation table name
	relEntries &&AOEFFRelEnt
	relCount   u32
	// number of relocation entries
}

struct AOEFFRelTableDir {
	reldTables &AOEFFRelTab
	reldCount  u8
	// number of relocation tables
}

// Relocation type constants
const (
	RE_ARU32_ABS14 = 0
	RE_ARU32_MEM9 = 1
	RE_ARU32_IR24 = 2
	RE_ARU32_IR19 = 3
)

struct AOEFFDyLibEnt {
	dlName u32
	// index of the dynamic library name in dynamic string table
	dlVersion u32
	// version of the dynamic library
}

struct AOEFFDyLibTab {
	dlEntries &AOEFFDyLibEnt
	dlCount   u32
	// number of dynamic library entries
}

struct AOEFFDyStrTab {
	dlstStrs &i8
}

struct AOEFFImportEnt {
	ieName u32
	// index of the imported symbol name in the string table
	ieDyLib u32
	// index of the dynamic library this symbol is imported from in the dynamic library table
}

struct AOEFFImportTab {
	imEntries &AOEFFImportEnt
	imCount   u32
	// number of import entries
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
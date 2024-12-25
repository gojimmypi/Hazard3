#ifndef _ZILSD_MACROS_H
#define _ZILSD_MACROS_H

// Macros for assembling Zilsd and Zclsd instructions in inline asm on
// toolchains which predate these extensions

// Numerical index defines for common registers
asm (
".set x_ra, 1\n"
".set x_sp, 2\n"
".set x_s0, 8\n"
".set x_s1, 9\n"
".set x_a0, 10\n"
".set x_a1, 11\n"
".set x_a2, 12\n"
".set x_a3, 13\n"
".set x_a4, 14\n"
".set x_a5, 15\n"
".set x_a6, 16\n"
".set x_a7, 17\n"
);

// Zilsd: ld
asm (
".macro zilsd.ld xdst, xbase, offset\n"
".if (\\xdst) < 0 || (\\xdst) > 31 || (\\xdst) & 1\n"
".error \"Invalid xdst for ld\"\n"
".endif\n"
".if (\\xbase) < 0 || (\\xbase) > 31\n"
".error \"Invalid xbase for ld\"\n"
".endif\n"
".if (\\offset) < -2048 || (\\offset) > 4095\n"
".error \"Invalid offset for ld\"\n"
".endif\n"
".insn 4, 0x00003003 + ((\\xdst) << 7) + ((\\xbase) << 15) + (((\\offset) & 0xfff) << 20)\n"
".endm\n"
);

// Zilsd: sd
asm(
".macro zilsd.sd xsrc, xbase, offset\n"
".if (\\xsrc) < 0 || (\\xsrc) > 31 || (\\xsrc) & 1\n"
".error \"Invalid xsrc for sd\"\n"
".endif\n"
".if (\\xbase) < 0 || (\\xbase) > 31\n"
".error \"Invalid xbase for sd\"\n"
".endif\n"
".if (\\offset) < -2048 || (\\offset) > 4095\n"
".error \"Invalid offset for sd\"\n"
".endif\n"
".insn 4, 0x00003023 + ((\\xsrc) << 20) + ((\\xbase) << 15) + (((\\offset) & 0x1f) << 7) + (((\\offset) & 0xfe0) << 20)\n"
".endm"
);

// Zclsd: c.ld
asm (
".macro zclsd.ld xdst, xbase, offset\n"
".if (\\xdst) < 8 || (\\xdst) > 15 || (\\xdst) & 1\n"
".error \"Invalid xdst for c.ld\"\n"
".endif\n"
".if (\\xbase) < 8 || (\\xbase) > 15\n"
".error \"Invalid xbase for c.ld\"\n"
".endif\n"
".if (\\offset) < -128 || (\\offset) > 255 || (\\offset) & 0x7\n"
".error \"Invalid offset for c.ld\"\n"
".endif\n"
".insn 2, 0x6000 + (((\\xdst) & 0x6) << 2) + (((\\xbase) & 0x7) << 7) + (((\\offset) & 0x38) << 7) + (((\\offset) & 0xc0) >> 1)\n"
".endm\n"
);

// Zilsd: sd
asm(
".macro zclsd.sd xsrc, xbase, offset\n"
".if (\\xsrc) < 0 || (\\xsrc) > 31 || (\\xsrc) & 1\n"
".error \"Invalid xsrc for c.sd\"\n"
".endif\n"
".if (\\xbase) < 0 || (\\xbase) > 31\n"
".error \"Invalid xbase for c.sd\"\n"
".endif\n"
".if (\\offset) < -128 || (\\offset) > 255 || (\\offset) & 0x7\n"
".error \"Invalid offset for c.sd\"\n"
".endif\n"
".insn 2, 0xe000 + (((\\xsrc) & 0x6) << 2) + (((\\xbase) & 0x7) << 7) + (((\\offset) & 0x38) << 7) + (((\\offset) & 0xc0) >> 1)\n"
".endm"
);

// Zclsd: c.ldsp
asm (
".macro zclsd.ldsp xdst, offset\n"
".if (\\xdst) < 0 || (\\xdst) > 31 || (\\xdst) & 1\n"
".error \"Invalid xdst for c.ldsp\"\n"
".endif\n"
".if (\\offset) < 0 || (\\offset) > 511 || (\\offset) & 0x7\n"
".error \"Invalid offset for c.ldsp\"\n"
".endif\n"
".insn 2, 0x6002 + (((\\xdst) & 0x1e) << 7) + (((\\offset) & 0x18) << 2) + (((\\offset) & 0x20) << 7) + (((\\offset) & 0x1c0) >> 4)\n"
".endm\n"
);

// Zclsd: c.sdsp
asm (
".macro zclsd.sdsp xsrc, offset\n"
".if (\\xsrc) < 0 || (\\xsrc) > 31 || (\\xsrc) & 1\n"
".error \"Invalid xsrc for c.sdsp\"\n"
".endif\n"
".if (\\offset) < 0 || (\\offset) > 511 || (\\offset) & 0x7\n"
".error \"Invalid offset for c.sdsp\"\n"
".endif\n"
".insn 2, 0xe002 + (((\\xsrc) & 0x1e) << 2) + (((\\offset) & 0x38) << 7) + (((\\offset) & 0x1c0) << 1)\n"
".endm\n"
);

#endif

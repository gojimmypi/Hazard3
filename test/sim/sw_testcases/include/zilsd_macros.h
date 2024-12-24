#ifndef _ZILSD_MACROS_H
#define _ZILSD_MACROS_H

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
".if \\xdst < 0 || \\xdst > 31\n"
".error \"Invalid xdst for ld\"\n"
".endif\n"
".if \\xbase < 0 || \\xbase > 31\n"
".error \"Invalid xbase for ld\"\n"
".endif\n"
".if \\offset < -2048 || \\offset > 4095\n"
".error \"Invalid offset for ld\"\n"
".endif\n"
".insn 4, 0x00003003 + (\\xdst << 7) + (\\xbase << 15) + ((\\offset & 0xfff) << 20)\n"
".endm\n"
);

// Zilsd: sd
asm(
".macro zilsd.sd xsrc, xbase, offset\n"
".if \\xsrc < 0 || \\xsrc > 31\n"
".error \"Invalid xsrc for sd\"\n"
".endif\n"
".if \\xbase < 0 || \\xbase > 31\n"
".error \"Invalid xbase for sd\"\n"
".endif\n"
".if \\offset < -2048 || \\offset > 4095\n"
".error \"Invalid offset for sd\"\n"
".endif\n"
".insn 4, 0x00003023 + (\\xsrc << 20) + (\\xbase << 15) + ((\\offset & 0x1f) << 7) + ((\\offset & 0xfe0) << 20)\n"
".endm"
);

#endif

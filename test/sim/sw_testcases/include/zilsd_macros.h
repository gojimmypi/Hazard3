#ifndef _ZILSD_MACROS_H
#define _ZILSD_MACROS_H

// Zilsd: ld
asm (
".macro zilsd_ld xdst, xbase, offset\n"
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
".macro zilsd_sd xsrc, xbase, offset\n"
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

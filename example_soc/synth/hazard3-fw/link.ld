ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 128K
}

SECTIONS
{
    .vectors 0x00000040 :
    {
        KEEP(*(.vectors))
    } > RAM

    .text :
    {
        *(.text*)
        *(.rodata*)
    } > RAM

    .data :
    {
        *(.data*)
        *(.sdata*)
    } > RAM

    .bss :
    {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        __bss_end = .;
    } > RAM

    . = ALIGN(16);
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}

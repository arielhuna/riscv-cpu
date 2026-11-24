/* Harvard: code in imem from 0x0, data in dmem from 0x0 (separate memories) */
SECTIONS
{
  . = 0x00000000;
  .text : { *(.text*) }
  . = 0x00000000;
  .data : { *(.data*) *(.sdata*) *(.rodata*) *(.bss*) *(.sbss*) }
}

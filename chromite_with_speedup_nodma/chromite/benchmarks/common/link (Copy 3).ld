/*======================================================================*/
/* Proxy kernel linker script                                           */
/*======================================================================*/

OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }

  .tohost ALIGN(0x1000) : { *(.tohost) }

  .text : { *(.text) }

  .rodata : { *(.rodata .rodata.* .gnu.linkonce.r.*) }

  .data : { *(.data) }

  .sdata : {
    __global_pointer$ = . + 0x800;
    *(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2) *(.srodata*)
    *(.sdata .sdata.* .gnu.linkonce.s.*)
  }

  /* __bss_start marks the beginning of all zeroed sections.
     crt.S zeroes from __bss_start to _end before calling _init. */
  __bss_start = .;

  .sbss : {
    *(.sbss .sbss.* .gnu.linkonce.sb.*)
    *(.scommon)
  }

  .bss : { *(.bss) }

  /* stack top — 1MB above load address, well above _end (~5KB of BSS) */
  _sp = 0x80100000;

  .tdata :
  {
    _tls_data = .;
    *(.tdata.begin)
    *(.tdata)
    *(.tdata.end)
  }
  .tbss :
  {
    *(.tbss)
    *(.tbss.end)
  }

  /* End of uninitialised data segment */
  _end = .;
}

.section .text
.global _start
.type _start, %function
_start:
    ldr x0, =stack_top
    mov sp, x0
    bl kernel_main
1:
    wfe
    b 1b

.section .bss
.align 16
stack_bottom:
    .skip 16384
stack_top:

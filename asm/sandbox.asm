%include "utils.asm"
section .data
    msg db 'Hello, World!', 0xA
    len equ $ - msg

section .text
    global _start

_start:
    PAUSE
    EXIT SUCCESS_EXIT

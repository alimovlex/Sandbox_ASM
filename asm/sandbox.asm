%include "utils.asm"
section .data
    msg db 'Welcome to my assembly x64 Sandbox!', 0xA
    prompt db 'Please enter any message below and it will be echoed here...', 0xA
    len equ $ - msg
    len2 equ $ - prompt
    name db "sandbox.log",0
    name2 db "sandbox_renamed.log",0

section .bss
    buffer resb 1
    fd resw 1
    time resb 1

section .text
    global _start

_start:
    WRITE STDOUT,msg, len
    WRITE STDOUT,prompt, len2
    READ STDIN,buffer, 128
    WRITE STDOUT,buffer, 128
    EXIT SUCCESS_EXIT

;CREAT name,O_CREAT
;TIME time
;RENAME name,name2
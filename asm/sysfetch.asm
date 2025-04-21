SYS_WRITE equ 1
SYS_EXIT  equ 60
SYS_UNAME equ 63
SYS_OPEN  equ 2
SYS_READ  equ 0
SYS_CLOSE equ 3

O_RDONLY equ 0 ; Read only flag for open

STDOUT equ 1
STDIN  equ 0
STDERR equ 2

SYS_NMLN equ 65 ; Usually 65 according to bits/utsname.h

section .data
    hostname_label db 'Hostname: ', 0
    hostname_label_len equ $ - hostname_label
    os_label db 'OS: ', 0
    os_label_len equ $ - os_label
    kernel_label db 'Kernel: ', 0
    kernel_label_len equ $ - kernel_label
    uptime_label db 'Uptime: ', 0
    uptime_label_len equ $ - uptime_label
    uptime_file db '/proc/uptime', 0
    days_str db ' days, ', 0
    days_str_len equ $ - days_str
    hours_str db ' hours, ', 0
    hours_str_len equ $ - hours_str
    mins_str db ' mins', 0
    mins_str_len equ $ - mins_str

    newline db 0xa, 0 ; Newline character

section .bss
    utsname_buf resb SYS_NMLN * 6 ; Reserve space for utsname struct (6 fields * 65 bytes)
    uptime_buf resb 64            ; Buffer to read /proc/uptime
    temp_str resb 20              ; Temporary buffer for itoa conversion

section .text
    global _start

; Function to calculate length of a null-terminated string
; Input: rdi = address of string
; Output: rax = length of string
strlen:
    xor rax, rax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

; Function to convert integer to ASCII string
; Input: rdi = integer value
;        rsi = buffer to store string
; Output: rax = number of digits written (pointer to end of string in rsi)
; Clobbers: rcx, rdx, rbx, r8
itoa:
    mov rcx, rsi ; Save buffer start pointer
    mov rbx, 10  ; Divisor
    xor r8, r8   ; digit counter

.convert_loop:
    xor rdx, rdx ; Clear rdx for division
    div rbx      ; rax = rax / 10, rdx = rax % 10
    add dl, '0'  ; Convert remainder to ASCII digit
    push rdx     ; Push digit onto stack
    inc r8       ; Increment digit count
    test rax, rax ; Is quotient zero?
    jnz .convert_loop

.store_loop:
    pop rax      ; Pop digit
    mov [rcx], al ; Store digit in buffer
    inc rcx
    dec r8
    jnz .store_loop

    mov byte [rcx], 0 ; Null terminate the string
    mov rax, rcx ; Return pointer to end of string
    ret

; Basic atoi: Convert string to integer
; Input: rdi = address of string
; Output: rax = integer value
; Clobbers: rcx, rsi
atoi:
    xor rax, rax ; Clear result (rax)
    xor rcx, rcx ; Clear index (rcx)
.loop:
    movzx rsi, byte [rdi + rcx] ; Get character
    cmp sil, '0'
    jl .done     ; Not a digit
    cmp sil, '9'
    jg .done     ; Not a digit

    sub sil, '0' ; Convert char to digit value

    imul rax, rax, 10 ; result = result * 10
    add rax, rsi      ; result = result + digit

    inc rcx
    jmp .loop
.done:
    ret

; Helper to print a null-terminated string
; Input: rsi = address of string
; Clobbers: rax, rdi, rdx (uses strlen and SYS_WRITE)
print_string:
    push rsi
    mov rdi, rsi
    call strlen
    pop rsi
    mov rdx, rax
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall
    ret

; Helper to print a number (using itoa)
; Input: rdi = number to print
; Clobbers: rax, rsi, plus itoa and print_string clobbers
print_number:
    push rdi ; Save number
    mov rsi, temp_str
    call itoa
    mov rsi, temp_str
    call print_string
    pop rdi ; Restore number
    ret

_start:
    ; Call uname(utsname_buf)
    mov rax, SYS_UNAME
    mov rdi, utsname_buf
    syscall
    ; TODO: Add error checking for syscalls (check rax < 0)

    ; Print "Hostname: " label
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, hostname_label
    mov rdx, hostname_label_len
    syscall

    ; Get hostname address (utsname_buf + offset of nodename)
    mov rsi, utsname_buf
    add rsi, SYS_NMLN ; Offset of nodename field

    ; Calculate hostname length
    push rsi ; Save hostname address before calling strlen
    mov rdi, rsi
    call strlen
    pop rsi  ; Restore hostname address
    mov rdx, rax ; Length is now in rdx for sys_write

    ; Print hostname
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    ; rsi already points to hostname
    ; rdx already contains hostname length
    syscall

    ; Print newline
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, newline
    mov rdx, 1 ; Length of newline
    syscall

    ; --- Print OS Name ---
    ; Print "OS: " label
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, os_label
    mov rdx, os_label_len
    syscall

    ; Get OS name address (utsname_buf + offset of sysname)
    mov rsi, utsname_buf ; Offset 0 for sysname

    ; Calculate OS name length
    push rsi
    mov rdi, rsi
    call strlen
    pop rsi
    mov rdx, rax

    ; Print OS name
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    ; Print newline
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, newline
    mov rdx, 1
    syscall

    ; --- Print Kernel Version ---
    ; Print "Kernel: " label
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, kernel_label
    mov rdx, kernel_label_len
    syscall

    ; Get Kernel version address (utsname_buf + offset of release)
    mov rsi, utsname_buf
    add rsi, SYS_NMLN * 2 ; Offset 2 * SYS_NMLN for release

    ; Calculate Kernel version length
    push rsi
    mov rdi, rsi
    call strlen
    pop rsi
    mov rdx, rax

    ; Print Kernel version
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    ; Print newline
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, newline
    mov rdx, 1
    syscall

    ; --- Print Uptime ---
    ; Open /proc/uptime
    mov rax, SYS_OPEN
    mov rdi, uptime_file
    mov rsi, O_RDONLY
    xor rdx, rdx ; mode = 0
    syscall
    ; rax now holds the file descriptor (or < 0 if error)
    mov r12, rax ; Save file descriptor in r12

    ; Read from /proc/uptime
    mov rax, SYS_READ
    mov rdi, r12 ; File descriptor
    mov rsi, uptime_buf
    mov rdx, 63 ; Max bytes to read (buffer size - 1)
    syscall
    ; rax holds number of bytes read (or < 0 if error)
    ; Null terminate the buffer just in case
    mov byte [rsi + rax], 0

    ; Close /proc/uptime
    mov rax, SYS_CLOSE
    mov rdi, r12 ; File descriptor
    syscall

    ; Parse uptime seconds from buffer
    mov rdi, uptime_buf
    call atoi
    ; rax now holds uptime in seconds

    ; Convert seconds to days, hours, minutes
    ; Use r10, r11, r12, r13, r14, r15 - safe across syscalls
    mov r15, rax ; Save total seconds in r15
    mov rbx, 60
    xor rdx, rdx
    div rbx      ; rax = total seconds / 60 (total minutes), rdx = remaining seconds (ignore)
    mov r14, rax ; Save total minutes in r14

    xor rdx, rdx
    div rbx      ; rax = total minutes / 60 (total hours), rdx = remaining minutes
    mov r13, rax ; Save total hours in r13
    mov r11, rdx ; Save remaining minutes in r11

    mov rbx, 24
    xor rdx, rdx
    div rbx      ; rax = total hours / 24 (days), rdx = remaining hours
    mov r12, rax ; Save total days in r12
    mov r10, rdx ; Save remaining hours in r10

    ; Print "Uptime: " label
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, uptime_label
    mov rdx, uptime_label_len
    syscall

    ; Print days
    mov rdi, r12
    call print_number
    mov rsi, days_str
    mov rdx, days_str_len
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    ; Print hours
    mov rdi, r10
    call print_number
    mov rsi, hours_str
    mov rdx, hours_str_len
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    ; Print minutes
    mov rdi, r11
    call print_number
    mov rsi, mins_str
    mov rdx, mins_str_len
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    ; Print final newline for uptime
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, newline
    mov rdx, 1
    syscall

    ; exit(0)
    mov rax, SYS_EXIT
    xor rdi, rdi        ; exit code 0
    syscall
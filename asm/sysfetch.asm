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

    cpu_label db 'CPU: ', 0
    cpu_label_len equ $ - cpu_label
    cpuinfo_file db '/proc/cpuinfo', 0
    model_name_prefix db 'model name', 0
    model_name_prefix_len equ 10
    cpu_read_error_msg db 'Error reading /proc/cpuinfo', 0
    cpu_read_error_msg_len equ $ - cpu_read_error_msg

    mem_label db 'Memory: ', 0
    mem_label_len equ $ - mem_label
    meminfo_file db '/proc/meminfo', 0
    mem_total_prefix db 'MemTotal:', 0
    mem_total_prefix_len equ 9
    mem_free_prefix db 'MemFree:', 0       ; Not currently used, but keep for potential future use
    mem_free_prefix_len equ 8
    mem_avail_prefix db 'MemAvailable:', 0
    mem_avail_prefix_len equ 13
    kb_unit db ' kB', 0
    kb_unit_len equ $ - kb_unit
    slash_separator db ' / ', 0
    slash_separator_len equ $ - slash_separator
    mem_read_error_msg db 'Error reading /proc/meminfo', 0
    mem_read_error_msg_len equ $ - mem_read_error_msg

    percent_str db ' (', 0
    percent_str_len equ $ - percent_str
    percent_sign db '%)', 0
    percent_sign_len equ $ - percent_sign

    newline db 0xa, 0 ; Newline character

section .bss
    utsname_buf resb SYS_NMLN * 6 ; Reserve space for utsname struct (6 fields * 65 bytes)
    uptime_buf resb 64            ; Buffer to read /proc/uptime
    temp_str resb 20              ; Temporary buffer for itoa conversion
    cpuinfo_buf resb 1024         ; Buffer for /proc/cpuinfo content
    meminfo_buf resb 1024         ; Buffer for /proc/meminfo content

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
    mov rax, rdi ; Move input number to rax for processing

    ; Handle zero separately
    test rax, rax
    jnz .convert_loop
    mov byte [rcx], '0'
    inc rcx
    inc r8
    jmp .store_loop_end

.convert_loop:
    xor rdx, rdx ; Clear rdx for division
    ; rax already holds the number to divide
    div rbx      ; rax = quotient, rdx = remainder
    ; rax now holds the quotient for the next iteration
    add dl, '0'  ; Convert remainder to ASCII digit
    push rdx     ; Push digit onto stack
    inc r8       ; Increment digit count
    test rax, rax ; Is quotient zero?
    jnz .convert_loop

.store_loop:
    pop rdx      ; Pop digit (value in dl)
    mov [rcx], dl ; Store the ASCII digit byte
    inc rcx
    dec r8
    jnz .store_loop

.store_loop_end:
    mov byte [rcx], 0 ; Null terminate the string
    ; Returning the start pointer (rsi) is more standard, even if print_number doesn't use it directly
    mov rax, rsi ; Return buffer start pointer 
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

; Helper to parse a line from meminfo buffer
; Checks if line starts with prefix, skips whitespace, calls atoi
; Input: rdi = line pointer, rsi = prefix pointer, rdx = prefix length
; Output: rax = parsed value (kB), or -1 if prefix not matched or parse error
; Clobbers: rcx, r8, r9, r10, r11 + atoi clobbers
parse_mem_value:
    mov r10, rdi ; Save line pointer
    mov r11, rsi ; Save prefix pointer
    mov r8, rdx  ; Save prefix length

    ; Compare prefix
    xor rcx, rcx ; index
.compare_loop:
    cmp rcx, r8 ; Compared full prefix length?
    je .prefix_matched

    mov al, [r10 + rcx]
    cmp al, 0
    je .parse_fail ; End of line before prefix end
    cmp al, [r11 + rcx]
    jne .parse_fail ; Mismatch

    inc rcx
    jmp .compare_loop

.prefix_matched:
    ; Prefix matches, advance line pointer past prefix
    add r10, r8

    ; Skip leading whitespace
.skip_whitespace:
    mov cl, [r10]
    cmp cl, 0
    je .parse_fail ; End of line after prefix
    cmp cl, ' '
    je .do_skip
    cmp cl, 9 ; Tab
    je .do_skip
    ; Not whitespace, should be a digit
    jmp .found_digit
.do_skip:
    inc r10
    jmp .skip_whitespace

.found_digit:
    ; Check if it's actually a digit
    cmp cl, '0'
    jl .parse_fail
    cmp cl, '9'
    jg .parse_fail

    ; It is a digit, call atoi
    mov rdi, r10 ; Set atoi input pointer
    call atoi
    ; rax now holds the parsed value
    jmp .parse_done

.parse_fail:
    mov rax, -1 ; Indicate failure

.parse_done:
    ret

; Finds and prints the CPU model name from cpuinfo buffer
; Input: rdi = pointer to cpuinfo buffer content
; Clobbers: rax, rsi, rdx, rcx, r8, r9, r10, r11
find_and_print_cpu_model:
    mov r10, rdi ; r10 = current position in buffer

.line_loop_cpu:
    mov rsi, r10     ; rsi points to the start of the current line

    ; Check if line starts with "model name"
    mov r8, model_name_prefix
    mov r9, model_name_prefix_len
    xor rcx, rcx ; index for comparison
.prefix_compare_loop:
    cmp rcx, r9
    je .prefix_match ; Compared full prefix length, it's a match

    mov al, [rsi + rcx]
    cmp al, 0 ; End of buffer?
    je .done_parsing_cpu
    cmp al, [r8 + rcx]
    jne .next_line_cpu   ; Characters don't match, move to next line

    inc rcx
    jmp .prefix_compare_loop

.prefix_match:
    ; Found the line starting with "model name"
    ; Now find the ':' character
    mov r11, rsi ; r11 = start of line pointer
.find_colon_loop:
    mov al, [r11]
    cmp al, 0
    je .done_parsing_cpu ; End of buffer unexpectedly
    cmp al, ':'
    je .found_colon
    cmp al, 0xa ; Check for newline before colon (shouldn't happen)
    je .next_line_cpu
    inc r11
    jmp .find_colon_loop

.found_colon:
    inc r11 ; Move past ':'

    ; Skip leading whitespace after colon
.skip_whitespace_loop:
    mov al, [r11]
    cmp al, 0
    je .done_parsing_cpu
    cmp al, ' '
    je .whitespace_found
    cmp al, 9 ; Tab character (ASCII 9)
    je .whitespace_found
    ; Not whitespace, start printing from here (r11)
    jmp .print_model_name

.whitespace_found:
    inc r11
    jmp .skip_whitespace_loop

.print_model_name:
    ; r11 points to the start of the actual model name
    mov rsi, r11
    ; Find the length of the model name (until newline)
    mov r11, rsi ; Use r11 as counter pointer
.find_newline_loop:
    mov al, [r11]
    cmp al, 0
    je .found_end_print ; End of buffer
    cmp al, 0xa
    je .found_end_print ; Found newline
    inc r11
    jmp .find_newline_loop

.found_end_print:
    mov rdx, r11
    sub rdx, rsi ; rdx = length of model name

    ; Print the model name
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    ; rsi already points to start of model name
    ; rdx already contains length
    syscall
    jmp .done_parsing_cpu ; Found and printed, we are done

.next_line_cpu:
    ; Find the next newline character to advance r10
.find_next_newline:
    mov al, [r10]
    cmp al, 0
    je .done_parsing_cpu ; End of buffer
    inc r10
    cmp al, 0xa
    jne .find_next_newline
    jmp .line_loop_cpu ; Found newline, start next line iteration

.done_parsing_cpu:
    ret

; Calculate and print memory usage percentage
; Input: rdi = available memory, rsi = total memory (both in kB)
; Clobbers: rax, rdx, rcx, r8, r9
calculate_and_print_percentage:
    ; Calculate used = total - available
    mov rax, rsi
    sub rax, rdi

    ; Multiply used by 100 for percentage
    mov r8, 100
    mul r8      ; rax = used * 100

    ; Divide by total to get percentage
    div rsi    ; rax = (used * 100) / total

    ; Print the percentage
    push rax   ; Save percentage

    ; Print " ("
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, percent_str
    mov rdx, percent_str_len
    syscall

    ; Print the percentage number
    pop rdi
    call print_number

    ; Print "%)"
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, percent_sign
    mov rdx, percent_sign_len
    syscall

    ret

; Finds and prints Memory info (Available / Total) from meminfo buffer
; Input: rdi = pointer to meminfo buffer content
; Output: Prints memory info or nothing if not found
; Clobbers: rax, rsi, rdx, rcx, r8, r9, r10, r11, r12, r13, r14
; Uses: parse_mem_value, print_number, print_string
find_and_print_memory_info:
    mov r14, rdi  ; r14 = current buffer position
    mov r12, -1   ; r12 = MemTotal value, init to -1 (not found)
    mov r13, -1   ; r13 = MemAvailable value, init to -1 (not found)

.line_loop:
    ; Check if we found both values already
    cmp r12, -1
    jne .check_available_found
.continue_check:

    ; Find end of current line or buffer
    mov r10, r14 ; r10 = line start pointer
.find_line_end:
    mov cl, [r14]
    cmp cl, 0
    je .parse_line ; End of buffer, parse last line
    inc r14
    cmp cl, 0xa
    jne .find_line_end
    ; Found newline

.parse_line:
    ; Save registers before calling helper
    push r12
    push r13
    push r14

    ; Try parsing MemTotal
    mov rdi, r10 ; line pointer
    mov rsi, mem_total_prefix
    mov rdx, mem_total_prefix_len
    call parse_mem_value
    cmp rax, -1
    jne .found_total

    ; Try parsing MemAvailable
    mov rdi, r10 ; line pointer
    mov rsi, mem_avail_prefix
    mov rdx, mem_avail_prefix_len
    call parse_mem_value
    cmp rax, -1
    jne .found_available

    ; Neither matched on this line
    jmp .restore_regs

.found_total:
    mov [rsp+16], rax ; Store found value in saved r12 on stack
    jmp .restore_regs

.found_available:
    mov [rsp+8], rax ; Store found value in saved r13 on stack

.restore_regs:
    pop r14
    pop r13
    pop r12

    ; If end of buffer, exit loop
    mov cl, [r14-1] ; Check char before current r14 pos
    cmp cl, 0
    je .print_results

    ; Check again if we found both
    cmp r12, -1
    jne .check_available_found_after_parse
.continue_loop:
    jmp .line_loop

.check_available_found:
    cmp r13, -1
    jne .print_results ; Found both, print
    jmp .continue_check

.check_available_found_after_parse:
    cmp r13, -1
    jne .print_results ; Found both, print
    jmp .continue_loop

.print_results:
    ; Check if we actually found the values
    cmp r12, -1
    je .mem_parse_done ; Total not found
    cmp r13, -1
    je .mem_parse_done ; Available not found

    ; Print "Memory: " label
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, mem_label
    mov rdx, mem_label_len
    syscall

    ; Print Available
    mov rdi, r13
    call print_number

    ; Print " / "
    mov rsi, slash_separator
    mov rdx, slash_separator_len
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    ; Print Total
    mov rdi, r12
    call print_number

    ; Print " kB"
    mov rsi, kb_unit
    mov rdx, kb_unit_len
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    ; Calculate and print percentage
    mov rdi, r13
    mov rsi, r12
    call calculate_and_print_percentage

    ; Print newline
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, newline
    mov rdx, 1
    syscall

.mem_parse_done:
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

    ; Save calculated values before printing syscalls clobber r11
    push r12 ; Save days   [rsp+16]
    push r10 ; Save hours  [rsp+8]
    push r11 ; Save minutes [rsp]

    ; Print "Uptime: " label
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, uptime_label
    mov rdx, uptime_label_len
    syscall

    ; Print days
    mov rdi, [rsp+16] ; Use saved days value from stack
    call print_number
    mov rsi, days_str
    mov rdx, days_str_len
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    ; Print hours
    mov rdi, [rsp+8] ; Use saved hours value from stack
    call print_number
    mov rsi, hours_str
    mov rdx, hours_str_len
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    ; Print minutes
    mov rdi, [rsp] ; Use saved minutes value from stack
    call print_number
    mov rsi, mins_str
    mov rdx, mins_str_len
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    ; Clean up stack (pop the 3 pushed values)
    add rsp, 24

    ; Print final newline for uptime
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, newline
    mov rdx, 1
    syscall

    ; --- Print CPU Model ---
    ; Open /proc/cpuinfo
    mov rax, SYS_OPEN
    mov rdi, cpuinfo_file
    mov rsi, O_RDONLY
    xor rdx, rdx ; mode = 0
    syscall
    ; rax now holds the file descriptor (or < 0 if error)
    mov r12, rax ; Save file descriptor in r12

    ; Read from /proc/cpuinfo
    mov rax, SYS_READ
    mov rdi, r12 ; File descriptor
    mov rsi, cpuinfo_buf
    mov rdx, 1023 ; Max bytes to read (buffer size - 1)
    syscall
    ; rax holds number of bytes read (or < 0 if error)

    ; Check if read failed (rax <= 0)
    cmp rax, 0
    jle .cpu_read_failed ; Jump if less than or equal to zero

    ; --- Read Success --- 
    ; Null terminate the buffer
    mov byte [rsi + rax], 0

    ; Close /proc/cpuinfo (success path)
    push rax ; Preserve bytes read (not needed here, but good practice)
    mov rax, SYS_CLOSE
    mov rdi, r12 ; File descriptor
    syscall
    pop rax

    ; Print "CPU: " label
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, cpu_label
    mov rdx, cpu_label_len
    syscall

    ; Find and print CPU model
    mov rdi, cpuinfo_buf
    call find_and_print_cpu_model

    ; Print newline after CPU info
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, newline
    mov rdx, 1
    syscall

    jmp .exit ; Done with CPU info, proceed to exit

.cpu_read_failed:
    ; Close /proc/cpuinfo (failure path)
    mov rax, SYS_CLOSE
    mov rdi, r12 ; File descriptor
    syscall

    ; Print error message to STDERR
    mov rax, SYS_WRITE
    mov rdi, STDERR      ; Use STDERR for errors
    mov rsi, cpu_read_error_msg
    mov rdx, cpu_read_error_msg_len
    syscall

    ; Also print a newline to STDERR after the error
    mov rax, SYS_WRITE
    mov rdi, STDERR
    mov rsi, newline
    mov rdx, 1
    syscall

    ; Fall through or jump to exit
    ; jmp .exit ; Explicit jump is fine too

.exit:
    ; Open /proc/meminfo
    mov rax, SYS_OPEN
    mov rdi, meminfo_file
    mov rsi, O_RDONLY
    xor rdx, rdx ; mode = 0
    syscall
    ; rax now holds the file descriptor (or < 0 if error)
    mov r12, rax ; Save file descriptor in r12

    ; Read from /proc/meminfo
    mov rax, SYS_READ
    mov rdi, r12 ; File descriptor
    mov rsi, meminfo_buf
    mov rdx, 1023 ; Max bytes to read (buffer size - 1)
    syscall
    ; rax holds number of bytes read (or < 0 if error)

    ; Check if read failed (rax <= 0)
    cmp rax, 0
    jle .mem_read_failed ; Jump if less than or equal to zero

    ; --- Read Success --- 
    ; Null terminate the buffer
    mov byte [rsi + rax], 0

    ; Close /proc/meminfo (success path)
    push rax ; Preserve bytes read (not needed here, but good practice)
    mov rax, SYS_CLOSE
    mov rdi, r12 ; File descriptor
    syscall
    pop rax

    ; Find and print Memory info
    mov rdi, meminfo_buf
    call find_and_print_memory_info

    jmp .exit2 ; Done with Memory info, proceed to exit

.mem_read_failed:
    ; Close /proc/meminfo (failure path)
    mov rax, SYS_CLOSE
    mov rdi, r12 ; File descriptor
    syscall

    ; Print error message to STDERR
    mov rax, SYS_WRITE
    mov rdi, STDERR      ; Use STDERR for errors
    mov rsi, mem_read_error_msg
    mov rdx, mem_read_error_msg_len
    syscall

    ; Also print a newline to STDERR after the error
    mov rax, SYS_WRITE
    mov rdi, STDERR
    mov rsi, newline
    mov rdx, 1
    syscall

.exit2:
    ; exit(0)
    mov rax, SYS_EXIT
    xor rdi, rdi        ; exit code 0
    syscall
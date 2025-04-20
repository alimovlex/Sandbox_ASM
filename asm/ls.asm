section .data
    dir_path db ".", 0          ; Path to open (current directory)
    newline db 0xa, 0           ; Newline character for printing

section .bss
    BUFFER_SIZE equ 1024
    buffer resb BUFFER_SIZE     ; Buffer for getdents64

section .text
    global _start

%define SYS_READ 0
%define SYS_WRITE 1
%define SYS_OPEN 2
%define SYS_CLOSE 3
%define SYS_EXIT 60
%define SYS_GETDENTS64 217
%define SYS_OPENAT 257

%define O_RDONLY 0
%define O_DIRECTORY 65536   ; Decimal value for O_DIRECTORY
%define AT_FDCWD -100

_start:
    ; Open the current directory
    mov rax, SYS_OPENAT
    mov rdi, AT_FDCWD
    mov rsi, dir_path
    mov rdx, O_RDONLY | O_DIRECTORY ; Flags
    mov r10, 0                      ; Mode (not used when opening)
    syscall

    ; rax now holds the file descriptor (fd) or -1 on error
    cmp rax, 0
    jle .error_exit       ; Exit if fd is invalid (<= 0)
    mov rbx, rax          ; Save fd in rbx

.read_loop:
    ; Read directory entries
    mov rax, SYS_GETDENTS64
    mov rdi, rbx          ; File descriptor
    mov rsi, buffer       ; Buffer address
    mov rdx, BUFFER_SIZE  ; Buffer size
    syscall

    ; rax holds number of bytes read, 0 on end-of-dir, < 0 on error
    cmp rax, 0
    jle .close_dir      ; Exit loop if end of dir or error

    mov r12, rax          ; Save bytes read in r12
    mov r13, buffer       ; Pointer to current position in buffer (r13)

.print_loop:
    ; Calculate the end address of the buffer data
    mov r15, buffer     ; Load buffer start address into r15
    add r15, r12        ; Add bytes read (r12) to get end address

    ; Check if we have processed all bytes read
    cmp r13, r15        ; Compare current pointer (r13) with end address (r15)
    jge .read_loop        ; If current_pos >= buffer_end, read more entries

    ; r13 points to a linux_dirent64 structure
    ; struct linux_dirent64 {
    ;   u64 d_ino;
    ;   u64 d_off;
    ;   u16 d_reclen;
    ;   u8  d_type;
    ;   char d_name[];
    ; };

    movzx rcx, word [r13 + 16] ; Get d_reclen (record length)
    push rcx                   ; Save d_reclen across syscalls

    mov rdx, r13               ; rdx points to the start of the struct
    add rdx, 19                ; Move pointer to d_name (offset 19)

    ; Find the length of d_name (null terminated)
    mov r14, rdx ; Save start of d_name in r14
.find_name_len:
    cmp byte [rdx], 0
    je .name_len_found
    inc rdx
    jmp .find_name_len
.name_len_found:
    sub rdx, r14 ; rdx now holds the length of d_name

    ; Print the filename (d_name)
    mov rax, SYS_WRITE
    mov rdi, 1              ; File descriptor 1 (stdout)
    mov rsi, r14            ; Address of the string (d_name)
    ; rdx already holds length
    syscall

    ; Print a newline
    mov rax, SYS_WRITE
    mov rdi, 1
    mov rsi, newline
    mov rdx, 1              ; Length of newline
    syscall

    pop rcx                    ; Restore d_reclen

    ; Move to the next dirent structure
    add r13, rcx            ; Add d_reclen to the current position pointer
    jmp .print_loop

.close_dir:
    ; Close the directory
    mov rax, SYS_CLOSE
    mov rdi, rbx          ; File descriptor to close
    syscall

.exit:
    mov rax, SYS_EXIT
    mov rdi, 0            ; Exit code 0 (success)
    syscall

.error_exit:
    ; Simple error handling: exit with code 1
    mov rax, SYS_EXIT
    mov rdi, 1            ; Exit code 1 (error)
    syscall
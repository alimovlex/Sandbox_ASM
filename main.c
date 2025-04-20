// main.c
// Compile with: gcc -nostdlib -static -o main main.c

void _start() {
    const char filename[] = "output.txt";
    const char msg[] = "Written from C!\n";
    long fd;

    // open("output.txt", O_WRONLY|O_CREAT|O_TRUNC, 0644)
    asm volatile (
        "mov $2, %%rax\n"          // syscall: open
        "mov %1, %%rdi\n"          // filename
        "mov $0x241, %%rsi\n"      // flags: O_WRONLY|O_CREAT|O_TRUNC
        "mov $420, %%rdx\n"        // mode: rw-r--r-- (0644 octal = 420 decimal)
        "syscall\n"
        "mov %%rax, %0\n"          // store fd
        : "=r"(fd)
        : "r"(filename)
        : "%rax", "%rdi", "%rsi", "%rdx"
    );

    // write(fd, msg, 16)
    asm volatile (
        "mov $1, %%rax\n"          // syscall: write
        "mov %0, %%rdi\n"          // fd
        "mov %1, %%rsi\n"          // buf
        "mov $16, %%rdx\n"         // count
        "syscall\n"
        :
        : "r"(fd), "r"(msg)
        : "%rax", "%rdi", "%rsi", "%rdx"
    );

    // close(fd)
    asm volatile (
        "mov $3, %%rax\n"          // syscall: close
        "mov %0, %%rdi\n"          // fd
        "syscall\n"
        :
        : "r"(fd)
        : "%rax", "%rdi"
    );

    // exit(0)
    asm volatile (
        "mov $60, %%rax\n"
        "xor %%rdi, %%rdi\n"
        "syscall\n"
        :
        :
        : "%rax", "%rdi"
    );
}
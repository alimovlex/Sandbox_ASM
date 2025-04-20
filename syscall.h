#define ASM_PRINT(str, len) \
    asm volatile ( \
        "mov $1, %%rax\n"          /* syscall: write */ \
        "mov $1, %%rdi\n"          /* fd: stdout */ \
        "syscall\n" \
        : \
        : "S"(str), "d"(len) \
        : "%rax", "%rdi" \
    )

#define ASM_EXIT() \
	asm volatile ( \
		"mov $60, %%rax\n" \
		"xor %%rdi, %%rdi\n" \
		"syscall\n" \
		: \
		: \
		: "%rax", "%rdi" \
	)
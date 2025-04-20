// main.c
// Compile with: gcc -nostdlib -static -o main main.c
#import "syscall.h"

void _start() {
	const char msg[] = "Written from C!\n";
    ASM_PRINT(msg, 16); 
	ASM_EXIT();
}

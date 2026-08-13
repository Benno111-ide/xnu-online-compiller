#include "kernel.h"

static const char banner[] = "XNU basic kernel artifact";

#if defined(ARCH_AMD64)
static volatile unsigned short *const vga = (volatile unsigned short *)0xb8000;

static void write_banner(void)
{
    for (unsigned long i = 0; banner[i] != '\0'; ++i) {
        vga[i] = (unsigned short)banner[i] | 0x0f00u;
    }
}
#else
static volatile unsigned long heartbeat;

static void write_banner(void)
{
    for (unsigned long i = 0; banner[i] != '\0'; ++i) {
        heartbeat += (unsigned long)banner[i];
    }
}
#endif

void kernel_main(void)
{
    write_banner();

    for (;;) {
#if defined(ARCH_AMD64)
        __asm__ volatile("hlt");
#elif defined(ARCH_ARM64)
        __asm__ volatile("wfe");
#else
        __asm__ volatile("");
#endif
    }
}

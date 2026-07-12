#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "doom_image_format.h"
#include "doomgeneric.h"
#include "hazard3_monitor_services.h"
#include "hazard3_platform.h"
#include "m_argv.h"
#include "z_zone.h"

#define DOOM_FRAMEBUFFER_BYTES \
    (DOOMGENERIC_RESX * DOOMGENERIC_RESY * sizeof(pixel_t))
#define DOOM_ZONE_EXPECTED_BYTES (6u * 1024u * 1024u)
#define DOOM_ZONE_PROBE_BYTES     4096u

static char argument_program[] = "doom";
static char argument_mb[] = "-mb";
static char argument_mb_value[] = "6";
static char argument_nogui[] = "-nogui";
static char argument_nosound[] = "-nosound";
static char argument_nomusic[] = "-nomusic";
static char* doom_arguments[] = {
    argument_program, argument_mb, argument_mb_value,
    argument_nogui, argument_nosound, argument_nomusic
};

static int services_are_valid(const hazard3_monitor_services_t* services)
{
    return services != (const hazard3_monitor_services_t*)0 &&
        services->abi_version == HAZARD3_MONITOR_ABI_VERSION &&
        services->struct_bytes >= sizeof(hazard3_monitor_services_t) &&
        services->console_puts != (void (*)(const char*))0 &&
        services->console_put_hex32 != (void (*)(uint32_t))0 &&
        services->ticks_ms != (uint32_t (*)(void))0 &&
        services->sleep_ms != (void (*)(uint32_t))0 &&
        services->sbrk != (void* (*)(ptrdiff_t))0 &&
        services->image_base == HAZARD3_DOOM_IMAGE_BASE &&
        services->image_limit == HAZARD3_DOOM_IMAGE_LIMIT &&
        services->heap_base == HAZARD3_DOOM_HEAP_BASE &&
        services->heap_limit == HAZARD3_DOOM_HEAP_LIMIT;
}

static int framebuffer_test(void)
{
    uint8_t* bytes = (uint8_t*)DG_ScreenBuffer;
    if (bytes == (uint8_t*)0) {
        return 0;
    }
    memset(bytes, 0x5au, DOOM_FRAMEBUFFER_BYTES);
    return bytes[0] == 0x5au &&
        bytes[DOOM_FRAMEBUFFER_BYTES / 2u] == 0x5au &&
        bytes[DOOM_FRAMEBUFFER_BYTES - 1u] == 0x5au;
}

static int zone_probe_test(void)
{
    uint8_t* probe = (uint8_t*)Z_Malloc(
        (int)DOOM_ZONE_PROBE_BYTES, PU_STATIC, (void*)0);
    if (probe == (uint8_t*)0) {
        return 0;
    }
    for (uint32_t i = 0u; i < DOOM_ZONE_PROBE_BYTES; ++i) {
        probe[i] = (uint8_t)(i ^ (i >> 8) ^ 0xa5u);
    }
    for (uint32_t i = 0u; i < DOOM_ZONE_PROBE_BYTES; ++i) {
        uint8_t expected = (uint8_t)(i ^ (i >> 8) ^ 0xa5u);
        if (probe[i] != expected) {
            return 0;
        }
    }
    Z_CheckHeap();
    return 1;
}

int32_t doom_image_main(const hazard3_monitor_services_t* services)
{
    uint32_t start_ticks;
    uint32_t zone_bytes;
    int framebuffer_passed;
    int zone_passed;
    int timer_passed;
    if (!services_are_valid(services)) {
        if (services != (const hazard3_monitor_services_t*)0 &&
            services->console_puts != (void (*)(const char*))0) {
            services->console_puts("Doom image: incompatible monitor service table\r\n");
        }
        return 1;
    }
    hazard3_monitor_services_bind(services);
    hazard3_console_puts("\r\nDoom SDRAM image startup\r\n");
    hazard3_console_puts("  monitor ABI: PASS\r\n");
    hazard3_console_puts("  image range: ");
    hazard3_console_put_hex32(services->image_base);
    hazard3_console_puts("-");
    hazard3_console_put_hex32(services->image_limit - 1u);
    hazard3_console_puts("\r\n  heap range: ");
    hazard3_console_put_hex32(services->heap_base);
    hazard3_console_puts("-");
    hazard3_console_put_hex32(services->heap_limit - 1u);
    hazard3_console_puts("\r\n");
    myargc = (int)(sizeof(doom_arguments) / sizeof(doom_arguments[0]));
    myargv = doom_arguments;
    DG_ScreenBuffer = (pixel_t*)malloc(DOOM_FRAMEBUFFER_BYTES);
    framebuffer_passed = framebuffer_test();
    hazard3_console_puts("  320x200 indexed framebuffer allocation: ");
    hazard3_console_puts(framebuffer_passed ? "PASS\r\n" : "FAIL\r\n");
    if (!framebuffer_passed) {
        return 2;
    }
    DG_Init();
    Z_Init();
    zone_bytes = Z_ZoneSize();
    zone_passed = zone_bytes >= DOOM_ZONE_EXPECTED_BYTES && zone_probe_test();
    hazard3_console_puts("  Doom zone allocator: ");
    hazard3_console_puts(zone_passed ? "PASS bytes=" : "FAIL bytes=");
    hazard3_console_put_hex32(zone_bytes);
    hazard3_console_puts("\r\n");
    start_ticks = hazard3_ticks_ms();
    hazard3_sleep_ms(20u);
    timer_passed = (uint32_t)(hazard3_ticks_ms() - start_ticks) >= 20u;
    hazard3_console_puts("  monitor timer service: ");
    hazard3_console_puts(timer_passed ? "PASS\r\n" : "FAIL\r\n");
    hazard3_console_puts("  full Doom engine objects: LINKED\r\n");
    hazard3_console_puts("  WAD storage: NOT IMPLMENTED\r\n");
    hazard3_console_puts("  heap_used=");
    hazard3_console_put_hex32(hazard3_heap_used());
    hazard3_console_puts(" heap_remaining=");
    hazard3_console_put_hex32(hazard3_heap_remaining());
    hazard3_console_puts("\r\n");
    if (!zone_passed || !timer_passed) {
        hazard3_console_puts("Doom SDRAM image startup: FAIL\r\n");
        return 3;
    }
    hazard3_console_puts("Doom SDRAM image startup: PASS\r\n");
    return 0;
}

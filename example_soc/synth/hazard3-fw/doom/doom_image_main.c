#include <stdint.h>

#include "doom_image_format.h"
#include "doomgeneric.h"
#include "doomgeneric_hazard3.h"
#include "hazard3_monitor_services.h"
#include "hazard3_platform.h"

#define DOOM_HEADLESS_EXTRA_TICKS 8u

static char argument_program[] = "doom";
static char argument_iwad[] = "-iwad";
static char argument_mb[] = "-mb";
static char argument_mb_value[] = "6";
static char argument_nogui[] = "-nogui";
static char argument_nosound[] = "-nosound";
static char argument_nomusic[] = "-nomusic";
static char* doom_arguments[] = {
    argument_program,
    argument_iwad,
    (char*)0,
    argument_mb,
    argument_mb_value,
    argument_nogui,
    argument_nosound,
    argument_nomusic
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
        services->heap_limit == HAZARD3_DOOM_HEAP_LIMIT &&
        services->wad_base == HAZARD3_DOOM_WAD_BASE &&
        services->wad_limit == HAZARD3_DOOM_WAD_LIMIT &&
        services->wad_bytes >= 12u &&
        services->wad_bytes <= services->wad_limit - services->wad_base &&
        services->wad_name != (const char*)0;
}

int32_t doom_image_main(const hazard3_monitor_services_t* services)
{
    uint32_t start_ticks;
    uint32_t timer_elapsed;
    uint32_t frame_count;
    if (!services_are_valid(services)) {
        if (services != (const hazard3_monitor_services_t*)0 &&
            services->console_puts != (void (*)(const char*))0) {
            services->console_puts(
                "Doom image: incompatible monitor service table or missing IWAD\r\n");
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
    hazard3_console_puts("\r\n  IWAD: ");
    hazard3_console_puts(services->wad_name);
    hazard3_console_puts(" base=");
    hazard3_console_put_hex32(services->wad_base);
    hazard3_console_puts(" bytes=");
    hazard3_console_put_hex32(services->wad_bytes);
    hazard3_console_puts("\r\n");

    start_ticks = hazard3_ticks_ms();
    hazard3_sleep_ms(20u);
    timer_elapsed = hazard3_ticks_ms() - start_ticks;
    hazard3_console_puts("  monitor timer service: ");
    hazard3_console_puts(timer_elapsed >= 20u ? "PASS\r\n" : "FAIL\r\n");
    if (timer_elapsed < 20u) {
        return 2;
    }

    doom_arguments[2] = (char*)services->wad_name;
    hazard3_console_puts("  entering Doom WAD discovery and initialization\r\n");
    doomgeneric_Create(
        (int)(sizeof(doom_arguments) / sizeof(doom_arguments[0])),
        doom_arguments);

    hazard3_console_puts("  Doom initialization returned; running headless ticks\r\n");
    for (uint32_t i = 0u; i < DOOM_HEADLESS_EXTRA_TICKS; ++i) {
        doomgeneric_Tick();
    }
    frame_count = hazard3_doom_draw_frame_count();
    hazard3_console_puts("  headless frames completed=");
    hazard3_console_put_hex32(frame_count);
    hazard3_console_puts("\r\n  heap_used=");
    hazard3_console_put_hex32(hazard3_heap_used());
    hazard3_console_puts(" heap_remaining=");
    hazard3_console_put_hex32(hazard3_heap_remaining());
    hazard3_console_puts("\r\n");
    if (frame_count == 0u) {
        hazard3_console_puts("Doom WAD/game-loop milestone: FAIL\r\n");
        return 3;
    }
    hazard3_console_puts("Doom WAD/game-loop milestone: PASS\r\n");
    return 0;
}

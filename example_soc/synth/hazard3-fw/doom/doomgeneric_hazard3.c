#include <stdint.h>

#include "doomgeneric.h"
#include "doomgeneric_hazard3.h"
#include "hazard3_platform.h"
#include "i_video.h"

#ifndef CMAP256
#error "The Hazard3 HDMI path requires Doomgeneric CMAP256 output"
#endif

#define HAZARD3_VIDEO_WIDTH  320u
#define HAZARD3_VIDEO_HEIGHT 200u
#define HAZARD3_VIDEO_BYTES  (HAZARD3_VIDEO_WIDTH * HAZARD3_VIDEO_HEIGHT)

static uint32_t draw_frame_count;
static volatile uint32_t* video_framebuffer;
static uint8_t rgb332_palette[256];
static int rgb332_palette_valid;
static int video_available;

static uint8_t color_to_rgb332(const struct color* color)
{
    return (uint8_t)((color->r & 0xe0u)
        | ((color->g >> 3) & 0x1cu)
        | (color->b >> 6));
}

void DG_Init(void)
{
    uint32_t video_base = hazard3_video_base();
    uint32_t video_limit = hazard3_video_limit();

    draw_frame_count = 0u;
    rgb332_palette_valid = 0;
    video_framebuffer = (volatile uint32_t*)(uintptr_t)video_base;
    video_available = video_base != 0u && video_limit >= video_base
        && video_limit - video_base >= HAZARD3_VIDEO_BYTES;

    hazard3_console_puts("Doom platform: Hazard3 HDMI RGB332 interface initialized\r\n");
    if (!video_available) {
        hazard3_console_puts("Doom HDMI framebuffer range: FAIL\r\n");
    }
}

void DG_DrawFrame(void)
{
    const uint8_t* source = (const uint8_t*)DG_ScreenBuffer;

    if (video_available && source != (const uint8_t*)0) {
        if (!rgb332_palette_valid || palette_changed) {
            for (uint32_t i = 0u; i < 256u; ++i) {
                rgb332_palette[i] = color_to_rgb332(&colors[i]);
            }
            rgb332_palette_valid = 1;
            palette_changed = false;
        }

        for (uint32_t i = 0u; i < HAZARD3_VIDEO_BYTES; i += 4u) {
            uint32_t packed = (uint32_t)rgb332_palette[source[i]]
                | ((uint32_t)rgb332_palette[source[i + 1u]] << 8)
                | ((uint32_t)rgb332_palette[source[i + 2u]] << 16)
                | ((uint32_t)rgb332_palette[source[i + 3u]] << 24);
            video_framebuffer[i / 4u] = packed;
        }

        hazard3_memory_barrier();
    }

    ++draw_frame_count;
    if (draw_frame_count == 1u) {
        hazard3_console_puts(
            video_available
                ? "Doom renderer: first HDMI framebuffer completed\r\n"
                : "Doom renderer: first headless frame completed\r\n");
    }
}

void DG_SleepMs(uint32_t milliseconds)
{
    hazard3_sleep_ms(milliseconds);
}

uint32_t DG_GetTicksMs(void)
{
    return hazard3_ticks_ms();
}

int DG_GetKey(int* pressed, unsigned char* key)
{
    (void)pressed;
    (void)key;

    /* Keyboard input is added after the first visible-video milestone. */
    return 0;
}

void DG_SetWindowTitle(const char* title)
{
    hazard3_console_puts("Doom title: ");
    hazard3_console_puts(title != (const char*)0 ? title : "(null)");
    hazard3_console_puts("\r\n");
}

uint32_t hazard3_doom_draw_frame_count(void)
{
    return draw_frame_count;
}

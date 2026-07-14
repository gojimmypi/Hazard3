#include <stdint.h>

#include "doomgeneric.h"
#include "doomgeneric_hazard3.h"
#include "doomkeys.h"
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

// UART input is converted into one-Doom-tic key pulses. A key-down event is
// emitted in the tick that receives a character, and the matching key-up is
// deferred until the next call to DG_GetKey(). This is important because Doom
// processes all events gathered during one tick before it builds the movement
// command; emitting down and up in the same tick would cancel movement.
static int key_release_pending;
static unsigned char key_release_code;
static int stop_input_scan;
static int exit_requested;

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

static int uart_character_to_doom_key(uint8_t character, unsigned char* key)
{
    switch (character) {
    case 'w':
    case 'W':
        *key = KEY_UPARROW;
        return 1;

    case 's':
    case 'S':
        *key = KEY_DOWNARROW;
        return 1;

    case 'a':
    case 'A':
        *key = KEY_LEFTARROW;
        return 1;

    case 'd':
    case 'D':
        *key = KEY_RIGHTARROW;
        return 1;

    case 'z':
    case 'Z':
        *key = KEY_STRAFE_L;
        return 1;

    case 'c':
    case 'C':
        *key = KEY_STRAFE_R;
        return 1;

    case 'f':
    case 'F':
    case ' ':
        *key = KEY_FIRE;
        return 1;

    case 'e':
    case 'E':
        *key = KEY_USE;
        return 1;

    case 'm':
    case 'M':
    case '\t':
        *key = KEY_TAB;
        return 1;

    case 'p':
    case 'P':
        *key = KEY_PAUSE;
        return 1;

    case '\r':
        *key = KEY_ENTER;
        return 1;

    case 0x1bu:
        *key = KEY_ESCAPE;
        return 1;

    case '1':
    case '2':
    case '3':
    case '4':
    case '5':
    case '6':
    case '7':
        *key = character;
        return 1;

    default:
        return 0;
    }
}

int DG_GetKey(int* pressed, unsigned char* key)
{
    uint8_t character;

    if (pressed == (int*)0 || key == (unsigned char*)0) {
        return 0;
    }

    if (stop_input_scan) {
        stop_input_scan = 0;
        return 0;
    }

    if (key_release_pending) {
        *pressed = 0;
        *key = key_release_code;
        key_release_pending = 0;
        return 1;
    }

    // Consume a bounded number of ignored terminal characters per tick. This
    // discards line-feed bytes from CR/LF terminals without risking an
    // unbounded loop if the UART receives unsupported escape sequences.
    for (uint32_t ignored = 0u; ignored < 4u; ++ignored) {
        if (!hazard3_console_getc_nonblocking(&character)) {
            return 0;
        }

        if (character == 0x18u) {
            // Ctrl-X exits the SDRAM Doom image and returns to the monitor.
            exit_requested = 1;
            return 0;
        }

        if (uart_character_to_doom_key(character, key)) {
            *pressed = 1;
            key_release_code = *key;
            key_release_pending = 1;
            stop_input_scan = 1;
            return 1;
        }
    }

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

void hazard3_doom_input_reset(void)
{
    key_release_pending = 0;
    key_release_code = 0u;
    stop_input_scan = 0;
    exit_requested = 0;
}

int hazard3_doom_exit_requested(void)
{
    return exit_requested;
}

#include <stdint.h>

#include "doomgeneric.h"
#include "hazard3_platform.h"

static uint32_t draw_frame_count;

void DG_Init(void)
{
    draw_frame_count = 0u;
    hazard3_console_puts("Doom platform: Hazard3 headless interface initialized\r\n");
}

void DG_DrawFrame(void)
{
    /*
     * The video milestone will replace this no-op with an SDRAM framebuffer
     * handoff. DG_ScreenBuffer is still allocated and rendered by Doom.
     */
    ++draw_frame_count;
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

    /* Keyboard input is added after the headless initialization milestone. */
    return 0;
}

void DG_SetWindowTitle(const char* title)
{
    hazard3_console_puts("Doom title: ");
    hazard3_console_puts(title != (const char*)0 ? title : "(null)");
    hazard3_console_puts("\r\n");
}

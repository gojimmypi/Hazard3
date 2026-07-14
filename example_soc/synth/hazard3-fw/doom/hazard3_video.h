#ifndef HAZARD3_VIDEO_H
#define HAZARD3_VIDEO_H

#include <stdint.h>

#include "hazard3_memory_map.h"

#define HAZARD3_VIDEO_REG_BASE          0x4000c000u
#define HAZARD3_VIDEO_STATUS            \
    (*(volatile uint32_t *)(HAZARD3_VIDEO_REG_BASE + 0x00u))
#define HAZARD3_VIDEO_CONTROL           \
    (*(volatile uint32_t *)(HAZARD3_VIDEO_REG_BASE + 0x04u))
#define HAZARD3_VIDEO_PALETTE_INDEX     \
    (*(volatile uint32_t *)(HAZARD3_VIDEO_REG_BASE + 0x08u))
#define HAZARD3_VIDEO_PALETTE_DATA      \
    (*(volatile uint32_t *)(HAZARD3_VIDEO_REG_BASE + 0x0cu))
#define HAZARD3_VIDEO_FRAME_COUNT       \
    (*(volatile uint32_t *)(HAZARD3_VIDEO_REG_BASE + 0x10u))
#define HAZARD3_VIDEO_DMA_CYCLES        \
    (*(volatile uint32_t *)(HAZARD3_VIDEO_REG_BASE + 0x14u))
#define HAZARD3_VIDEO_PRESENT_COUNT     \
    (*(volatile uint32_t *)(HAZARD3_VIDEO_REG_BASE + 0x18u))

#define HAZARD3_VIDEO_STATUS_FRONT_BUFFER    (1u << 0)
#define HAZARD3_VIDEO_STATUS_PRESENT_PENDING (1u << 1)
#define HAZARD3_VIDEO_STATUS_INDEXED         (1u << 2)
#define HAZARD3_VIDEO_STATUS_VBLANK          (1u << 3)
#define HAZARD3_VIDEO_STATUS_SDRAM_READY      (1u << 4)
#define HAZARD3_VIDEO_STATUS_FRAME_VALID      (1u << 5)
#define HAZARD3_VIDEO_STATUS_INTERNAL_BUFFER   (1u << 6)
#define HAZARD3_VIDEO_STATUS_DMA_BUSY          (1u << 7)
#define HAZARD3_VIDEO_STATUS_SWAP_PENDING      (1u << 8)

#define HAZARD3_VIDEO_CONTROL_INDEXED         (1u << 0)
#define HAZARD3_VIDEO_CONTROL_BUFFER1         (1u << 1)
#define HAZARD3_VIDEO_CONTROL_PRESENT         (1u << 2)

#define HAZARD3_VIDEO_FRAMEBUFFER_WIDTH       320u
#define HAZARD3_VIDEO_FRAMEBUFFER_HEIGHT      200u
#define HAZARD3_VIDEO_FRAMEBUFFER_BYTES       \
    (HAZARD3_VIDEO_FRAMEBUFFER_WIDTH * HAZARD3_VIDEO_FRAMEBUFFER_HEIGHT)

#define HAZARD3_DOOM_SCREENBUFFER_BASE       0x00010000u
#define HAZARD3_DOOM_SCREENBUFFER_BYTES      HAZARD3_VIDEO_FRAMEBUFFER_BYTES

static inline volatile uint32_t* hazard3_video_framebuffer_words(
    uint32_t buffer_index)
{
    uintptr_t address = buffer_index != 0u
        ? HAZARD3_VIDEO_FRAMEBUFFER1_BASE
        : HAZARD3_VIDEO_FRAMEBUFFER0_BASE;
    return (volatile uint32_t*)address;
}

#endif

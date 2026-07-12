#ifndef DOOM_IMAGE_FORMAT_H
#define DOOM_IMAGE_FORMAT_H

#include <stdint.h>

#define HAZARD3_DOOM_IMAGE_MAGIC          0x31443348u /* "H3D1" */
#define HAZARD3_DOOM_IMAGE_FORMAT_VERSION 1u
#define HAZARD3_DOOM_IMAGE_HEADER_BYTES   64u
#define HAZARD3_DOOM_IMAGE_FLAG_CRC32     (1u << 0)

#define HAZARD3_SDRAM_BASE                0x20000000u
#define HAZARD3_DOOM_IMAGE_BASE           0x20100000u
#define HAZARD3_DOOM_IMAGE_LIMIT          0x20400000u
#define HAZARD3_DOOM_HEAP_BASE            0x20400000u
#define HAZARD3_DOOM_HEAP_LIMIT           0x22c00000u
#define HAZARD3_DOOM_WAD_BASE             0x22c00000u
#define HAZARD3_DOOM_WAD_LIMIT            0x23c00000u
#define HAZARD3_VIDEO_BASE                0x23c00000u
#define HAZARD3_VIDEO_LIMIT               0x24000000u

typedef struct hazard3_doom_image_header {
    uint32_t magic;
    uint32_t header_bytes;
    uint32_t format_version;
    uint32_t flags;
    uint32_t load_address;
    uint32_t image_bytes;
    uint32_t entry_address;
    uint32_t bss_address;
    uint32_t bss_bytes;
    uint32_t payload_crc32;
    uint32_t reserved[6];
} hazard3_doom_image_header_t;

typedef char hazard3_doom_image_header_size_must_be_64_bytes[
    sizeof(hazard3_doom_image_header_t) == HAZARD3_DOOM_IMAGE_HEADER_BYTES ? 1 : -1];

#endif

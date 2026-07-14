#!/bin/bash

mkdir -p ./patches

git -C ../third_party/doomgeneric config core.fileMode false

git -C ../third_party/doomgeneric diff HEAD --binary -- \
    doomgeneric/doomgeneric.c \
    doomgeneric/i_video.c \
    > patches/doomgeneric-hazard3-shared-screenbuffer.patch

grep '^diff --git' \
    patches/doomgeneric-hazard3-shared-screenbuffer.patch


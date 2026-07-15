#!/bin/bash

cd /mnt/c/workspace/Hazard3/example_soc/synth

rm -f fpga_ulx4m_ld_blinky.{json,config,bit,svf}
rm -f fpga_ulx4m_ld_blinky_um85.bit

make -B -f ULX4M_LD_BLINKY_85F.mk bit-um 2>&1 |
    tee ulx4m_blinky_um_build.log
#!/bin/bash

echo "Clean..."
rm -f fpga_ulx3s.json fpga_ulx3s.config fpga_ulx3s.bit fpga_ulx3s.svf
rm -f synth.log pnr.log


# fpga_ulx4m_ld.json
echo "Build..."
make -B -f ULX3S.mk bit

echo "Flash..."
./fujprog-v48-win64.exe fpga_ulx3s.bit

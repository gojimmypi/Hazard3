# Doom Install Checklist

This is still a semi-manual, multi-step process.

Using Windows: Ubuntu WSL, DOS/PowerShell prompts.

## ULX3S

[ ] ULX3S Configured with FTDI Drivers

[ ] `soc` tab. Synthesize bitstream and build Doom: `/mnt/c/workspace/Hazard3/example_soc/synth` run  `./build-ulx3s-doom.sh 2>&1 | tee build-ulx3s-doom.log`

[ ] `syth` tab. Load FPGA bitstream: `./fujprog-v48-win64.exe fpga_ulx3s.bit`

[ ] `openOCD` tab. `C:\SysGCC\esp32-master\tools\openocd-esp32\v0.12.0-esp32-20240318\openocd-esp32\bin\openocd -d2 -f ulx3s-openocd.cfg`
[ ] `gdb` tab in `example_soc/synth/hazard3-fw` run `./load_firmware.sh` (same for both ULX3S and ULX4M via OpenOCD)

[ ] `WAD` tab. from `PS C:\workspace\hazard3\example_soc\synth\hazard3-fw` load Doom `py .\doom\upload-doom-image.py  .\doom\build-doom-image\hazard3-doom.h3d  --port COM10`
[ ]  putty: connect to COM10 and test. Disconnect putty to continue next step.
[ ] `WAD` tab. Launch Doom `py .\doom\upload-wad.py  .\doom1.wad  --port COM10  --launch`


## ULX4M

[ ] ULX4M in bootloader mode. (hold middle `BTN2` during power up.

[ ] `soc` tab. Synthesize bitstream: `/mnt/c/workspace/Hazard3/example_soc/synth` run  `make -B -f ULX4M_LD_85F.mk`

[ ] `syth` tab. Load FPGA bitstream: `./openFPGALoader.exe --dfu --vid 0x1d50 --pid 0x614b --altsetting 0 fpga_ulx4m_ld.bit`
[ ] Power cycle, ULX4M *NOT* in bootloader mode.

[ ] `fw` tab. Build Doom: `HAZARD3_MEMORY_PROFILE=64m HAZARD3_SYS_CLK_HZ=50000000 ./build.sh`
[ ] `fw` tab. Build image: `HAZARD3_MEMORY_PROFILE=64m ./doom/build-doom-image.sh`

[ ] `openOCD` tab. `C:\SysGCC\esp32-master\tools\openocd-esp32\v0.12.0-esp32-20240318\openocd-esp32\bin\openocd  -d2  -f C:\workspace\hazard3\example_soc\ulx4m-openocd-tigard-fixed.cfg`
[ ] `gdb` tab in `example_soc/synth/hazard3-fw` run `./load_firmware.sh`

[ ] `WAD` tab. from `PS C:\workspace\hazard3\example_soc\synth\hazard3-fw` load Doom `py .\doom\upload-doom-image.py  .\doom\build-doom-image\hazard3-doom.h3d  --port COM10`
[ ]  putty: connect to COM10 and test. Disconnect putty to continue next step.
[ ] `WAD` tab. Launch Doom `py .\doom\upload-wad.py  .\doom1.wad  --port COM10  --launch`

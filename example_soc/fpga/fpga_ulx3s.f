# ULX3S 85F Performance-R5 source list.
# The 12K device does not have enough EBR capacity for the shared Doom design.
file fpga_ulx3s.v
file pll_25_50.v
file pll_25_50_250.v
file ulx3s_hdmi_test_pattern.v
file ulx3s_hdmi_framebuffer.v
file ../libfpga/common/reset_sync.v
file ../libfpga/common/fpga_reset.v
file ../libfpga/common/ddr_out.v
file ../libfpga/common/popcount.v
file ../libfpga/video/tmds_encode.v

list ../soc/soc.f

# ECP5 DTM is not in main SoC list because the JTAGG primitive doesn't exist
# on most platforms
list ../../hdl/debug/dtm/hazard3_ecp5_jtag_dtm.f


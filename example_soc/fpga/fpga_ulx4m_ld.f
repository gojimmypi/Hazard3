file fpga_ulx4m_ld.v
file pll_25_25_100_90.v
file pll_25_50_250.v
file ulx3s_hdmi_test_pattern.v
file ulx3s_hdmi_framebuffer.v
file ../libfpga/common/reset_sync.v
file ../libfpga/common/fpga_reset.v
file ../libfpga/common/blinky.v
file ../libfpga/common/ddr_out.v
file ../libfpga/common/popcount.v
file ../libfpga/video/tmds_encode.v

list ../soc/soc.f
file ../soc/ahb_uberddr3.v

file ../third_party/UberDDR3/rtl/ddr3_top.v
file ../third_party/UberDDR3/rtl/ddr3_controller.v
file ../third_party/UberDDR3/rtl/ecp5_phy/ddr3_phy_ecp5.v
file ../third_party/UberDDR3/rtl/ecp5_phy/iserdes_soft.v
file ../third_party/UberDDR3/rtl/ecp5_phy/oserdes_soft.v

# ECP5 DTM is not in the main SoC list because the JTAGG primitive does not
# exist on most platforms.
list ../../hdl/debug/dtm/hazard3_ecp5_jtag_dtm.f

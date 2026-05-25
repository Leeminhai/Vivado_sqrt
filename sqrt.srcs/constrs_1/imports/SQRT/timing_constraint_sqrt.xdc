###############################################################################
# AC701 constraints for SQRTApprox_vio_top
# Board  : Xilinx AC701
# Clock  : 200 MHz differential system clock
###############################################################################

set_property PACKAGE_PIN R3 [get_ports {SYSCLK_P}]
set_property PACKAGE_PIN P3 [get_ports {SYSCLK_N}]
set_property IOSTANDARD LVDS_25 [get_ports {SYSCLK_P}]
set_property IOSTANDARD LVDS_25 [get_ports {SYSCLK_N}]

create_clock -period 5.000 -name SYSCLK_200MHz [get_ports {SYSCLK_P}]
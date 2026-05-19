# Copyright 2024 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Re-applied at the start of stage 03 (CTS) after loading the placement
# checkpoint so slink clock exclusions stay in effect without re-running
# floorplan.  The same rules are also in constraints.sdc for new runs.

source src/instances.tcl

set_ideal_network [get_ports {slink_ddr_rcv_clk_i slink_credit_recv_clk_i}]

foreach pin [concat $SLINK_TX_RCLK_Q $SLINK_TX_SLOW_Q $SLINK_CRED_ICG_CLKO] {
	if {[llength $pin] > 0} { set_ideal_network $pin }
}
foreach port [concat $SLINK_TX_RCLK_PORTS $SLINK_CRED_RTRN_PORT] {
	if {[llength $port] > 0} { set_ideal_network $port }
}

# Copyright 2024 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

# Automatic collection of SRAMs and delay-line macros
# Used for automatic macro placement
# set macros [list]

# set srams [get_cells *RM_IHP*]
# foreach inst $srams {
#     lappend macros $inst
# }


# Macro names as produced by the yosys synthesis
# Used for manual macro placement

set CROC            i_croc_soc/i_croc
set USER            i_croc_soc/i_user
set IBEX            $CROC/i_core_wrap.i_ibex
set SRAM            $CROC/gen_sram_bank
set JTAG            $CROC/i_dmi_jtag
set SRAM_512x32     gen_512x32xBx1.i_cut

# Serial link (slink) -- top instance and the (currently single) channel
set SLINK              $USER/i_slink
set SLINK_LINK_LAYER   $SLINK.i_serial_link_data_link
set SLINK_CRED_CDC     $SLINK_LINK_LAYER.i_credit_recv_cdc_fifo_gray
set SLINK_CRED_ICG     $SLINK_LINK_LAYER.i_clk_gate

# Number of physical channels (must match slink_reg_pkg::NumChannels)
set SLINK_NUM_CHANNELS 1

# Per-channel PHY block paths.
# We assemble the genfor index segment via brace-quoting so that the literal
# `\[N\]` survives all the way to OpenROAD's glob matcher (`get_cells` etc.
# treat bare `[N]` as a character class).  Same convention as the SRAM
# bank lookup further below.
set SLINK_PHY_LIST        [list]
set SLINK_PHY_TX_LIST     [list]
set SLINK_PHY_RX_LIST     [list]
set SLINK_PHY_RX_CDC_LIST [list]
for {set i 0} {$i < $SLINK_NUM_CHANNELS} {incr i} {
	set ch_idx {\[}
	append ch_idx $i {\]}
	set phy ${SLINK}.gen_phy_channels${ch_idx}.i_serial_link_physical
	lappend SLINK_PHY_LIST        $phy
	lappend SLINK_PHY_TX_LIST     ${phy}.i_serial_link_physical_tx
	lappend SLINK_PHY_RX_LIST     ${phy}.i_serial_link_physical_rx
	lappend SLINK_PHY_RX_CDC_LIST ${phy}.i_serial_link_physical_rx.i_cdc_in
}

# memory banks
set sram {\[0\].i_sram/}
set bank0_sram0 $SRAM$sram$SRAM_512x32
set sram {\[1\].i_sram/}
set bank1_sram0 $SRAM$sram$SRAM_512x32

# JTAG request and response CDCs
# Goal: Find the async nets and their source and destination cells
# We only want to constrain paths internal to the CDC and going through the async nets.
# It is more complex than usual due to how OpenROAD currently dissolves hierarchy when reading in designs.
set JTAG_CDC_REQ $JTAG/i_dmi_cdc.i_cdc_req
# find all startpoints (flops) that drive through async_data nets and flops that directly drive async nets
set JTAG_ASYNC_REQ_START [get_fanin -to [get_nets $JTAG_CDC_REQ/*async_data*] -flat -startpoints_only -only_cells]
set JTAG_ASYNC_REQ_START [concat $JTAG_ASYNC_REQ_START [get_cells $JTAG_CDC_REQ/*async*_o*_reg]]
# find all endpoints (flops) that are driven through async nets and are in the CDC
set JTAG_ASYNC_REQ_END [list]
set JTAG_ASYNC_REQ_CANDIDATES [get_fanout -from [get_nets $JTAG_CDC_REQ/*async*_data*] -flat -endpoints_only -only_cells]
foreach cell $JTAG_ASYNC_REQ_CANDIDATES {
	if {[string match "${JTAG_CDC_REQ}/*" [get_name $cell]]} {
		lappend JTAG_ASYNC_REQ_END $cell
	}
}
# These paths (clear and isolate) go out of the CDC but we know they cannot cause timing violations
# because they have a seperate 4-phase handshake making sure they stay stable for multiple cycles in each clock domain.
lappend JTAG_ASYNC_REQ_END {*}[get_fanout -from [get_pins $JTAG_CDC_REQ/*i_cdc_reset_ctrlr_half_a*async_data*_reg/Q] -flat -endpoints_only -only_cells]

# The same for the response CDC
set JTAG_CDC_RSP $JTAG/i_dmi_cdc.i_cdc_resp
set JTAG_ASYNC_RSP_START [get_fanin -to [get_nets $JTAG_CDC_RSP/*async_data*] -flat -startpoints_only -only_cells]
set JTAG_ASYNC_RSP_START [concat $JTAG_ASYNC_RSP_START [get_cells $JTAG_CDC_RSP/*async*_o*_reg]]
set JTAG_ASYNC_RSP_END [list]
set JTAG_ASYNC_RSP_CANDIDATES [get_fanout -from [get_nets $JTAG_CDC_RSP/*async*_data*] -flat -endpoints_only -only_cells]
foreach cell $JTAG_ASYNC_RSP_CANDIDATES {
	if {[string match "${JTAG_CDC_RSP}/*" [get_name $cell]]} {
		lappend JTAG_ASYNC_RSP_END $cell
	}
}
lappend JTAG_ASYNC_RSP_END {*}[get_fanout -from [get_pins $JTAG_CDC_RSP/*i_cdc_reset_ctrlr_half_a*async_data*_reg/Q] -flat -endpoints_only -only_cells]


##############################
## Serial Link async / clocks
##############################
# The serial link uses `cdc_fifo_gray` for two crossings per channel:
#   1) RX path : ddr_rcv_clk_i  -> clk_sys   (in i_serial_link_physical_rx/i_cdc_in)
#   2) Credit  : credit_recv_clk_i -> clk_sys (in i_serial_link_data_link/i_credit_recv_cdc_fifo_gray)
# `cdc_fifo_gray_src` / `cdc_fifo_gray_dst` are preserved during synthesis
# (see yosys/scripts/yosys_synthesis.tcl: t:cdc*_src*$* / t:cdc*_dst*$*),
# but the surrounding `cdc_fifo_gray` module itself is flattened.  The
# multi-bit `async_*` nets between src and dst therefore live one level up
# (inside the flattened i_cdc_in / i_credit_recv_cdc_fifo_gray scope).

# --- Per-channel RX (off-chip data) CDC: ddr_rcv_clk_i -> clk_sys ---
set SLINK_RX_ASYNC_NETS  [list]
set SLINK_RX_ASYNC_START [list]
set SLINK_RX_ASYNC_END   [list]

foreach cdc $SLINK_PHY_RX_CDC_LIST {
	# Gray-coded ptrs + data wires that cross between i_src and i_dst.
	set nets [get_nets -quiet ${cdc}.async_*]
	if {[llength $nets] > 0} {
		set SLINK_RX_ASYNC_NETS [concat $SLINK_RX_ASYNC_NETS $nets]
		# All flops driving the async wires are the proper startpoints.
		set st [get_fanin -to $nets -flat -startpoints_only -only_cells]
		if {[llength $st] > 0} { set SLINK_RX_ASYNC_START [concat $SLINK_RX_ASYNC_START $st] }
		# All flops fed by the async wires are the proper endpoints
		# (these are the first stage of the synchronizers inside i_dst,
		# and -- for the data ports -- the spill-register flops).
		set ed [get_fanout -from $nets -flat -endpoints_only -only_cells]
		if {[llength $ed] > 0} { set SLINK_RX_ASYNC_END [concat $SLINK_RX_ASYNC_END $ed] }
	}
}

# --- Credit-return CDC (single, common to all channels): credit_recv_clk_i -> clk_sys ---
set SLINK_CRED_ASYNC_NETS  [get_nets   -quiet ${SLINK_CRED_CDC}.async_*]
set SLINK_CRED_ASYNC_START [list]
set SLINK_CRED_ASYNC_END   [list]
if {[llength $SLINK_CRED_ASYNC_NETS] > 0} {
	set SLINK_CRED_ASYNC_START [get_fanin  -to   $SLINK_CRED_ASYNC_NETS -flat -startpoints_only -only_cells]
	set SLINK_CRED_ASYNC_END   [get_fanout -from $SLINK_CRED_ASYNC_NETS -flat -endpoints_only   -only_cells]
}

# --- TX clock launch flops (one per channel) ---
# ddr_rcv_clk_o is generated by a programmable T-flip-flop clocked by clk_sys.
# data_out_q (which actually drives the off-chip ddr_o lanes) is clocked by
# clk_slow.  We need the Q-pins of these two flops to anchor the generated
# clocks defined in constraints.sdc.
#
# If the ddr_rcv_clk_o flop cannot be found (yosys may not suffix it *_reg
# because it uses blocking assignments), constraints.sdc falls back to
# defining clk_sli_tx_<ch> directly on the output port.
set SLINK_TX_RCLK_REGS  [list]
set SLINK_TX_RCLK_Q     [list]
set SLINK_TX_RCLK_CLK   [list]
set SLINK_TX_SLOW_REGS  [list]
set SLINK_TX_SLOW_Q     [list]
set SLINK_TX_RCLK_PORTS [get_ports -quiet slink_ddr_rcv_clk_o]

foreach tx $SLINK_PHY_TX_LIST {
	set s [get_cells -quiet ${tx}.clk_slow_reg]
	if {[llength $s] == 0} { set s [get_cells -quiet ${tx}*clk_slow*_reg] }
	if {[llength $s] > 0} {
		lappend SLINK_TX_SLOW_REGS $s
		lappend SLINK_TX_SLOW_Q   [get_pins -of_objects $s -filter "name == Q"]
	}
}

# clk_slow fallback: design-wide search under i_slink
if {[llength $SLINK_TX_SLOW_Q] < $SLINK_NUM_CHANNELS} {
	foreach c [get_cells -quiet -hier *i_slink*clk_slow*_reg] {
		set q [get_pins -quiet -of_objects $c -filter "name == Q"]
		if {[llength $q] > 0} {
			lappend SLINK_TX_SLOW_REGS $c
			lappend SLINK_TX_SLOW_Q   $q
		}
	}
}

# ddr_rcv_clk_o flop: cheshire-style wildcard (blocking-assign FF may not be
# named ddr_rcv_clk_o_reg).  Restrict to cells inside the slink hierarchy.
foreach c [get_cells -quiet -hier *ddr_rcv_clk_o*] {
	if {![string match *i_slink* [get_full_name $c]]} { continue }
	if {[string match *pad* [get_full_name $c]]} { continue }
	set q [get_pins -quiet -of_objects $c -filter "name == Q"]
	if {[llength $q] == 0} { continue }
	lappend SLINK_TX_RCLK_REGS $c
	lappend SLINK_TX_RCLK_Q   $q
	set clk_pin [get_pins -quiet -of_objects $c -filter "name == CLK"]
	if {[llength $clk_pin] > 0} { lappend SLINK_TX_RCLK_CLK $clk_pin }
}

# Per-channel TX path fallback (same patterns as before)
foreach tx $SLINK_PHY_TX_LIST {
	if {[llength $SLINK_TX_RCLK_Q] >= $SLINK_NUM_CHANNELS} { break }
	set r [get_cells -quiet ${tx}.ddr_rcv_clk_o_reg]
	if {[llength $r] == 0} { set r [get_cells -quiet ${tx}*ddr_rcv_clk_o*] }
	foreach c $r {
		set q [get_pins -quiet -of_objects $c -filter "name == Q"]
		if {[llength $q] == 0} { continue }
		lappend SLINK_TX_RCLK_REGS $c
		lappend SLINK_TX_RCLK_Q   $q
		set clk_pin [get_pins -quiet -of_objects $c -filter "name == CLK"]
		if {[llength $clk_pin] > 0} { lappend SLINK_TX_RCLK_CLK $clk_pin }
	}
}

# Credit-return clock launch (tc_clk_gating -> sg13g2_slgcp_1 after mapping).
# The wrapper may be flattened so clk_o is not visible; try GCLK on i_clkgate.
set SLINK_CRED_ICG_CELL  [list]
set SLINK_CRED_ICG_CLKO  [list]
set SLINK_CRED_RTRN_PORT [get_ports -quiet slink_credit_rtrn_clk_o]

foreach pat [list $SLINK_CRED_ICG *i_slink*i_clk_gate* *i_slink*i_serial_link_data_link*i_clk_gate*] {
	set c [get_cells -quiet -hier $pat]
	if {[llength $c] > 0} {
		set SLINK_CRED_ICG_CELL $c
		break
	}
}

if {[llength $SLINK_CRED_ICG_CELL] > 0} {
	set SLINK_CRED_ICG_CLKO [get_pins -quiet -of_objects $SLINK_CRED_ICG_CELL \
		-filter {name == clk_o || name == GCLK}]
	if {[llength $SLINK_CRED_ICG_CLKO] == 0} {
		set SLINK_CRED_ICG_CLKO [get_pins -quiet -hier *i_slink*i_clk_gate*/i_clkgate/GCLK]
	}
	if {[llength $SLINK_CRED_ICG_CLKO] == 0} {
		set SLINK_CRED_ICG_CLKO [get_pins -quiet -hier *i_slink*i_clk_gate*/GCLK]
	}
}


# Copyright 2024 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

# Backend constraints

############
## Global ##
############

source src/instances.tcl


#############################
## Driving Cells and Loads ##
#############################

# As a default, drive multiple GPIO pads and be driven by one.
# accomodate for driving up to 2 74HC pads plus a 5pF trace
set_load [expr 2 * 5.0 + 5.0] [all_outputs]
set_driving_cell [all_inputs] -lib_cell sg13g2_IOPadOut16mA -pin pad

# Serial-link DDR data and the source-synchronous clocks must drive a
# realistic external load (PCB trace + receiver pin).  Override the default
# pessimistic load with min/max to give the tool a tighter operating range,
# similar to what cheshire-ihp130-o does for its serial link.
set SLINK_OUT_PADS [get_ports {slink_ddr*_o slink_ddr_rcv_clk_o slink_credit_rtrn_clk_o}]
set_load -min  4.0 $SLINK_OUT_PADS
set_load -max 12.0 $SLINK_OUT_PADS


##################
## Input Clocks ##
##################
puts "Clocks..."

# We target 100 MHz
set TCK_SYS 10.0
create_clock -name clk_sys -period $TCK_SYS [get_ports clk_i]

set TCK_JTG 25.0
create_clock -name clk_jtg -period $TCK_JTG [get_ports jtag_tck_i]

set TCK_RTC 50.0
create_clock -name clk_rtc -period $TCK_RTC [get_ports ref_clk_i]

# Serial link source-synchronous clocks coming back from the far end.
# - slink_ddr_rcv_clk_i carries the off-chip DDR data clock from the remote
#   slink_phys_layer TX (its ddr_rcv_clk_o).  We size it for the worst-case
#   target operating point: clk_sys divided by 4.
# - slink_credit_recv_clk_i carries the remote credit-return clock and can
#   in principle pulse at the full system rate (it is a gated clk_sys on
#   the far side), so we size it for the full TCK_SYS.
set TCK_SLI       [expr 4 * $TCK_SYS] ; # nominal slink rate (clk_sys / 4)
set TCK_SLI_CRED  $TCK_SYS            ; # credit clock can match clk_sys
create_clock -name clk_sli_rx   -period $TCK_SLI      [get_ports slink_ddr_rcv_clk_i]
create_clock -name clk_sli_cred -period $TCK_SLI_CRED [get_ports slink_credit_recv_clk_i]


######################
## Generated Clocks ##
######################
puts "Generated Clocks..."

# The slink TX physical layer produces two related clocks from clk_sys:
#   * clk_slow            -- internal SDR clock that latches data_out_q (the
#                            register that ultimately drives the ddr_o lanes)
#   * ddr_rcv_clk_o       -- chip output clock, 90 deg shifted relative to
#                            clk_slow, sent off-chip together with the data
# Both are programmable divisors of clk_sys.  We size them at the worst-case
# operating point (divide-by-4) which matches the cheshire-ihp130-o setup.
# `-edges {1 5 9}` describes a 50%-duty divide-by-4 starting half a clk_sys
# period after the source edge.  `-edges {3 7 11}` is the same pattern but
# 90 deg later, modelling the source-synchronous quarter-period skew.
for {set ch 0} {$ch < $SLINK_NUM_CHANNELS} {incr ch} {
	set rclk_q [lindex $SLINK_TX_RCLK_Q $ch]
	set slow_q [lindex $SLINK_TX_SLOW_Q $ch]
	if {[llength $slow_q] > 0} {
		create_generated_clock -name clk_sli_tx_drv_$ch \
			-edges {1 5 9} \
			-source [get_ports clk_i] \
			$slow_q
	} else {
		puts "WARNING: clk_sli_tx_drv_$ch not created (clk_slow flop not found)"
	}
	if {[llength $rclk_q] > 0} {
		create_generated_clock -name clk_sli_tx_$ch \
			-edges {3 7 11} \
			-source [get_ports clk_i] \
			$rclk_q
	} elseif {[llength $SLINK_TX_RCLK_PORTS] > 0} {
		# Flop not found (common when ddr_rcv_clk_o uses blocking assigns).
		# Anchor the forwarded DDR clock at the output pad instead.
		set rclk_port [lindex $SLINK_TX_RCLK_PORTS $ch]
		if {$rclk_port eq ""} { set rclk_port [lindex $SLINK_TX_RCLK_PORTS 0] }
		create_generated_clock -name clk_sli_tx_$ch \
			-edges {3 7 11} \
			-source [get_ports clk_i] \
			$rclk_port
	} else {
		puts "WARNING: clk_sli_tx_$ch not created (no ddr_rcv_clk_o flop or port)"
	}
}

# Credit-return clock: a gated clk_sys forwarded off-chip through the slink
# `tc_clk_gating` cell.  Define it as divide-by-1 generated clock so that
# IO timing on the output port is well defined.
if {[llength $SLINK_CRED_ICG_CLKO] > 0} {
	create_generated_clock -name clk_sli_cred_rtrn \
		-divide_by 1 \
		-source [get_ports clk_i] \
		$SLINK_CRED_ICG_CLKO
} elseif {[llength $SLINK_CRED_RTRN_PORT] > 0} {
	create_generated_clock -name clk_sli_cred_rtrn \
		-divide_by 1 \
		-source [get_ports clk_i] \
		$SLINK_CRED_RTRN_PORT
} else {
	puts "WARNING: clk_sli_cred_rtrn not created (no ICG output or port found)"
}


#####################
## CTS exclusions  ##
#####################
puts "CTS exclusions..."

# Off-chip / source-synchronous clocks at the pads: used only for I/O delay
# checks.  They must NOT get an on-chip CTS tree (clk_sli_rx alone had 4000+
# register sinks and crashed CTS).
set_ideal_network [get_ports {slink_ddr_rcv_clk_i slink_credit_recv_clk_i}]

# Slink generated clocks are logical views of logic already timed by clk_sys
# (divider flops, T-flop, ICG).  Mark their roots ideal so CTS builds only the
# main clk_sys / clk_jtg / clk_rtc trees.
foreach pin [concat $SLINK_TX_RCLK_Q $SLINK_TX_SLOW_Q $SLINK_CRED_ICG_CLKO] {
	if {[llength $pin] > 0} { set_ideal_network $pin }
}
foreach port [concat $SLINK_TX_RCLK_PORTS $SLINK_CRED_RTRN_PORT] {
	if {[llength $port] > 0} { set_ideal_network $port }
}


##################################
## Clock Groups & Uncertainties ##
##################################

# Define which clocks are asynchronous to each other.
# - clk_sys (and everything derived from it inside the slink TX/credit-return
#   tree) is plesiochronous to clk_jtg/clk_rtc.
# - The slink RX clocks come from a separate remote die; they are completely
#   asynchronous to clk_sys and to each other.
# If you have added a clock it is a good idea to temporarily add -allow_paths.
# This means the paths between clocks (CDC) are timed and will show up as
# violations, making them very easy to find and write constraints for.
set sys_group_clocks {clk_sys}
foreach clk {clk_sli_cred_rtrn} {
	if {[llength [get_clocks -quiet $clk]] > 0} {
		lappend sys_group_clocks $clk
	}
}
for {set ch 0} {$ch < $SLINK_NUM_CHANNELS} {incr ch} {
	foreach clk [list clk_sli_tx_drv_$ch clk_sli_tx_$ch] {
		if {[llength [get_clocks -quiet $clk]] > 0} {
			lappend sys_group_clocks $clk
		}
	}
}

set_clock_groups -asynchronous -name clk_groups_async \
     -group {clk_rtc} \
     -group {clk_jtg} \
     -group $sys_group_clocks \
     -group {clk_sli_rx} \
     -group {clk_sli_cred}

# We set reasonable uncertainties in their transistion timing
# and transition (rise/fall) times for all clocks (ns)
set CLK_UNCERTAINTY 0.1
set_clock_uncertainty $CLK_UNCERTAINTY [all_clocks]
set_clock_transition  0.2              [all_clocks]


####################
## Cdcs and Syncs ##
####################
puts "CDC/Sync..."

# Clock Domain Crossings: paths going from an FF with one clock to an FF with another.
# The setup/hold checks on these paths are deactivated by set_clock_groups -asynchronous.
# An additional requirement is that the max delay is below min(T_src, T_dst)
# so that any pointer/data change propagates within one cycle of either clock.
# An (optional) lower delay is better for metastability recovery -> 3ns as a reasonable goal.
# A slightly negative min delay compensates for clock uncertainty and discourages the
# tool from inserting hold-fixing buffers on these wires.
# See: https://gist.github.com/brabect1/7695ead3d79be47576890bbcd61fe426

## Constrain `cdc_2phase` for DMI request
set_max_delay  3.0                   -from $JTAG_ASYNC_REQ_START -to $JTAG_ASYNC_REQ_END -ignore_clock_latency

# Constrain `cdc_2phase` for DMI response
set_max_delay  3.0                   -from $JTAG_ASYNC_RSP_START -to $JTAG_ASYNC_RSP_END -ignore_clock_latency

# Constrain the per-channel `cdc_fifo_gray` of the slink RX (ddr_rcv_clk_i -> clk_sys).
# We use the `async_*` net names produced by the (flattened) cdc_fifo_gray wrapper
# as the `-through` anchor; this keeps the constraint robust against renames.
if {[llength $SLINK_RX_ASYNC_NETS] > 0} {
	set_max_delay 3.0                 -through $SLINK_RX_ASYNC_NETS -ignore_clock_latency
	set_min_delay [expr -$CLK_UNCERTAINTY] -through $SLINK_RX_ASYNC_NETS -ignore_clock_latency
} elseif {[llength $SLINK_RX_ASYNC_START] > 0 && [llength $SLINK_RX_ASYNC_END] > 0} {
	# Fallback in case the async_* nets did not survive synthesis renaming.
	set_max_delay 3.0                 -from $SLINK_RX_ASYNC_START -to $SLINK_RX_ASYNC_END -ignore_clock_latency
	set_min_delay [expr -$CLK_UNCERTAINTY] -from $SLINK_RX_ASYNC_START -to $SLINK_RX_ASYNC_END -ignore_clock_latency
}

# Constrain the single `cdc_fifo_gray` of the credit-return path
# (credit_recv_clk_i -> clk_sys).  Same approach as above.
if {[llength $SLINK_CRED_ASYNC_NETS] > 0} {
	set_max_delay 3.0                 -through $SLINK_CRED_ASYNC_NETS -ignore_clock_latency
	set_min_delay [expr -$CLK_UNCERTAINTY] -through $SLINK_CRED_ASYNC_NETS -ignore_clock_latency
} elseif {[llength $SLINK_CRED_ASYNC_START] > 0 && [llength $SLINK_CRED_ASYNC_END] > 0} {
	set_max_delay 3.0                 -from $SLINK_CRED_ASYNC_START -to $SLINK_CRED_ASYNC_END -ignore_clock_latency
	set_min_delay [expr -$CLK_UNCERTAINTY] -from $SLINK_CRED_ASYNC_START -to $SLINK_CRED_ASYNC_END -ignore_clock_latency
}


#############
## SoC Ins ##
#############
puts "Input/Outputs..."

# Reset should propagate to system domain within a clock cycle.
set_input_delay -max [ expr $TCK_JTG * 0.10 ] [get_ports {rst_ni testmode_i}]  
set_false_path -hold   -from [get_ports {rst_ni testmode_i}]
set_max_delay $TCK_SYS -from [get_ports {rst_ni testmode_i}]


##########
## JTAG ##
##########
puts "JTAG..."

set_input_delay  -min -add_delay -clock clk_jtg [ expr $TCK_JTG * 0.10 ] [get_ports {jtag_tdi_i jtag_tms_i}]
set_input_delay  -max -add_delay -clock clk_jtg [ expr $TCK_JTG * 0.30 ] [get_ports {jtag_tdi_i jtag_tms_i}]
set_output_delay -min -add_delay -clock clk_jtg [ expr $TCK_JTG * 0.10 ] [get_ports jtag_tdo_o]
set_output_delay -max -add_delay -clock clk_jtg [ expr $TCK_JTG * 0.20 ] [get_ports jtag_tdo_o]

# Reset should propagate to system domain within a clock cycle.
set_input_delay -max [ expr $TCK_JTG * 0.10 ] [get_ports jtag_trst_ni]  
set_false_path -hold    -from [get_ports jtag_trst_ni]
set_max_delay $TCK_JTG  -from [get_ports jtag_trst_ni]


##########
## GPIO ##
##########
puts "GPIO..."

set_input_delay  -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports {gpio*}]
set_input_delay  -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports {gpio*}]

set_output_delay -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports {gpio*}]
set_output_delay -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports {gpio*}]

# The timing of these signals are not important but we want to keep them in-cycle
set_output_delay -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports {status_o unused*}]
set_output_delay -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports {status_o unused*}]


##########
## UART ##
##########
puts "UART..."

set_input_delay  -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports uart_rx_i]
set_input_delay  -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports uart_rx_i]
set_output_delay -min -add_delay -clock clk_sys [ expr $TCK_SYS * 0.10 ] [get_ports uart_tx_o]
set_output_delay -max -add_delay -clock clk_sys [ expr $TCK_SYS * 0.30 ] [get_ports uart_tx_o]


#################
## Serial Link ##
#################
puts "Serial Link..."

# Source-synchronous DDR interface, modelled on cheshire-ihp130-o.
#
# Layout of the off-chip protocol (per channel):
#   * Far end launches DDR data on both edges of its TX clock and ships
#     out the matching clock 90 deg shifted with the data.  That clock
#     enters our chip as `slink_ddr_rcv_clk_i` and reaches us *centre-
#     aligned* on its own data lanes (`slink_ddr*_i`).
#   * Our end is symmetric: data_out_q on the TX side is launched by
#     `clk_slow` (clk_sli_tx_drv_*) and the matching DDR clock that goes
#     to the receiver is `slink_ddr_rcv_clk_o`, defined as the same /4
#     of clk_sys but 90 deg later (clk_sli_tx_*).
#
# Skew budget on the off-chip nets (PCB routing + receiver jitter + our
# pad spread).  Keep loosely matched to the 1.5 ns input-side guard
# margin used by cheshire-ihp130-o for IHP13.
set SLI_MAX_SKEW   0.55
set SLI_RX_GUARD   1.5

set SLI_IN_DATA  [get_ports {slink_ddr0_i slink_ddr1_i slink_ddr2_i slink_ddr3_i \
                             slink_ddr4_i slink_ddr5_i slink_ddr6_i slink_ddr7_i}]
set SLI_OUT_DATA [get_ports {slink_ddr0_o slink_ddr1_o slink_ddr2_o slink_ddr3_o \
                             slink_ddr4_o slink_ddr5_o slink_ddr6_o slink_ddr7_o}]
set SLI_OUT_CLK  [get_ports slink_ddr_rcv_clk_o]

# ---- DDR INPUT ----------------------------------------------------------
# The far end centres `slink_ddr_rcv_clk_i` in the eye of `slink_ddr*_i`,
# i.e. data transitions happen at clk +/- T/4 worst case (~half period
# centred on the toggle).  Subtract our PCB skew to obtain the usable eye.
# The local sampler is on the rising edge of ddr_rcv_clk_i (PHY RX `ddr_q`
# is on the *negedge* but the cdc_fifo_gray src samples `data_in` on the
# posedge -- effectively both edges of ddr_rcv_clk_i sample data).
set_input_delay -min -add_delay -clock clk_sli_rx                        -network_latency_included $SLI_MAX_SKEW                              $SLI_IN_DATA
set_input_delay -min -add_delay -clock_fall -clock clk_sli_rx            -network_latency_included $SLI_MAX_SKEW                              $SLI_IN_DATA
set_input_delay -max -add_delay -clock clk_sli_rx                        -network_latency_included [expr $TCK_SLI / 2 - $SLI_RX_GUARD - $SLI_MAX_SKEW] $SLI_IN_DATA
set_input_delay -max -add_delay -clock_fall -clock clk_sli_rx            -network_latency_included [expr $TCK_SLI / 2 - $SLI_RX_GUARD - $SLI_MAX_SKEW] $SLI_IN_DATA

# ---- DDR OUTPUT ---------------------------------------------------------
# We are the source: we launch data with the SDR `clk_slow` (clk_sli_tx_drv_0)
# and forward `slink_ddr_rcv_clk_o` (clk_sli_tx_0) as the centre-aligned DDR
# clock.  Constrain the output relative to the launched DDR clock; this
# guarantees that data and clock arrive at the pad with the same routing
# latency (any extra clock latency is mirrored on the reference pin).
for {set ch 0} {$ch < $SLINK_NUM_CHANNELS} {incr ch} {
	set tx_clk clk_sli_tx_$ch
	if {[llength [get_clocks -quiet $tx_clk]] == 0} { continue }
	# If multiple channels exist, each channel has its own ddr_rcv_clk_o pad.
	# For NumChannels == 1 we use the unique output port.
	set tx_clkpad [get_ports slink_ddr_rcv_clk_o]
	if {[llength $tx_clkpad] > 1} {
		set tx_clkpad [lindex $tx_clkpad $ch]
	}
	set_output_delay -min -add_delay -clock $tx_clk             -reference_pin $tx_clkpad [expr -$TCK_SLI / 4 + $SLI_MAX_SKEW] $SLI_OUT_DATA
	set_output_delay -min -add_delay -clock_fall -clock $tx_clk -reference_pin $tx_clkpad [expr -$TCK_SLI / 4 + $SLI_MAX_SKEW] $SLI_OUT_DATA
	set_output_delay -max -add_delay -clock $tx_clk             -reference_pin $tx_clkpad [expr  $TCK_SLI / 4 - $SLI_MAX_SKEW] $SLI_OUT_DATA
	set_output_delay -max -add_delay -clock_fall -clock $tx_clk -reference_pin $tx_clkpad [expr  $TCK_SLI / 4 - $SLI_MAX_SKEW] $SLI_OUT_DATA

	# Forwarded DDR clock pad (was missing set_output_delay): generated in the
	# clk_sys domain by slink_phys_layer and must reach the pad with matched
	# latency vs. the data lanes that use this port as -reference_pin.
	set_output_delay -min -add_delay -clock clk_sys -reference_pin $tx_clkpad \
		[expr $TCK_SYS * 0.10] $tx_clkpad
	set_output_delay -max -add_delay -clock clk_sys -reference_pin $tx_clkpad \
		[expr $TCK_SLI / 4 - $SLI_MAX_SKEW] $tx_clkpad
}

# Fallback if clk_sli_tx_* was not created (channel loop skipped) but the pad exists
if {[llength [get_clocks -quiet clk_sli_tx_0]] == 0} {
	foreach tx_clkpad [get_ports -quiet slink_ddr_rcv_clk_o] {
		set_output_delay -min -add_delay -clock clk_sys [expr $TCK_SYS * 0.10] $tx_clkpad
		set_output_delay -max -add_delay -clock clk_sys [expr $TCK_SLI / 4 - $SLI_MAX_SKEW] $tx_clkpad
	}
}

# Suppress the redundant min/max edge checks between the driving SDR clock
# and the DDR clock we generate from the same source -- they share a flop
# and would otherwise be timed as if they were separate phase variants.
for {set ch 0} {$ch < $SLINK_NUM_CHANNELS} {incr ch} {
	set drv clk_sli_tx_drv_$ch
	set ddr clk_sli_tx_$ch
	if {[llength [get_clocks -quiet $drv]] == 0} { continue }
	if {[llength [get_clocks -quiet $ddr]] == 0} { continue }
	set_false_path -setup -rise_from [get_clocks $drv] -rise_to [get_clocks $ddr]
	set_false_path -setup -fall_from [get_clocks $drv] -fall_to [get_clocks $ddr]
	set_false_path -hold  -rise_from [get_clocks $drv] -fall_to [get_clocks $ddr]
	set_false_path -hold  -fall_from [get_clocks $drv] -rise_to [get_clocks $ddr]
}

# ---- Credit return / credit receive -------------------------------------
# slink_credit_rtrn_clk_o is a clock-only pad (no data carried with it);
# it just signals "+1 credit" on each gated clk_sys rising edge.  We still
# constrain a sensible launch-to-pad budget so that placement keeps the
# ICG close to the pad.
if {[llength [get_clocks -quiet clk_sli_cred_rtrn]] > 0} {
	set_output_delay -min -add_delay -clock clk_sli_cred_rtrn [expr $TCK_SYS * 0.10] [get_ports slink_credit_rtrn_clk_o]
	set_output_delay -max -add_delay -clock clk_sli_cred_rtrn [expr $TCK_SYS * 0.40] [get_ports slink_credit_rtrn_clk_o]
}

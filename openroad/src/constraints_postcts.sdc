# Copyright 2024 ETH Zurich and University of Bologna.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
# SPDX-License-Identifier: SHL-0.51

# Post-CTS overrides.  Sourced by 03_cts.tcl after CTS has built the real
# clock trees and again by 04_routing.tcl after global route, so that
# repair_timing / detailed route work with realistic clock latencies and
# without the pre-CTS-only path exceptions.

source src/instances.tcl

# Switch every clock to propagated mode so that real CTS-inserted insertion
# delays and skew are honoured for setup/hold checks from here on.
set_propagated_clock [all_clocks]

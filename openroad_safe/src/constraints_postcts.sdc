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

# Today none of our pre-CTS constraints involve clock-as-data muxing into
# the slink data path (the DDR mux is implicit in `data_out_q + ddr_sel`
# which is normal data-path logic, not a clock-stop boundary).  If a
# future revision adds explicit `set_sense -clock -stop_propagation` on
# any of the slink TX muxes, the matching `unset_path_exceptions ...`
# calls go here -- mirroring cheshire-ihp130-o's basilisk_postcts.sdc.

// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

`include "obi/typedef.svh"
`include "slink_obi/typedef.svh"

package user_pkg;

  //////////////////
  // User Manager //
  //////////////////

  localparam int unsigned NumMuxMgr = 1;


  /// Enum with user domain multiplexer manager idxs
  typedef enum bit [0:0]  {
    SerialLinkMgr    = 0
  } user_mux_inputs_e;

  ///////////////////////
  // User Subordinates //
  ///////////////////////

  // The base address of the user domain can be retrived from `croc_pkg::UserBaseAddr`
  // Recommended: place subordinates at 4KB boundaries (32'hXXXX_X000)

  /// Enum with user domain demultiplexer subordinate idxs
  typedef enum bit [2:0]  {
    UserError        = 0,
    SerialLinkSbr    = 1,
    SerialLinkConfig = 2
  } user_demux_outputs_e;



  /// Address rules given to user domain demultiplexer (see croc_pkg.sv for examples)
  localparam croc_pkg::addr_map_rule_t [1:0] UserAddrMap = '{
    '{
      idx:        SerialLinkConfig,
      start_addr: croc_pkg::UserBaseAddr,
      end_addr:   croc_pkg::UserBaseAddr + slink_reg_pkg::SLINK_REG_SIZE
    },
    '{
      idx:        SerialLinkSbr,
      start_addr: 32'h1000_0000,
      end_addr:   32'hFFFF_FFFF
    }
  };
  // All addresses outside the defined address rules go to the error subordinate

  // +1 for additional OBI error
  localparam int unsigned NumDemuxSbr = $size(UserAddrMap) + 1;

endpackage

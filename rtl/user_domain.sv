// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter         <phsauter@iis.ee.ethz.ch>
// - Fabian Aegerter         <faegerter@ethz.ch>
// - Llorenç Muela Hausmann  <lmuela@ethz.ch>

`include "slink_obi/typedef.svh"

module user_domain import user_pkg::*; import croc_pkg::*; import slink_pkg::*; #(
  parameter int unsigned GpioCount = 16,
  parameter int unsigned NumExternalIrqs = 4,
  parameter int unsigned SlinkNumChannels = 1,
  parameter int unsigned SlinkNumLanes = 8
) (
  input  logic      clk_i,
  input  logic      ref_clk_i,
  input  logic      rst_ni,
  input  logic      testmode_i,

  input  sbr_obi_req_t user_sbr_obi_req_i, // User Sbr (rsp_o), Croc Mgr (req_i)
  output sbr_obi_rsp_t user_sbr_obi_rsp_o,

  output mgr_obi_req_t user_mgr_obi_req_o, // User Mgr (req_o), Croc Sbr (rsp_i)
  input  mgr_obi_rsp_t user_mgr_obi_rsp_i,

  input  logic [      GpioCount-1:0] gpio_in_sync_i, // synchronized GPIO inputs
  output logic [NumExternalIrqs-1:0] interrupts_o,    // interrupts to core


  input   logic  [SlinkNumChannels-1:0]                    slink_ddr_rcv_clk_i,    
  output  logic  [SlinkNumChannels-1:0]                    slink_ddr_rcv_clk_o,    
  input   logic  [SlinkNumChannels-1:0][SlinkNumLanes-1:0] slink_ddr_i,            
  output  logic  [SlinkNumChannels-1:0][SlinkNumLanes-1:0] slink_ddr_o,            
  input   logic                                            slink_credit_recv_clk_i,
  output  logic                                            slink_credit_rtrn_clk_o
);

  assign interrupts_o = '0;

  //////////////////////
  // User Manager MUX //
  //////////////////////


  // ----------------------------------------------------------------------------------------------
  // User Manager Buses
  // ----------------------------------------------------------------------------------------------

  // collection of signals from the multiplexer

  mgr_obi_req_t [NumMuxMgr-1:0] all_user_mgr_obi_req;
  mgr_obi_rsp_t [NumMuxMgr-1:0] all_user_mgr_obi_rsp;


  mgr_obi_req_t slink_obi_req_o;
  mgr_obi_rsp_t slink_obi_rsp_i;

  assign all_user_mgr_obi_req[SerialLinkMgr] = slink_obi_req_o;
  assign slink_obi_rsp_i                     = all_user_mgr_obi_rsp[SerialLinkMgr];


  if(NumMuxMgr > 1) begin : gen_user_mgr_mux

    obi_mux #(
      .SbrPortObiCfg      ( MgrObiCfg             ),
      .sbr_port_obi_req_t ( mgr_obi_req_t         ),
      .sbr_port_a_chan_t  ( sbr_obi_a_chan_t      ), 
      .sbr_port_obi_rsp_t ( mgr_obi_rsp_t         ),
      .sbr_port_r_chan_t  ( sbr_obi_r_chan_t      ),
      .NumSbrPorts        ( NumMuxMgr             ),
      .NumMaxTrans        ( 2                     ),
      .UseIdForRouting    ( 1'b0                  )
    ) i_obi_mux (
      .clk_i,
      .rst_ni,
      
      .testmode_i         (1'b0                   ),

      .sbr_ports_req_i    ( all_user_mgr_obi_req  ),
      .sbr_ports_rsp_o    ( all_user_mgr_obi_rsp  ),

      .mgr_port_req_o     ( user_mgr_obi_req_o    ),
      .mgr_port_rsp_i     ( user_mgr_obi_rsp_i    )
    );

  end else begin : gen_no_user_mgr_mux 

    assign user_mgr_obi_req_o = all_user_mgr_obi_req[0];
    assign all_user_mgr_obi_rsp[0] = user_mgr_obi_rsp_i;

  end



  ////////////////////////////
  // User Subordinate DEMUX //
  ////////////////////////////

  // ----------------------------------------------------------------------------------------------
  // User Subordinate Buses
  // ----------------------------------------------------------------------------------------------

  // collection of signals from the demultiplexer
  sbr_obi_req_t [NumDemuxSbr-1:0] all_user_sbr_obi_req;
  sbr_obi_rsp_t [NumDemuxSbr-1:0] all_user_sbr_obi_rsp;

  // Error Subordinate Bus
  sbr_obi_req_t user_error_obi_req;
  sbr_obi_rsp_t user_error_obi_rsp;

  // OBI bus Serial link
  sbr_obi_req_t slink_obi_req_i;
  sbr_obi_rsp_t slink_obi_rsp_o;

  // OBI bus Serial link config
  sbr_obi_req_t slink_cfg_obi_req_i;
  sbr_obi_rsp_t slink_cfg_obi_rsp_o;

  // Fanout into more readable signals
  assign user_error_obi_req                     = all_user_sbr_obi_req[UserError];
  assign all_user_sbr_obi_rsp[UserError]        = user_error_obi_rsp;
  assign slink_obi_req_i                        = all_user_sbr_obi_req[SerialLinkSbr];
  assign all_user_sbr_obi_rsp[SerialLinkSbr]    = slink_obi_rsp_o;
  assign slink_cfg_obi_req_i                    = all_user_sbr_obi_req[SerialLinkConfig];
  assign all_user_sbr_obi_rsp[SerialLinkConfig] = slink_cfg_obi_rsp_o;

  //-----------------------------------------------------------------------------------------------
  // Demultiplex to User Subordinates according to address map
  //-----------------------------------------------------------------------------------------------

  logic [cf_math_pkg::idx_width(NumDemuxSbr)-1:0] user_idx;

  addr_decode #(
    .NoIndices ( NumDemuxSbr                    ),
    .NoRules   ( $size(UserAddrMap)             ),
    .addr_t    ( logic[SbrObiCfg.DataWidth-1:0] ),
    .rule_t    ( addr_map_rule_t                ),
    .Napot     ( 1'b0                           )
  ) i_addr_decode_periphs (
    .addr_i           ( user_sbr_obi_req_i.a.addr ),
    .addr_map_i       ( UserAddrMap               ),
    .idx_o            ( user_idx                  ),
    .dec_valid_o      (),
    .dec_error_o      (),
    .en_default_idx_i ( 1'b1      ),
    .default_idx_i    ( UserError )
  );

  obi_demux #(
    .ObiCfg      ( SbrObiCfg     ),
    .obi_req_t   ( sbr_obi_req_t ),
    .obi_rsp_t   ( sbr_obi_rsp_t ),
    .NumMgrPorts ( NumDemuxSbr   ),
    .NumMaxTrans ( 2             )
  ) i_obi_demux (
    .clk_i,
    .rst_ni,

    .sbr_port_select_i ( user_idx             ),
    .sbr_port_req_i    ( user_sbr_obi_req_i   ),
    .sbr_port_rsp_o    ( user_sbr_obi_rsp_o   ),

    .mgr_ports_req_o   ( all_user_sbr_obi_req ),
    .mgr_ports_rsp_i   ( all_user_sbr_obi_rsp )
  );


//-------------------------------------------------------------------------------------------------
// User Subordinates
//-------------------------------------------------------------------------------------------------

  // Error Subordinate
  obi_err_sbr #(
    .ObiCfg      ( SbrObiCfg     ),
    .obi_req_t   ( sbr_obi_req_t ),
    .obi_rsp_t   ( sbr_obi_rsp_t ),
    .NumMaxTrans ( 1             ),
    .RspData     ( 32'hBADCAB1E  )
  ) i_user_err (
    .clk_i,
    .rst_ni,
    .testmode_i ( testmode_i         ),
    .obi_req_i  ( user_error_obi_req ),
    .obi_rsp_o  ( user_error_obi_rsp )
  );


//-------------------------------------------------------------------------------------------------
// User Managers and Subordinates
//-------------------------------------------------------------------------------------------------

  localparam slink_obi_cfg_t SlinkObiCfg = slink_obi_cfg(
      SbrObiCfg.AddrWidth, SbrObiCfg.DataWidth, SbrObiCfg.DataWidth, SbrObiCfg.IdWidth, SbrObiCfg.BeFull, (SbrObiCfg.OptionalCfg != '0));

  `SLINK_OBI_TYPEDEF_DEFAULT(slink_obi, SlinkObiCfg)
  
  slink #(
    .obi_req_mgr_t   ( mgr_obi_req_t            ),
    .obi_rsp_mgr_t   ( mgr_obi_rsp_t            ),
    .obi_req_sbr_t   ( sbr_obi_req_t            ),
    .obi_rsp_sbr_t   ( sbr_obi_rsp_t            ),
    .obi_r_chan_sbr_t( sbr_obi_r_chan_t         ),
    .a_optional_t    ( sbr_obi_a_chan_t         ), 
    .r_optional_t    ( sbr_obi_r_chan_t         ),
    .a_chan_write_t  ( slink_obi_a_chan_write_t ),
    .a_chan_read_t   ( slink_obi_a_chan_read_t  ),
    .r_chan_write_t  ( slink_obi_r_chan_write_t ),
    .r_chan_read_t   ( slink_obi_r_chan_read_t  ),
    .slink_obi_cfg   ( SlinkObiCfg              )
  ) i_slink (
    .clk_i             ( clk_i                   ),
    .rst_ni            ( rst_ni                  ),
    .testmode_i        ( testmode_i              ), 
    .obi_in_req_i      ( slink_obi_req_i         ),
    .obi_in_rsp_o      ( slink_obi_rsp_o         ),
    .obi_out_req_o     ( slink_obi_req_o         ),
    .obi_out_rsp_i     ( slink_obi_rsp_i         ),
    .obi_reg_req_i     ( slink_cfg_obi_req_i     ),
    .obi_reg_rsp_o     ( slink_cfg_obi_rsp_o     ),
    .ddr_rcv_clk_i     ( slink_ddr_rcv_clk_i     ),
    .ddr_rcv_clk_o     ( slink_ddr_rcv_clk_o     ),
    .ddr_i             ( slink_ddr_i             ),
    .ddr_o             ( slink_ddr_o             ),
    .credit_recv_clk_i ( slink_credit_recv_clk_i ),
    .credit_rtrn_clk_o ( slink_credit_rtrn_clk_o )
  );

endmodule

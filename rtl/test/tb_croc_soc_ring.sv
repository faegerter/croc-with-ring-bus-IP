// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`define TRACE_WAVE

// --------------------------------------------------------------------
//  tb_croc_soc_ring
//
//  Instantiates NumNodes croc_soc instances connected in a serial-link
//  ring.  Each node loads its own pre-compiled hex binary:
//
//    bin/serial_link_test_node1.hex  (NODE_ID=1)
//    bin/serial_link_test_node2.hex  (NODE_ID=2)
//    ...
//
//  Override the binary directory at runtime:
//    +bin_dir=../sw/bin
//
//  Ring wiring (same convention as tb_obi_slink):
//    node i  →  drives slink wires at index NEXT = (i+1) % NumNodes
//    node i  ←  receives slink wires at index i   (driven by node i-1)
// --------------------------------------------------------------------

module tb_croc_soc_ring #(
  parameter int unsigned NumNodes         = 4,
  parameter int unsigned GpioCount        = 16,
  parameter int unsigned SlinkNumChannels = 1,
  parameter int unsigned SlinkNumLanes    = 8
);

  import tb_croc_pkg::*;

  // ================================================================
  //  Per-node signal arrays
  // ================================================================
  logic rst_n      [NumNodes];
  logic sys_clk    [NumNodes];
  logic ref_clk    [NumNodes];

  logic jtag_tck   [NumNodes];
  logic jtag_trst_n[NumNodes];
  logic jtag_tms   [NumNodes];
  logic jtag_tdi   [NumNodes];
  logic jtag_tdo   [NumNodes];

  logic uart_rx    [NumNodes];
  logic uart_tx    [NumNodes];

  logic [GpioCount-1:0] gpio_in     [NumNodes];
  logic [GpioCount-1:0] gpio_out    [NumNodes];
  logic [GpioCount-1:0] gpio_out_en [NumNodes];

  // ================================================================
  //  Serial-link ring wires
  //
  //  Node i drives index NEXT; node i reads index i.
  //  Using plain logic arrays — each element is driven by exactly
  //  one node's output port, which is fine in simulation.
  // ================================================================
  logic [SlinkNumChannels-1:0]                    slink_ddr_rcv_clk [NumNodes];
  logic [SlinkNumChannels-1:0][SlinkNumLanes-1:0] slink_ddr          [NumNodes];
  logic                                           slink_credit_clk   [NumNodes];

  // ================================================================
  //  EOC tracking
  // ================================================================
  logic [NumNodes-1:0] node_done = '0;   // set by proc_test[i] on completion
  int   unsigned       node_result[NumNodes];  // tb_data from jtag_wait_for_eoc

  // ================================================================
  //  Binary directory (override with +bin_dir=<path>)
  // ================================================================
  string bin_dir;
  initial begin
    if (!$value$plusargs("bin_dir=%s", bin_dir))
      bin_dir = "../sw/bin";
    $display("[TB] Binary directory: %s", bin_dir);
  end

  // ================================================================
  //  Generate: one VIP + one croc_soc per node
  // ================================================================
  generate
    for (genvar i = 0; i < NumNodes; i++) begin : gen_nodes

      localparam int unsigned NEXT = (i + 1) % NumNodes;

      // ------------------------------------------------------------
      //  Verification IP — drives clocks, reset and JTAG for node i
      // ------------------------------------------------------------
      croc_vip #(
        .GpioCount ( GpioCount )
      ) i_vip (
        .rst_no        ( rst_n      [i] ),
        .sys_clk_o     ( sys_clk    [i] ),
        .ref_clk_o     ( ref_clk    [i] ),
        .jtag_tck_o    ( jtag_tck   [i] ),
        .jtag_trst_no  ( jtag_trst_n[i] ),
        .jtag_tms_o    ( jtag_tms   [i] ),
        .jtag_tdi_o    ( jtag_tdi   [i] ),
        .jtag_tdo_i    ( jtag_tdo   [i] ),
        .uart_rx_o     ( uart_rx    [i] ),
        .uart_tx_i     ( uart_tx    [i] ),
        .gpio_out_en_i ( gpio_out_en[i] ),
        .gpio_out_i    ( gpio_out   [i] ),
        .gpio_in_o     ( gpio_in    [i] )
      );

      // ------------------------------------------------------------
      //  DUT — croc_soc instance
      //
      //  Ring connections:
      //    output ports → drive wire at index NEXT
      //    input  ports ← read  wire at index i (driven by node i-1)
      // ------------------------------------------------------------
      `ifdef TARGET_NETLIST_YOSYS
      \croc_soc$croc_chip.i_croc_soc i_croc_soc (
      `else
      croc_soc #(
        .GpioCount        ( GpioCount        ),
        .SlinkNumChannels ( SlinkNumChannels ),
        .SlinkNumLanes    ( SlinkNumLanes    )
      ) i_croc_soc (
      `endif
        .clk_i                   ( sys_clk    [i] ),
        .rst_ni                  ( rst_n      [i] ),
        .ref_clk_i               ( ref_clk    [i] ),
        .testmode_i              ( 1'b0            ),
        .status_o                (                 ),
        .jtag_tck_i              ( jtag_tck   [i] ),
        .jtag_tdi_i              ( jtag_tdi   [i] ),
        .jtag_tdo_o              ( jtag_tdo   [i] ),
        .jtag_tms_i              ( jtag_tms   [i] ),
        .jtag_trst_ni            ( jtag_trst_n[i] ),
        .uart_rx_i               ( uart_rx    [i] ),
        .uart_tx_o               ( uart_tx    [i] ),
        .gpio_i                  ( gpio_in    [i] ),
        .gpio_o                  ( gpio_out   [i] ),
        .gpio_out_en_o           ( gpio_out_en[i] ),
        // --- ring outputs: drive NEXT node's input wires ---
        .slink_ddr_rcv_clk_o     ( slink_ddr_rcv_clk[NEXT] ),
        .slink_ddr_o             ( slink_ddr        [NEXT] ),
        .slink_credit_rtrn_clk_o ( slink_credit_clk [i] ),
        // --- ring inputs: read this node's wire (driven by node i-1) ---
        .slink_ddr_rcv_clk_i     ( slink_ddr_rcv_clk[i]    ),
        .slink_ddr_i             ( slink_ddr        [i]     ),
        .slink_credit_recv_clk_i ( slink_credit_clk [NEXT]     )
      );

      // ------------------------------------------------------------
      //  Per-node test process
      //
      //  1. Wait for reset
      //  2. Init JTAG
      //  3. Load node-specific binary  (1-indexed NODE_ID = i+1)
      //  4. Wake core via CLINT msip
      //  5. Wait for EOC
      //  6. Signal completion via node_done[i]
      // ------------------------------------------------------------
      initial begin : proc_test
        automatic string hex_path;
        automatic logic [31:0] tb_data;

        // Derive path: NODE_IDs are 1-indexed in the C code
        $sformat(hex_path, "%s/serial_link_test_node%0d.hex", bin_dir, i + 1);
        $display("@%t | [Node %0d] Binary: %s", $time, i, hex_path);

        #ClkPeriodSys;

        gen_nodes[i].i_vip.jtag_init();

        $display("@%t | [Node %0d] Loading binary...", $time, i);
        gen_nodes[i].i_vip.jtag_load_hex(hex_path);

        $display("@%t | [Node %0d] Waking core via CLINT msip", $time, i);
        gen_nodes[i].i_vip.jtag_write_reg32(ClintBaseAddr, 32'h1);

        gen_nodes[i].i_vip.jtag_halt();
        gen_nodes[i].i_vip.jtag_resume();

        // Poll corestatus manually instead of calling jtag_wait_for_eoc,
        // which calls $finish() internally and would kill all other nodes.
        $display("@%t | [Node %0d] Waiting for EOC...", $time, i);
        begin
          automatic dm::sbcs_t sbcs = dm::sbcs_t'{sbreadonaddr: 1'b1, sbaccess: 2, default: '0};
          tb_data = 0;
          gen_nodes[i].i_vip.jtag_write(dm::SBCS, sbcs, 0, 1);
          gen_nodes[i].i_vip.jtag_write(dm::SBAddress1, '0);
          do begin
            gen_nodes[i].i_vip.jtag_write(dm::SBAddress0, CoreStatusAddr);
            gen_nodes[i].i_vip.jtag_dbg.wait_idle(20);
            gen_nodes[i].i_vip.jtag_dbg.read_dmi_exp_backoff(dm::SBData0, tb_data);
          end while (tb_data == 0);
        end

        node_result[i] = tb_data >> 1;
        node_done[i]   = 1'b1;

        $display("@%t | [Node %0d] EOC received, return value = 0x%08X (%s)",
          $time, i, node_result[i], (node_result[i] == 0) ? "PASS" : "FAIL");

      end : proc_test

    end // for genvar i
  endgenerate

  // ================================================================
  //  Main control: wait for all nodes, print summary, finish
  // ================================================================
  initial begin : proc_main
    automatic int unsigned passed = 0;
    automatic int unsigned failed = 0;

    $timeformat(-9, 0, "ns", 12);

    // Wait for every node to reach EOC
    wait (node_done == '1);
    repeat (50) @(posedge sys_clk[0]);

    $display("==========================================================");
    $display("[TB] Simulation complete at %0t", $time);
    $display("[TB] Nodes: %0d", NumNodes);
    for (int n = 0; n < NumNodes; n++) begin
      if (node_result[n] == 0) passed++;
      else                      failed++;
      $display("[TB]   Node %0d (NODE_ID=%0d): %s (ret=0x%08X)",
        n, n+1, (node_result[n] == 0) ? "PASS" : "FAIL", node_result[n]);
    end
    $display("[TB] Passed: %0d / %0d", passed, NumNodes);
    if (failed == 0)
      $display("[TB] *** ALL NODES PASSED ***");
    else
      $display("[TB] *** %0d NODE(S) FAILED ***", failed);
    $display("==========================================================");

    $finish();
  end : proc_main

  // ================================================================
  //  Waveform dump
  // ================================================================
  initial begin
    `ifdef TRACE_WAVE
      `ifdef VERILATOR
        $dumpfile("croc_ring.fst");
        $dumpvars(1, tb_croc_soc_ring);
      `else
        $dumpfile("croc_ring.vcd");
        $dumpvars(1, tb_croc_soc_ring);
      `endif
    `endif
  end

  final begin
    `ifdef TRACE_WAVE
      $dumpflush;
    `endif
  end

endmodule : tb_croc_soc_ring
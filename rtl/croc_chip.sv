// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

module croc_chip import croc_pkg::*; #() (
  input  wire clk_i,
  input  wire rst_ni,
  input  wire ref_clk_i,

  input  wire jtag_tck_i,
  input  wire jtag_trst_ni,
  input  wire jtag_tms_i,
  input  wire jtag_tdi_i,
  output wire jtag_tdo_o,

  input  wire uart_rx_i,
  output wire uart_tx_o,

  input  wire testmode_i,
  output wire status_o,

  input  wire slink_ddr_rcv_clk_i,    
  output wire slink_ddr_rcv_clk_o,    
  input  wire slink_ddr0_i,
  input  wire slink_ddr1_i,
  input  wire slink_ddr2_i,
  input  wire slink_ddr3_i,
  input  wire slink_ddr4_i,
  input  wire slink_ddr5_i,
  input  wire slink_ddr6_i,
  input  wire slink_ddr7_i,
  output wire slink_ddr0_o,
  output wire slink_ddr1_o,
  output wire slink_ddr2_o,
  output wire slink_ddr3_o,
  output wire slink_ddr4_o,
  output wire slink_ddr5_o,
  output wire slink_ddr6_o,
  output wire slink_ddr7_o,          
  input  wire slink_credit_recv_clk_i,
  output wire slink_credit_rtrn_clk_o,

  inout  wire gpio0_io,
  inout  wire gpio1_io,
  inout  wire gpio2_io,
  inout  wire gpio3_io,
  inout  wire gpio4_io,
  inout  wire gpio5_io,
  inout  wire gpio6_io,
  inout  wire gpio7_io,
  inout  wire gpio8_io,
  inout  wire gpio9_io,
  inout  wire gpio10_io,
  inout  wire gpio11_io,
  inout  wire gpio12_io,
  inout  wire gpio13_io,
  inout  wire gpio14_io,
  inout  wire gpio15_io,

  inout wire VDD,
  inout wire VSS,
  inout wire VDDIO,
  inout wire VSSIO
);
    logic soc_clk_i;
    logic soc_rst_ni;
    logic soc_ref_clk_i;
    logic soc_testmode_i;

    logic soc_jtag_tck_i;
    logic soc_jtag_trst_ni;
    logic soc_jtag_tms_i;
    logic soc_jtag_tdi_i;
    logic soc_jtag_tdo_o;

    logic soc_status_o;

    localparam int unsigned SlinkNumChannels = 1;
    localparam int unsigned SlinkNumLanes = 8;

    logic [SlinkNumChannels-1:0] soc_slink_ddr_rcv_clk_i;
    logic [SlinkNumChannels-1:0] soc_slink_ddr_rcv_clk_o;    

    logic [SlinkNumChannels-1:0][SlinkNumLanes-1:0] soc_slink_ddr_i;        
    logic [SlinkNumChannels-1:0][SlinkNumLanes-1:0] soc_slink_ddr_o;  

    logic  soc_slink_credit_recv_clk_i;
    logic  soc_slink_credit_rtrn_clk_o;
      
    localparam int unsigned GpioCount = 16;

    logic [GpioCount-1:0] soc_gpio_i;
    logic [GpioCount-1:0] soc_gpio_o;
    logic [GpioCount-1:0] soc_gpio_out_en_o; // Output enable signal; 0 -> input, 1 -> output


    sg13g2_IOPadIn        pad_clk_i        (.pad(clk_i),        .p2c(soc_clk_i));
    sg13g2_IOPadIn        pad_rst_ni       (.pad(rst_ni),       .p2c(soc_rst_ni));
    sg13g2_IOPadIn        pad_ref_clk_i    (.pad(ref_clk_i),    .p2c(soc_ref_clk_i));
    sg13g2_IOPadIn        pad_jtag_tck_i   (.pad(jtag_tck_i),   .p2c(soc_jtag_tck_i));
    sg13g2_IOPadIn        pad_jtag_trst_ni (.pad(jtag_trst_ni), .p2c(soc_jtag_trst_ni));
    sg13g2_IOPadIn        pad_jtag_tms_i   (.pad(jtag_tms_i),   .p2c(soc_jtag_tms_i));
    sg13g2_IOPadIn        pad_jtag_tdi_i   (.pad(jtag_tdi_i),   .p2c(soc_jtag_tdi_i));
    sg13g2_IOPadOut16mA   pad_jtag_tdo_o   (.pad(jtag_tdo_o),   .c2p(soc_jtag_tdo_o));

    sg13g2_IOPadIn        pad_uart_rx_i    (.pad(uart_rx_i),  .p2c(soc_uart_rx_i));
    sg13g2_IOPadOut16mA   pad_uart_tx_o    (.pad(uart_tx_o),  .c2p(soc_uart_tx_o));

    sg13g2_IOPadIn        pad_testmode_i   (.pad(testmode_i), .p2c(soc_testmode_i));
    sg13g2_IOPadOut16mA   pad_status_o     (.pad(status_o),   .c2p(soc_status_o));


    sg13g2_IOPadIn        pad_slink_ddr_rcv_clk_i     (.pad(slink_ddr_rcv_clk_i),     .p2c(soc_slink_ddr_rcv_clk_i));
    sg13g2_IOPadOut16mA   pad_slink_ddr_rcv_clk_o     (.pad(slink_ddr_rcv_clk_o),     .c2p(soc_slink_ddr_rcv_clk_o));
    sg13g2_IOPadIn        pad_slink_ddr0_i            (.pad(slink_ddr0_i),            .p2c(soc_slink_ddr_i[0][0]));
    sg13g2_IOPadIn        pad_slink_ddr1_i            (.pad(slink_ddr1_i),            .p2c(soc_slink_ddr_i[0][1]));
    sg13g2_IOPadIn        pad_slink_ddr2_i            (.pad(slink_ddr2_i),            .p2c(soc_slink_ddr_i[0][2]));
    sg13g2_IOPadIn        pad_slink_ddr3_i            (.pad(slink_ddr3_i),            .p2c(soc_slink_ddr_i[0][3]));
    sg13g2_IOPadIn        pad_slink_ddr4_i            (.pad(slink_ddr4_i),            .p2c(soc_slink_ddr_i[0][4]));
    sg13g2_IOPadIn        pad_slink_ddr5_i            (.pad(slink_ddr5_i),            .p2c(soc_slink_ddr_i[0][5]));
    sg13g2_IOPadIn        pad_slink_ddr6_i            (.pad(slink_ddr6_i),            .p2c(soc_slink_ddr_i[0][6]));
    sg13g2_IOPadIn        pad_slink_ddr7_i            (.pad(slink_ddr7_i),            .p2c(soc_slink_ddr_i[0][7]));
    sg13g2_IOPadOut16mA   pad_slink_ddr0_0            (.pad(slink_ddr0_o),            .c2p(soc_slink_ddr_o[0][0]));
    sg13g2_IOPadOut16mA   pad_slink_ddr1_0            (.pad(slink_ddr1_o),            .c2p(soc_slink_ddr_o[0][1]));
    sg13g2_IOPadOut16mA   pad_slink_ddr2_0            (.pad(slink_ddr2_o),            .c2p(soc_slink_ddr_o[0][2]));
    sg13g2_IOPadOut16mA   pad_slink_ddr3_0            (.pad(slink_ddr3_o),            .c2p(soc_slink_ddr_o[0][3]));
    sg13g2_IOPadOut16mA   pad_slink_ddr4_0            (.pad(slink_ddr4_o),            .c2p(soc_slink_ddr_o[0][4]));
    sg13g2_IOPadOut16mA   pad_slink_ddr5_0            (.pad(slink_ddr5_o),            .c2p(soc_slink_ddr_o[0][5]));
    sg13g2_IOPadOut16mA   pad_slink_ddr6_0            (.pad(slink_ddr6_o),            .c2p(soc_slink_ddr_o[0][6]));
    sg13g2_IOPadOut16mA   pad_slink_ddr7_0            (.pad(slink_ddr7_o),            .c2p(soc_slink_ddr_o[0][7]));
    sg13g2_IOPadIn        pad_slink_credit_recv_clk_i (.pad(slink_credit_recv_clk_i), .p2c(soc_slink_credit_recv_clk_i));
    sg13g2_IOPadOut16mA   pad_slink_credit_rtrn_clk_o (.pad(slink_credit_rtrn_clk_o), .c2p(soc_slink_credit_rtrn_clk_o));


    sg13g2_IOPadInOut30mA pad_gpio0_io     (.pad(gpio0_io),  .c2p(soc_gpio_o[0]),  .p2c(soc_gpio_i[0]),  .c2p_en(soc_gpio_out_en_o[0]));
    sg13g2_IOPadInOut30mA pad_gpio1_io     (.pad(gpio1_io),  .c2p(soc_gpio_o[1]),  .p2c(soc_gpio_i[1]),  .c2p_en(soc_gpio_out_en_o[1]));
    sg13g2_IOPadInOut30mA pad_gpio2_io     (.pad(gpio2_io),  .c2p(soc_gpio_o[2]),  .p2c(soc_gpio_i[2]),  .c2p_en(soc_gpio_out_en_o[2]));
    sg13g2_IOPadInOut30mA pad_gpio3_io     (.pad(gpio3_io),  .c2p(soc_gpio_o[3]),  .p2c(soc_gpio_i[3]),  .c2p_en(soc_gpio_out_en_o[3]));
    sg13g2_IOPadInOut30mA pad_gpio4_io     (.pad(gpio4_io),  .c2p(soc_gpio_o[4]),  .p2c(soc_gpio_i[4]),  .c2p_en(soc_gpio_out_en_o[4]));
    sg13g2_IOPadInOut30mA pad_gpio5_io     (.pad(gpio5_io),  .c2p(soc_gpio_o[5]),  .p2c(soc_gpio_i[5]),  .c2p_en(soc_gpio_out_en_o[5]));
    sg13g2_IOPadInOut30mA pad_gpio6_io     (.pad(gpio6_io),  .c2p(soc_gpio_o[6]),  .p2c(soc_gpio_i[6]),  .c2p_en(soc_gpio_out_en_o[6]));
    sg13g2_IOPadInOut30mA pad_gpio7_io     (.pad(gpio7_io),  .c2p(soc_gpio_o[7]),  .p2c(soc_gpio_i[7]),  .c2p_en(soc_gpio_out_en_o[7]));
    sg13g2_IOPadInOut30mA pad_gpio8_io     (.pad(gpio8_io),  .c2p(soc_gpio_o[8]),  .p2c(soc_gpio_i[8]),  .c2p_en(soc_gpio_out_en_o[8]));
    sg13g2_IOPadInOut30mA pad_gpio9_io     (.pad(gpio9_io),  .c2p(soc_gpio_o[9]),  .p2c(soc_gpio_i[9]),  .c2p_en(soc_gpio_out_en_o[9]));
    sg13g2_IOPadInOut30mA pad_gpio10_io    (.pad(gpio10_io), .c2p(soc_gpio_o[10]), .p2c(soc_gpio_i[10]), .c2p_en(soc_gpio_out_en_o[10]));
    sg13g2_IOPadInOut30mA pad_gpio11_io    (.pad(gpio11_io), .c2p(soc_gpio_o[11]), .p2c(soc_gpio_i[11]), .c2p_en(soc_gpio_out_en_o[11]));
    sg13g2_IOPadInOut30mA pad_gpio12_io    (.pad(gpio12_io), .c2p(soc_gpio_o[12]), .p2c(soc_gpio_i[12]), .c2p_en(soc_gpio_out_en_o[12]));
    sg13g2_IOPadInOut30mA pad_gpio13_io    (.pad(gpio13_io), .c2p(soc_gpio_o[13]), .p2c(soc_gpio_i[13]), .c2p_en(soc_gpio_out_en_o[13]));
    sg13g2_IOPadInOut30mA pad_gpio14_io    (.pad(gpio14_io), .c2p(soc_gpio_o[14]), .p2c(soc_gpio_i[14]), .c2p_en(soc_gpio_out_en_o[14]));
    sg13g2_IOPadInOut30mA pad_gpio15_io    (.pad(gpio15_io), .c2p(soc_gpio_o[15]), .p2c(soc_gpio_i[15]), .c2p_en(soc_gpio_out_en_o[15]));


    (* dont_touch = "true" *)sg13g2_IOPadVdd pad_vdd0();
    (* dont_touch = "true" *)sg13g2_IOPadVdd pad_vdd1();
    (* dont_touch = "true" *)sg13g2_IOPadVdd pad_vdd2();
    (* dont_touch = "true" *)sg13g2_IOPadVdd pad_vdd3();

    (* dont_touch = "true" *)sg13g2_IOPadVss pad_vss0();
    (* dont_touch = "true" *)sg13g2_IOPadVss pad_vss1();
    (* dont_touch = "true" *)sg13g2_IOPadVss pad_vss2();
    (* dont_touch = "true" *)sg13g2_IOPadVss pad_vss3();

    (* dont_touch = "true" *)sg13g2_IOPadIOVdd pad_vddio0();
    (* dont_touch = "true" *)sg13g2_IOPadIOVdd pad_vddio1();
    (* dont_touch = "true" *)sg13g2_IOPadIOVdd pad_vddio2();
    (* dont_touch = "true" *)sg13g2_IOPadIOVdd pad_vddio3();

    (* dont_touch = "true" *)sg13g2_IOPadIOVss pad_vssio0();
    (* dont_touch = "true" *)sg13g2_IOPadIOVss pad_vssio1();
    (* dont_touch = "true" *)sg13g2_IOPadIOVss pad_vssio2();
    (* dont_touch = "true" *)sg13g2_IOPadIOVss pad_vssio3();

  croc_soc #(
    .GpioCount        ( GpioCount        ),
    .SlinkNumChannels ( SlinkNumChannels ),
    .SlinkNumLanes    ( SlinkNumLanes    )
  )
  i_croc_soc (
    .clk_i          ( soc_clk_i      ),
    .rst_ni         ( soc_rst_ni     ),
    .ref_clk_i      ( soc_ref_clk_i  ),
    .testmode_i     ( soc_testmode_i ),
    .status_o       ( soc_status_o   ),

    .jtag_tck_i     ( soc_jtag_tck_i   ),
    .jtag_tdi_i     ( soc_jtag_tdi_i   ),
    .jtag_tdo_o     ( soc_jtag_tdo_o   ),
    .jtag_tms_i     ( soc_jtag_tms_i   ),
    .jtag_trst_ni   ( soc_jtag_trst_ni ),

    .uart_rx_i      ( soc_uart_rx_i ),
    .uart_tx_o      ( soc_uart_tx_o ),

    .gpio_i         ( soc_gpio_i        ),
    .gpio_o         ( soc_gpio_o        ),
    .gpio_out_en_o  ( soc_gpio_out_en_o ),

    .slink_ddr_rcv_clk_i      ( soc_slink_ddr_rcv_clk_i     ),    
    .slink_ddr_rcv_clk_o      ( soc_slink_ddr_rcv_clk_o     ), 
  
    .slink_ddr_i              ( soc_slink_ddr_i             ),            
    .slink_ddr_o              ( soc_slink_ddr_o             ), 

    .slink_credit_recv_clk_i  ( soc_slink_credit_recv_clk_i ),
    .slink_credit_rtrn_clk_o  ( soc_slink_credit_rtrn_clk_o )
  );

endmodule

// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Fabian Aegerter         <faegerter@ethz.ch>
// Llorenç Muela Hausmann  <lmuela@ethz.ch>

#include "serial_link.h"
#include "util.h"
#include "config.h"


//TODO add a running register to the IP and then check this register if it is running.
//Otherwise we'd propably corrupt the data.

_Bool slink_set_node_id(uint8_t id){
    if(id >= 16){
        return 0;
    }
    *reg8(SLINK_CFG_BASE_ADDR, SLINK_REG_NODE_ID_REG_OFFSET) = id;
    return 1;
}

uint8_t slink_get_node_id(){
    return *reg8(SLINK_CFG_BASE_ADDR, SLINK_REG_NODE_ID_REG_OFFSET);
}

_Bool slink_set_tx_clk_div(uint16_t clk_div){
    if(clk_div >= SLINK_MAX_TX_CLK_DIV || clk_div == 0){
        return 0;
    }
    *reg32(SLINK_CFG_BASE_ADDR, SLINK_REG_TX_PHY_CLK_DIV_0_REG_OFFSET) = clk_div;
    return 1;
}

uint16_t slink_get_tx_clk_div(){
    return (uint16_t) *reg32(SLINK_CFG_BASE_ADDR, SLINK_REG_TX_PHY_CLK_DIV_0_REG_OFFSET);
}

_Bool slink_set_tx_clk_start(uint16_t clk_start){
    if(clk_start >= SLINK_MAX_TX_CLK_DIV){
        return 0;
    }
    *reg32(SLINK_CFG_BASE_ADDR, SLINK_REG_TX_PHY_CLK_START_0_REG_OFFSET) = clk_start;
    return 1;
}

uint16_t slink_get_tx_clk_start(){
    return (uint16_t) *reg32(SLINK_CFG_BASE_ADDR, SLINK_REG_TX_PHY_CLK_START_0_REG_OFFSET);
}

_Bool slink_set_tx_clk_end(uint16_t clk_end){
    if(clk_end >= SLINK_MAX_TX_CLK_DIV){
        return 0;
    }
    *reg32(SLINK_CFG_BASE_ADDR, SLINK_REG_TX_PHY_CLK_END_0_REG_OFFSET) = clk_end;
    return 1;
}

uint16_t slink_get_tx_clk_end(){
    return (uint16_t) *reg32(SLINK_CFG_BASE_ADDR, SLINK_REG_TX_PHY_CLK_END_0_REG_OFFSET);
}
//TODO check if that is the way we want to do it
void slink_send_data(uint32_t address, uint32_t data){
    *reg32(address, 0) = data;
}

uint32_t slink_read_data(uint32_t address){
    return *reg32(address, 0);
}
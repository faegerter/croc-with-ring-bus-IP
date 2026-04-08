// Copyright 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Fabian Aegerter         <faegerter@ethz.ch>
// Llorenç Muela Hausmann  <lmuela@ethz.ch>


#include "util.h"
#include "serial_link.h"
#include "config.h"
#include "print.h"


#ifndef NUM_NODES
#define NUM_NODES 2
#endif

#ifndef NODE_ID
#error "NODE_ID not defined"
#endif

#if NUM_NODES < 2 || NUM_NODES > 16
#error "NUM_NODES must be between 2 and 16"
#endif

#if NODE_ID < 0 || NODE_ID >= NUM_NODES
#error "NODE_ID must be in range [0, NUM_NODES-1]"
#endif

#define N_TESTS 15

#define ADDR_DEST_SHIFT  28U
#define ADDR_DEST_MASK   (0xFU << ADDR_DEST_SHIFT)

#define TEST_ADDR(dst, src, i) \
    (((uint32_t)(dst) << ADDR_DEST_SHIFT) | \
     (SRAM_BANK_0_BASE_ADDR + ( (uint32_t)(src) * N_TESTS + (uint32_t)(i)) * 2U))

#define TEST_DATA(src, dst, i)   ((uint32_t)((src) << 16 | (dst) << 8 | (i)))

int main() {

    while(!slink_set_node_id(NODE_ID));

    if(slink_get_node_id() != NODE_ID){
        printf("Node ID Verification Failed\n");
        return 0;
    }

    uint32_t compare_data[NUM_NODES-1][N_TESTS];

    uint32_t i_idx = 0;;
    for(int i = 0; i < NUM_NODES; i++){ 
        if(i == NODE_ID){
            continue;
        }
        for(int j = 0; j < N_TESTS; j++){
            uint32_t addr = TEST_ADDR(i, NODE_ID, j);
            uint32_t data = TEST_DATA(NODE_ID, i, j);
            slink_send_data(addr, data);
            compare_data[i_idx][j] = data; 
        }
        i_idx++;
    }
    
    i_idx = 0;
    uint32_t errors = 0;

    for(int i = 0; i < NUM_NODES; i++){
        if(i == NODE_ID){
            continue;
        }
        for(int j = 0; j < N_TESTS; j++){
            uint32_t addr = TEST_ADDR(i, NODE_ID, j);
            if(slink_read_data(addr) != compare_data[i_idx][j]){
                errors++;
            }
        }
        i_idx++;
    }
    if(errors > 0){
        printf("Serial Link Test Failed\n");
        printf("Number of Errors: %x\n", errors);
        return 0;
    }

    printf("Serial Link Test Success!!\n");

    return 1;
}


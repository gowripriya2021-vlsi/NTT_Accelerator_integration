// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd.
// See LICENSE.incore for More details
/*--------------------------------------------------------------------------------------------------
    Author: Babu P S
    Email id: info@incoresemi.com
--------------------------------------------------------------------------------------------------*/
package tb_spi ;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import clock_divider :: *;
import TriState      :: *;

// `include "Logger.bsv"
`include "spi.defines"

import spi          :: * ;
import apb          :: * ;
import StmtFSM      :: * ;
import DCBus        :: * ;
import Connectable  :: * ;
import Semi_FIFOF   :: * ;

`define clk_Src               1
`define stup_dly_en           0
`define stup_dly_val          0
`define hold_dly_en           0
`define hold_dly_val          0
`define xfer_dly_en           0
`define xfer_dly_val          0

`define datasize              32
`define paddr                 32
`define base                 'h20000
`define cpol                 'h0
`define cpha                 'h0
`define ctrler               'h1
`define lsb1st               'h0
`define idle_mosi            'h0
`define nss_pulse            'h0
`define duplex               'h0
`define is_rx_1st            'h0
`define tx_total_bits        'h20
`define rx_total_bits        'h0
`define prescalar_clk        'h4
`define sync_disable         'h0


`define spi_cpha                0
`define spi_cpol                1
`define spi_master              2
//`define spi_rx_start          4
//`define spi_hybrid_start      5
`define spi_rx_first            6
`define spi_lsbfirst            7
//`define spi_ssi               8
//`define spi_ssm               9
`define spi_fifo_clr           10
`define spi_crc_length         12
`define spi_crc_enable         13
`define spi_duplex             14
`define spi_async_disable      15
`define spi_tx_total_bits      16
`define spi_rx_total_bits      24


//`define spi_rx_dma_en         0
//`define spi_tx_dma_en         1
//`define spi_ssoe              2
`define spi_nss_pulse           3
`define spi_idle_mosi           4
`define spi_err_int_en          5
`define spi_rx_ne_int_en        6
`define spi_tx_int_en           7
//`define spi_data_size         8
`define spi_frxth              12
//`define spi_ldma_rx          13
//`define spi_ldma_tx          14
`define spi_reflect_crc_in     16
`define spi_reflect_crc_out    17
`define spi_slave_selector     24

`define spi_dly_clk_src         0
`define spi_dly_setup_en        1
`define spi_dly_hold_en         2
`define spi_dly_xfer_en         3
`define spi_dly_setup_dur       8
`define spi_dly_hold_dur       16
`define spi_dly_xfer_dur       24

`define dr1_const      'hD1ADB1EF
`define dr2_const      'hF2DEF2CE
`define dr3_const      'hD3ADF3DE
`define dr4_const      'hD4ADF4CE
`define dr5_const      'hB5EFD5AD

typedef `rx_total_bits RXLEN;

(*synthesize*)
/*doc:module: implements the SPI as APB Interface */
module mkinst_spi_apb(Ifc_spi_apb#(`PDATASIZE, `PADDR, 0,`SLAVES_SERVED, `TXFIFO_DEPTH));
    let core_clock<-exposeCurrentClock;
    let core_reset<-exposeCurrentReset;
    let ifc();
    mkspi_apb#(`base, core_clock, core_reset) _temp(ifc);
    return ifc;
endmodule:mkinst_spi_apb

/*doc:module: A Simple Testbench that performs
1. Setting all input values to multiple channels
2. runs both channels simulataneously and captures interrupts
3. Stops a running SPI
4. Tries to access not-allowed channels & registers
 */
module mkTb(Empty);
    let mod <- mkinst_spi_apb;

    Reg#(Bool) block_reporting_cipo <- mkReg(True);
    Reg#(Bool) block_reporting_copi <- mkReg(True);
    Reg#(int)  iter      <- mkReg (0);
    Reg#(int)  data_full <- mkReg (0);
    Reg#(int)  bytshift  <- mkReg (0);
    Reg#(Bit#(8)) cipo_data  <- mkReg(0);
    Reg#(Bit#(32)) drx_reg  <- mkReg(0);
    Reg#(Bit#(288)) copi_data_block  <- mkReg(0);
    Reg#(Bool) read_now_cipo <- mkReg( False);
    Reg#(Bool) send_now_copi <- mkReg( False);
    Reg#(int)  data_send <- mkReg (0);
    Reg#(Bit#(`datasize)) stat_reg_tx <- mkReg(0);
    Reg#(Bit#(`datasize)) stat_reg_rx <- mkReg(0);
    Reg#(Bit#(16)) rg_prescalar <- mkReg(0);
    Reg#(bit)  rg_ncs <- mkReg(1);
    Bit#(2) mode = (`cpol << 1 | `cpha);
    Wire#(bit) ncs <- mkDWire(1);
    bit ref_clk = (mode == 1 || mode == 2) ? 1 : 0 ;

    Ifc_clock_divider#(16) clk_divider <- mkclock_divider;
    Ifc_apb_master_xactor#(`paddr,`datasize,0) master <- mkapb_master_xactor;

    TriState#(Bit#(`SLAVES_SERVED)) ncs_io <- mkTriState(unpack(`ctrler), zeroExtend(rg_ncs));
    TriState#(Bit#(1)) sclk_io <- mkTriState(unpack(`ctrler), clk_divider.get.clk_pol);
    TriState#(Bit#(1)) cipo_io <- mkTriState(!unpack(`ctrler), truncateLSB(copi_data_block));
    TriState#(Bit#(1)) copi_io <- mkTriState(unpack(`ctrler), truncateLSB(copi_data_block));

    mkConnection(master.apb_side,mod.slave);
    mkConnection(mod.device.io.sclk , sclk_io.io );
    mkConnection(mod.device.io.ncs  , ncs_io.io  );
    mkConnection(mod.device.io.copi , copi_io.io );
    mkConnection(mod.device.io.cipo , cipo_io.io );

    `include "tb_common.bsv"
    Bit#(32) ctrl_reg[2];

    ctrl_reg[0]= ( `rx_total_bits << `spi_rx_total_bits | `tx_total_bits << `spi_tx_total_bits |
                   `sync_disable << `spi_async_disable  | `is_rx_1st << `spi_rx_first |
                   `lsb1st << `spi_lsbfirst | `ctrler << `spi_master |
                   `cpol << `spi_cpol | `cpha << `spi_cpha );

    ctrl_reg[1]= ( 0 << `spi_slave_selector | `idle_mosi << `spi_idle_mosi );

    Stmt delay_states = (
        seq
            fn_send_write(`base + `spi_delay_reg, ( `clk_Src << `spi_dly_clk_src |
            `hold_dly_val << `spi_dly_hold_dur  | `hold_dly_en << `spi_dly_hold_en  |
            `stup_dly_val << `spi_dly_setup_dur | `stup_dly_en << `spi_dly_setup_en |
            `xfer_dly_val << `spi_dly_xfer_dur  | `xfer_dly_en << `spi_dly_xfer_en  ), '1);
            fn_fail_on_apb_error(1);
        endseq
    );

    Stmt clear_fifo = (
        seq
            fn_send_write(`base + `spi_prescalar_reg, `prescalar_clk,'1);
            fn_fail_on_apb_error(1);

            /*doc:note: set config register 1 */
            fn_send_write(`base + `spi_control_config_1, (ctrl_reg[0] | 1 << `spi_fifo_clr ) , '1);
            fn_fail_on_apb_error(2);
            delay(10);

            /*doc:note: set config register 2 */
            fn_send_write(`base + `spi_control_config_2,ctrl_reg[1],'1);
            fn_fail_on_apb_error(3);

            fn_send_read(`base +`spi_control_config_2);
            fn_checknfail_on_apb_error(4,ctrl_reg[1]);
        endseq
    );

	Stmt send_data = (
        seq
            while(!block_reporting_cipo && data_send < `tx_total_bits)
            seq
                fn_send_read(`base +`spi_status_reg);
                action
                    let lv_stat_val <- fn_ret_val;
                    stat_reg_tx <= lv_stat_val;
                endaction
                while((stat_reg_tx & 2) == 0)
                seq
                    delay(60);
                    fn_send_read(`base +`spi_status_reg);
                    action
                        let new_lv_val <- fn_ret_val;
                        stat_reg_tx <= new_lv_val;
                    endaction
                endseq
                fn_send_write(`base + `spi_data_reg_tx, `dr1_const,'1);
                fn_fail_on_apb_error(1);
                action
                    $display("[%8d] Slave Sent %x ",$time, `dr1_const);
                    data_send <= data_send + 32;
                endaction
            endseq
        endseq
    );

    Stmt recv_data = (
        seq
            while(!block_reporting_copi && data_full < `rx_total_bits)
            seq
                fn_send_read(`base +`spi_status_reg);
                action
                    let lv_stat_val <- fn_ret_val;
                    stat_reg_rx <= lv_stat_val;
                endaction
                while((stat_reg_rx & 1) == 0)
                seq
                    delay(60);
                    fn_send_read(`base +`spi_status_reg);
                    action
                        let new_lv_val <- fn_ret_val;
                        stat_reg_rx <= new_lv_val;
                    endaction
                endseq
                fn_send_read(`base +`spi_data_reg_rx);
                action
                    let lv_recv_val <- fn_ret_val;
                    $display("[%8d] Received %x ",$time, lv_recv_val);
                    data_full <= data_full + 32;
                endaction
            endseq
        endseq
    );

    Stmt end_transaction = (
        seq
            rg_ncs <= 1;
            delay(50);
            clk_divider.set.divisor(0);
        endseq
    );

    Stmt ctrl_full_duplex_test = (
        par
            seq
                delay_states;

                fn_send_write(`base + `spi_control_config_1, ( ctrl_reg[0] | (1<< `spi_duplex )), '1);
                fn_fail_on_apb_error(3);
                delay(10);

                copi_data_block <= `dr3_const << 224 | `dr2_const << 192 |`dr1_const << 160 |
                                   `dr5_const << 128 | `dr4_const << 96  |`dr3_const << 64  |
                                   `dr2_const << 32  | `dr1_const;

                fn_send_write(`base + `spi_en, 1,'1);
                fn_fail_on_apb_error(1);
                delay(10);

                block_reporting_cipo <= False;
            endseq

            seq
                fn_send_write(`base + `spi_data_reg_tx, `dr1_const,'1);
                fn_fail_on_apb_error(1);
                delay(50);

                block_reporting_cipo <= False;
                iter <= 0;
            endseq

        endpar
    );

    Stmt periph_full_duplex_test = (
        seq
            fn_send_write(`base + `spi_control_config_1, ( ctrl_reg[0] | (1 << `spi_duplex )), '1);
            fn_fail_on_apb_error(3);
            delay(10);

            fn_send_write(`base + `spi_data_reg_tx, `dr1_const,'1);
            fn_fail_on_apb_error(1);
            data_send <= data_send + 32;

            block_reporting_cipo <= False;
            iter <= 0;

            copi_data_block <= `dr4_const << 256 | `dr3_const << 224 | `dr2_const << 192 |
                               `dr1_const << 160 | `dr5_const << 128 | `dr4_const << 96  |
                               `dr3_const << 64  | `dr2_const << 32  | `dr1_const;
            delay(1);
            block_reporting_copi <= False;

            fn_send_write(`base + `spi_en, 1,'1);
            fn_fail_on_apb_error(1);
            delay(10);

            rg_ncs <= 0;
            clk_divider.set.clk_pol(`cpol);
            clk_divider.set.divisor(10);
        endseq
    );

    Stmt ctrl_half_duplex_test = (
        seq
            delay_states;

            fn_send_write(`base + `spi_control_config_2, ( ctrl_reg[1] | `nss_pulse << `spi_nss_pulse |
                            1 << `spi_reflect_crc_in | 1 << `spi_reflect_crc_out ), '1);
            fn_fail_on_apb_error(1);
            delay(10);

            fn_send_write(`base + `spi_control_config_1, ( ctrl_reg[0] | 0 << `spi_duplex |
                            0 << `spi_crc_enable | 0 << `spi_crc_length ), '1);
            fn_fail_on_apb_error(2);
            delay(10);

            //fn_send_write(`base + `spi_crc_poly_reg, 'h8005, '1 );
            //fn_fail_on_apb_error(3);
            //delay(20);

            //fn_send_write(`base + `spi_crc_init, 'h00000000, '1 );
            //fn_fail_on_apb_error(3);
            //delay(20);

            fn_send_write(`base + `spi_data_reg_tx, `dr1_const , '1 );
            fn_fail_on_apb_error(4);
            delay(20);

            fn_send_write(`base + `spi_en, 1,'1);
            fn_fail_on_apb_error(5);

            block_reporting_copi <= False;
            iter <= 0;
            delay(60);

            copi_data_block <= `dr4_const << 256 | `dr3_const << 224 | `dr2_const << 192 |
                               `dr1_const << 160 | `dr5_const << 128 | `dr4_const << 96  |
                               `dr3_const << 64  | `dr2_const << 32  | `dr1_const;
            delay(1);
            block_reporting_cipo <= False;
        endseq
    );
	
    Stmt periph_half_duplex_test = (
        seq
            fn_send_write(`base + `spi_control_config_2, ( ctrl_reg[1] | 1 << `spi_nss_pulse ), '1);
            fn_fail_on_apb_error(2);

            fn_send_write(`base + `spi_control_config_1, ( ctrl_reg[0] | 0 << `spi_duplex ), '1);
            fn_fail_on_apb_error(3);
            delay(100);

            fn_send_write(`base + `spi_data_reg_tx, `dr2_const,'1);
            fn_fail_on_apb_error(4);
            data_send <= data_send + 32;
            delay(20);

            block_reporting_cipo <= False;
            iter <= 0;

            copi_data_block <= `dr4_const << 256 | `dr3_const << 224 | `dr2_const << 192 |
                               `dr1_const << 160 | `dr5_const << 128 | `dr4_const << 96  |
                               `dr3_const << 64  | `dr2_const << 32  | `dr1_const ;
            delay(1);
            block_reporting_copi <= False;

            fn_send_write(`base + `spi_en, 1,'1);
            fn_fail_on_apb_error(1);
            delay(10);

            rg_ncs <= 0;
            clk_divider.set.clk_pol(`cpol);
            clk_divider.set.divisor(10);
        endseq
    );

    Stmt wait4_completion = (
        seq
            fn_send_read(`base +`spi_status_reg);
            action
                let lv_stat_val <- fn_ret_val;
                stat_reg_rx <= lv_stat_val;
            endaction
            while((stat_reg_rx & 'h800) != 0)
            seq
                delay(200);
                fn_send_read(`base +`spi_status_reg);
                action
                    let new_lv_val <- fn_ret_val;
                    stat_reg_rx <= new_lv_val;
                endaction
            endseq
        endseq
    );

    (* fire_when_enabled *)
    rule rl_copi_drive(rg_ncs == 0 && copi_data_block != '0 && !block_reporting_copi);
        if(clk_divider.get.clk_pol == ref_clk && send_now_copi) begin
            copi_data_block <= copi_data_block << 1;
            send_now_copi   <= False;
        end
        else if(clk_divider.get.clk_pol != ref_clk) begin
            send_now_copi   <= True ;
        end
    endrule

    rule rl_cipo_monitor(rg_ncs == 0 && !block_reporting_cipo);
        Bit#(2) mode = (`cpol << 1 | `cpha);
        bit ref_clk = (mode == 0 || mode == 3) ? 0 : 1 ;
        if(clk_divider.get.clk_pol == ref_clk && read_now_cipo) begin
        if(iter ==7) begin
            drx_reg   <=  drx_reg | zeroExtend(cipo_data | zeroExtend(cipo_io) << 7) << bytshift;
            bytshift  <= bytshift + 8;
            iter      <= 0;
            cipo_data <= 0;
        end else begin
    //       $display("[ %8d] SPI Tb - Received Data = %b",$time,mod.device.io.mosi);
            iter <= iter + 1;
            cipo_data <= cipo_data | zeroExtend(cipo_io) << (iter) ;
        end
            read_now_cipo <= False;
        end else if(clk_divider.get.clk_pol != ref_clk) begin
            read_now_cipo <= True;
        end
    endrule

    rule rl_data_aggregation(bytshift==32);
        bytshift <= 0;
        case (drx_reg)
            `dr1_const: begin
                            block_reporting_cipo <= True;
                            $display("[%8d] Master Transmitted  %x of dr1 ", $time, drx_reg);
                        end
            `dr2_const: $display("[%8d] Master Transmitted  %x of dr2 ",$time,drx_reg);
            `dr3_const: $display("[%8d] Master Transmitted  %x of dr3 ",$time,drx_reg);
            `dr4_const: $display("[%8d] Master Transmitted  %x of dr4 ",$time,drx_reg);
            `dr5_const: $display("[%8d] Master Transmitted  %x of dr5 ",$time,drx_reg);
            default: $display("[%8d] Master Transmitted  %x ",$time,drx_reg);
        endcase
        drx_reg <= 0;
    endrule

    Stmt access_errors = (
        seq
            //fn_send_write(`base + `spi_tx_crc_reg, '1 , '1);
            //fn_fail_on_apb_error(3);
            //delay(100);
            fn_send_read( `base + `spi_tx_crc_reg);
            fn_fail_on_apb_error(21);
            delay(15);

            fn_send_write(`base + `spi_control_config_1, (ctrl_reg[0] | 1 << `spi_fifo_clr ) , '1);
            fn_fail_on_apb_error(2);
            delay(10);
        endseq
    );

    mkAutoFSM(
        seq
            //$display("[ %8d] Full duplex test ",$time);
            //clear_fifo;
            //delay(50);
            //full_duplex_test;
            //delay(20);
            //recv_data;

            $display("[ %8d] Half duplex test ",$time);
            clear_fifo;
            delay(10);
            ctrl_half_duplex_test;
            delay(20);
            recv_data;
            wait4_completion;
            delay(10);
            //access_errors;
            $display("[ %8d] Exiting SPI Testbench",$time);
            end_transaction;
            $finish(0);
        endseq
    );

endmodule
endpackage: tb_spi

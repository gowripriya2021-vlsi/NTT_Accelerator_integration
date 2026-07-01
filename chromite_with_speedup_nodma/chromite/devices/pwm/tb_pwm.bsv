// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
package tb_pwm ;
import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;

// `include "Logger.bsv"
`include "pwm.defines"

import pwm         :: * ;
import apb          :: * ;
import StmtFSM      :: * ;
import DCBus        :: * ;
import Connectable  :: * ;
import Semi_FIFOF   :: * ;

`define datasize 32
`define channels 3
`define paddr    16
`define base    'h300
`define PWMWIDTH 16
`define comp_out_en 'h1

`define test_pwm_period 'h60
`define test_duty_cycle 'h30
`define deadband_delay  'h5
`define clk_source      'h1
`define clk_prescaler   'h10

`define pwm_load_val    12
`define pwm_rise_int     8
`define pwm_fall_int     7
`define pwm_hf_prd_int   6
`define pwm_cmp_out_en   5
`define pwm_cntr_reset   4
`define pwm_out_pol      3
`define pwm_out_en       2
`define pwm_start        1
`define pwm_en           0

(*synthesize*)
/*doc:module: implements the PWM as APB Interface */
module mkinst_pwm_apb(Ifc_pwm_apb#(`paddr, `datasize, 0, `PWMWIDTH, `channels, `comp_out_en));
	let core_clock<-exposeCurrentClock;
	let core_reset<-exposeCurrentReset;
    let ifc();
    mkpwm_apb#(`base, core_clock, core_reset, core_clock, core_reset) _temp(ifc);
    return ifc;
endmodule:mkinst_pwm_apb

/*doc:module: A Simple Testbench that performs
1. Setting all input values to multiple channels
2. runs both channels simulataneously and captures interrupts
3. Stops a running PWM
4. Tries to access not-allowed channels & registers */
module mkTb(Empty);
    let mod <- mkinst_pwm_apb;

    Reg#(Bool) block_reporting <- mkReg(False);
    Reg#(int)  iter <- mkReg (0);

    int channel_num[`channels];
    for(Integer i= 0;i < `channels; i=i+1)
        channel_num[i] = fromInteger(i) << 4;

    Ifc_apb_master_xactor#(`paddr,`datasize,0) master <- mkapb_master_xactor;
    mkConnection(master.apb_side,mod.slave);

    `include "tb_common.bsv"
    Bit#(32) ctrl_reg[`channels];
    ctrl_reg[0]=((0 << `pwm_rise_int  ) | (0 << `pwm_fall_int)   | (0 << `pwm_hf_prd_int) |
                  (0 << `pwm_cntr_reset) | (1 << `pwm_out_pol   ));

    ctrl_reg[1]=((0 << `pwm_rise_int  ) | (0 << `pwm_fall_int)   | (0 << `pwm_hf_prd_int) |
                  (0 << `pwm_cntr_reset) | (1 << `pwm_out_pol   ));

    Stmt set_values = (
        seq
            /*doc:note: set clock prescaler and source */
            fn_send_write(`base + `Pwm_clock, (`clk_prescaler<<1 | `clk_source), '1);
            fn_fail_on_apb_error(1);
            delay(10);
            fn_send_read(`base + `Pwm_clock);
            fn_checknfail_on_apb_error(2,(`clk_prescaler<<1 | `clk_source));

            /*doc:note: set Period */
            fn_send_write(`base + truncate(pack(channel_num[0])) + `Pwm_period,`test_pwm_period,'1);
            fn_fail_on_apb_error(3);
            fn_send_read(`base +truncate(pack(channel_num[0])) + `Pwm_period);
            fn_checknfail_on_apb_error(4,`test_pwm_period);

            /*doc:note: set DutyCycle */
            fn_send_write(`base + truncate(pack(channel_num[0])) + `Pwm_duty_cycle,`test_duty_cycle,'1);
            fn_fail_on_apb_error(5);
            fn_send_read(`base + truncate(pack(channel_num[0])) +`Pwm_duty_cycle);
            fn_checknfail_on_apb_error(6,`test_duty_cycle);

            /*doc:note: set deadband */
            fn_send_write(`base + truncate(pack(channel_num[0])) +`Pwm_deadband_delay,`deadband_delay,'1);
            fn_fail_on_apb_error(7);
            fn_send_read(`base + truncate(pack(channel_num[0])) +`Pwm_deadband_delay);
            fn_checknfail_on_apb_error(8,`deadband_delay);

            /*doc:note: set Period */
            fn_send_write(`base + truncate(pack(channel_num[1])) + `Pwm_period,`test_pwm_period/3,'1);
            fn_fail_on_apb_error(9);
            fn_send_read(`base + truncate(pack(channel_num[1])) +`Pwm_period);
            fn_checknfail_on_apb_error(10,`test_pwm_period/3);

            /*doc:note: set DutyCycle */
            fn_send_write(`base + truncate(pack(channel_num[1])) + `Pwm_duty_cycle,`test_duty_cycle/2,'1);
            fn_fail_on_apb_error(11);
            fn_send_read(`base + truncate(pack(channel_num[1])) +`Pwm_duty_cycle);
            fn_checknfail_on_apb_error(12,`test_duty_cycle/2);

            /*doc:note: set deadband */
            fn_send_write(`base + truncate(pack(channel_num[1])) +`Pwm_deadband_delay,`deadband_delay,'1);
            fn_fail_on_apb_error(13);
            fn_send_read(`base + truncate(pack(channel_num[1])) +`Pwm_deadband_delay);
            fn_checknfail_on_apb_error(14,`deadband_delay);

        endseq
    );
    Stmt wait_states = (
        seq
            delay(1800);
        endseq
    );
    Stmt load_pwm = (
        seq
            /*doc:note: set control bits */
            fn_send_write(`base + truncate(pack(channel_num[0])) + `Pwm_control, ctrl_reg[0] | (1 << `pwm_load_val ), '1);
            fn_fail_on_apb_error(15);

            /*doc:note: set control bits */
            fn_send_write(`base + truncate(pack(channel_num[1])) + `Pwm_control, ctrl_reg[1] | (1 << `pwm_load_val ), '1);
            fn_fail_on_apb_error(16);
        endseq
    );
    Stmt enable_pwm = (
        seq
            /*doc:note: set control bits */
            fn_send_write(`base + truncate(pack(channel_num[0])) + `Pwm_control, ctrl_reg[0]
                | 1 << `pwm_en | (1 << `pwm_start) , '1);
            fn_fail_on_apb_error(17);

            /*doc:note: set control bits */
            fn_send_write(`base + truncate(pack(channel_num[1])) + `Pwm_control, ctrl_reg[1]
                | 1 << `pwm_en | (1 << `pwm_start) , '1);
            fn_fail_on_apb_error(18);
        endseq
    );
    Stmt start_pwm = (
        seq
            /*doc:note: set control bits */
            fn_send_write(`base + truncate(pack(channel_num[0])) + `Pwm_control, ctrl_reg[0]
                | 1 << `pwm_en | (1 << `pwm_start) | (1 << `pwm_cmp_out_en) | (1 << `pwm_out_en) , '1);
            fn_fail_on_apb_error(19);

            /*doc:note: set control bits */
            fn_send_write(`base + truncate(pack(channel_num[1])) + `Pwm_control, ctrl_reg[1]
                | 1 << `pwm_en | (1 << `pwm_start) | (1 << `pwm_cmp_out_en) | (1 << `pwm_out_en) , '1);
            fn_fail_on_apb_error(20);
        endseq
    );
    Stmt read_pwm = (
        seq
            /*doc:note: set control bits */
            fn_send_read(`base + truncate(pack(channel_num[0])) + `Pwm_control);
            fn_checknfail_on_apb_error(21, ctrl_reg[0] & 'hEFFF);

            /*doc:note: set control bits  */
            fn_send_read(`base + truncate(pack(channel_num[1])) + `Pwm_control);
            fn_checknfail_on_apb_error(22, ctrl_reg[1] & 'hEFFF);
        endseq
    );

    Stmt reset_pwm = (
        seq
            /*doc:note: set control bits */
            fn_send_write(`base + truncate(pack(channel_num[0])) + `Pwm_control, ctrl_reg[0]
                | 1 << `pwm_en | (1 << `pwm_start) | (1 << `pwm_cntr_reset) , '1);
            fn_fail_on_apb_error(23);

            /*doc:note: set control bits  */
            fn_send_write(`base + truncate(pack(channel_num[1])) + `Pwm_control, ctrl_reg[1]
                | 1 << `pwm_en | (1 << `pwm_start) | (1 << `pwm_cntr_reset) , '1);
            fn_fail_on_apb_error(24);
        endseq
    );

     Stmt unreset_pwm = (
        seq
            /*doc:note: set control bits */
            fn_send_write(`base + truncate(pack(channel_num[0])) + `Pwm_control, (ctrl_reg[0]
                 | (1 << `pwm_start) | 1 << `pwm_en) & ~(1 << `pwm_cntr_reset) , '1);
            fn_fail_on_apb_error(25);

            /*doc:note: set control bits  */
            fn_send_write(`base + truncate(pack(channel_num[1])) + `Pwm_control, (ctrl_reg[1]
                 | (1 << `pwm_start) | 1 << `pwm_en) & ~(1 << `pwm_cntr_reset) , '1);
            fn_fail_on_apb_error(26);
        endseq
    );

    Stmt stop_pwm = (
        seq
            fn_send_write(`base + truncate(pack(channel_num[1])) + `Pwm_control, (ctrl_reg[1] & 'hFFFD), '1);
            fn_fail_on_apb_error(27);
        endseq
    );

    rule interrupt_tracer(pack(mod.device.sb_interrupt) != 0 && !block_reporting );
        $display("[ %8d] Captured INTERRUPT: %b",$time,pack(mod.device.sb_interrupt));
        block_reporting <= True;
        iter <= 15;
        //$finish(0);
    endrule

    rule interrupt_blocker(block_reporting);
        if(iter == 0)
            block_reporting <= False;
        else
            iter <= iter - 1;
    endrule

    Stmt access_errors = (
        seq
        /*doc:note: Access invalid channel  */
            fn_send_read(`base + (4 << 4) + 0);
            fn_pass_on_apb_error(27);

        /*doc:note: Access invalid location of channel 1  */
            fn_send_read(`base + 'h2);
            fn_pass_on_apb_error(28);

        /*doc:note: Write to RO interrupt flags in control reg of ch 1. */
            delay(15);
            fn_send_write( `base + `Pwm_control,'hf03,'1 );
            fn_fail_on_apb_error(29);
            delay(15);
            if( pack(mod.device.sb_interrupt) != 0)
                $display("[ %8d] Captured INTERRUPT: %b",$time,pack(mod.device.sb_interrupt));
        endseq
    );

    mkAutoFSM(seq
        $display("[ %8d] Setting PWM",$time);
        set_values;
        load_pwm;
        $display("[ %8d] Running PWM",$time);
        enable_pwm;
        start_pwm;
        wait_states;
        read_pwm;
        wait_states;
        wait_states;
        $display("[ %8d] Resetting PWM",$time);
        reset_pwm;
        delay(50);
        $display("[ %8d] unResetting PWM",$time);
        unreset_pwm;
        wait_states;
        wait_states;
        $display("[ %8d] Stopping Channel 2 PWM",$time);
        stop_pwm;
        wait_states;
        access_errors;
        $finish(0);
    endseq);

endmodule
endpackage: tb_pwm

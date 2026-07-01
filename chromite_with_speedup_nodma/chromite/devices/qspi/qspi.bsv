// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Thursday 23 April 2020 05:30:48 PM IST
*/

package qspi;

  import ConcatReg ::*;
  import Semi_FIFOF::*;
  import FIFOLevel::*;
  import axi4l::*;
  import axi4::*;
  import apb::*;
  import Connectable ::*;
  import FIFO::*;
  import FIFOF::*;
  import Clocks::*;
  import SpecialFIFOs::*;
  import ClientServer::*;
  import MIMO::*;
  import MIMO_MODIFY::*;
  import DefaultValue ::*;
  import ConfigReg::*;
  import Vector::*;
  import UniqueWrappers::*;
  import DReg::*;
  import BUtils::*;
  import DCBus::*;
  import Reserved::*;
  import qspi_attributes_DCBus::*;
  `include "qspi.defines"
  `include "Logger.bsv"


  /*doc:note: interface combines the axi4-lite interface with qspi controller interface*/
  typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Ifc_qspi_controller#(aw, dw, uw,mem_id, mem_aw, mem_dw, mem_uw))
    Ifc_qspi_axi4l#(type aw, type dw, type uw,type mem_id, type mem_aw, type mem_dw, type mem_uw);

  /*doc:note: interface combines the apb interface with qspi controller interface*/
  typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_qspi_controller#(aw, dw, uw, mem_id, mem_aw, mem_dw, mem_uw))
    Ifc_qspi_apb#(type aw, type dw, type uw, type mem_id, type mem_aw, type mem_dw, type mem_uw);

  /*doc:note: QSPI_out: interface to the flash device*/
  (*always_ready, always_enabled*)
  interface QSPI_out;
    method bit clk_o;
    method Bit#(4) io_o;
    method Bit#(4) io_enable;
    (*prefix=""*)
    method Action io_i ((* port="io_in" *) Bit#(4) io_in);
    method bit ncs_o;
  endinterface:QSPI_out

  /*doc:note: Ifc_qspi_controller : interface to the flash device and processor*/
  interface Ifc_qspi_controller#(numeric type aw,
                                 numeric type dw,
                                 numeric type uw,
                                 numeric type mem_id,
                                 numeric type mem_aw,
                                 numeric type mem_dw,
                                 numeric type mem_uw
                                 );
    interface QSPI_out io;
    method Bit#(6) mv_interrupts; // 0=TOF, 1=SMF, 2=Threshold, 3=TCF, 4=TEF 5 = request_ready
    interface Ifc_axi4_slave#(mem_id,mem_aw, mem_dw, mem_uw) mem_slave;
  endinterface:Ifc_qspi_controller

  //-------------------------------------------------------------------------------------------
  //-------------------------------------------------------------------------------------------
  /*doc:note: struct elements of qspi registers*/
  typedef struct{
    ReservedZero#(3) dcr_res1;
    Bit#(8) dcr_mode_byte;
    Bit#(5) fsize;
    ReservedZero#(5) dcr_res2;
    Bit#(3) csht ;
    ReservedZero#(7) dcr_res3;
    Bit#(1) ckmode ;
  } DCRReg deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(32) data_length;
  } DLRReg deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(32) address;
  } ARReg deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(32) alternate_byte;
  } ABRReg deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(32) mask;
  } PSMKReg deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(32) mat;
  } PSMAReg deriving(Bits, Eq, FShow);

  typedef struct{
    ReservedZero#(16) pir_res1;
    Bit#(16) interval;
  } PIRReg deriving(Bits, Eq, FShow);

  typedef struct{
    ReservedZero#(16) lptr_res1;
    Bit#(16) time_out;
  } LPTRReg deriving(Bits, Eq, FShow);

  /*doc:note: qspi transaction FSM phases*/
  typedef enum {Instruction_phase=0,
    Address_phase=1,
    AlternateByte_phase=2,
    Dummy_phase=3,
    DataRead_phase=4,
    DataWait_phase=5,
    DataWrite_phase=6,
    Idle=7} Phase deriving (Bits,Eq,FShow);


  /*doc:module: MIMO Read-write
  //Action on Read : None // Action on Write : None // Condition on Read : None // Condition on Write : None*/
  //--------------------------------------------------------------------------------------------------------
  module mk_MIMORWSe#(DCRAddr#(aw,o) attr, MIMOConfiguration cfg, Action _act)(IWithDCBus#(DCBus#(aw, dw), MIMO#(4,4,16,Bit#(8))))
    provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(e__, TDiv#(dw, 8), 8)
    );

    MIMO#(4,4,16,Bit#(8)) fifo <-mkMIMO(cfg);
    Reg#(Bit#(32)) x();
    mkReg#(0) inner_reg(x);
    PulseWire wr_written   <- mkPulseWire;
    PulseWire wr_read_done <- mkPulseWire;


    interface DCBus dcbus;
      method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
        Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
        Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
        Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
        if ((req_index == reg_index) && perm) begin
          let {succ, temp} <- fn_adjust_write(addr, data, strobe, pack(x), attr.min, attr.max, attr.mask);
          if(succ) begin
            x <= unpack(temp);
            wr_written.send;
            _act;
            if(strobe==1)begin
              Vector#(4,Bit#(8)) v_temp=newVector();
              v_temp[0]=temp[7:0];
              if(fifo.enqReadyN(1))
                fifo.enq(1,v_temp);
            end
            else if(strobe==3)begin
              Vector#(4,Bit#(8)) v_temp = newVector();
              v_temp[0]= temp[15:8];
              v_temp[1]= temp[7:0];
              if(fifo.enqReadyN(2))
                fifo.enq(2,v_temp);
            end
            else if(strobe==15)begin
              Vector#(4,Bit#(8)) v_temp = newVector();
              v_temp[0]= temp[31:24];
              v_temp[1]= temp[23:16];
              v_temp[2]= temp[15:8];
              v_temp[3]= temp[7:0];
              if(fifo.enqReadyN(4))
                fifo.enq(4,v_temp);
            end
          end
          return (succ);
        end
        else
          return False;
      endmethod:write

      method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
        Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
        Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
        Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
        if ((req_index == reg_index) && perm) begin
          wr_read_done.send;
          if(fifo.deqReadyN(4))
            begin
              let v_temp={fifo.first[0],fifo.first[1],fifo.first[2],fifo.first[3]};
              let temp = fn_adjust_read(addr, size, v_temp, attr.min, attr.max, attr.mask );
              fifo.deq(4);
              return temp;
            end
          else if(fifo.deqReadyN(2))
            begin
              let v_temp={fifo.first[0],fifo.first[1]};
              let temp = fn_adjust_read(addr, size, v_temp, attr.min, attr.max, attr.mask );
              fifo.deq(2);
              return temp;
            end
          else if(fifo.deqReadyN(1))
            begin
              let v_temp=fifo.first[0];
              let temp = fn_adjust_read(addr, size, v_temp, attr.min, attr.max, attr.mask );
              fifo.deq(1);
              return temp;
            end
          else
            return tuple2(False, 0);
        end
        else
          return tuple2(False, 0);
      endmethod:read
    endinterface:dcbus

    interface MIMO device;
      method Action enq(LUInt#(4) count, Vector#(4, Bit#(8)) data);
        if(!wr_written)
          fifo.enq(count,data);
      endmethod
      method Vector#(4, Bit#(8)) first();
        return fifo.first();
      endmethod

      method Action deq(LUInt#(4) count);
        if(!wr_read_done)
          fifo.deq(count);
      endmethod

      method Bool enqReady();
        return fifo.enqReady();
      endmethod

      method Bool enqReadyN(LUInt#(4) count);
        return fifo.enqReadyN(count);
      endmethod

      method Bool deqReady();
        return fifo.deqReady();
      endmethod

      method Bool deqReadyN(LUInt#(4) count);
        return fifo.deqReadyN(count);
      endmethod

      method LUInt#(16) count();
        return fifo.count();
      endmethod

      method Action clear();
        fifo.clear();
      endmethod
    endinterface
  endmodule:mk_MIMORWSe

  // A wrapper to provide just a normal Reg interface and automatically
  // add the CBus interface to the collection. This is the module used
  // in designs (as a normal register would be used).
  module [ModWithDCBus#(aw, dw)] mk_DCBMIMORWSe#(DCRAddr#(aw,o) attr, MIMOConfiguration cfg, Action _act)(MIMO#(4,4,16,Bit#(8)))
    provisos (
      Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
      Add#(a__, o, aw),
      Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
      Add#(dw, b__, 64), // bus side data should be <= 64
      Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
      Add#(e__, TDiv#(dw, 8), 8)
    );
    let ifc();
    collectDCBusIFC#(mk_MIMORWSe(attr, cfg, _act)) _temp(ifc);
    return(ifc);
  endmodule:mk_DCBMIMORWSe


  (*preempts=" rl_data_write_phase, rl_delayed_sr_tcf_signal"*)
  (*preempts=" rl_data_read_phase, rl_delayed_sr_tcf_signal"*)
  //-------------------------------------------------------------
  /*doc:module: mkQspi :qspi implementation Module with Ifc_qspi_controller Interface*/
  module [ModWithDCBus#(aw,dw)] mkQspi(Ifc_qspi_controller#(aw, dw, uw, mem_id, mem_aw, mem_dw, mem_uw))
    provisos (
      Add#(e__, 28, aw),Mul#(32, f__, dw),
      Add#(16, _a, aw),
      Add#(8, _b, dw), // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(dw, _c, 32), // not more than 32 gpios per block
      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(d__, TDiv#(dw, 8), 8),
      Mul#(16, b__, dw),
      Add#(g__, 28, mem_aw),
      Mul#(32, h__, mem_dw),
      Mul#(16, i__, mem_dw),
      Mul#(8, j__, mem_dw)
    );

    /*doc:reg: List of implementation defined Registers*/
    Reg#(bit) rg_clk                  <-mkReg(1);
    Reg#(bit) rg_ddr_clk              <-mkReg(1);
    Reg#(Bit#(8)) rg_clk_counter      <-mkReg(0);
    Reg#(Bit#(8)) rg_ddr_counter      <-mkReg(0);
    Reg#(Bit#(1)) rg_wr_clk_count      <-mkReg(0);
    MIMOConfiguration cfg             =defaultValue;
    cfg.unguarded                     =True;
    Reg#(Phase) rg_phase              <-mkConfigReg(Idle);
    Reg#(Bit#(4)) rg_output           <-mkReg(0);
    Reg#(Bit#(4)) rg_output_en        <-mkReg(0);
    Reg#(Bit#(32)) rg_count_bits      <-mkReg(0);
    Reg#(Bit#(32)) rg_delay_count_bits<-mkReg(0);
    Reg#(Bit#(32)) rg_count_bytes     <-mkReg(0);
    Reg#(Bool) rg_instruction_written <-mkDReg(False);
    Reg#(Bool) rg_address_written     <-mkDReg(False);
    Reg#(Bool) rg_data_written        <-mkDReg(False);
    Reg#(Bool) rg_instruction_sent    <-mkReg(False);
    Reg#(Bit#(1)) rg_ncs              <-mkReg(1);
    Reg#(Bit#(1)) rg_delay_ncs        <-mkReg(1);
    Reg#(Bool) rg_half_cycle_delay    <-mkReg(False);
    Reg#(Bool) rg_read_true           <-mkReg(False);
    Reg#(Bool) rg_first_read          <-mkConfigReg(False);
    Reg#(Bit#(1)) rg_delay_sr_tcf     <- mkReg(0);
    /*doc:wire: List of implementation defined Wires*/
    Wire#(Bool) wr_sdr_clock          <-mkDWire(False);
    Wire#(Bool) wr_ddr_clock          <-mkDWire(False);
    Wire#(Bit#(4)) wr_input           <-mkDWire(0);
    Wire#(Bool) wr_status_read        <-mkDWire(False);
    Wire#(Bool) wr_data_read          <-mkDWire(False);
    /*doc:note: End of implementation defined Registers*/

    //-----------------------------------------------------------------------------------
    /*doc:note: Definition of QSPI registers wih DCBus interface*/
    Reg#(Bit#(1)) rg_sr_busy <-mkConfigReg(0);
    Reg#(Bit#(5)) rg_sr_flevel <-mkConfigReg(0);
    Reg#(Bit#(1)) rg_sr_tof <-mkConfigReg(0);
    Reg#(Bit#(1)) rg_sr_smf <-mkConfigReg(0);
    Reg#(Bit#(1)) rg_sr_ftf <-mkConfigReg(0);
    Reg#(Bit#(1)) rg_sr_tcf <-mkConfigReg(0);
    Reg#(Bit#(1)) rg_sr_tef <-mkConfigReg(0);

    DCRAddr#(addr_width,2) sr_addr = DCRAddr {addr: 'h8, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(Bit#(32)) rg_sr <- mkDCBBypassWireRO(sr_addr);

    DCRAddr#(addr_width,2) dcr_addr = DCRAddr {addr: 'h4, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(DCRReg) rg_dcr <- mkDCBRegRWCond(dcr_addr,unpack(0), rg_sr_busy==0);

    DCRAddr#(addr_width,2) cr_addr = DCRAddr {addr: 'h0, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(CRReg) rg_cr <- mkDCBRegCRRWCond(cr_addr, unpack(0) , rg_sr_busy==0);

    DCRAddr#(addr_width,2) fcr_addr = DCRAddr {addr: 'hC, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(FCRReg) rg_fcr <- mkDCBRegWOCSe(fcr_addr, unpack(0), rg_sr_tef._write(0), rg_delay_sr_tcf._write(0), rg_sr_tcf._write(0), rg_sr_smf._write(0), rg_sr_tof._write(0));

    DCRAddr#(addr_width,2) dlr_addr = DCRAddr {addr: 'h10, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(DLRReg) rg_dlr <- mkDCBRegRWCond(dlr_addr, unpack(0), rg_sr_busy==0);

    DCRAddr#(addr_width,2) ccr_addr = DCRAddr {addr: 'h14, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(CCRReg) rg_ccr <- mkDCBRegRWCondCCRe(ccr_addr, unpack(0), rg_instruction_written._write(True), rg_first_read._write(True), rg_sr_busy==0);

    DCRAddr#(addr_width,2) ar_addr = DCRAddr {addr: 'h18, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(ARReg) rg_ar <- mkDCBRegRWCondSe(ar_addr, unpack(0), rg_address_written._write(True), rg_sr_busy==0 && rg_ccr.fmode!='b11);

    DCRAddr#(addr_width,2) abr_addr = DCRAddr {addr: 'h1C, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(ABRReg) rg_abr <- mkDCBRegRWCond(abr_addr, unpack(0), rg_sr_busy==0);

    DCRAddr#(addr_width,2) dr_addr = DCRAddr {addr: 'h20, min: Sz1, max: Sz4, mask: 2'b11};
    MIMO#(4,4,16,Bit#(8)) fifo <- mk_DCBMIMORWSe(dr_addr, cfg, rg_data_written._write(True));

    DCRAddr#(addr_width,2) psmk_addr = DCRAddr {addr: 'h24, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(PSMKReg) rg_psmk <- mkDCBRegRWCond(psmk_addr, unpack(0), rg_sr_busy==0);

    DCRAddr#(addr_width,2) psma_addr = DCRAddr {addr: 'h28, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(PSMAReg) rg_psma <- mkDCBRegRWCond(psma_addr, unpack(0), rg_sr_busy==0);

    DCRAddr#(addr_width,2) pir_addr = DCRAddr {addr: 'h2C, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(PIRReg) rg_pir <- mkDCBRegRWCond(pir_addr, unpack(0), rg_sr_busy==0);

    DCRAddr#(addr_width,2) lptr_addr = DCRAddr {addr: 'h30, min: Sz1, max: Sz4, mask: 2'b11};
    Reg#(LPTRReg) rg_lptr <- mkDCBRegRWCond(lptr_addr, unpack(0), rg_sr_busy==0);

    /*doc:note: End of Definition of QSPI registers wih DCBus interface*/

    /*doc:reg: List of implementation defined Registers*/
    Reg#(Bit#(5)) rg_mode_byte_counter <- mkReg('d31);
    Reg#(Bool) rg_delay_dummy          <- mkReg(False);
    Reg#(Bool) rg_thres                <- mkReg(False);
    Reg#(Bool) rg_request_ready        <- mkReg(True);
    Reg#(Bit#(8)) rg_count             <- mkReg(0);
    Reg#(bit) rg_ddr_en                <- mkReg(0);
    Reg#(bit) rg_init_mm_xip_delay     <- mkReg(0);
    Reg#(Bit#(32)) rg_mm_data_length   <- mkConfigReg(0);
    Reg#(Bit#(28)) rg_mm_address       <- mkConfigReg(0);
    Reg#(Bit#(28)) rg_prev_addr        <- mkConfigReg(0);
    Reg#(Bit#(32)) rg_dr_val           <- mkReg(0);
    Reg#(Bit#(16)) rg_timecounter      <- mkReg(0);
    Reg#(Bit#(32)) rg_axi4_rd_counter  <- mkReg(0);
    Reg#(Bit#(mem_id))  rg_axi4_rd_arid     <- mkReg(0);
    Reg#(Bit#(mem_uw)) rg_axi4_rd_user     <- mkReg(0);
    Reg#(Bit#(3)) rg_axi4_rd_rsize     <- mkReg(0);

    /*doc:note: List of implementation defined local_variables*/
    Bool lv_ddr_clock      = wr_ddr_clock;
    Bool lv_transfer_cond  = (rg_sr_busy==1 && rg_cr.en==1);
    Bool lv_clock_cond     = ((wr_sdr_clock && rg_ccr.ddrm==0) || (wr_ddr_clock && rg_ccr.ddrm==1));
    Bool lv_qspi_flush     = (rg_cr.en == 0);
    Bit#(1) smf            = 0;
    Bit#(32) lv_counter    = 0;


    Ifc_axi4_slave_xactor#(mem_id, mem_aw, mem_dw, mem_uw) mem_slave_xactor <- mkaxi4_slave_xactor(defaultValue);

    /*doc:rule: this rule collects the read request from Axi4 Bus*/
    rule rl_read_from_bus(rg_mm_data_length == 0 && rg_ccr.fmode=='b11);
      let read_req <- pop_o(mem_slave_xactor.fifo_side.o_rd_addr);
      rg_mm_data_length <= {24'b0,read_req.arlen};
      Axi4_rd_data#(mem_id,mem_dw,mem_uw) resp_pkt;
      resp_pkt.rid = read_req.arid;
      resp_pkt.ruser = read_req.aruser;
      rg_axi4_rd_arid <= read_req.arid;
      rg_axi4_rd_user <= read_req.aruser;
      rg_axi4_rd_rsize <= read_req.arsize;
      rg_mm_address    <= truncate(read_req.araddr);
      resp_pkt.rlast = (read_req.arlen == 0);
      if(fifo.deqReadyN(4) && read_req.arsize== 2) begin
        let v_temp={fifo.first[0],fifo.first[1],fifo.first[2],fifo.first[3]};
        fifo.deq(4);
        resp_pkt.rdata = duplicate(v_temp);
        resp_pkt.rresp = 0;
        if(read_req.arlen == 0) begin
          rg_axi4_rd_counter <= 0;
        end
        else begin
          rg_axi4_rd_counter <= rg_axi4_rd_counter + 4;
        end
      end
      else if(fifo.deqReadyN(2) && read_req.arsize== 1) begin
        let v_temp={fifo.first[0],fifo.first[1]};
        fifo.deq(2);
        resp_pkt.rdata = duplicate(v_temp);
        resp_pkt.rresp = 0;
        if(read_req.arlen == 0) begin
          rg_axi4_rd_counter <= 0;
        end
        else begin
          rg_axi4_rd_counter <= rg_axi4_rd_counter + 2;
        end
      end
      else if(fifo.deqReadyN(1) && read_req.arsize== 1) begin
        let v_temp={fifo.first[0]};
        fifo.deq(1);
        resp_pkt.rdata = duplicate(v_temp);
        resp_pkt.rresp = 0;
        if(read_req.arlen == 0) begin
          rg_axi4_rd_counter <= 0;
        end
        else begin
          rg_axi4_rd_counter <= rg_axi4_rd_counter + 1;
        end
      end
      else begin
        resp_pkt.rresp = 2;
      end
    endrule:rl_read_from_bus

    /*doc:rule: this rule is for burst transactions in memory mapped mode*/
    rule rl_read_from_bus_burst(rg_mm_data_length != 0 && rg_ccr.fmode=='b11);
      Axi4_rd_data#(mem_id,mem_dw,mem_uw) resp_pkt;
      resp_pkt.rid = rg_axi4_rd_arid;
      resp_pkt.ruser = rg_axi4_rd_user;
      resp_pkt.rlast = (rg_axi4_rd_counter == rg_mm_data_length)?True:False;
      if(resp_pkt.rlast == True) begin
        rg_mm_data_length <= 0;
      end
      if(fifo.deqReadyN(4) && rg_axi4_rd_rsize== 2) begin
        let v_temp={fifo.first[0],fifo.first[1],fifo.first[2],fifo.first[3]};
        fifo.deq(4);
        resp_pkt.rdata = duplicate(v_temp);
        resp_pkt.rresp = 0;
        if(resp_pkt.rlast == True) begin
          rg_axi4_rd_counter <= 0;
        end
        else begin
          rg_axi4_rd_counter <= rg_axi4_rd_counter + 4;
        end
      end
      else if(fifo.deqReadyN(2) && rg_axi4_rd_rsize== 1) begin
        let v_temp={fifo.first[0],fifo.first[1]};
        fifo.deq(2);
        resp_pkt.rdata = duplicate(v_temp);
        resp_pkt.rresp = 0;
        if(resp_pkt.rlast == True) begin
          rg_axi4_rd_counter <= 0;
        end
        else begin
          rg_axi4_rd_counter <= rg_axi4_rd_counter + 2;
        end
      end
      else if(fifo.deqReadyN(1) && rg_axi4_rd_rsize== 1)begin
        let v_temp={fifo.first[0]};
        fifo.deq(1);
        resp_pkt.rdata = duplicate(v_temp);
        resp_pkt.rresp = 0;
        if(resp_pkt.rlast == True) begin
          rg_axi4_rd_counter <= 0;
        end
        else begin
          rg_axi4_rd_counter <= rg_axi4_rd_counter + 2;
        end
      end
      else begin
        resp_pkt.rresp = 2;
        rg_axi4_rd_counter <= 0;
      end
    endrule:rl_read_from_bus_burst



    /*doc:rule: this rule updates the Status register*/
    rule rl_sr_update;
      rg_sr._write({19'd0,rg_sr_flevel,2'd0,rg_sr_busy,rg_sr_tof,rg_sr_smf,rg_sr_ftf,rg_sr_tcf,rg_sr_tef});
    endrule

    /*doc:rule: this rule updates the tcf flag of the SR register*/
    rule rl_delayed_sr_tcf_signal(lv_transfer_cond && ((rg_ccr.ddrm==1 && lv_ddr_clock && (rg_ccr.admode!=0 || rg_ccr.dmode!=0)) || wr_sdr_clock));
      rg_sr_tcf    <=rg_delay_sr_tcf;
    endrule

    /*doc:rule: this rule updates the rg_delay_ncs*/
    rule rl_delayed_rg_ncs_generation;
      rg_delay_ncs  <=rg_ncs;
    endrule

    /*doc:rule: this rule generates ddr clock/detect the both posedge and negedge of sdr clock*/
    rule rl_ddr_clk_gen;
      if(rg_ccr.ddrm == 1) begin
        if(rg_delay_ncs==1)begin
          rg_ddr_counter<=0;
          rg_ddr_clk <= rg_dcr.ckmode;
        end
        else begin
          let half_clock_value=(rg_cr.prescaler>>1);
          let lv_dummy = (rg_cr.prescaler + half_clock_value)>>1;
          if(rg_cr.prescaler[0]==0)begin // odd division
            if(rg_ddr_counter==(half_clock_value)>>1 || rg_ddr_counter==half_clock_value || rg_ddr_counter==lv_dummy || rg_ddr_counter==rg_cr.prescaler)begin
              rg_ddr_clk<=~rg_ddr_clk;
            end
            if(rg_ddr_counter==rg_cr.prescaler)
              rg_ddr_counter<=0;
            else
              rg_ddr_counter<=rg_ddr_counter+1;
            if(rg_ddr_counter==(half_clock_value)>>1 || rg_ddr_counter==half_clock_value || rg_ddr_counter==lv_dummy || rg_ddr_counter==rg_cr.prescaler)begin
              wr_ddr_clock<= rg_phase==DataRead_phase?unpack(~rg_ddr_clk):unpack(rg_ddr_clk);
            end
          end
          else begin // even division
            if(rg_ddr_counter==(half_clock_value)>>1 || rg_ddr_counter==half_clock_value)begin
              rg_ddr_clk<=~rg_ddr_clk;
              wr_ddr_clock <= (rg_phase==DataRead_phase) ? unpack(~rg_ddr_clk): unpack(rg_ddr_clk);
            end
            if(rg_ddr_counter==half_clock_value) begin
              rg_ddr_counter<=0;
            end
            else if(rg_delay_ncs==0)
              rg_ddr_counter<=rg_ddr_counter+1;
          end
        end
      end
    endrule

    /*doc:rule: this rule generates the slow clock signal from master clock*/
    rule rl_generate_clk_from_master;
      if(rg_delay_ncs==1)begin
        rg_clk_counter<=0;
        rg_clk <= rg_dcr.ckmode;
      end
      else begin
        let half_clock_value=rg_cr.prescaler>>1;
        if(rg_cr.prescaler[0]==0)begin // odd division
          if(rg_clk_counter == half_clock_value || rg_clk_counter==rg_cr.prescaler)
            rg_clk<=~rg_clk;
          if(rg_clk_counter==rg_cr.prescaler)
            rg_clk_counter<=0;
          else
            rg_clk_counter<=rg_clk_counter+1;
          if(rg_clk_counter == half_clock_value || rg_clk_counter==rg_cr.prescaler)begin
            wr_sdr_clock<= rg_phase==DataRead_phase?unpack(~rg_clk):unpack(rg_clk);
          end
        end
        else begin // even division
          if(rg_clk_counter==half_clock_value)begin
            rg_clk<=~rg_clk;
            rg_clk_counter<=0;
            wr_sdr_clock <= (rg_phase==DataRead_phase) ? unpack(~rg_clk): unpack(rg_clk);
          end
          else if(rg_delay_ncs==0)
            rg_clk_counter<=rg_clk_counter+1;
        end
      end
    endrule

    /*doc:rule: this rule handles transfer error flag of status register*/
    rule rl_set_error_signal;
      Bit#(32) actual_address=1<<(rg_dcr.fsize);
      if(rg_address_written && rg_ar.address>actual_address && (rg_ccr.fmode=='b00 || rg_ccr.fmode=='b01))
        rg_sr_tef<=1;
      else if(rg_address_written && rg_ar.address+rg_dlr.data_length>actual_address &&(rg_ccr.fmode=='b00 || rg_ccr.fmode=='b01))
        rg_sr_tef<=1;
      else if(rg_address_written)
        rg_sr_tef<=0;
    endrule

    /*doc:rule: this rule handles timeout flag of status register*/
    rule rl_timeout_counter;
      if(rg_cr.tcen==1 && rg_sr_tof==0) begin// rg_timecounter is enabled
        if(rg_timecounter==rg_lptr.time_out[15:0])begin
          rg_timecounter<=0;
          rg_sr_tof<=1;
        end
        else
          rg_timecounter<=rg_timecounter+1;
      end
      else
        rg_timecounter <=0;
    endrule

    /*doc:rule: this rule handles fifo threshold flag of status register*/
    rule rl_update_threshold_flag;
      if(rg_ccr.fmode=='b00)begin// indirect write mode
        rg_sr_ftf<=pack(16-pack(fifo.count)>={1'b0,rg_cr.fthres}+1);
      end
      else if(rg_ccr.fmode=='b01) begin
        rg_sr_ftf<=pack(pack(fifo.count)>=({1'b0,rg_cr.fthres}+1));
      end
      else if(rg_ccr.fmode=='b10 && wr_status_read)begin // auto_status polling mode
        rg_sr_ftf<=1;
      end
      else if(rg_ccr.fmode=='b10 && wr_data_read)begin // auto_status polling mode
        rg_sr_ftf<=0;
      end
      else if(rg_ccr.fmode=='b11) begin
        rg_sr_ftf<=pack(pack(fifo.count)>=({1'b0,rg_cr.fthres}+1));
        if(pack(fifo.count)>={1'b0,rg_cr.fthres}+1) begin
          rg_ncs<=1;
          rg_sr_busy<=0;
          rg_phase<=Idle; // Will this work?
          rg_thres<= True;
          rg_request_ready <= True;
        end
      end
    endrule

    /*doc:rule: update the status flag on each cycle*/
    rule rl_update_fifo_level;
      rg_sr_flevel<=pack(fifo.count);
    endrule

   /*doc:rule: abort functionality*/
    rule rl_if_abort(lv_qspi_flush);
      rg_phase            <=Idle;
      rg_ncs              <= 1;
      rg_sr_busy          <= 0;
      rg_thres            <= False;
      rg_read_true        <= False;
      rg_first_read       <= False;
      rg_instruction_sent <= False;
      rg_half_cycle_delay <= False;
      fifo.clear();
    endrule

    /*doc:rule: this rule is to de-assert the busy signal*/
    rule rl_reset_busy_signal(rg_sr_busy==1);
      if(rg_ccr.fmode=='b00 || rg_ccr.fmode=='b01)begin
        if(rg_sr_tcf==1)begin
          rg_sr_busy<=0;
          rg_ncs<=1;
        end
      end
      else if(rg_ccr.fmode=='b10)begin // automatic polling mode
        if(rg_sr_smf==1)begin
          rg_sr_busy<=0;
          rg_ncs<=1;
        end
      end
      else if(rg_ccr.fmode=='b11)begin
        if(rg_sr_tof==1 || rg_cr.en==0 || rg_cr.abort==1) begin// timeout event
          rg_sr_busy<=0;
          rg_ncs<=1;
        end
      end
    endrule

    /*doc:rule: this rule is to assert the busy signal*/
    rule rl_set_busy_signal(rg_sr_busy==0 && rg_phase==Idle && rg_cr.en==1);
      rg_output_en<=0;
      rg_instruction_sent<=False;
      Phase next_phase = Idle;
      let lv_counter = 0;
      if(rg_instruction_written)begin
        rg_sr_busy<=1;
        rg_ncs<=0;
        rg_phase<=Instruction_phase;
        rg_count_bits<=8;
       `logLevel(qspi, 0, $format("Entering Instruction phase"))
      end
      else if(rg_address_written && rg_ccr.admode!=0 && (rg_ccr.fmode=='b01 || rg_ccr.dmode=='d0 || rg_ccr.fmode=='b10))begin
        rg_sr_busy<=1; // start some transaction
       `logLevel(qspi, 0, $format(": Address Written and going to Some mode"))
        rg_ncs<=0;
        if(next_phase == Idle)
          next_phase = Instruction_phase;
        if(next_phase==Instruction_phase && (rg_ccr.imode==0||(rg_ccr.sioo==1 && rg_instruction_sent)))
          next_phase = Address_phase;
        if(next_phase==Address_phase && rg_ccr.admode==0)
          next_phase=AlternateByte_phase;
        if(next_phase==AlternateByte_phase && rg_ccr.abmode==0)
          next_phase=Dummy_phase;
        if(next_phase==Dummy_phase && rg_ccr.dcyc==0)
          next_phase=rg_ccr.fmode==0?DataWrite_phase:DataRead_phase;
        if(next_phase==Dummy_phase && (rg_ccr.fmode=='b10 && rg_pir.interval==0))begin
          next_phase=Instruction_phase;
        end
        if((next_phase == DataWrite_phase || next_phase == DataRead_phase) && rg_ccr.dmode==0 && rg_ccr.fmode!='b11)begin
          if(rg_ccr.fmode=='b01 || rg_ccr.fmode=='b00)
            next_phase=Idle;
          else if(rg_ccr.fmode=='b10)
            if(smf==1)
              next_phase=Idle;
            else
              next_phase=Dummy_phase;
        end

        //For rg_count_bits
        if(next_phase==Instruction_phase)begin
          lv_counter=8;
        end
        if(next_phase==Address_phase)begin
          lv_counter=(rg_ccr.fmode=='b11)?32:(case(rg_ccr.adsize)	0:8;	1:16;	2:24;	3:32; endcase);
        end
        if(next_phase==AlternateByte_phase)begin
          lv_counter=(case(rg_ccr.absize)	0:8;	1:16;	2:24;	3:32; endcase);
        end
        if(next_phase==Dummy_phase)begin
          lv_counter=(rg_ccr.fmode=='b10)? zeroExtend(rg_pir.interval):zeroExtend(rg_ccr.dcyc);
        end
        if(next_phase==DataWrite_phase)begin
          lv_counter=8;
        end
        if(next_phase==DataRead_phase)begin
          lv_counter= 0;
        end
        rg_phase<=next_phase;
        rg_count_bytes<=0;
       `logLevel(qspi, 0, $format(": Mode is :",fshow(rg_phase),"Count_bits : %d",rg_count_bits))
        if(next_phase==DataRead_phase) begin
          rg_read_true <= True;
          rg_count_bits <= 0;
        end
        else
          rg_count_bits <= lv_counter;
      end
      else if(rg_data_written && rg_ccr.admode!=0 && rg_ccr.dmode!=0 && rg_ccr.fmode=='b00)begin
       `logLevel(qspi, 0, $format(": Waiting for all the data to be transmitted "))
        rg_phase<=DataWait_phase;
      end
    endrule

    /*doc:rule: this rule waits for the data to be send to the flash is written into the FIFO*/
    rule rl_data_wait(rg_sr_busy==0 && rg_phase==DataWait_phase && rg_cr.en==1);
      if(pack(fifo.count) >= rg_dlr.data_length[4:0] + 1)begin
       `logLevel(qspi, 0, $format("In Data_wait_phase All the write data received!!!!! "))
        rg_sr_busy <= 1;
        rg_ncs <= 0;
        rg_count_bits<=8;
        rg_count_bytes<=0;
        rg_phase<=Instruction_phase;
      end
    endrule

    /*doc:rule: this rule to transfer the instruction of 8-bits outside. THe size of instruction is fixed
    to 8 bits by protocol. Instruction phase will always be in SDR mode*/
    rule rl_transfer_instruction(rg_phase==Instruction_phase && lv_transfer_cond && wr_sdr_clock && !lv_qspi_flush);
      Bool end_of_phase=False;
      let reverse_instruction=rg_ccr.instruction;
      let count_val=rg_count_bits;
      Phase next_phase = Instruction_phase;
      Bit#(32) lv_counter = 8;
     `logLevel(qspi, 1, $format(": Executing Instruction Phase SPI Mode: %b Count_bits: %d InstructionReverse: %h",rg_ccr.imode,rg_count_bits,reverse_instruction))
      Bit#(4) enable_o=0;
      if(rg_ccr.imode=='b01)begin // single spi mode;
        enable_o=4'b1101;
        rg_output<={1'b1,1'b0,1'b0,reverse_instruction[rg_count_bits-1]};
        if(rg_count_bits==1)begin// end of instruction stream
          end_of_phase=True;
        end
        else
          count_val=rg_count_bits-1;
      end
      else if (rg_ccr.imode=='b10)begin // dual mode;
        enable_o=4'b1111;
        rg_output<={1'b1,1'b0,reverse_instruction[rg_count_bits-1:rg_count_bits-2]};
        if(rg_count_bits==2)begin// end of instruction stream
          end_of_phase=True;
        end
        else
          count_val=rg_count_bits-2;
      end
      else if (rg_ccr.imode=='b11)begin // quad mode;
        enable_o=4'b1111;
        rg_output<=reverse_instruction[rg_count_bits-1:rg_count_bits-4];
        if(rg_count_bits==4)begin// end of instruction stream
          end_of_phase=True;
        end
        else
          count_val=rg_count_bits-4;
      end
      if(end_of_phase || rg_ccr.imode==0)begin // end of instruction or no instruction phase
        if(next_phase == Instruction_phase)
          next_phase = Address_phase;
        if(next_phase==Address_phase && rg_ccr.admode==0)
          next_phase=AlternateByte_phase;
        if(next_phase==AlternateByte_phase && rg_ccr.abmode==0)
          next_phase=Dummy_phase;
        if(next_phase==Dummy_phase && rg_ccr.dcyc==0)
          next_phase=rg_ccr.fmode==0? DataWrite_phase:DataRead_phase;
        if(next_phase==Dummy_phase && (rg_ccr.fmode=='b10 && rg_pir.interval==0))begin
          next_phase=Instruction_phase;
        end
        if((next_phase == DataWrite_phase || next_phase == DataRead_phase) && rg_ccr.dmode==0 && rg_ccr.fmode!='b11)begin
          if(rg_ccr.fmode=='b01 || rg_ccr.fmode=='b00)
            next_phase=Idle;
          else if(rg_ccr.fmode=='b10)
            if(smf==1)
              next_phase=Idle;
            else
              next_phase=Dummy_phase;
        end

        //For rg_count_bits
        if(next_phase==Address_phase)begin
          lv_counter=(rg_ccr.fmode=='b11)?32:(case(rg_ccr.adsize)	0:8;	1:16;	2:24;	3:32; endcase);
        end
        if(next_phase==AlternateByte_phase)begin
          lv_counter=(case(rg_ccr.absize)	0:8;	1:16;	2:24;	3:32; endcase);
        end
        if(next_phase==Dummy_phase)begin
          lv_counter=(rg_ccr.fmode=='b10)? zeroExtend(rg_pir.interval):zeroExtend(rg_ccr.dcyc);
        end
        if(next_phase==DataWrite_phase)begin
          lv_counter=8;
        end
        if(next_phase==DataRead_phase)begin
          lv_counter= 0;
        end
        Bit#(1) tcf=0;
        if(next_phase==Idle && (rg_ccr.fmode=='b00 || rg_ccr.fmode=='b01))begin
          tcf=1;
        end
        rg_delay_sr_tcf <= tcf;
        rg_phase<=next_phase;
        rg_instruction_sent<=True;
        rg_count_bytes<=0;
        if(rg_ccr.ddrm==1)
          rg_half_cycle_delay<=True;
        if(next_phase==DataRead_phase) begin
          rg_read_true <= True;
          rg_count_bits <= 0;
        end
        else
          rg_count_bits <= lv_counter;
      end
      else begin
        rg_count_bits<=count_val;
        rg_output_en<=enable_o;
      end
    endrule

    /*doc:rule: this rule to transfer the address bits of address outside. The size of address is
    defined by the ccr_adsize register in ccr*/
    rule rl_transfer_address(rg_phase==Address_phase && lv_transfer_cond && !lv_qspi_flush);
      Phase next_phase = Address_phase;
      Bit#(8) lv_delay = ((rg_cr.prescaler+1)+(rg_cr.prescaler+1)>>1)-1;
      Bit#(32) lv_counter = (rg_ccr.fmode=='b11)?32:(case(rg_ccr.adsize)	0:8;	1:16;	2:24;	3:32; endcase);
      if(rg_half_cycle_delay && rg_ccr.ddrm == 0 && lv_clock_cond) begin
        rg_half_cycle_delay<=False;
        rg_read_true <= True;
      end
      else if(rg_half_cycle_delay && rg_ccr.ddrm == 1 && rg_ddr_en == 0 && rg_ccr.fmode != 'b11) begin
        if(rg_count == lv_delay) begin
          rg_ddr_en <= 1;
          rg_half_cycle_delay <= False;
              end
        else begin
          rg_count <= rg_count + 1;
        end
      end
      else if(rg_ccr.ddrm == 1 && rg_ddr_en == 0) begin
        rg_count <= 1;
        rg_ddr_en <= 1;
      end
      else if((lv_clock_cond && rg_ccr.ddrm == 0) || (rg_ccr.ddrm == 1 && rg_ddr_en == 1 && lv_clock_cond)) begin
        rg_count <= 0;
        rg_ddr_en <= 0;
        Bool end_of_phase=False;
        Bit#(4) enable_o=0;
        let count_val=rg_count_bits;
        Bit#(32) address=(rg_ccr.fmode=='b11)?zeroExtend(rg_mm_address):rg_ar.address;
        rg_prev_addr <= truncate(address);
        `logLevel(qspi, 1, $format(": Executing Address Phase SPI Mode: %b Address Size: %d Count_bits: %d Address: %b",rg_ccr.admode,rg_ccr.adsize,rg_count_bits,address))
        if(rg_ccr.admode=='b01)begin // single spi mode;
          enable_o=4'b1101;
          rg_output<={1'b1,1'b0,1'b0,address[rg_count_bits-1]};
         `logLevel(qspi, 0, $format("Single: Sending Address bit %h bit_number: %d total_address: %h",rg_count_bits-1,address[rg_count_bits-1],address))
          if(rg_count_bits==1)begin// end of address stream
            end_of_phase=True;
          end
          else
            count_val=rg_count_bits-1;
        end
        else if (rg_ccr.admode=='b10)begin // dual mode;
          enable_o=4'b1111;
          rg_output<={1'b1,1'b0,address[rg_count_bits-1:rg_count_bits-2]};
          if(rg_count_bits==2)begin// end of address stream
            end_of_phase=True;
          end
          else
            count_val=rg_count_bits-2;
        end
        else if (rg_ccr.admode=='b11)begin // quad mode;
          enable_o=4'b1111;
          rg_output<=address[rg_count_bits-1:rg_count_bits-4];
          if(rg_count_bits==4)begin// end of address stream
            end_of_phase=True;
          end
          else
            count_val=rg_count_bits-4;
        end

        if(end_of_phase || rg_ccr.admode==0)begin
          if(next_phase == Address_phase)
            next_phase = AlternateByte_phase;
          if(next_phase==AlternateByte_phase && rg_ccr.abmode==0)
            next_phase=Dummy_phase;
          if(next_phase==Dummy_phase && rg_ccr.dcyc==0)
            next_phase=rg_ccr.fmode==0?DataWrite_phase:DataRead_phase;
          if(next_phase==Dummy_phase && (rg_ccr.fmode=='b10 && rg_pir.interval==0))
            next_phase=Instruction_phase;
          if((next_phase == DataWrite_phase || next_phase == DataRead_phase) && rg_ccr.dmode==0 && rg_ccr.fmode!='b11)begin
            if(rg_ccr.fmode=='b01 || rg_ccr.fmode=='b00)
              next_phase=Idle;
            else if(rg_ccr.fmode=='b10)
              if(smf==1)
                next_phase=Idle;
              else
                next_phase=Dummy_phase;
          end

          //For rg_count_bits
          if(next_phase==AlternateByte_phase)begin
            lv_counter=(case(rg_ccr.absize)	0:8;	1:16;	2:24;	3:32; endcase);
          end
          if(next_phase==Dummy_phase)begin
            lv_counter=(rg_ccr.fmode=='b10)? zeroExtend(rg_pir.interval):zeroExtend(rg_ccr.dcyc);
          end
          if(next_phase==DataWrite_phase)begin
            lv_counter=8;
          end
          if(next_phase==DataRead_phase)begin
            lv_counter= 0;
          end
          Bit#(1) tcf=0;
          if(next_phase==Idle && (rg_ccr.fmode=='b00 || rg_ccr.fmode=='b01))begin
            tcf=1;
          end
          rg_delay_sr_tcf <= tcf;
          rg_phase<=next_phase;
          rg_count_bytes<=0;
          rg_init_mm_xip_delay <= 0;
          if(rg_ccr.ddrm == 1 && rg_ccr.dmode != 1)
            rg_half_cycle_delay <= True;
          if(next_phase==DataRead_phase) begin
            rg_read_true <= True;
            rg_count_bits <= 0;
          end
          else
            rg_count_bits <= lv_counter;
        end
        else begin
          rg_count_bits<=count_val;
          rg_output_en<=enable_o;
        end
      end
    endrule


    /*doc:rule: this rule to transfer the alternate bytes. The size of alternate bytes is
    defined by the ccr_absize register in ccr*/
    rule rl_transfer_alternatebytes(rg_phase==AlternateByte_phase && lv_transfer_cond && lv_clock_cond && !lv_qspi_flush);
      Bool end_of_phase=False;
      let count_val=rg_count_bits;
      Phase next_phase = AlternateByte_phase;
      Bit#(32) lv_counter = (case(rg_ccr.absize)	0:8;	1:16;	2:24;	3:32; endcase);
     `logLevel(qspi, 1, $format("Executing AltByte Phase SPI Mode: %b AltByte Size: %d Count_bits: %d AltByte: %b",rg_ccr.abmode,rg_ccr.absize,rg_count_bits,rg_abr.alternate_byte))
      Bit#(4) enable_o=0;
      if(rg_ccr.abmode=='b01)begin // single spi mode;
        enable_o=4'b1101;
        rg_output<={1'b1,1'b0,1'b0,rg_abr.alternate_byte[rg_count_bits-1]};
        if(rg_count_bits==1)begin// end of instruction stream
          end_of_phase=True;
        end
      else
        count_val=rg_count_bits-1;
      end
      else if (rg_ccr.abmode=='b10)begin // dual mode;
        enable_o=4'b1111;
        rg_output<={1'b1,1'b0,rg_abr.alternate_byte[rg_count_bits-1:rg_count_bits-2]};
        if(rg_count_bits==2)begin// end of instruction stream
          end_of_phase=True;
        end
        else
          count_val=rg_count_bits-2;
      end
      else if (rg_ccr.abmode=='b11)begin // quad mode;
        enable_o=4'b1111;
        rg_output<=rg_abr.alternate_byte[rg_count_bits-1:rg_count_bits-4];
        if(rg_count_bits==4)begin// end of instruction stream
          end_of_phase=True;
        end
        else
          count_val=rg_count_bits-4;
      end
      if(end_of_phase || rg_ccr.abmode==0)begin
        if(next_phase == AlternateByte_phase)
          next_phase = Dummy_phase;
        if(next_phase==Dummy_phase && rg_ccr.dcyc==0)
          next_phase=rg_ccr.fmode==0?DataWrite_phase:DataRead_phase;
        if(next_phase==Dummy_phase && (rg_ccr.fmode=='b10 && rg_pir.interval==0))begin
          next_phase=Instruction_phase;
        end
        if((next_phase == DataWrite_phase || next_phase == DataRead_phase) && rg_ccr.dmode==0 && rg_ccr.fmode!='b11)begin
          if(rg_ccr.fmode=='b01 || rg_ccr.fmode=='b00)
            next_phase=Idle;
          else if(rg_ccr.fmode=='b10) begin
            if(smf==1)
              next_phase=Idle;
            else
              next_phase=Dummy_phase;
          end
        end
        //For rg_count_bits
        if(next_phase==Dummy_phase)begin
          lv_counter=(rg_ccr.fmode=='b10)? zeroExtend(rg_pir.interval):zeroExtend(rg_ccr.dcyc);
        end
        if(next_phase==DataWrite_phase)begin
          lv_counter=8;
        end
        if(next_phase==DataRead_phase)begin
          lv_counter= 0;
        end
        Bit#(1) tcf=0;
        if(next_phase==Idle && (rg_ccr.fmode=='b00 || rg_ccr.fmode=='b01))begin
          tcf=1;
        end
        rg_delay_sr_tcf <= tcf;
        rg_phase<=next_phase;
        rg_count_bytes<=0;
        if(next_phase==DataRead_phase) begin
          rg_read_true <= True;
          rg_count_bits <= 0;
        end
        else
          rg_count_bits <= lv_counter;
      end
      else begin
        rg_count_bits<=count_val;
        rg_output_en<=enable_o;
      end
    endrule

    /*doc:rule: this rule is to transfer the dummy cycles only in SDR mode according to ISSI Flash Datasheet*/
    rule rl_transfer_dummy_cycle(rg_phase==Dummy_phase && lv_transfer_cond && !lv_qspi_flush);
      Phase next_phase = Dummy_phase;
      Bit#(32) rg_mode_bytes = {rg_dcr.dcr_mode_byte,24'd0};
      Bit#(32) lv_counter = (rg_ccr.fmode=='b10)? zeroExtend(rg_pir.interval):zeroExtend(rg_ccr.dcyc);
      //DDR to SDR handling
      if(rg_count==(rg_cr.prescaler>>1)-1) begin
        rg_delay_dummy <= True;
        rg_count <= rg_count+1;
      end
      else if(rg_count<(rg_cr.prescaler>>1)-1)
        rg_count <= rg_count+1;

      else if(((rg_delay_dummy || wr_sdr_clock) && rg_ccr.ddrm==1) || (wr_sdr_clock && rg_ccr.ddrm==0)) begin
        rg_delay_dummy <= False;
        if(next_phase == Dummy_phase)
          next_phase=(rg_ccr.fmode=='b00)?DataWrite_phase:DataRead_phase;

        if((next_phase == DataWrite_phase || next_phase == DataRead_phase) && rg_ccr.dmode==0 && rg_ccr.fmode!='b11)begin
          if(rg_ccr.fmode=='b01 || rg_ccr.fmode=='b00)
            next_phase=Idle;
          else if(rg_ccr.fmode=='b10)
            if(smf==1)
              next_phase=Idle;
            else
              next_phase=Dummy_phase;
        end
        //For rg_count_bits
        if(next_phase==DataWrite_phase)begin
          lv_counter=8;
        end
        if(next_phase==DataRead_phase)begin
          lv_counter= 0;
        end
        Bit#(1) tcf=0;
        if(next_phase==Idle && (rg_ccr.fmode=='b00 || rg_ccr.fmode=='b01))begin
          tcf=1;
        end
        Bit#(5) count_val = rg_mode_byte_counter;
        Bit#(4) enable_o = rg_output_en;
       `logLevel(qspi, 0, $format(": Executing Dummy Phase: rg_mode_bytes: %b rg_mode_byte_counter: %d",rg_mode_bytes, rg_mode_byte_counter))
        if(rg_ccr.dmode==1) begin
          if(rg_ccr.dummy_confirmation==1) begin
            enable_o = 4'b1101;
            rg_output <= {1'b1,1'b0,1'b0,rg_mode_bytes[rg_mode_byte_counter]};
            if(count_val>=28)
              count_val = count_val - 1;
            else
              enable_o = 4'b1100;
          end
          else begin
            enable_o = 4'b1100;
            rg_output <= {1'b1,1'b0,1'b0,1'b0};
          end
        end
        else if(rg_ccr.dmode==2) begin
          if(rg_ccr.dummy_confirmation==1) begin
            enable_o = 4'b1111;
            rg_output <= {1'b1,1'b0,rg_mode_bytes[rg_mode_byte_counter:rg_mode_byte_counter-1]};
            if(count_val>=28)
               count_val = count_val - 2;
            else
               enable_o = 4'b1100;
          end
          else begin
            enable_o = 4'b1100;
            rg_output <= {1'b1,1'b0,1'b0,1'b0};
          end
        end
        else begin
          if(rg_ccr.dummy_confirmation==1) begin
            enable_o = 4'b1111;
            rg_output <= rg_mode_bytes[rg_mode_byte_counter:rg_mode_byte_counter-3];
            if(count_val>=28)
              count_val = count_val - 4;
            else
              enable_o = 4'b0000;
          end
          else begin
            enable_o = 4'b0000;
          end
        end
        if(rg_count_bits==1)begin // end of dummy cycles;
          rg_delay_sr_tcf<=tcf;
          rg_phase<=next_phase;
          rg_count <= 0;
         `logLevel(qspi, 0, $format("From Dummy to :",fshow(next_phase)))
          if(next_phase==DataRead_phase) begin
            if(rg_ccr.ddrm == 0)
              rg_read_true <= True;
          end
          rg_count_bytes<=0;
          rg_count_bits<=lv_counter;
          rg_mode_byte_counter <= 'd-1;
          if(rg_ccr.ddrm==1)
            rg_half_cycle_delay<=True;
        end
        else begin
          rg_count_bits<=rg_count_bits-1;
          rg_mode_byte_counter <= count_val;
          rg_output_en <= enable_o;
        end
      end
    endrule

    /*doc:rule: read data from the flash memory and store it in the DR register. Simulataneously
    put Bytes in the FIFO*/
    rule rl_data_read_phase(rg_phase==DataRead_phase && lv_transfer_cond && !lv_qspi_flush);
      Phase next_phase = DataRead_phase;
      Bit#(32) lv_counter = 0;
      Bool lv_smf = ((smf&rg_cr.apms)==1);
      if((rg_half_cycle_delay || rg_read_true) && rg_ccr.ddrm == 0 && lv_clock_cond) begin
        rg_half_cycle_delay<=False;
        rg_read_true <= False;
      end
      //else if((rg_half_cycle_delay || rg_read_true) && rg_ccr.ddrm == 1) begin
      else if((rg_half_cycle_delay || rg_read_true) && rg_ccr.ddrm == 1 && lv_clock_cond) begin
        if(rg_count == 1) begin
          rg_half_cycle_delay<=False;
          rg_read_true <= False;
        end
        else
          rg_count <= rg_count + 1;
      end
      else if(lv_clock_cond) begin
        rg_count <= 0;
        Bit#(32) lv_data_reg=rg_dr_val;
        Bit#(32) lv_count_byte=rg_count_bytes;
        Bit#(32) lv_count_bits=rg_count_bits;
        Bit#(32) lv_data_length1=(rg_ccr.fmode=='b11)?rg_mm_data_length:rg_dlr.data_length;
       `logLevel(qspi, 1, $format(": Executing DataRead Phase SPI Mode: %b DLR : %h Count_bits: %d Input :%h ccr_ddrm: %b rg_count_byte %h",rg_ccr.dmode,lv_data_length1,rg_count_bits,wr_input,rg_ccr.ddrm,rg_count_bytes))
        /* write incoming bit to the data register */
        if(rg_ccr.dmode==1)begin // single line mode;
          lv_data_reg = {lv_data_reg[30:0],wr_input[1]};
         `logLevel(qspi, 0, $format("Single lv_data_reg : %h",lv_data_reg))
          lv_count_bits=lv_count_bits+1;
          rg_output_en <= 4'b1101;
          rg_output <= {1'b1,1'b0,1'b0,1'b0};
        end
        else if(rg_ccr.dmode==2)begin // dual line mode;
          rg_output_en <= 4'b1100;
          lv_data_reg=lv_data_reg<<2;
          lv_data_reg[1:0]=wr_input[1:0];
          lv_count_bits=lv_count_bits+1;
          rg_output <= {1'b1,1'b0,1'b0,1'b0};
        end
        else if(rg_ccr.dmode==3) begin// quad line mode;
          rg_output_en <= 4'b0000;
          lv_data_reg=lv_data_reg<<4;
          lv_data_reg[3:0]=wr_input;
          lv_count_bits=lv_count_bits+1;
        end

        /* write the last successfully received byte into the FIFO */
        if(rg_ccr.dmode==1)begin
          if(lv_count_byte==lv_data_length1 +1 && rg_ccr.ddrm==1) begin // && lv_count_bits[2:0] =='b111) begin
            rg_ncs<=1;
          end
          if(rg_count_bits[2:0]=='b111)begin
           `logLevel(qspi, 1, $format("Enquing FIFO lv_count_byte %h", lv_count_byte))
            Vector#(4,Bit#(8)) temp = newVector();
            temp[0]=lv_data_reg[7:0];
           `logLevel(qspi, 0, $format("Single Enqueing FIFO : data is %h",temp[0]))
            if(!rg_first_read)begin
              fifo.enq(1,temp);
            end
            lv_count_byte=lv_count_byte+1;
          end
        end
        else if(rg_ccr.dmode==2) begin // dual line mode
          if(lv_count_byte==lv_data_length1+1 && rg_ccr.ddrm==1) begin //&& lv_count_bits[1:0]=='b11) begin
            rg_ncs<=1;
          end
          if(rg_count_bits[1:0]=='b11)begin
            Vector#(4,Bit#(8)) temp = newVector();
            temp[0]=lv_data_reg[7:0];
            if(!rg_first_read)
              fifo.enq(1,temp);
            lv_count_byte=lv_count_byte+1;
          end
        end
        else if(rg_ccr.dmode==3) begin // quad line mode
          if(lv_count_byte==lv_data_length1+1 && rg_ccr.ddrm==1) // && lv_count_bits[0]=='b1)
            rg_ncs<=1;
          if(rg_count_bits[0]=='b1)begin
            Vector#(4,Bit#(8)) temp = newVector();
            temp[0]=lv_data_reg[7:0];
            if(!rg_first_read)
              fifo.enq(1,temp);
            lv_count_byte=lv_count_byte+1;
          end
        end
        bit smf=0;
       `logLevel(qspi, 0, $format("lv_count_byte: %h lv_data_length1: %h",lv_count_byte, lv_data_length1))
        /* condition for termination of dataread_phase */
        if(lv_data_length1!='hFFFFFFFF)begin // if limit is not undefined
          if(lv_count_byte==lv_data_length1+1) begin
            `logLevel(qspi, 0, $format("Limit hasreached: rg_count_bytes %h data_length %h",lv_count_byte,rg_dlr.data_length))
            if(rg_ccr.fmode=='b10)begin // auto-status polling mode
              if(rg_cr.pmm==0)begin // ANDed mode
               if((rg_psma.mat&rg_psmk.mask) == (rg_psmk.mask&{fifo.first[0],fifo.first[1],fifo.first[2],fifo.first[3]})) // is the unmasked bits match
                  smf=1;
                else
                  smf=0;
              end
              else begin// ORed mode
                let p=rg_psmk.mask&{fifo.first[0],fifo.first[1],fifo.first[2],fifo.first[3]};
                let q=rg_psmk.mask&rg_psma.mat;
                let r=~(p^q);
                if(|(r)==1)
                  smf=1;
                else
                  smf=0;
              end
            end
            //For rg_phase
            if(next_phase == DataRead_phase) begin
              if(rg_ccr.fmode=='b01 || rg_ccr.fmode=='b10) // indirect modes
                next_phase=Idle;
              else if(rg_ccr.fmode=='b10)// auto-status polling mode
                if(smf==1)
                  next_phase=Idle;
                else
                  next_phase=Dummy_phase;
              else
                next_phase=DataRead_phase; //Memory Mapped mode
            end

            if(next_phase==Dummy_phase && (rg_ccr.fmode=='b10 && rg_pir.interval==0))begin
              next_phase=Instruction_phase;
            end
            if(( next_phase == DataRead_phase) && rg_ccr.dmode==0 && rg_ccr.fmode!='b11)begin
              if(rg_ccr.fmode=='b01 && rg_ccr.fmode=='b00) // indirect modes
                next_phase=Idle;
              else if(rg_ccr.fmode=='b10) // auto-status polling mode
                if(smf==1)
                  next_phase=Idle;
                else
                  next_phase=Dummy_phase;
            end

            //For rg_count_bits
            if(next_phase==Dummy_phase)begin
              lv_counter=(rg_ccr.fmode=='b10)? zeroExtend(rg_pir.interval):zeroExtend(rg_ccr.dcyc);
            end
            if(next_phase==DataRead_phase)begin
              lv_counter= 0;
            end
            Bit#(1) tcf=0;
            if(next_phase==Idle && (rg_ccr.fmode=='b00 || rg_ccr.fmode=='b01))begin
              tcf=1;
            end
            if(next_phase==DataRead_phase)
              rg_read_true <= True;
            rg_phase<=next_phase;
           `logLevel(qspi, 0,  $format("rg_phase: ",fshow(next_phase)," rg_sr_tcf: %d",tcf))
            rg_sr_tcf<=tcf; // set completion of transfer flag
            rg_count_bytes<=0;
            rg_count_bits<=0;
          end
          else begin
            rg_count_bytes<=lv_count_byte;
            rg_count_bits<=lv_count_bits;
          end
        end
        else if(rg_dcr.fsize!='h1f)begin // if limit is not infinite
          Bit#(32) new_limit=1<<(rg_dcr.fsize);
         `logLevel(qspi, 1, $format("Sending completion -- newlimit : %h",new_limit))
          if(truncate(rg_count_bytes)==new_limit)begin // if reached end of Flash memory
            //For rg_phase
            if(next_phase == DataRead_phase) begin
              if(rg_ccr.fmode=='b01 || rg_ccr.fmode=='b10) // indirect modes
                next_phase=Idle;
              else if(rg_ccr.fmode=='b10)// auto-status polling mode
                if(smf==1)
                  next_phase=Idle;
                else
                  next_phase=Dummy_phase;
              else
                next_phase=DataRead_phase; //Memory Mapped mode
            end

            if(next_phase==Dummy_phase && (rg_ccr.fmode=='b10 && rg_pir.interval==0))begin
              next_phase=Instruction_phase;
            end
            if(( next_phase == DataRead_phase) && rg_ccr.dmode==0 && rg_ccr.fmode!='b11)begin
              if(rg_ccr.fmode=='b01 && rg_ccr.fmode=='b00) // indirect modes
                next_phase=Idle;
              else if(rg_ccr.fmode=='b10) // auto-status polling mode
                if(smf==1)
                  next_phase=Idle;
                else
                  next_phase=Dummy_phase;
            end

            //For rg_count_bits
            if(next_phase==Dummy_phase)begin
              lv_counter=(rg_ccr.fmode=='b10)? zeroExtend(rg_pir.interval):zeroExtend(rg_ccr.dcyc);
            end
            if(next_phase==DataRead_phase)begin
              lv_counter= 0;
            end
            Bit#(1) tcf=0;
            if(next_phase==Idle && (rg_ccr.fmode=='b00 || rg_ccr.fmode=='b01))begin
              tcf=1;
            end
            rg_phase<=next_phase;
            rg_sr_tcf<=tcf;
            rg_count_bytes<=0;
            rg_count_bits<=0;
            if(next_phase==DataRead_phase)
              rg_read_true <= True;
          end
          else begin
            rg_count_bytes<=lv_count_byte;
            rg_count_bits<=lv_count_bits;
          end
        end
        else begin
          rg_count_bytes<=lv_count_byte;
          rg_count_bits<=lv_count_bits;
        end
        rg_sr_smf<=smf;
        rg_dr_val <= lv_data_reg;
      end
    endrule

    /*doc:rule: write data from the FIFO to the FLASH*/
    rule rl_data_write_phase(rg_phase==DataWrite_phase && lv_transfer_cond && lv_clock_cond && !lv_qspi_flush);
      if(rg_half_cycle_delay)
        rg_half_cycle_delay<=False;
      else begin
        Bit#(8) lv_data_reg=fifo.first()[0];
        Bit#(32) lv_count_byte=rg_count_bytes;
        Bit#(32) lv_count_bits=rg_count_bits;
        Bit#(4) enable_o=0;
        rg_delay_count_bits <= rg_count_bits;
        /* write incoming bit to the data register */
        if(rg_ccr.dmode==1)begin // single line mode;
          enable_o=4'b1101;
          rg_output<={1'b1,1'b0,1'b0,lv_data_reg[rg_count_bits-1]};
          lv_count_bits=lv_count_bits-1;
        end
        else if(rg_ccr.dmode==2)begin // dual line mode;
          enable_o=4'b1111;
          rg_output<={1'b1,1'b0,lv_data_reg[rg_count_bits-1:rg_count_bits-2]};
          lv_count_bits=lv_count_bits-2;
        end
        else if(rg_ccr.dmode==3) begin// quad line mode;
          enable_o=4'b1111;
          rg_output<=lv_data_reg[rg_count_bits-1:rg_count_bits-4];
          lv_count_bits=lv_count_bits-4;
        end
        /* write the last successfully received byte into the FIFO */
        if(rg_ccr.dmode==1)begin// single line mode
          if(rg_count_bits==1)begin // multiple of eight bits have been read.
            fifo.deq(1);
            lv_count_byte=lv_count_byte+1;
            lv_count_bits=8;
          end
        end
        else if(rg_ccr.dmode==2) begin // dual line mode
          if(rg_count_bits==2)begin // multiple of eight bits have been read.
            fifo.deq(1);
            lv_count_byte=lv_count_byte+1;
            lv_count_bits=8;
          end
        end
        else if(rg_ccr.dmode==3) begin // quad line mode
          if(rg_count_bits==4)begin // multiple of eight bits have been read.
            fifo.deq(1);
            lv_count_byte=lv_count_byte+1;
            lv_count_bits=8;
          end
        end
        /* condition for termination of datawrite_phase */
        if(rg_dlr.data_length!='hFFFFFFFF)begin // if limit is not undefined
          if((rg_count_bytes==rg_dlr.data_length + 1)&& ((rg_ccr.dmode == 3 && rg_delay_count_bits == 4) ||(rg_ccr.dmode == 2 && rg_delay_count_bits ==2) ||(rg_ccr.dmode == 1 && rg_delay_count_bits == 1) ))begin // if limit has bee reached.
            rg_phase<=Idle;
            rg_sr_tcf<=1; // set completion of transfer flag
            rg_count_bytes<=0;
            rg_count_bits<=0;
          end
          else begin
            rg_count_bytes<=lv_count_byte;
            rg_count_bits<=lv_count_bits;
          end
        end
        else if(rg_dcr.fsize!='h1f)begin // if limit is not infinite
          Bit#(32) new_limit=1<<(rg_dcr.fsize);
          if(truncate(rg_count_bytes)==new_limit)begin // if reached end of Flash memory
            rg_phase<=Idle;
            rg_sr_tcf<=1; // set completion of transfer flag
            rg_count_bytes<=0;
            rg_count_bits<=0;
          end
          else begin
            rg_count_bytes<=lv_count_byte;
            rg_count_bits<=lv_count_bits;
          end
        end
        else begin // keep looping untill abort signal is not raised.
          rg_count_bytes<=lv_count_byte;
          rg_count_bits<=lv_count_bits;
        end
        rg_output_en<=enable_o;
      end
    endrule

    /*doc:note: Definition of methods of QSPI_out interface*/
    interface QSPI_out io;
      method bit clk_o;
        return rg_delay_ncs==1?rg_dcr.ckmode:rg_clk;
      endmethod
      method Bit#(4) io_o;
        return rg_output;
      endmethod
      method Bit#(4) io_enable;
        return rg_output_en;
      endmethod
      method Action io_i (Bit#(4) io_in);
        if(rg_phase==DataRead_phase) begin
          wr_input<=io_in;
        end
      endmethod
      method bit ncs_o = rg_ncs;
    endinterface
    method Bit#(6) mv_interrupts; // 0=TOF, 1=SMF, 2=Threshold, 3=TCF, 4=TEF 5=request_ready
      return {pack(rg_request_ready),rg_sr_tef&rg_cr.teie, rg_sr_tcf&rg_cr.tcie, rg_sr_ftf&rg_cr.ftie, rg_sr_smf&rg_cr.smie , rg_sr_tof&rg_cr.toie};
    endmethod
    interface mem_slave = mem_slave_xactor.axi4_side;
  endmodule:mkQspi


  /*doc:module: mkQspi_block with Ifc_qspi_controller interface: */
  module [Module] mkQspi_block(IWithDCBus#(DCBus#(aw,dw), Ifc_qspi_controller#(aw, dw, uw, mem_id,mem_aw,mem_dw, mem_uw)))
    provisos(
      Add#(e__, 28, aw),
      Mul#(32, f__, dw),
      Add#(16, _a, aw),
      Add#(8, _b, dw), // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(dw, _c, 32), // not more than 32 gpios per block
      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(d__, TDiv#(dw, 8), 8),
      Mul#(16, b__, dw),
      Add#(g__, 28, mem_aw),
      Mul#(32, h__, mem_dw),
      Mul#(16, i__, mem_dw),
      Mul#(8, j__, mem_dw)
    );

    let ifc <- exposeDCBusIFC(mkQspi);
    return (ifc);
  endmodule:mkQspi_block

  /*doc:module: mkqspi_axi4l with Ifc_qspi_axi4l interface: */
  module [Module] mkqspi_axi4l#(parameter Integer base, Clock slowclock, Reset slow_rst)(Ifc_qspi_axi4l#(aw,
                                                                                                        dw, uw,
                                                                                                        mem_id,mem_aw,mem_dw, mem_uw))
    provisos(
      Add#(e__, 28, aw),
      Mul#(32, f__, dw),
      Add#(16, _a, aw),
      Add#(8, _b, dw), // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(dw, _c, 32), // not more than 32 gpios per block
      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(d__, TDiv#(dw, 8), 8),
      Mul#(16, b__, dw),
      Add#(g__, 28, mem_aw),
      Mul#(32, h__, mem_dw),
      Mul#(16, i__, mem_dw),
      Mul#(8, j__, mem_dw)
    );
    let device = mkQspi_block(clocked_by slowclock, reset_by slow_rst);
    Ifc_qspi_axi4l#(aw,dw,uw,mem_id,mem_aw,mem_dw, mem_uw) qspi <- dc2axi4l(device, base, slowclock, slow_rst);
    return qspi;
  endmodule:mkqspi_axi4l

  /*doc:module: mkqspi_apb with Ifc_qspi_apb interface: */
  module [Module] mkqspi_apb#(parameter Integer base, Clock slowclock, Reset slow_rst)(Ifc_qspi_apb#(aw,
                                                                                                    dw,
                                                                                                    uw, mem_id,mem_aw,mem_dw, mem_uw))
    provisos(
      Add#(e__, 28, aw),Mul#(32, f__, dw),
      Add#(16, _a, aw),
      Add#(8, _b, dw), // data atleast 8 bits
      Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
      Add#(dw, _c, 32), // not more than 32 gpios per block
      Add#(a__, 2, aw),
      Add#(dw, c__, 64),
      Add#(TExp#(TLog#(dw)),0,dw),
      Add#(d__, TDiv#(dw, 8), 8),
      Mul#(16, b__, dw),
      Add#(g__, 28, mem_aw),
      Mul#(32, h__, mem_dw),
      Mul#(16, i__, mem_dw),
      Mul#(8, j__, mem_dw)
    );

    let device = mkQspi_block(clocked_by slowclock, reset_by slow_rst);
    Ifc_qspi_apb#(aw,dw,uw,mem_id,mem_aw,mem_dw, mem_uw) qspi <- dc2apb(device, base, slowclock, slow_rst);
    return qspi;
  endmodule:mkqspi_apb

endpackage


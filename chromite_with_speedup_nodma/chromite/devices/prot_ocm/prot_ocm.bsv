// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd.
// see LICENSE.incore for more details on licensing terms
/*
Author: Babu P S, babu.ps@incoresemi.com @eflaner
Created on: Thursday 30 September 2021
*/
package prot_ocm;

  import FIFOF        :: * ;
  import Vector       :: * ;
  import Semi_FIFOF   :: * ;
  import DCBus        :: * ;

  import ram1rw_user  :: * ;
  import apb          :: * ;
  import axi4l        :: * ;
  import axi4         :: * ;
  import mem_config   :: * ;

  `define Machine_mode  2'b01 //Privileged Secure mode of AxPROT

  typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw),
                      Ifc_ocm_config#(id, addr, data, user, entries, width, banks))
    Ifc_ocmconfig_axi4l#(type aw, type dw, type uw, type id, type addr, type data,
                         type user, type entries, type width, type banks);
  typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw),
                      Ifc_ocm_config#(id, addr, data, user, entries, width, banks))
    Ifc_ocmconfig_apb#(type aw, type dw, type uw, type id, type addr, type data,
                       type user, type entries, type width, type banks);

  typedef enum {Idle, ReadBurst, WriteBurst} Fabric_State deriving(Eq, Bits, FShow);


  // ------------------------------ One Time Write-Only register -----------------------------------
  // Configuration register with One Time Write Capability.
  module regw1#(DCRAddr#(aw,o) attr, r rst)(IWithDCBus#(DCBus#(aw, dw), Reg#(r)))
    provisos (
        Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o)
      , Bits#(r, m), Eq#(r), Literal#(r)
      , Add#(a__, o, aw)
      , Mul#(TDiv#(dw, 8), 8, dw)   // bus-side data-width should be multiples of 8
      , Mul#(TDiv#(m, 8), 8, m)     // register data-width should be multiples of 8
      , Add#(dw, b__, 64)           // bus side data should be <= 64
      , Add#(m, c__, 64)            // register data should be <= 64
      , Add#(TExp#(TLog#(dw)),0,dw) // bus-side should be a power of 2.
      , Add#(TExp#(TLog#(m)),0,m)   // register side should be a power of 2
      , Add#(e__, TDiv#(dw, 8), 8)
    );

    Reg#(r) x();
    mkReg#(rst) inner_reg(x);
    PulseWire written <- mkPulseWire;

    interface DCBus dcbus;

      method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
        Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
        Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
        Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
        if ((req_index == reg_index) && perm) begin
          let {succ, temp} <- fn_adjust_write(addr, data, strobe, 0, attr.min, attr.max, attr.mask);
          if(succ && (x == rst)) begin  // give cbus write priority over device _write.
            x <= unpack(temp);
            written.send;
          end
          return succ;
        end
        else
          return False;
      endmethod:write

      method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
        return tuple2(False, 0);
      endmethod:read
    endinterface:dcbus

    interface Reg device;
      method Action _write (value);
        if (!written) x <= value;
      endmethod:_write

      method _read = x._read;
    endinterface
  endmodule:regw1

  // A wrapper to provide just a normal Reg interface and automatically
  // add the CBus interface to the collection.
  module [ModWithDCBus#(aw, dw)] mkDCBRegW1#(DCRAddr#(aw,o) attr, r x)(Reg#(r))
    provisos (
        Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o)
      , Bits#(r, m), Eq#(r), Literal#(r)
      , Add#(a__, o, aw)
      , Mul#(TDiv#(dw, 8), 8, dw)   // bus-side data-width should be multiples of 8
      , Mul#(TDiv#(m, 8), 8, m)     // register data-width should be multiples of 8
      , Add#(dw, b__, 64)           // bus side data should be <= 64
      , Add#(m, c__, 64)            // register data should be <= 64
      , Add#(TExp#(TLog#(dw)),0,dw) // bus-side should be a power of 2.
      , Add#(TExp#(TLog#(m)),0,m)   // register side should be a power of 2
      , Add#(e__, TDiv#(dw, 8), 8)
    );
    let ifc();
    collectDCBusIFC#(regw1(attr, x)) _temp(ifc);
    return(ifc);
  endmodule:mkDCBRegW1
  // -----------------------------------------------------------------------------------------------

  interface Ifc_ocm_config#(numeric type id, numeric type addr,
                            numeric type data, numeric type user,
                            numeric type entries, numeric type width,
                            numeric type banks);
    interface Ifc_axi4_slave#(id, addr, data, user) slave;
  endinterface:Ifc_ocm_config

  (*preempts="rl_read_request,rl_write_request"*)
  module [ModWithDCBus#(aw,dw)] mk_ocmblock#(parameter Integer base,
                                parameter Vector#(banks, LoadFormat) filename,
                                parameter String mode)
    (Ifc_ocm_config#(id, addr, data, user, entries, width, banks))
    provisos(
        Add#(16, _a, aw)        // address atleast 16 bits
      , Add#(8, _b, dw)         // data atleast 8 bits
      , Mul#(TDiv#(dw,8),8, dw) // dw is a proper multiple of 8 bits
      , Add#(_c, 3, aw)
      , Add#(dw, _d, 64)
      , Add#(_f, TDiv#(dw, 8), 8)
      , Add#(TExp#(TLog#(dw)),0,dw)
      , Log# (entries, index_size)
      , Div#(width, banks, bpb)
      , Div#(width,8,enables)
      , Div#(enables,banks,epb)
      , Mul#(bpb, banks, width)
      , Add#(a__, bpb, width)
      , Add#(index_size, b__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))))
      , Add#(c__, data, width)
      , Add#(d__, TDiv#(width, 8), TDiv#(data, 8))
      , Add#(e__, width, data)
      , Add#(f__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))), addr)
      , Add#(addr, h__, 64)
      , Add#(TExp#(TLog#(addr)), 0, addr)
      , Mul#(TDiv#(addr, 8), 8, addr)
    );

    DCRAddr#(aw,3) attr_txt_start = DCRAddr {addr: 'h0, min: Sz4, max: Sz8, mask: 'h0};
    Reg#(Bit#(addr)) rg_ocm_txt_start <- mkDCBRegW1(attr_txt_start , '0);

    DCRAddr#(aw,3) attr_txt_end = DCRAddr {addr: 'h8, min: Sz4, max: Sz8, mask: 'h0};
    Reg#(Bit#(addr)) rg_ocm_txt_end <- mkDCBRegW1(attr_txt_start , '0);

    DCRAddr#(aw,3) attr_lock_txt = DCRAddr {addr: 'h10, min: Sz1, max: Sz8, mask: 'h0};
    Reg#(Bit#(8)) rg_ocm_lock_txt <- mkDCBRegW1(attr_lock_txt , '0);

    Ifc_axi4_slave_xactor#(id, addr, data, user) s_xactor <- mkaxi4_slave_xactor_2;
    Ifc_ram1rw_user#(entries, width, banks)      ram <- mk_ram1rw_user(filename, mode);

    /*doc:reg: */
    Reg#(Fabric_State) rg_state <- mkReg(Idle);
    /*doc:reg: hold the request on the read-channel*/
    Reg#(Axi4_rd_addr#(id, addr, user)) rg_rd_req <- mkReg(unpack(0));
    /*doc:reg: hold the request on the read-channel*/
    Reg#(Axi4_wr_addr#(id, addr, user)) rg_wr_req <- mkReg(unpack(0));
    /*doc:reg: count the number of beats performed*/
    Reg#(Bit#(8)) rg_readreq_count<-mkReg(0);
    /*doc:reg: count the number of beats performed*/
    Reg#(Bit#(8)) rg_readresp_count[2] <-mkCReg(2,0);
    /*doc:reg: indicate the repsonse rule can fire now*/
    Reg#(Bool) rg_capture_response[2] <- mkCReg(2,False);
    /*doc:reg: Capture prot bits in ar_mode*/
    Reg#(Bit#(2)) rg_capture_prot[2] <-mkCReg(2,0);
    /*doc:reg: register holds the temp response for burst writes*/
    Reg#(Axi4_wr_resp #(id, user)) rg_write_response <-mkReg(unpack(0));

    /*doc:rule: read first request and send it to the dut.
      If it is a burst request then change state to Burst.
      capture the request type and keep track of counter.*/
    rule rl_read_request(rg_state == Idle && !rg_capture_response[1]);
      let ar <- pop_o(s_xactor.fifo_side.o_rd_addr);
      Bit#(addr) rel_addr = ar.araddr - fromInteger(base);
      if (truncate(ar.arprot) == `Machine_mode) begin
        ram.ma_request(False,truncate(rel_addr), ?, 0);
      end
      if(ar.arlen != 0)
        rg_state <= ReadBurst;
      rg_readreq_count <= ar.arlen;
      rg_readresp_count[1] <= ar.arlen;
      rg_capture_response[1] <= True;
      rg_capture_prot[1] <= truncate(ar.arprot);
      rg_rd_req <= ar;
    endrule:rl_read_request

    /*doc:rule: incase of burst read, generate the new
      address and send it to the dut untill the burst
      count has been reached. */
    rule rl_read_request_burst(rg_state == ReadBurst && !rg_capture_response[1]);
      if(rg_readreq_count == 1)
        rg_state <= Idle;

      let address=fn_axi4burst_addr(rg_rd_req.arlen,   rg_rd_req.arsize,
                                    rg_rd_req.arburst, rg_rd_req.araddr);
      rg_rd_req.araddr <= address;
      rg_readreq_count <= rg_readreq_count - 1;
      Bit#(addr) rel_addr = address - fromInteger(base);
      if (truncate(rg_rd_req.arprot) == `Machine_mode) begin
        ram.ma_request(False, truncate(rel_addr), ?, 0);
      end
      rg_capture_response[1] <= True;
    endrule:rl_read_request_burst

    rule rl_read_response (rg_capture_response[0]);
      Axi4_resp defalt = axi4_resp_slverr;
      Bit#(width) rd_data = ?;
      if (truncate(rg_capture_prot[0]) == `Machine_mode) begin
        let {data, err} = ram.mv_read_response;
        defalt = axi4_resp_okay;
        rd_data = data;
      end
      rg_readresp_count[0] <= rg_readresp_count[0] - 1;
      Axi4_rd_data#(id, data, user) r = Axi4_rd_data {rresp: defalt,
                                                      rdata: truncate(rd_data) ,
                                                      rlast: rg_readresp_count[0]==0,
                                                      ruser: 0,
                                                      rid  : rg_rd_req.arid};
      s_xactor.fifo_side.i_rd_data.enq(r);
      rg_capture_response[0] <= False;
    endrule:rl_read_response

    rule rl_write_request(rg_state == Idle);
      let aw <- pop_o (s_xactor.fifo_side.o_wr_addr);
      let w  <- pop_o (s_xactor.fifo_side.o_wr_data);
      let b = Axi4_wr_resp {bresp: axi4_resp_okay, buser: aw.awuser, bid:aw.awid};

      if((truncate(aw.awprot) != `Machine_mode) || ((rg_ocm_lock_txt != 0) &&
         ((aw.awaddr >= rg_ocm_txt_start) && (aw.awaddr <= rg_ocm_txt_end))))
          b = Axi4_wr_resp {bresp: axi4_resp_slverr, buser: aw.awuser, bid:aw.awid};
      else begin // allow access to everything
        Bit#(addr) rel_addr = aw.awaddr - fromInteger(base);
        ram.ma_request(True,truncate(rel_addr), truncate(w.wdata),truncate(w.wstrb));
      end
      if(!w.wlast) rg_state <= WriteBurst;
      else s_xactor.fifo_side.i_wr_resp.enq (b);
      rg_write_response <= b;
      rg_wr_req <= aw;
    endrule:rl_write_request

    /*doc:rule: if the request is a write burst then keeping
      popping all the data on the data_channel and send a
      error response on receiving the last data. */
    rule rl_write_response (rg_state == WriteBurst);
      let w  <- pop_o (s_xactor.fifo_side.o_wr_data);
      let address=fn_axi4burst_addr(rg_wr_req.awlen,   rg_wr_req.awsize,
                                    rg_wr_req.awburst, rg_wr_req.awaddr);
      rg_wr_req.awaddr <= address;
      let b = rg_write_response;
      b.buser = w.wuser;
      if(b.bresp != axi4_resp_slverr) begin
        Bit#(addr) rel_addr = address - fromInteger(base);
        ram.ma_request(True,truncate(rel_addr), truncate(w.wdata),truncate(w.wstrb));
      end
      if(w.wlast)begin
        s_xactor.fifo_side.i_wr_resp.enq (b);
        rg_state<= Idle;
      end
    endrule:rl_write_response

    interface slave = s_xactor.axi4_side;

  endmodule: mk_ocmblock

  module [Module] mk_prot_ocm_block#(parameter Integer base,
                                parameter Vector#(banks, LoadFormat) filename,
                                parameter String mode)
    (IWithDCBus#(DCBus#(aw,dw), Ifc_ocm_config#(id, addr, data, user, entries, width, banks)))
    provisos(
        Add#(16, _a, aw)
      , Add#(8, _b, dw)        // data atleast 8 bits
      , Mul#(TDiv#(dw,8),8, dw) // dw is a proper multiple of 8 bits
      , Add#(_c, 3, aw)
      , Add#(dw, _d, 64)
      , Add#(_f, TDiv#(dw, 8), 8)
      , Add#(TExp#(TLog#(dw)),0,dw)
      , Log# (entries, index_size)
      , Div#(width, banks, bpb)
      , Div#(width,8,enables)
      , Div#(enables,banks,epb)
      , Mul#(bpb, banks, width)
      , Add#(a__, bpb, width)
      , Add#(index_size, b__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))))
      , Add#(c__, data, width)
      , Add#(d__, TDiv#(width, 8), TDiv#(data, 8))
      , Add#(e__, width, data)
      , Add#(f__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))), addr)
      , Add#(addr, h__, 64)
      , Add#(TExp#(TLog#(addr)), 0, addr)
      , Mul#(TDiv#(addr, 8), 8, addr)
    );
    let ifc <- exposeDCBusIFC(mk_ocmblock(base, filename, mode));
    return ifc;
  endmodule:mk_prot_ocm_block

  module [Module] mk_prot_ocm_axi4l#(parameter Integer cfg_base, parameter Integer base,
                                parameter Vector#(banks, LoadFormat) filename,
                                parameter String mode, Clock cfg_clk, Reset cfg_rst)
    (Ifc_ocmconfig_axi4l#(aw, dw, uw, id, addr, data, user, entries, width, banks))
    provisos(
        Add#(16, _a, aw)
      , Add#(8, _b, dw)         // data atleast 8 bits
      , Mul#(TDiv#(dw,8),8, dw) // dw is a proper multiple of 8 bits
      , Add#(_c, 3, aw)
      , Add#(dw, _d, 64)
      , Add#(TExp#(TLog#(dw)),0,dw)
      , Add#(_f, TDiv#(dw, 8), 8)
      , Log# (entries, index_size)
      , Div#(width, banks, bpb)
      , Div#(width,8,enables)
      , Div#(enables,banks,epb)
      , Mul#(bpb, banks, width)
      , Add#(a__, bpb, width)
      , Add#(index_size, b__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))))
      , Add#(c__, data, width)
      , Add#(d__, TDiv#(width, 8), TDiv#(data, 8))
      , Add#(e__, width, data)
      , Add#(f__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))), addr)
      , Add#(addr, h__, 64)
      , Add#(TExp#(TLog#(addr)), 0, addr)
      , Mul#(TDiv#(addr, 8), 8, addr)
    );

    let ocm_mod = mk_prot_ocm_block(base, filename, mode, clocked_by cfg_clk, reset_by cfg_rst);
    Ifc_ocmconfig_axi4l#(aw, dw, uw, id, addr, data, user, entries, width, banks) ocmconfig <-
        dc2axi4l(ocm_mod, cfg_base, cfg_clk, cfg_rst);
    return ocmconfig;
  endmodule:mk_prot_ocm_axi4l

  module [Module] mk_prot_ocm_apb#(parameter Integer cfg_base, parameter Integer base,
                              parameter Vector#(banks, LoadFormat) filename,
                              parameter String mode, Clock cfg_clk, Reset cfg_rst)
    (Ifc_ocmconfig_apb#(aw, dw, uw, id, addr, data, user, entries, width, banks))
    provisos(
        Add#(16, _a, aw)
      , Add#(8, _b, dw)         // data atleast 8 bits
      , Mul#(TDiv#(dw,8),8, dw) // dw is a proper multiple of 8 bits
      , Add#(_c, 3, aw)
      , Add#(dw, _d, 64)
      , Add#(TExp#(TLog#(dw)),0,dw)
      , Add#(_f, TDiv#(dw, 8), 8)
      , Log# (entries, index_size)
      , Div#(width, banks, bpb)
      , Div#(width,8,enables)
      , Div#(enables,banks,epb)
      , Mul#(bpb, banks, width)
      , Add#(a__, bpb, width)
      , Add#(index_size, b__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))))
      , Add#(c__, data, width)
      , Add#(d__, TDiv#(width, 8), TDiv#(data, 8))
      , Add#(e__, width, data)
      , Add#(f__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))), addr)
      , Add#(addr, h__, 64)
      , Add#(TExp#(TLog#(addr)), 0, addr)
      , Mul#(TDiv#(addr, 8), 8, addr)
    );

    let ocm_mod = mk_prot_ocm_block(base, filename, mode, clocked_by cfg_clk, reset_by cfg_rst);
    Ifc_ocmconfig_apb#(aw, dw, uw, id, addr, data, user, entries, width, banks) ocmconfig <-
        dc2apb(ocm_mod, cfg_base, cfg_clk, cfg_rst);
    return ocmconfig;
  endmodule:mk_prot_ocm_apb

endpackage: prot_ocm

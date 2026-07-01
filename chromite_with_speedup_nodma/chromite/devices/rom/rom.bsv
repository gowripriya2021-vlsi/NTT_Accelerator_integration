// Copyright (c) InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Saturday 18 April 2020 09:50:58 PM IST

*/
package rom ;

import axi4         :: * ;
import axi4l        :: * ;
import apb          :: * ;
import DReg         :: * ;
import Vector       :: * ;

import Semi_FIFOF   :: * ;


export Ifc_rom_apb   (..);
export Ifc_rom_axi4l (..);
export Ifc_rom_axi4  (..);
export mk_rom_apb;
export mk_rom_axi4l;
export mk_rom_axi4;

`include "Logger.bsv"
import rom_user     :: * ;
interface Ifc_rom_apb# (numeric type addr, 
                        numeric type data, 
                        numeric type user, 
                        numeric type entries,
                        numeric type width, 
                        numeric type banks);
  interface Ifc_apb_slave#(addr, data, user) slave;
endinterface:Ifc_rom_apb

module mk_rom_apb#(parameter Integer base,
                   parameter Vector#(banks,String) filename)
  (Ifc_rom_apb#(addr, data, user, entries, width, banks))
  provisos( Log# (entries, index_size),
            Div#(width, banks, bpb),
            Mul#(bpb, banks, width),
            Add#(a__, bpb, width),
            Add#(b__, data, width),
            Add#(c__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))), addr)
  );
  Ifc_apb_slave_xactor#(addr, data, user) s_xactor <- mkapb_slave_xactor;
  Ifc_rom_user#(entries, width, banks)    rom      <- mk_rom_user(filename);
  /*doc:reg: capture request user info*/
  Reg#(Bit#(user)) rg_user <- mkReg(0);
  /*doc:reg: if write operation is received then set this to True*/
  Reg#(Bool) rg_fault <- mkDReg(False);
  /*doc:reg: indicate the repsonse rule can fire now*/
  Reg#(Bool) rg_capture_response <- mkDReg(False);

  /*doc:rule: */
  rule rl_receive_request;
    let req <- pop_o (s_xactor.fifo_side.o_request);
	  Bit#(addr) rel_addr = req.paddr - fromInteger(base);
    if (req.pwrite) begin
      rg_fault <= True;
    end
    else begin
      rom.ma_read(truncate(rel_addr));
      rg_user <= req.puser;
    end
    rg_capture_response <= True;
  endrule:rl_receive_request

  /*doc:rule: */
  rule rl_send_response(rg_capture_response);
    let {data, err} = rom.mv_read_response;
    APB_response#(data, user) resp = APB_response{prdata  : truncate(data), 
                                                  pslverr : rg_fault, 
                                                  puser   : rg_user};
    s_xactor.fifo_side.i_response.enq(resp);
  endrule:rl_send_response

  interface slave = s_xactor.apb_side;

endmodule: mk_rom_apb

interface Ifc_rom_axi4l# (numeric type addr, 
                        numeric type data, 
                        numeric type user, 
                        numeric type entries,
                        numeric type width, 
                        numeric type banks);
  interface Ifc_axi4l_slave#(addr, data, user) slave;
endinterface:Ifc_rom_axi4l

module mk_rom_axi4l#(parameter Integer base,
                     parameter Vector#(banks,String) filename)
  (Ifc_rom_axi4l#(addr, data, user, entries, width, banks))
  provisos( Log# (entries, index_size),
            Div#(width, banks, bpb),
            Mul#(bpb, banks, width),
            Add#(a__, bpb, width),
            Add#(b__, data, width),
            Add#(c__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))), addr)
  );
  Ifc_axi4l_slave_xactor#(addr, data, user) s_xactor <- mkaxi4l_slave_xactor_2;
  Ifc_rom_user#(entries, width, banks)      rom      <- mk_rom_user(filename);
  /*doc:reg: capture request user info*/
  Reg#(Bit#(user)) rg_user <- mkReg(0);
  /*doc:reg: indicate the repsonse rule can fire now*/
  Reg#(Bool) rg_capture_response <- mkDReg(False);

  /*doc:rule: */
  rule rl_receive_rd_request;
    let req <- pop_o (s_xactor.fifo_side.o_rd_addr);
	  Bit#(addr) rel_addr = req.araddr - fromInteger(base);
    rom.ma_read(truncate(rel_addr));
    rg_user <= req.aruser;
    rg_capture_response <= True;
  endrule:rl_receive_rd_request

  /*doc:rule: */
  rule rl_read_send_response(rg_capture_response);
    let {data, err} = rom.mv_read_response;
    Axi4l_rd_data#(data, user) resp = Axi4l_rd_data{rdata  : truncate(data), 
                                                    rresp  : axi4l_resp_okay, 
                                                    ruser  : rg_user};
    s_xactor.fifo_side.i_rd_data.enq(resp);
  endrule:rl_read_send_response
  
  rule rl_receive_wr_request;
    let req <- pop_o (s_xactor.fifo_side.o_wr_addr);
    let req_data <- pop_o (s_xactor.fifo_side.o_wr_data);
    s_xactor.fifo_side.i_wr_resp.enq(Axi4l_wr_resp{bresp: axi4l_resp_slverr, buser:req.awuser});
  endrule:rl_receive_wr_request

  interface slave = s_xactor.axi4l_side;

endmodule: mk_rom_axi4l

interface Ifc_rom_axi4# (numeric type id,
                         numeric type addr, 
                         numeric type data, 
                         numeric type user, 
                         numeric type entries,
                         numeric type width, 
                         numeric type banks);
  interface Ifc_axi4_slave#(id, addr, data, user) slave;
endinterface:Ifc_rom_axi4
  
typedef enum {Idle, Burst} Fabric_State deriving(Eq, Bits, FShow);

module mk_rom_axi4#(parameter Integer base,
                     parameter Vector#(banks,String) filename)
  (Ifc_rom_axi4#(id, addr, data, user, entries, width, banks))
  provisos( Log# (entries, index_size),
            Div#(width, banks, bpb),
            Mul#(bpb, banks, width),
            Add#(a__, bpb, width),
            Add#(b__, data, width),
            Add#(c__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))), addr)
  );

  Ifc_axi4_slave_xactor#(id,addr, data, user) s_xactor <- mkaxi4_slave_xactor_2;
  Ifc_rom_user#(entries, width, banks)        rom      <- mk_rom_user(filename);

  /*doc:reg: */
  Reg#(Fabric_State) rg_rd_state <- mkReg(Idle);
  /*doc:reg: */
  Reg#(Fabric_State) rg_wr_state <- mkReg(Idle);

  /*doc:reg: hold the request on the read-channel*/
  Reg#(Axi4_rd_addr#(id, addr, user)) rg_rd_req <- mkReg(unpack(0));
  /*doc:reg: count the number of beats performed*/
	Reg#(Bit#(8)) rg_readreq_count<-mkReg(0);
  /*doc:reg: count the number of beats performed*/
	Reg#(Bit#(8)) rg_readresp_count <-mkReg(0);
  /*doc:reg: indicate the repsonse rule can fire now*/
  Reg#(Bool) rg_capture_response <- mkDReg(False);
	
	/*doc:reg: register holds the temp response for burst writes*/
  Reg#(Axi4_wr_resp	#(id, user)) rg_write_response <-mkReg(unpack(0));

  /*doc:rule: read first request and send it to the dut. If it is a burst request then change state to
  Burst. capture the request type and keep track of counter.*/
  rule rl_read_request(rg_rd_state == Idle && !rg_capture_response);
	  let ar<- pop_o(s_xactor.fifo_side.o_rd_addr);
	  Bit#(addr) rel_addr = ar.araddr - fromInteger(base);
    rom.ma_read(truncate(rel_addr));
    if(ar.arlen != 0)
      rg_rd_state <= Burst;
    rg_readreq_count <= ar.arlen-1;
    rg_readresp_count <= ar.arlen;
	  rg_rd_req <= ar;
	  rg_capture_response <= True;
	  `logLevel( rom, 0, $format("ROM: RdReq: ",fshow(ar)))
  endrule:rl_read_request

  // incase of burst read,  generate the new address and send it to the dut untill the burst
  // count has been reached.
  rule rl_read_request_burst(rg_rd_state == Burst);
  	if(rg_readreq_count == 0)
  	  rg_rd_state <= Idle;

  	let address=fn_axi4burst_addr(rg_rd_req.arlen,   rg_rd_req.arsize, 
                                  rg_rd_req.arburst, rg_rd_req.araddr);
    rg_rd_req.araddr <= address;
	  Bit#(addr) rel_addr = address - fromInteger(base);
    rg_readreq_count <= rg_readreq_count - 1;
    rom.ma_read(truncate(rel_addr));
	  rg_capture_response <= True;
  endrule:rl_read_request_burst
  // get data from the bootrom. shift,  truncate, duplicate based on the size and offset.
  rule rl_read_response (rg_capture_response);
    let {data, err} = rom.mv_read_response;
    rg_readresp_count <= rg_readresp_count - 1;
    Axi4_rd_data#(id, data, user) r = Axi4_rd_data {rresp: axi4_resp_okay, 
                                                    rdata: truncate(data) , 
                                                    rlast: rg_readresp_count == 0, 
                                                    ruser: 0, 
                                                    rid  : rg_rd_req.arid};
    s_xactor.fifo_side.i_rd_data.enq(r);
   `logLevel( rom, 1, $format("ROM : RdResp: ", fshow (r)))
  endrule:rl_read_response
  
  rule rl_write_request(rg_wr_state == Idle);
    let aw <- pop_o (s_xactor.fifo_side.o_wr_addr);
    let w  <- pop_o (s_xactor.fifo_side.o_wr_data);
	  let b = Axi4_wr_resp {bresp: axi4_resp_slverr, buser: aw.awuser, bid:aw.awid};
    if(!w.wlast)
      rg_wr_state <= Burst;
    else
    	s_xactor.fifo_side.i_wr_resp.enq (b);
    rg_write_response <= b;
  endrule:rl_write_request
  // if the request is a write burst then keeping popping all the data on the data_channel and
  // send a error response on receiving the last data.
  rule rl_write_response (rg_wr_state == Burst);
    let w  <- pop_o (s_xactor.fifo_side.o_wr_data);
    let b = rg_write_response;
    b.buser = w.wuser;
    if(w.wlast)begin
		  s_xactor.fifo_side.i_wr_resp.enq (b);
      rg_wr_state<= Idle;
    end
  endrule:rl_write_response

  interface slave = s_xactor.axi4_side;

endmodule: mk_rom_axi4

endpackage: rom


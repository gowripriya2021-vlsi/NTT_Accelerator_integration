// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Sunday 19 April 2020 04:33:43 PM IST

*/
package ram2rw ;
import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import DReg         :: * ;
`include "Logger.bsv"
import apb          :: * ;
import axi4l        :: * ;
import axi4         :: * ;
import ram2rw_user  :: * ;
import Semi_FIFOF   :: * ;
import mem_config   :: * ;

export Ifc_ram2rw_apb   (..);
export Ifc_ram2rw_axi4l (..);
export Ifc_ram2rw_axi4  (..);
export mk_ram2rw_apb;
export mk_ram2rw_axi4l;
export mk_ram2rw_axi4;

interface Ifc_ram2rw_apb# (numeric type addr, 
                           numeric type data, 
                           numeric type user, 
                           numeric type entries,
                           numeric type width, 
                           numeric type banks);
  interface Ifc_apb_slave#(addr, data, user) slave;
endinterface:Ifc_ram2rw_apb

module mk_ram2rw_apb#(parameter Integer base,
                      parameter Vector#(banks,LoadFormat) filename, 
                      parameter String mode)
  (Ifc_ram2rw_apb#(addr, data, user, entries, width, banks))
  provisos( Log# (entries, index_size),
            Div#(width, banks, bpb),
            Div#(width,8,enables),
            Div#(enables,banks,epb),
            Mul#(bpb, banks, width),
            Add#(a__, bpb, width) ,
            Add#(index_size, b__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))))

            ,Add#(c__, data, width)
            ,Add#(d__, TDiv#(width, 8), TDiv#(data, 8))
            ,Add#(e__, width, data)
            ,Add#(f__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))), addr)

  );
  Ifc_apb_slave_xactor#(addr, data, user) s_xactor <- mkapb_slave_xactor;
  Ifc_ram2rw_user#(entries, width, banks) ram      <- mk_ram2rw_user(filename, mode);
  /*doc:reg: capture request user info*/
  Reg#(Bit#(user)) rg_user <- mkReg(0);
  /*doc:reg: indicate the repsonse rule can fire now*/
  Reg#(Bool) rg_capture_response <- mkDReg(False);

  /*doc:rule: */
  rule rl_receive_request;
    let req <- pop_o (s_xactor.fifo_side.o_request);
	  Bit#(addr) rel_addr = req.paddr - fromInteger(base);
    if(req.pwrite)
      ram.ma_write(truncate(rel_addr), truncate(req.pwdata), truncate(req.pstrb));
    else
      ram.ma_read(truncate(rel_addr));
    rg_capture_response <= True;
    rg_user <= req.puser;
  endrule:rl_receive_request

  /*doc:rule: */
  rule rl_send_response(rg_capture_response);
    let {data, err} = ram.mv_read_response;
    APB_response#(data, user) resp = APB_response{prdata  : truncate(data), 
                                                  pslverr : False, 
                                                  puser   : rg_user};
    s_xactor.fifo_side.i_response.enq(resp);
  endrule:rl_send_response

  interface slave = s_xactor.apb_side;

endmodule: mk_ram2rw_apb

interface Ifc_ram2rw_axi4l# (numeric type addr, 
                        numeric type data, 
                        numeric type user, 
                        numeric type entries,
                        numeric type width, 
                        numeric type banks);
  interface Ifc_axi4l_slave#(addr, data, user) slave;
endinterface:Ifc_ram2rw_axi4l

module mk_ram2rw_axi4l#(parameter Integer base,
                        parameter Vector#(banks, LoadFormat) filename,
                        parameter String mode)
  (Ifc_ram2rw_axi4l#(addr, data, user, entries, width, banks))
  provisos( Log# (entries, index_size),
            Div#(width, banks, bpb),
            Div#(width,8,enables),
            Div#(enables,banks,epb),
            Mul#(bpb, banks, width),
            Add#(a__, bpb, width) ,
            Add#(index_size, b__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))))

            ,Add#(c__, data, width)
            ,Add#(d__, TDiv#(width, 8), TDiv#(data, 8))
            ,Add#(e__, width, data)
            ,Add#(f__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))), addr)
  );
  Ifc_axi4l_slave_xactor#(addr, data, user) s_xactor <- mkaxi4l_slave_xactor_2;
  Ifc_ram2rw_user#(entries, width, banks)   ram      <- mk_ram2rw_user(filename, mode);
  /*doc:reg: capture request user info*/
  Reg#(Bit#(user)) rg_user <- mkReg(0);
  /*doc:reg: indicate the repsonse rule can fire now*/
  Reg#(Bool) rg_capture_response <- mkDReg(False);

  /*doc:rule: */
  rule rl_receive_rd_request;
    let req <- pop_o (s_xactor.fifo_side.o_rd_addr);
	  Bit#(addr) rel_addr = req.araddr - fromInteger(base);
    ram.ma_read(truncate(rel_addr));
    rg_user <= req.aruser;
    rg_capture_response <= True;
  endrule:rl_receive_rd_request

  /*doc:rule: */
  rule rl_read_send_response(rg_capture_response);
    let {data, err} = ram.mv_read_response;
    Axi4l_rd_data#(data, user) resp = Axi4l_rd_data{rdata  : truncate(data), 
                                                    rresp  : axi4l_resp_okay, 
                                                    ruser  : rg_user};
    s_xactor.fifo_side.i_rd_data.enq(resp);
  endrule:rl_read_send_response
  
  rule rl_receive_wr_request;
    let req <- pop_o (s_xactor.fifo_side.o_wr_addr);
    let req_data <- pop_o (s_xactor.fifo_side.o_wr_data);
	  Bit#(addr) rel_addr = req.awaddr - fromInteger(base);
    ram.ma_write(truncate(rel_addr), truncate(req_data.wdata), truncate(req_data.wstrb));
    s_xactor.fifo_side.i_wr_resp.enq(Axi4l_wr_resp{bresp: axi4l_resp_okay, buser:req.awuser});
  endrule:rl_receive_wr_request

  interface slave = s_xactor.axi4l_side;

endmodule: mk_ram2rw_axi4l

interface Ifc_ram2rw_axi4# (numeric type id,
                            numeric type addr, 
                            numeric type data, 
                            numeric type user, 
                            numeric type entries,
                            numeric type width, 
                            numeric type banks);
  interface Ifc_axi4_slave#(id, addr, data, user) slave;
endinterface:Ifc_ram2rw_axi4
  
typedef enum {Idle, Burst} Fabric_State deriving(Eq, Bits, FShow);

module mk_ram2rw_axi4#( parameter Integer base,
                        parameter Vector#(banks, LoadFormat) filename,
                        parameter String mode)
  (Ifc_ram2rw_axi4#(id, addr, data, user, entries, width, banks))
  provisos( Log# (entries, index_size),
            Div#(width, banks, bpb),
            Div#(width,8,enables),
            Div#(enables,banks,epb),
            Mul#(bpb, banks, width),
            Add#(a__, bpb, width) ,
            Add#(index_size, b__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))))

            ,Add#(c__, data, width)
            ,Add#(d__, TDiv#(width, 8), TDiv#(data, 8))
            ,Add#(e__, width, data)
            ,Add#(f__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8))), addr)
  );

  Ifc_axi4_slave_xactor#(id,addr, data, user) s_xactor <- mkaxi4_slave_xactor_2;
  Ifc_ram2rw_user#(entries, width, banks)     ram      <- mk_ram2rw_user(filename, mode);

  /*doc:reg: */
  Reg#(Fabric_State) rg_rd_state <- mkReg(Idle);
  /*doc:reg: */
  Reg#(Fabric_State) rg_wr_state <- mkReg(Idle);

  /*doc:reg: hold the request on the read-channel*/
  Reg#(Axi4_rd_addr#(id, addr, user)) rg_rd_req <- mkReg(unpack(0));
  /*doc:reg: hold the request on the read-channel*/
  Reg#(Axi4_wr_addr#(id, addr, user)) rg_wr_req <- mkReg(unpack(0));
  /*doc:reg: count the number of beats performed*/
	Reg#(Bit#(8)) rg_readreq_count<-mkReg(0);
  /*doc:reg: count the number of beats performed*/
	Reg#(Bit#(8)) rg_readresp_count[2] <-mkCReg(2, 0);
  /*doc:reg: indicate the repsonse rule can fire now*/
  Reg#(Bool) rg_capture_response[2] <- mkCReg(2,False);
	
	/*doc:reg: register holds the temp response for burst writes*/
  Reg#(Axi4_wr_resp	#(id, user)) rg_write_response <-mkReg(unpack(0));

  /*doc:rule: read first request and send it to the dut. If it is a burst request then change state to
  Burst. capture the request type and keep track of counter.*/
  rule rl_read_request(rg_rd_state == Idle && !rg_capture_response[1]);
	  let ar<- pop_o(s_xactor.fifo_side.o_rd_addr);
	  Bit#(addr) rel_addr = ar.araddr - fromInteger(base);
    ram.ma_read(truncate(rel_addr));
    if(ar.arlen != 0)
      rg_rd_state <= Burst;
    rg_readreq_count <= ar.arlen;
    rg_readresp_count[1] <= ar.arlen;
	  rg_rd_req <= ar;
	  rg_capture_response[1] <= True;
   `logLevel( ram2rw, 1, $format("RAM2RW : RdReq: ", fshow (ar)))
  endrule:rl_read_request

  // incase of burst read,  generate the new address and send it to the dut untill the burst
  // count has been reached.
  rule rl_read_request_burst(rg_rd_state == Burst && !rg_capture_response[1]);
  	if(rg_readreq_count == 1)
  	  rg_rd_state <= Idle;

  	let address=fn_axi4burst_addr(rg_rd_req.arlen,   rg_rd_req.arsize, 
                                  rg_rd_req.arburst, rg_rd_req.araddr);
    rg_rd_req.araddr <= address;
	  Bit#(addr) rel_addr = address - fromInteger(base);
    rg_readreq_count <= rg_readreq_count - 1;
   `logLevel( ram2rw, 1, $format("RAM2RW : Burst RdReq: ", fshow (rg_rd_req)))
    ram.ma_read(truncate(rel_addr));
	  rg_capture_response[1] <= True;
  endrule:rl_read_request_burst

  rule rl_read_response (rg_capture_response[0]);
    let {data, err} = ram.mv_read_response;
    rg_readresp_count[0] <= rg_readresp_count[0] - 1;
    Axi4_rd_data#(id, data, user) r = Axi4_rd_data {rresp: axi4_resp_okay, 
                                                    rdata: truncate(data) , 
                                                    rlast: rg_readresp_count[0]==0, 
                                                    ruser: 0, 
                                                    rid  : rg_rd_req.arid};
    s_xactor.fifo_side.i_rd_data.enq(r);
    rg_capture_response[0] <= False;

   `logLevel( ram2rw, 1, $format("RAM2RW : RdResp: ", fshow (r)))
  endrule:rl_read_response
  
  rule rl_write_request(rg_wr_state == Idle);
    let aw <- pop_o (s_xactor.fifo_side.o_wr_addr);
    let w  <- pop_o (s_xactor.fifo_side.o_wr_data);
	  let b = Axi4_wr_resp {bresp: axi4_resp_okay, buser: aw.awuser, bid:aw.awid};
	  Bit#(addr) rel_addr = aw.awaddr - fromInteger(base);
    ram.ma_write(truncate(rel_addr), truncate(w.wdata),truncate(w.wstrb));
    if(!w.wlast)
      rg_wr_state <= Burst;
    else
    	s_xactor.fifo_side.i_wr_resp.enq (b);
    rg_write_response <= b;
    rg_wr_req <= aw;
   `logLevel( ram2rw, 1, $format("RAM2RW : WrReq: ", fshow (aw)))
   `logLevel( ram2rw, 1, $format("RAM2RW : WrDReq: ", fshow (w)))
  endrule:rl_write_request
  // if the request is a write burst then keeping popping all the data on the data_channel and
  // send a error response on receiving the last data.
  rule rl_write_response (rg_wr_state == Burst);
    let w  <- pop_o (s_xactor.fifo_side.o_wr_data);
  	let address=fn_axi4burst_addr(rg_wr_req.awlen,   rg_wr_req.awsize, 
                                  rg_wr_req.awburst, rg_wr_req.awaddr);
    rg_wr_req.awaddr <= address;
    let b = rg_write_response;
    b.buser = w.wuser;
	  Bit#(addr) rel_addr = address - fromInteger(base);
    ram.ma_write(truncate(rel_addr), truncate(w.wdata),truncate(w.wstrb));
    if(w.wlast)begin
		  s_xactor.fifo_side.i_wr_resp.enq (b);
      rg_wr_state<= Idle;
      `logLevel( ram2rw, 1, $format("RAM2RW : RdResp: ", fshow (b)))
    end
  endrule:rl_write_response

  interface slave = s_xactor.axi4_side;

endmodule: mk_ram2rw_axi4

endpackage: ram2rw


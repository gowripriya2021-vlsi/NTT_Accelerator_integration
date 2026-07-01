/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Mon Mar 07, 2022 10:32:21 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
 */
package elfmem;

  `include "Logger.bsv"
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

  import "BDPI" function ActionValue#(Bit#(64)) load_elf(Bit#(64) base, Bit#(64) size,
  String modname);
  import "BDPI" function ActionValue#(Bit#(64)) read_f(Bit#(64) ptr, Bit#(64) addr);
  import "BDPI" function Action write_f(Bit#(64) ptr, Bit#(64) addr, Bit#(64) val, Bit#(8) sz);



  interface Ifc_elfmem#(numeric type addrwidth, numeric type respwidth);
    method ActionValue#(Bit#(respwidth)) mav_read(Bit#(addrwidth) addr);
    method Action ma_write(Bit#(addrwidth) addr, Bit#(respwidth) value, 
      Bit#(TDiv#(respwidth,8)) strb);
    method Bit#(respwidth) mv_read_response;
  endinterface

  module mk_elfmem#(Integer base, Integer bound,String debug)
      (Ifc_elfmem#(addrwidth,respwidth))provisos(
    Add#(a__, addrwidth, 64),
    Add#(b__,8, addrwidth),
    Mul#(TDiv#(respwidth, 64), 64, respwidth),
    Add#(c__, 8, TDiv#(respwidth, 8))
  );
    Reg#(Bit#(64)) rg_ptr <- mkReg(0);
    Reg#(Bool) rg_init <- mkReg(False);
    Reg#(Bit#(respwidth)) rg_last <- mkReg(0);

    rule rl_init(!rg_init);
      let lv_ptr <- load_elf(fromInteger(base),fromInteger(bound-base+1), debug);
      if(lv_ptr == 0) begin
        $fdisplay(stderr,"Error initialising memory from elf. File not found or error in file. Check log for further information.");
        $finish;
      end
      else begin
        rg_ptr <= lv_ptr;
        rg_init <= True;
      end
     
    endrule
    method ActionValue#(Bit#(respwidth)) mav_read(Bit#(addrwidth) addr) if (rg_init);
      Bit#(64) lv_response[valueof(respwidth)/64];
      for (Integer i = 0; i<valueof(respwidth)/64; i=i+1) begin
        let lv_resp <- read_f(rg_ptr,zeroExtend(addr+fromInteger(i*(8))));
        lv_response[i] = lv_resp;
      end
      rg_last <= pack(arrayToVector(lv_response));
      return pack(arrayToVector(lv_response));
    endmethod
    method Action ma_write(Bit#(addrwidth) addr, Bit#(respwidth) value, 
      Bit#(TDiv#(respwidth,8)) wstrb) 
      if (rg_init);
      Vector#(TDiv#(respwidth,64),Bit#(64)) lv_data = unpack(value);
      /* Bit#(addrwidth) lv_size = size; */
      for (Integer i=0; i<valueof(respwidth)/64;i=i+1) begin
        /* Bit#(addrwidth) temp = lv_size % 8; */
        Bit#(8) sz = truncate(wstrb >> i*8) ;
        let lv_addr = zeroExtend(addr+fromInteger(i*8));
        `logLevel(elfmem,1,$format(fshow(addr)," ",fshow(wstrb)," ",fshow(value)," ",fshow(sz)))
        write_f(rg_ptr,lv_addr,lv_data[i],sz);
      end
    endmethod
    method mv_read_response = rg_last;
  endmodule

  interface Ifc_elfmem_axi4# (numeric type id,
                              numeric type addr, 
                              numeric type data, 
                              numeric type user
                              );
    interface Ifc_axi4_slave#(id, addr, data, user) slave;
  endinterface:Ifc_elfmem_axi4
    
  typedef enum {Idle, Burst} Fabric_State deriving(Eq, Bits, FShow);

  function Bit#(m) resize(Bit#(n) x) provisos(Add#(m,n,mn));
    Bit#(mn) _temp = zeroExtend(x);
    return truncate(_temp);
  endfunction
  
  module mk_elfmem_axi4#(Integer base,
                         Integer bound,
                         String debug
                          )
    (Ifc_elfmem_axi4#(id, addr, data, user))
    provisos( 
      Add#(a__, addr, 64),
      Add#(b__,8, addr),
      Max#(data,64,edata),
      Mul#(TDiv#(edata, 64), 64, edata),
      Add#(c__, 8, TDiv#(edata, 8))
    );
  
    Ifc_axi4_slave_xactor#(id,addr, data, user) s_xactor <- mkaxi4_slave_xactor_2;
    Ifc_elfmem#(addr,edata)     mem      <- mk_elfmem(base,bound,debug);
  
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
  	  Bit#(addr) rel_addr = ar.araddr - fromInteger(base) - (ar.araddr%fromInteger(valueof(data)/8));
      let x <- mem.mav_read(truncate(rel_addr));
      if(ar.arlen != 0)
        rg_rd_state <= Burst;
      rg_readreq_count <= ar.arlen;
      rg_readresp_count[1] <= ar.arlen;
  	  rg_rd_req <= ar;
  	  rg_capture_response[1] <= True;
     `logLevel( elfmem, 1, $format("elfmem : RdReq: ", fshow (ar)))
    endrule:rl_read_request
  
    // incase of burst read,  generate the new address and send it to the dut untill the burst
    // count has been reached.
    rule rl_read_request_burst(rg_rd_state == Burst && !rg_capture_response[1]);
    	if(rg_readreq_count == 1)
    	  rg_rd_state <= Idle;
  
    	let address=fn_axi4burst_addr(rg_rd_req.arlen,   rg_rd_req.arsize, 
                                    rg_rd_req.arburst, rg_rd_req.araddr);
      rg_rd_req.araddr <= address;
  	  Bit#(addr) rel_addr = address - fromInteger(base) - (address%fromInteger(valueof(data)/8));
      rg_readreq_count <= rg_readreq_count - 1;
     `logLevel( elfmem, 1, $format("elfmem : Burst RdReq: ", fshow (rg_rd_req)))
      let _x <- mem.mav_read(resize(rel_addr));
  	  rg_capture_response[1] <= True;
    endrule:rl_read_request_burst
  
    rule rl_read_response (rg_capture_response[0]);
      let data = mem.mv_read_response;
      /* let err = False; */
      rg_readresp_count[0] <= rg_readresp_count[0] - 1;
      Axi4_rd_data#(id, data, user) r = Axi4_rd_data {rresp: axi4_resp_okay, 
                                                      rdata: resize(data) , 
                                                      rlast: rg_readresp_count[0]==0, 
                                                      ruser: 0, 
                                                      rid  : rg_rd_req.arid};
      s_xactor.fifo_side.i_rd_data.enq(r);
      rg_capture_response[0] <= False;
  
     `logLevel( elfmem, 1, $format("elfmem : RdResp: ", fshow (r)))
    endrule:rl_read_response
    
    rule rl_write_request(rg_wr_state == Idle);
      let aw <- pop_o (s_xactor.fifo_side.o_wr_addr);
      let w  <- pop_o (s_xactor.fifo_side.o_wr_data);
  	  let b = Axi4_wr_resp {bresp: axi4_resp_okay, buser: aw.awuser, bid:aw.awid};
  	  Bit#(addr) rel_addr = aw.awaddr - fromInteger(base);
      mem.ma_write(resize(rel_addr), resize(w.wdata),resize(w.wstrb));
      if(!w.wlast)
        rg_wr_state <= Burst;
      else
      	s_xactor.fifo_side.i_wr_resp.enq (b);
      rg_write_response <= b;
      rg_wr_req <= aw;
     `logLevel( elfmem, 1, $format("elfmem : WrReq: ", fshow (aw)))
     `logLevel( elfmem, 1, $format("elfmem : WrDReq: ", fshow (w)))
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
      mem.ma_write(resize(rel_addr), resize(w.wdata),resize(w.wstrb));
      if(w.wlast)begin
  		  s_xactor.fifo_side.i_wr_resp.enq (b);
        rg_wr_state<= Idle;
        `logLevel( elfmem, 1, $format("elfmem : RdResp: ", fshow (b)))
      end
    endrule:rl_write_response
  
    interface slave = s_xactor.axi4_side;
  
  endmodule: mk_elfmem_axi4


endpackage

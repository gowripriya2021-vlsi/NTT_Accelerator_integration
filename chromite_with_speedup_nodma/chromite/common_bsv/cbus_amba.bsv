// see LICENSE.incore for more details on licensing terms
/*
Author: Arjun Menon, arjun@incoresemi.com
Description: This package consists of modules that convert a module with IWithCBus interface to one
             with AXI4 or AXI4-Lite slave interfaces.
*/
package cbus_amba;
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import axi4l      :: * ;
  import axi4       :: * ;
  import apb        :: * ;
  import CBus       :: * ;
  import Semi_FIFOF :: * ;
  import FIFO       :: * ;
  import Clocks     :: * ;
  `include "Logger.bsv"

  interface Ifc_device#(type device_ifc);
    interface device_ifc io;
  endinterface

  interface IWithBus#(type slave_ifc, type device_ifc);
    interface slave_ifc slave;
    interface device_ifc device;
  endinterface

  function Bit#(cs) gen_cbus_strb(Bit#(as) axi_strb, Bit#(k) lower_addr_bits)
  provisos(Add#(cs, z__, as), Div#(as, cs, divs), Log#(cs, csbits));
    let v_k= valueOf(k);
    let v_csbits= valueOf(csbits);
    Bit#(csbits) some_zeros= 'd0;
    Bit#(TSub#(k,csbits)) addr_offset_to_shift= lower_addr_bits[v_k-1:v_csbits];
    Bit#(cs) cbus_strb= truncate(axi_strb >> { addr_offset_to_shift, some_zeros});
    return cbus_strb;
  endfunction

  module [Module] convertToAXI4LiteSlave#(module#(IWithCBus#(CBus#(j,k), i)) cbusM, Clock device_clk,
  Reset device_rst, parameter String name) (IWithBus#(Ifc_axi4l_slave#(aw, dw, uw), i))
  provisos(Mul#(TDiv#(dw,8), 8, dw),
           Log#(TDiv#(dw,8), dw_div8_bits),
           Add#(a__, j, aw),
           Add#(b__, k, dw),
           Add#(TDiv#(k, 8), c__, TDiv#(dw, 8)),
           Add#(d__, dw_div8_bits, aw));
    let v_awbits= valueOf(TLog#(aw));

    IWithCBus#(CBus#(j,k), i) cbusM_ifc();
    liftModule#(cbusM) _temp(cbusM_ifc);

    CBus#(j,k) uart_cbus_ifc = cbusM_ifc.cbus_ifc;
    i lv_device_ifc = cbusM_ifc.device_ifc;

    Ifc_axi4l_slave_xactor#(aw, dw, uw)  s_xactor<- mkaxi4l_slave_xactor_2();
    Clock bus_clk<-exposeCurrentClock;
    Reset bus_rst<-exposeCurrentReset;
    Bool sync_required=(bus_clk!=device_clk);

    if(!sync_required) begin // if bus clock and device clock are same

      //capturing the read requests
      rule capture_read_request;
        let rd_req <- pop_o (s_xactor.fifo_side.o_rd_addr);
        `logLevel( name, 0, $format("%s: Read req: ", name, fshow(rd_req)))
        let {rdata, succ} <- uart_cbus_ifc.read(truncate(rd_req.araddr));
        let lv_resp= Axi4l_rd_data {rresp: succ? axi4l_resp_okay : axi4l_resp_slverr, 
                                        rdata: zeroExtend(rdata), ruser: rd_req.aruser};
        s_xactor.fifo_side.i_rd_data.enq(lv_resp);
      endrule              
  
      // capturing write requests
      rule capture_write_request;
        let wr_req  <- pop_o(s_xactor.fifo_side.o_wr_addr);
        let wr_data <- pop_o(s_xactor.fifo_side.o_wr_data);
        `logLevel( name, 0, $format("%s: Write req: ", name, fshow(wr_req)))
        Bit#(dw_div8_bits) lv_lower_addr_bits= truncate(wr_req.awaddr);
        Bit#(TDiv#(k,8)) cbus_strb= gen_cbus_strb(wr_data.wstrb, lv_lower_addr_bits);
        let succ <- uart_cbus_ifc.write(truncate(wr_req.awaddr),truncate(wr_data.wdata), cbus_strb);
        let lv_resp = Axi4l_wr_resp {bresp: succ? axi4l_resp_okay : axi4l_resp_slverr, buser: ?};
        s_xactor.fifo_side.i_wr_resp.enq(lv_resp);
      endrule
    end
    else begin // if bus clock and device clock are different

      SyncFIFOIfc#(Axi4l_rd_addr#(aw,uw)) ff_rd_req  <- mkSyncFIFOFromCC(3,device_clk);
      SyncFIFOIfc#(Axi4l_wr_addr#(aw,uw)) ff_wr_req  <- mkSyncFIFOFromCC(3,device_clk);
      SyncFIFOIfc#(Axi4l_wr_data#(dw)) ff_wdata_req  <- mkSyncFIFOFromCC(3,device_clk);
      SyncFIFOIfc#(Axi4l_rd_data#(dw,uw)) ff_rd_resp <- mkSyncFIFOToCC(3,device_clk,device_rst);
      SyncFIFOIfc#(Axi4l_wr_resp#(uw)) ff_wr_resp    <- mkSyncFIFOToCC(3,device_clk,device_rst);

      //capturing the read requests
      rule capture_read_request;
        let rd_req <- pop_o (s_xactor.fifo_side.o_rd_addr);
        ff_rd_req.enq(rd_req);
      endrule

      rule perform_read;
        let rd_req = ff_rd_req.first;
        `logLevel( name, 0, $format("%s: Read req: ", name, fshow(rd_req)))
        ff_rd_req.deq;
        let {rdata, succ} <- uart_cbus_ifc.read(truncate(rd_req.araddr));
        let lv_resp= Axi4l_rd_data {rresp: succ? axi4l_resp_okay : axi4l_resp_slverr, 
                                        rdata: zeroExtend(rdata), ruser: rd_req.aruser};
        ff_rd_resp.enq(lv_resp);
      endrule

      rule send_read_response;
        ff_rd_resp.deq;
        s_xactor.fifo_side.i_rd_data.enq(ff_rd_resp.first);
      endrule              
  
      // capturing write requests
      rule capture_write_request;
        let wr_req  <- pop_o(s_xactor.fifo_side.o_wr_addr);
        let wr_data <- pop_o(s_xactor.fifo_side.o_wr_data);
        ff_wr_req.enq(wr_req);
        ff_wdata_req.enq(wr_data);
      endrule

      rule perform_write;
        let wr_req  = ff_wr_req.first;
        let wr_data = ff_wdata_req.first;
        `logLevel( name, 0, $format("%s: Write req: ", name, fshow(wr_req)))
        Bit#(dw_div8_bits) lv_lower_addr_bits= truncate(wr_req.awaddr);
        Bit#(TDiv#(k,8)) cbus_strb= gen_cbus_strb(wr_data.wstrb, lv_lower_addr_bits);
        let succ <- uart_cbus_ifc.write(truncate(wr_req.awaddr),truncate(wr_data.wdata), cbus_strb);
        let lv_resp = Axi4l_wr_resp {bresp: succ? axi4l_resp_okay : axi4l_resp_slverr,
                                         buser: wr_req.awuser};
        ff_wr_resp.enq(lv_resp);
      endrule

      rule send_write_response;
        ff_wr_resp.deq;
        s_xactor.fifo_side.i_wr_resp.enq(ff_wr_resp.first);
      endrule
    end

    interface slave = s_xactor.axi4l_side;
    interface device = lv_device_ifc; 
  endmodule

  module [Module] convertToAXI4Slave#(module#(IWithCBus#(CBus#(j,k), i)) cbusM, Clock device_clk,
  Reset device_rst, parameter String name) (IWithBus#(Ifc_axi4_slave#(iw, aw, dw, uw), i))
  provisos(Mul#(TDiv#(dw,8), 8, dw),
           Log#(TDiv#(dw,8), dw_div8_bits),
           Add#(a__, j, aw),
           Add#(b__, k, dw),
           Add#(TDiv#(k, 8), c__, TDiv#(dw, 8)),
           Add#(d__, dw_div8_bits, aw));
    let v_awbits= valueOf(TLog#(aw));
    
    IWithCBus#(CBus#(j,k), i) cbusM_ifc();
    liftModule#(cbusM) _temp(cbusM_ifc);

    CBus#(j,k) uart_cbus_ifc = cbusM_ifc.cbus_ifc;
    i lv_device_ifc = cbusM_ifc.device_ifc;

    Ifc_axi4_slave_xactor#(iw, aw, dw, uw)  s_xactor <- mkaxi4_slave_xactor_2();
    Clock bus_clk<-exposeCurrentClock;
    Reset bus_rst<-exposeCurrentReset;
    Bool sync_required=(bus_clk!=device_clk);
    Reg#(Bit#(8)) rg_rdburst_count <- mkReg(0, clocked_by device_clk, reset_by device_rst);
    Reg#(Bit#(8)) rg_wrburst_count <- mkReg(0, clocked_by device_clk, reset_by device_rst);

    if(!sync_required) begin // if bus clock and device clock are same
      Reg#(Axi4_rd_addr#(iw, aw,uw)) rg_rdpacket <- mkReg(?);
      Reg#(Axi4_wr_addr#(iw, aw,uw)) rg_wrpacket <- mkReg(?);
      //capturing the read requests
      rule capture_read_request(rg_rdburst_count==0);
        let rd_req <- pop_o (s_xactor.fifo_side.o_rd_addr);
        let {rdata, succ} <- uart_cbus_ifc.read(truncate(rd_req.araddr));
        rg_rdpacket<=rd_req;  
        `logLevel( name, 0, $format("%s: Read req: ", name, fshow(rd_req)))
        `logLevel( name, 0, $format("%s: Read resp: %d", name, rdata))
        if(rd_req.arlen!=0)
          rg_rdburst_count<=1;
        let lv_resp= Axi4_rd_data {rresp: succ? axi4_resp_okay : axi4_resp_slverr, rid:rd_req.arid, 
                                   rlast: (rd_req.arlen==0), rdata: zeroExtend(rdata),
                                   ruser: rd_req.aruser}; //TODO user?
        s_xactor.fifo_side.i_rd_data.enq(lv_resp);//sending back the response
      endrule             

      rule burst_reads(rg_rdburst_count!=0);
        let rd_req=rg_rdpacket;
        let {rdata, succ} <- uart_cbus_ifc.read(truncate(rd_req.araddr));
        if(rg_rdburst_count==rd_req.arlen)
          rg_rdburst_count<=0;
        else
          rg_rdburst_count<=rg_rdburst_count+1;
        let lv_resp= Axi4_rd_data {rresp: succ? axi4_resp_okay : axi4_resp_slverr, rid:rd_req.arid, 
                                   rlast: (rd_req.arlen==rg_rdburst_count), rdata: zeroExtend(rdata),
                                   ruser: rd_req.aruser}; //TODO user?
        s_xactor.fifo_side.i_rd_data.enq(lv_resp);//sending back the response
      endrule
  
      // capturing write requests
      rule capture_write_request(rg_wrburst_count==0);
        let wr_req  <- pop_o(s_xactor.fifo_side.o_wr_addr);
        let wr_data <- pop_o(s_xactor.fifo_side.o_wr_data);
        `logLevel( name, 0, $format("%s: Write req: ", name, fshow(wr_req)))
        Bit#(dw_div8_bits) lv_lower_addr_bits= truncate(wr_req.awaddr);
        Bit#(TDiv#(k,8)) cbus_strb= gen_cbus_strb(wr_data.wstrb, lv_lower_addr_bits);
        let succ <- uart_cbus_ifc.write(truncate(wr_req.awaddr),truncate(wr_data.wdata), cbus_strb);
        rg_wrpacket<=wr_req;  
        if(wr_req.awlen!=0)
          rg_wrburst_count<=1;
        let lv_resp = Axi4_wr_resp {bresp: succ? axi4_resp_okay : axi4_resp_slverr,
                                    buser: wr_req.awuser, bid: wr_req.awid};
        if(wr_data.wlast)
          s_xactor.fifo_side.i_wr_resp.enq(lv_resp);//enqueuing the write response
      endrule

      rule burst_writes(rg_wrburst_count!=0);
        let wr_req=rg_wrpacket;
        let wr_data <- pop_o(s_xactor.fifo_side.o_wr_data);
        Bit#(dw_div8_bits) lv_lower_addr_bits= truncate(wr_req.awaddr);
        Bit#(TDiv#(k,8)) cbus_strb= gen_cbus_strb(wr_data.wstrb, lv_lower_addr_bits);
        let succ <- uart_cbus_ifc.write(truncate(wr_req.awaddr),truncate(wr_data.wdata), cbus_strb);
        if(rg_wrburst_count==wr_req.awlen)
          rg_wrburst_count<=0;
        else
          rg_wrburst_count<=rg_wrburst_count+1;
        let lv_resp = Axi4_wr_resp {bresp: succ? axi4_resp_okay : axi4_resp_slverr,
                                    buser: wr_req.awuser, bid: wr_req.awid};
        if(wr_data.wlast)
          s_xactor.fifo_side.i_wr_resp.enq(lv_resp);//enqueuing the write response
      endrule
    end
    else begin // if core clock and device_clk is different.
      SyncFIFOIfc#(Axi4_rd_addr#(iw, aw, uw)) ff_rd_request  <- mkSyncFIFOFromCC(3,device_clk);
      SyncFIFOIfc#(Axi4_wr_addr#(iw, aw, uw)) ff_wr_request  <- mkSyncFIFOFromCC(3,device_clk);
      SyncFIFOIfc#(Axi4_wr_data#(dw, uw)) ff_wdata_request   <- mkSyncFIFOFromCC(3,device_clk);
      SyncFIFOIfc#(Axi4_rd_data#(iw, dw, uw)) ff_rd_response <- mkSyncFIFOToCC(3,device_clk,device_rst);
      SyncFIFOIfc#(Axi4_wr_resp#(iw, uw)) ff_wr_response     <- mkSyncFIFOToCC(3,device_clk,device_rst);

      //capturing the read requests
      rule capture_read_request;
        let rd_req <- pop_o (s_xactor.fifo_side.o_rd_addr);
        ff_rd_request.enq(rd_req);
      endrule

      rule perform_read(rg_rdburst_count==0);
        let rd_req = ff_rd_request.first;
        `logLevel( name, 0, $format("%s: Read req: ", name, fshow(rd_req)))
        if(rd_req.arlen!=0)
          rg_rdburst_count<=1;
        else
          ff_rd_request.deq;
        let {rdata, succ} <- uart_cbus_ifc.read(truncate(rd_req.araddr));
        let lv_resp= Axi4_rd_data {rresp: succ? axi4_resp_okay : axi4_resp_slverr, rid: rd_req.arid, 
                                   rlast: (rg_rdburst_count==rd_req.arlen), rdata: zeroExtend(rdata),
                                   ruser: rd_req.aruser}; //TODO user?
        ff_rd_response.enq(lv_resp);
      endrule

      rule perform_read_burst(rg_rdburst_count!=0);
        let rd_req = ff_rd_request.first;
        let {rdata, succ} <- uart_cbus_ifc.read(truncate(rd_req.araddr));
        if(rg_rdburst_count==rd_req.arlen)begin
          rg_rdburst_count<=0;
          ff_rd_request.deq;
        end
        else
          rg_rdburst_count<=rg_rdburst_count+1;
          let lv_resp= Axi4_rd_data {rresp: succ? axi4_resp_okay : axi4_resp_slverr, rid: rd_req.arid, 
                                     rlast: (rd_req.arlen==rg_rdburst_count), rdata: zeroExtend(rdata),
                                     ruser: rd_req.aruser}; //TODO user?
          ff_rd_response.enq(lv_resp);//sending back the response
      endrule

      rule send_read_response;
        ff_rd_response.deq;
        s_xactor.fifo_side.i_rd_data.enq(ff_rd_response.first);//sending back the response
      endrule              
  
      // capturing write requests
      rule capture_writeaddr_request;
        let wr_req  <- pop_o(s_xactor.fifo_side.o_wr_addr);
        ff_wr_request.enq(wr_req);
      endrule
      
      rule capture_writedata_request;
        let wr_data <- pop_o(s_xactor.fifo_side.o_wr_data);
        ff_wdata_request.enq(wr_data);
      endrule

      rule perform_write(rg_wrburst_count==0);
        let wr_req  = ff_wr_request.first;
        let wr_data = ff_wdata_request.first;
        `logLevel( name, 0, $format("%s: Write req: ", name, fshow(wr_req)))
        if( wr_req.awlen!=0)
          rg_wrburst_count<=1;
        else 
          ff_wr_request.deq;
  
        ff_wdata_request.deq;
        Bit#(dw_div8_bits) lv_lower_addr_bits= truncate(wr_req.awaddr);
        Bit#(TDiv#(k,8)) cbus_strb= gen_cbus_strb(wr_data.wstrb, lv_lower_addr_bits);
        let succ <- uart_cbus_ifc.write(truncate(wr_req.awaddr),truncate(wr_data.wdata), cbus_strb);
        let lv_resp = Axi4_wr_resp {bresp: succ? axi4_resp_okay : axi4_resp_slverr,
                                    buser: wr_req.awuser, bid: wr_req.awid};
        if(wr_data.wlast)
          ff_wr_response.enq(lv_resp);
      endrule
      
      rule perform_burst_writes(rg_wrburst_count!=0);
        let wr_req=ff_wr_request.first;
        let wr_data =ff_wdata_request.first;
        Bit#(dw_div8_bits) lv_lower_addr_bits= truncate(wr_req.awaddr);
        Bit#(TDiv#(k,8)) cbus_strb= gen_cbus_strb(wr_data.wstrb, lv_lower_addr_bits);
        let succ <- uart_cbus_ifc.write(truncate(wr_req.awaddr),truncate(wr_data.wdata), cbus_strb);
        if(rg_wrburst_count==wr_req.awlen)begin
          rg_wrburst_count<=0;
          ff_wr_request.deq;
        end
        else
          rg_wrburst_count<=rg_wrburst_count+1;
        let lv_resp = Axi4_wr_resp {bresp: succ? axi4_resp_okay : axi4_resp_slverr,
                                    buser: wr_req.awuser, bid: wr_req.awid};
        if(wr_data.wlast)
          ff_wr_response.enq(lv_resp);
      endrule

      rule send_write_response;
        ff_wr_response.deq;
        s_xactor.fifo_side.i_wr_resp.enq(ff_wr_response.first);//enqueuing the write response
      endrule
    end

    interface slave = s_xactor.axi4_side;
    interface device = lv_device_ifc; 
  endmodule

  module [Module] convertToAPBSlave#(module#(IWithCBus#(CBus#(j,k), i)) cbusM, Clock device_clk,
  Reset device_rst, parameter String name) (IWithBus#(Ifc_apb_slave#(aw, dw, uw), i))
  provisos(Mul#(TDiv#(dw,8), 8, dw),
           Log#(TDiv#(dw,8), dw_div8_bits),
           Add#(a__, j, aw),
           Add#(b__, k, dw),
           Add#(TDiv#(k, 8), c__, TDiv#(dw, 8)),
           Add#(d__, dw_div8_bits, aw)
      );
    //let v_awbits= valueOf(TLog#(aw));

    IWithCBus#(CBus#(j,k), i) cbusM_ifc();
    liftModule#(cbusM) _temp(cbusM_ifc);

    CBus#(j,k) uart_cbus_ifc = cbusM_ifc.cbus_ifc;
    i lv_device_ifc = cbusM_ifc.device_ifc;

    Ifc_apb_slave_xactor#(aw, dw, uw) s_xactor <- mkapb_slave_xactor;
    Clock bus_clk<-exposeCurrentClock;
    Reset bus_rst<-exposeCurrentReset;
    Bool sync_required=(bus_clk!=device_clk);

    if(!sync_required) begin // if bus clock and device clock are same
      rule rl_take_request;
        let req <- pop_o(s_xactor.fifo_side.o_request);
        APB_response#(dw, uw) resp;
        `logLevel( name, 1, $format("%s: Req:", name, fshow_apb_req(req)))
        if ( req.pwrite ) begin // write operation
          Bit#(dw_div8_bits) lv_lower_addr_bits= truncate(req.paddr);
          Bit#(TDiv#(k,8)) cbus_strb= gen_cbus_strb(req.pstrb, lv_lower_addr_bits);
          let succ <- uart_cbus_ifc.write(truncate(req.paddr),truncate(req.pwdata), cbus_strb);
          resp= APB_response{ pslverr: succ, prdata: ?, puser:req.puser};
          `logLevel( name, 1, $format("%s: Write Resp:", name, fshow_apb_resp(resp)))
        end
        else begin  //read operation
          let {rdata, succ} <- uart_cbus_ifc.read(truncate(req.paddr));
          resp= APB_response{ pslverr: succ, prdata: zeroExtend(rdata), puser:req.puser};
          `logLevel( name, 1, $format("%s: Read Resp:", name, fshow_apb_resp(resp)))
        end
        s_xactor.fifo_side.i_response.enq(resp);
      endrule
    end
    else begin
      SyncFIFOIfc#(APB_request#(aw, dw, uw)) ff_request  <- mkSyncFIFOFromCC(3,device_clk);
      SyncFIFOIfc#(APB_response#(dw, uw)) ff_response <- mkSyncFIFOToCC(3,device_clk,device_rst);

      //capturing the requests
      rule capture_request;
        let req <- pop_o (s_xactor.fifo_side.o_request);
        ff_request.enq(req);
      endrule

      rule perform_req;
        let req = ff_request.first;
        ff_request.deq;
        APB_response#(dw, uw) resp;
        `logLevel( name, 1, $format("%s: Req:", name, fshow_apb_req(req)))
        if ( req.pwrite ) begin // write operation
          Bit#(dw_div8_bits) lv_lower_addr_bits= truncate(req.paddr);
          Bit#(TDiv#(k,8)) cbus_strb= gen_cbus_strb(req.pstrb, lv_lower_addr_bits);
          let succ <- uart_cbus_ifc.write(truncate(req.paddr),truncate(req.pwdata), cbus_strb);
          resp= APB_response{ pslverr: succ, prdata: ?, puser:req.puser};
          `logLevel( name, 1, $format("%s: Write Resp:", name, fshow_apb_resp(resp)))
        end
        else begin  //read operation
          let {rdata, succ} <- uart_cbus_ifc.read(truncate(req.paddr));
          resp= APB_response{ pslverr: succ, prdata: zeroExtend(rdata), puser:req.puser};
          `logLevel( name, 1, $format("%s: Read Resp:", name, fshow_apb_resp(resp)))
        end
        ff_response.enq(resp);
      endrule

      rule send_response;
        ff_response.deq;
        s_xactor.fifo_side.i_response.enq(ff_response.first);//enqueuing the response
      endrule
    end
    interface slave = s_xactor.apb_side;
    interface device = lv_device_ifc; 
  endmodule
endpackage

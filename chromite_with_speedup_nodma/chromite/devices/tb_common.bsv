// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Saturday 25 April 2020 07:49:08 AM IST

*/
  
function Action fn_pass_on_apb_error(Integer i);
  action
    let resp <- pop_o(master.fifo_side.o_response);
    if (resp.pslverr) $display("[%2d] Bus Error Caught: %h",i,resp.prdata);
    else begin $display("[%2d] FAILED: Expected SLVERR",i); $finish(0); end
  endaction
endfunction

function Action fn_fail_on_apb_error(Integer i);
  action
    let resp <- pop_o(master.fifo_side.o_response);
    if (!resp.pslverr) $display("Response[%2d] OKAY: %h",i,resp.prdata);
    else begin $display("[%2d] FAILED: Expected NO SLVERR", i); $finish(0); end
  endaction
endfunction

function Action fn_send_read (Bit#(`paddr) addr);
  action
    master.fifo_side.i_request.enq(APB_request {paddr:addr, pwdata: ?, pwrite: False, pstrb:'1});      
  endaction
endfunction

function Action fn_send_write (Bit#(`paddr) addr, Bit#(`datasize) data, Bit#(TDiv#(`datasize,8)) strobe);
  action
    master.fifo_side.i_request.enq(APB_request {paddr:addr, pwdata: data, pwrite: True,
    pstrb:strobe});      
  endaction
endfunction

function Action fn_checknfail_on_apb_error(Integer i, Bit#(`datasize) exp_data);
  action
    let resp <- pop_o(master.fifo_side.o_response);
    if (!resp.pslverr) $display("Response[%2d] Resp-OKAY: Received%h",i,resp.prdata);
    else begin $display("[%2d] FAILED: Expected NO SLVERR", i); $finish(0); end

    if(resp.prdata != exp_data) begin $display("[%2d] FAILED: Expected Data:%h",i,exp_data);end
  endaction
endfunction


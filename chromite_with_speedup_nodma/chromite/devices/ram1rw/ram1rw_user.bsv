// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Sunday 19 April 2020 01:56:02 PM IST

*/
package ram1rw_user ;
  import FIFOF        :: * ;
  import Vector       :: * ;
  import SpecialFIFOs :: * ;
  import FIFOF        :: * ;
  import BUtils       :: * ;
  import Assert       :: * ;
 
  import mem_config   :: * ;

  `include "Logger.bsv"
interface Ifc_ram1rw_user #( numeric type entries, 
                             numeric type width,
                             numeric type banks);
  (*always_ready*)
  method Tuple2#(Bit#(width),Bool) mv_read_response;
  (*always_ready, always_enabled*)
  method Action ma_request  ( Bool read_write, 
                            Bit#(TAdd#(TLog#(entries),TLog#(TDiv#(width,8)))) addr, 
                            Bit#(width) data,
                            Bit#(TDiv#(width,8)) strb);
endinterface:Ifc_ram1rw_user

/*doc:module: */
module mk_ram1rw_user #(
                        parameter Vector#(banks,LoadFormat) filename, 
                        parameter String mode)
  (Ifc_ram1rw_user#(entries, width, banks))
  provisos( Log# (entries, index_size),
            Div#(width, banks, bpb),
            Div#(width,8,enables),
            Div#(enables,banks,epb),
            Mul#(bpb, banks, width),
            Add#(a__, bpb, width) ,
            Add#(index_size, b__, TAdd#(TLog#(entries), TLog#(TDiv#(width, 8)))));

  staticAssert( mode == "nc" || mode == "wf" || mode == "rf", "Mode for ram1rw module can \
be only one of the following: nc (no-change), wf(write-first), rf(read-first)");

  let v_entries = valueOf(entries);
  let v_banks   = valueOf(banks);
  let v_bpb     = valueOf(bpb);
  let v_epb      = valueOf(epb);
  let v_offset  = valueOf(TLog#(TDiv#(width,8)));

  Vector #( banks, Ifc_brambe_1rw#( index_size, bpb, entries)) v_mem;
  for (Integer i = 0; i< v_banks; i = i + 1) begin
    v_mem[i] <- mkbrambe_1rw(filename[i], mode);
  end
  
  method Tuple2#(Bit#(width),Bool) mv_read_response;
    Bit#(width) _temp = ?;
    for (Integer i = 0; i< v_banks; i = i + 1) begin
      _temp[i*v_bpb+v_bpb - 1:i*v_bpb] = v_mem[i].response();
    end
    return tuple2(_temp, False);
  endmethod:mv_read_response

  method Action ma_request( Bool read_write, 
                            Bit#(TAdd#(TLog#(entries),TLog#(TDiv#(width,8)))) addr, 
                            Bit#(width) data,
                            Bit#(TDiv#(width,8)) strb);
    addr = addr >> v_offset;
    for (Integer i = 0; i<v_banks; i = i + 1) begin
      v_mem[i].request( duplicate(pack(read_write)) &strb[i*v_epb+v_epb-1:i*v_epb], 
                    truncate(addr), 
                    data[i*v_bpb+v_bpb-1:i*v_bpb]) ;
    end
  endmethod:ma_request
endmodule:mk_ram1rw_user

endpackage: ram1rw_user


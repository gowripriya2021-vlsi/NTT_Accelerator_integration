/*
see LICENSE.incore
see LICENSE.iitm

Author: Neel Gala,Deepa N. Sarma
Email id: neelgala@gmail.com
Details:
--------------------------------------------------------------------------------------------------
*/
package imem_tb;

  import imem::*;
  import icache_types::*;
  import mem_config::*;
  import GetPut::*;
  import FIFOF::*;
  import BUtils ::*;
  import FIFOF ::*;
  import DReg::*;
  import RegFile::*;
  import Vector::*;
  import Connectable::*;
  import test_icache::*;
  import io_func :: * ;
  `include "Logger.bsv"


  (*synthesize*)
  module mktest(Ifc_test_caches#(`iwords , `iblocks , `isets , `iways, 
                                      TMul#(`iwords,8) ,`paddr, `ibuswidth ));
    let ifc();
    mktest_caches _temp(ifc);
    return (ifc);
  endmodule
  function Bit#(awidth) fn_axi4burst_addr(Bit#(8) arlen, Bit#(3) arsize, Bit#(2) arburst, 
                                          Bit#(awidth) address );

	  // this variable will decide the index above which part of the address should
	  // not change in WRAP mode. Bits below this index value be incremented according
	  // to the value of arlen and arsize;
	  Bit#(3) wrap_size;
	  case(arlen)
		  3: wrap_size= 2;
		  7: wrap_size= 3;
		  15: wrap_size=4;
		  default:wrap_size=1;
	  endcase

    // this is address will directly be used for INCR mode
	  Bit#(awidth) new_address=address+(('b1)<<arsize);
	  Bit#(awidth) mask;
	  mask=('1)<<(zeroExtend(arsize)+wrap_size);	// create a mask for bits which will remain constant in WRAP.
	  Bit#(awidth) temp1=address& mask;	  // capture the constant part of the addr in WRAP.
	  Bit#(awidth) temp2=new_address& (~mask);//capture the incremental part of the addr in WRAP.

	  if(arburst== 0) // FIXED
		  return address;
	  else if(arburst== 1) // INCR
		  return new_address;
	  else // WRAP
		  return temp1|temp2; // create the new address in the wrap mode by ORing the masked values.
  endfunction

 
  (*synthesize*)
 // (*preempts="write_mem_nc_resp,write_mem_resp"*)
  module mkimem_tb(Empty);

  let imem <- mkimem(0 `ifdef pmp ,unpack(0), unpack(0) `endif );
  let testcache<- mktest();

  RegFile#(Bit#(18), Bit#(TAdd#(TAdd#(TMul#(`iwords, 8), 8), `paddr ))) stim <- mkRegFileFullLoad("test.mem");
  RegFile#(Bit#(19), Bit#(`ibuswidth)) data <- mkRegFileFullLoad("data.mem");

  Reg#(Bit#(32)) index<- mkReg(0);
  Reg#(Bit#(32)) e_index<- mkReg(0);
  Reg#(Maybe#(ICache_mem_readreq#(32))) read_mem_req<- mkReg(tagged Invalid);
  Reg#(Bit#(8)) rg_read_burst_count <- mkReg(0);
  Reg#(Bit#(8)) rg_write_burst_count <- mkReg(0);
  Reg#(Bit#(32)) rg_test_count <- mkReg(1);

  FIFOF#(Bit#(TAdd#(TAdd#(TMul#(`iwords, 8), 8), `paddr ) )) ff_req <- mkSizedFIFOF(32);

  `ifdef perfmonitors
    Vector#(5,Reg#(Bit#(32))) rg_counters <- replicateM(mkReg(0));
  
  rule performance_counters;
    Bit#(5) incr = imem.mv_icache_perf_counters;
    for(Integer i=0;i<5;i=i+1)
      rg_counters[i]<=rg_counters[i]+zeroExtend(incr[i]);
  endrule
  `endif
  
  rule rl_nop;
  `logLevel( tb, 0, $format("\n\n"))
  endrule
  

  rule enable_disable_cache;
    imem.ma_cache_enable(True);
    imem.ma_curr_priv('d3);
  endrule

`ifdef supervisor
  rule tlb_csr_info;
    imem.ma_satp_from_csr(0);
  endrule
 `endif

  Wire#(Bool) wr_cache_avail <- mkWire();

  rule check_cache_avail;
    wr_cache_avail <= imem.mv_cache_available;
  endrule

  rule core_req(wr_cache_avail);
    let stime<-$stime;
    if(stime>=(20)) begin
      let req=stim.sub(truncate(index));
      // read/write : delay/nodelay : Fence/noFence : Null 
      Bit#(8) control = req[`paddr + 7: `paddr ];
      Bit#(2) readwrite=control[7:6];
      Bit#(3) size=control[5:3];
      Bit#(1) delay=control[2];
      Bit#(1) fence=control[1];
      Bit#(`paddr) address = truncate(req);
      Bit#(TAdd#(`paddr ,  8)) request = truncate(req);
      Bit#(TMul#(`iwords, 8)) writedata=truncateLSB(req);
      `logLevel( tb, 0, $format("TB: Req from Stimulus: ",fshow(req)))
      if(request!=0) begin // // not end of simulation
        if(request!='1 && delay==0) begin
          imem.put_core_req.put(IMem_core_request{address:zeroExtend(address),
							      fence : unpack(fence),
							      epochs: 0 
                  `ifdef supervisor
							        , sfence: False
                  `endif });
        `logLevel( tb, 0, $format("TB: Sending core request for addr: %h",req))
        end
        index<=index+1;
      end
      if((delay==0 && fence!=1) || (&request[31:0]) == 1 )begin // if not a fence instruction
        `logLevel( tb, 0, $format("TB: Enquiing request: %h",req))
        ff_req.enq(req);
      end
    end
  endrule

  rule end_sim;
    Bit#(TAdd#(`paddr ,  8)) request = truncate(ff_req.first());
    if(request==0)begin
      $display("TB: All Tests PASSED. Total TestCount: %d", rg_test_count-1);
      $finish(0);
    end
  endrule

  rule checkout_request(ff_req.first[35:0] =='1);
    ff_req.deq;
    rg_test_count<=rg_test_count+1;
    $display("TB: ********** Test:%d PASSED****",rg_test_count);
  endrule


  rule core_resp(ff_req.first[35:0]!='1);
    let resp <- imem.get_core_resp.get();
    let req = ff_req.first;
    ff_req.deq();
    Bit#(8) control = req[`paddr + 7: `paddr ];
    Bit#(2) readwrite=control[7:6];
    Bit#(3) size=control[5:3];
    Bit#(1) delay=control[2];
    Bit#(1) fence=control[1];
    Bit#(TMul#(`iwords, 8)) writedata=truncateLSB(req);

    if(fence==0)begin
      let expected_data<-testcache.memory_operation(truncate(req),readwrite,size,0);
      Bool metafail=False;
      Bool datafail=False;
      let lv_req_io = isIO(truncate(req),True);
  
        if(zeroExtend(expected_data)!=resp.line)begin
            `logLevel( tb, 0, $format("TB: Output from cache is wrong for Req: %h",req))
            `logLevel( tb, 0, $format("TB: Expected: %h, Received: %h",expected_data,resp.line))
            datafail=True;
        end

        if(metafail||datafail)begin
          $display("\tTB: Test: %d Failed",rg_test_count);
          $finish(0);
        end
        else
          `logLevel( tb, 0, $format("TB: Core received correct response: ",fshow(resp)," For req:  %h",req))
    end
    else begin
      `logLevel( tb, 0, $format("TB: Response from Cache: ",fshow(resp)))
    end
  endrule

  rule read_mem_request(read_mem_req matches tagged Invalid);
    let req<- imem.get_read_mem_req.get;
      read_mem_req<=tagged Valid req;
    `logLevel( tb, 0, $format("TB: Memory Read request: ",fshow(req)))
  endrule

  rule read_mem_resp(read_mem_req matches tagged Valid .req);
    let rd_req= req;
    if(rg_read_burst_count == rd_req.burst_len) begin
      rg_read_burst_count<=0;
      read_mem_req<=tagged Invalid;
    end
    else begin
      rg_read_burst_count<=rg_read_burst_count+1;
      read_mem_req <= tagged Valid (ICache_mem_readreq{address : (fn_axi4burst_addr(rd_req.burst_len,rd_req.burst_size,2,rd_req.address)),
						       burst_len : rd_req.burst_len,
						       burst_size : rd_req.burst_size}); // parameterize
    end
    let v_wordbits = valueOf(TLog#(TDiv#(`ibuswidth,8)));
    Bit#(19) index = truncate(rd_req.address>>v_wordbits);
    let dat=data.sub(truncate(index));
    Bit#(TLog#(TDiv#(`ibuswidth,8))) zeros = 0;
    Bit#(TMul#(2,TLog#(TDiv#(`ibuswidth,8)))) shift={rd_req.address[v_wordbits-1:0],zeros};
    dat = dat >> shift;
    imem.put_read_mem_resp.put(ICache_mem_readresp{data : dat,
						   last : (rg_read_burst_count==rd_req.burst_len),
                                                                                        err:False});
    `logLevel( tb, 0, $format("TB: Memory Read index: %d responding with: %h ",index,dat))
  endrule

endmodule

endpackage

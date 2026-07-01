// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 
package mem_config;
 
  import BRAMCore::*;
  import DReg::*;
  import FIFOF::*;
  import SpecialFIFOs::*;
  import Assert::*;
  import ecc_hamming :: * ;
  `include "Logger.bsv"

  typedef union tagged {
    void None;
    String File;
  } LoadFormat deriving (Eq);

  interface Ifc_bram_1r1w#(numeric type addr_width, numeric type data_width, numeric type memsize);
  	(*always_enabled*)
  	method Action write (Bit#(data_width) dina, Bit#(addr_width) addra, Bit#(1) wea);
  	(*always_enabled*)
  	method Action read (Bit#(addr_width) addrb);
  	(*always_enabled*)
  	method Bit#(data_width) response ();
  endinterface
  
  import "BVI" bram_1r1w_load =
  module mkbram_1r1w_load #(parameter String filename)  (Ifc_bram_1r1w#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
  	method write (dina /*DATA_WIDTH-1:0*/, addra /*ADDR_WIDTH-1:0*/, wea /*0:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method read (addrb /*ADDR_WIDTH-1:0*/)
  		 enable(enb) clocked_by(clk_clkb);
  	method doutb /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clkb);
  
  	schedule write C write;
  	schedule write CF read;
  	schedule write CF response;
  	schedule read C read;
  	schedule read CF response;
  	schedule response CF response;
  endmodule:mkbram_1r1w_load
  
  import "BVI" bram_1r1w =
  module mkbram_1r1w_noload  (Ifc_bram_1r1w#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
  	method write (dina /*DATA_WIDTH-1:0*/, addra /*ADDR_WIDTH-1:0*/, wea /*0:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method read (addrb /*ADDR_WIDTH-1:0*/)
  		 enable(enb) clocked_by(clk_clkb);
  	method doutb /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clkb);
  
  	schedule write C write;
  	schedule write CF read;
  	schedule write CF response;
  	schedule read C read;
  	schedule read CF response;
  	schedule response CF response;
  endmodule:mkbram_1r1w_noload

  module mkbram_1r1w #(parameter LoadFormat filepath)
    (Ifc_bram_1r1w#(addr_width, data_width, memsize));

    if (filepath matches tagged File .filename) begin 
      let _x <- mkbram_1r1w_load(filename);
      return _x;
    end
    else begin
      let _x <- mkbram_1r1w_noload();
      return _x;
    end
  endmodule:mkbram_1r1w

  interface Ifc_bram_1rw#(numeric type addr_width, numeric type data_width, numeric type memsize);
  	(*always_enabled*)
  	method Action request (Bit#(1) wea, Bit#(addr_width) addra, Bit#(data_width) dina);
  	(*always_enabled*)
  	method Bit#(data_width) response ();
  endinterface
  
  import "BVI" bram_1rw_nc_load =
  module mkbram_1rw_nc_load #(parameter String filename) (Ifc_bram_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbram_1rw_nc_load
  
  import "BVI" bram_1rw_nc =
  module mkbram_1rw_nc  (Ifc_bram_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbram_1rw_nc
  
  import "BVI" bram_1rw_rf =
  module mkbram_1rw_rf  (Ifc_bram_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbram_1rw_rf
  
  import "BVI" bram_1rw_rf_load =
  module mkbram_1rw_rf_load#(parameter String filename)(Ifc_bram_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbram_1rw_rf_load
  
  import "BVI" bram_1rw_wf =
  module mkbram_1rw_wf  (Ifc_bram_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbram_1rw_wf
  
  import "BVI" bram_1rw_wf_load =
  module mkbram_1rw_wf_load #(parameter String filename)(Ifc_bram_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbram_1rw_wf_load
  
  module mkbram_1rw #(parameter LoadFormat filepath, parameter String mode)
      (Ifc_bram_1rw#(addr_width, data_width, memsize));
  
    if (filepath matches tagged File .filename) begin 
      if (mode == "nc") begin
        let _x <- mkbram_1rw_nc_load(filename);
        return _x;
      end
      else if( mode == "wf" ) begin
        let _x <- mkbram_1rw_wf_load(filename);
        return _x;
      end
      else begin
        let _x <- mkbram_1rw_rf_load(filename);
        return _x;
      end
    end
    else begin
      if (mode == "nc") begin
        let _x <- mkbram_1rw_nc();
        return _x;
      end
      else if( mode == "wf" ) begin
        let _x <- mkbram_1rw_wf();
        return _x;
      end
      else begin
        let _x <- mkbram_1rw_rf();
        return _x;
      end
    end 
  endmodule:mkbram_1rw

  interface Ifc_brambe_1rw#(numeric type addr_width, numeric type data_width, numeric type memsize);
  	(*always_enabled*)
  	method Action request (Bit#(TDiv#(data_width,8)) wea, Bit#(addr_width) addra, Bit#(data_width) dina);
  	(*always_enabled*)
  	method Bit#(data_width) response ();
  endinterface:Ifc_brambe_1rw
  
  import "BVI" brambe_1rw_nc_load =
  module mkbrambe_1rw_nc_load #(parameter String filename) (Ifc_brambe_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbrambe_1rw_nc_load
  
  import "BVI" brambe_1rw_wf_load =
  module mkbrambe_1rw_wf_load #(parameter String filename) (Ifc_brambe_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbrambe_1rw_wf_load
  
  import "BVI" brambe_1rw_rf_load =
  module mkbrambe_1rw_rf_load #(parameter String filename) (Ifc_brambe_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbrambe_1rw_rf_load
  
  
  
  import "BVI" brambe_1rw_nc =
  module mkbrambe_1rw_nc  (Ifc_brambe_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbrambe_1rw_nc
  
  import "BVI" brambe_1rw_wf =
  module mkbrambe_1rw_wf  (Ifc_brambe_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbrambe_1rw_wf
  
  import "BVI" brambe_1rw_rf =
  module mkbrambe_1rw_rf  (Ifc_brambe_1rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  
  
  	method request (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  		 enable(ena) clocked_by(clk_clka);
  	method douta /* DATA_WIDTH-1 : 0 */ response ()
  		 clocked_by(clk_clka);
  
  	schedule request C request;
  	schedule request CF response;
  	schedule response CF response;
  endmodule:mkbrambe_1rw_rf
  
  module mkbrambe_1rw #(parameter LoadFormat filepath, parameter String mode)
      (Ifc_brambe_1rw#(addr_width, data_width, memsize));
  
    if (filepath matches tagged File .filename) begin 
      if (mode == "nc") begin
        let _x <- mkbrambe_1rw_nc_load(filename);
        return _x;
      end
      else if( mode == "wf" ) begin
        let _x <- mkbrambe_1rw_wf_load(filename);
        return _x;
      end
      else begin
        let _x <- mkbrambe_1rw_rf_load(filename);
        return _x;
      end
    end
    else begin
      if (mode == "nc") begin
        let _x <- mkbrambe_1rw_nc();
        return _x;
      end
      else if( mode == "wf" ) begin
        let _x <- mkbrambe_1rw_wf();
        return _x;
      end
      else begin
        let _x <- mkbrambe_1rw_rf();
        return _x;
      end
    end
  
  endmodule: mkbrambe_1rw

  interface Ifc_brambe_2rw#(numeric type addr_width, numeric type data_width, numeric type memsize);
  	(*always_enabled*)
  	method Action request_a (Bit#(TDiv#(data_width,8)) wea, Bit#(addr_width) addra, Bit#(data_width) dina);
  	(*always_enabled*)
  	method Bit#(data_width) response_a ();
  	(*always_enabled*)
  	method Action request_b (Bit#(TDiv#(data_width,8)) web, Bit#(addr_width) addrb, Bit#(data_width) dinb);
  	(*always_enabled*)
  	method Bit#(data_width) response_b ();
  endinterface:Ifc_brambe_2rw
  
  import "BVI" brambe_2rw_nc_load =
  module mkbrambe_2rw_nc_load #(parameter String filename) (Ifc_brambe_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule:mkbrambe_2rw_nc_load
  
  import "BVI" brambe_2rw_wf_load =
  module mkbrambe_2rw_wf_load #(parameter String filename) (Ifc_brambe_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule:mkbrambe_2rw_wf_load
  
  import "BVI" brambe_2rw_rf_load =
  module mkbrambe_2rw_rf_load #(parameter String filename) (Ifc_brambe_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule:mkbrambe_2rw_rf_load
  
  import "BVI" brambe_2rw_nc =
  module mkbrambe_2rw_nc (Ifc_brambe_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule:mkbrambe_2rw_nc
  
  import "BVI" brambe_2rw_wf =
  module mkbrambe_2rw_wf (Ifc_brambe_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule:mkbrambe_2rw_wf
  
  import "BVI" brambe_2rw_rf =
  module mkbrambe_2rw_rf (Ifc_brambe_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule:mkbrambe_2rw_rf
  
  module mkbrambe_2rw #(parameter LoadFormat filepath, parameter String mode)
      (Ifc_brambe_2rw#(addr_width, data_width, memsize));
  
    if (filepath matches tagged File .filename) begin 
      if (mode == "nc") begin
        let _x <- mkbrambe_2rw_nc_load(filename);
        return _x;
      end
      else if( mode == "wf" ) begin
        let _x <- mkbrambe_2rw_wf_load(filename);
        return _x;
      end
      else begin
        let _x <- mkbrambe_2rw_rf_load(filename);
        return _x;
      end
    end
    else begin
      if (mode == "nc") begin
        let _x <- mkbrambe_2rw_nc();
        return _x;
      end
      else if( mode == "wf" ) begin
        let _x <- mkbrambe_2rw_wf();
        return _x;
      end
      else begin
        let _x <- mkbrambe_2rw_rf();
        return _x;
      end
    end
  
  endmodule: mkbrambe_2rw
  
  interface Ifc_bram_2rw#(numeric type addr_width, numeric type data_width, numeric type memsize);
  	(*always_enabled*)
  	method Action request_a (Bit#(1) wea, Bit#(addr_width) addra, Bit#(data_width) dina);
  	(*always_enabled*)
  	method Bit#(data_width) response_a ();
  	(*always_enabled*)
  	method Action request_b (Bit#(1) web, Bit#(addr_width) addrb, Bit#(data_width) dinb);
  	(*always_enabled*)
  	method Bit#(data_width) response_b ();
  endinterface
  
  import "BVI" bram_2rw_nc_load =
  module mkbram_2rw_nc_load#(parameter String filename) (Ifc_bram_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule
  
  import "BVI" bram_2rw_rf_load =
  module mkbram_2rw_rf_load#(parameter String filename) (Ifc_bram_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule
  
  import "BVI" bram_2rw_wf_load =
  module mkbram_2rw_wf_load#(parameter String filename) (Ifc_bram_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  	parameter FILENAME = filename;
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule

  import "BVI" bram_2rw_nc =
  module mkbram_2rw_nc (Ifc_bram_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule
  
  import "BVI" bram_2rw_rf =
  module mkbram_2rw_rf (Ifc_bram_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule
  
  import "BVI" bram_2rw_wf =
  module mkbram_2rw_wf (Ifc_bram_2rw#(addr_width, data_width, memsize));
  
  	parameter ADDR_WIDTH = valueOf(addr_width);
  	parameter DATA_WIDTH = valueOf(data_width);
  	parameter MEMSIZE = valueOf(memsize);
  
  	default_clock clk_clka;
  	default_reset no_reset;
  
  	input_clock clk_clka (clka)  <- exposeCurrentClock;
  	input_clock clk_clkb (clkb)  <- exposeCurrentClock;
  
  
    	method request_a (wea , addra /*ADDR_WIDTH-1:0*/, dina /*DATA_WIDTH-1:0*/)
  	  	 enable(ena) clocked_by(clk_clka);
    	method douta /* DATA_WIDTH-1 : 0 */ response_a ()
  	  	 clocked_by(clk_clka);
  
    	method request_b (web , addrb /*ADDR_WIDTH-1:0*/, dinb /*DATA_WIDTH-1:0*/)
  	  	 enable(enb) clocked_by(clk_clkb);
    	method doutb /* DATA_WIDTH-1 : 0 */ response_b ()
  	  	 clocked_by(clk_clkb);
  
  	schedule request_a C request_a;
  	schedule request_a CF response_a;
  	schedule response_a CF response_a;
  
  	schedule request_b C request_b;
  	schedule request_b CF response_b;
  	schedule response_b CF response_b;
  
  	schedule request_b CF request_a;
  	schedule request_b CF response_a;
  	schedule response_b CF request_a;
  	schedule response_b CF response_a;
  endmodule
  
  module mkbram_2rw #(parameter LoadFormat filepath, parameter String mode)
      (Ifc_bram_2rw#(addr_width, data_width, memsize));
  
    if (filepath matches tagged File .filename) begin 
      if (mode == "nc") begin
        let _x <- mkbram_2rw_nc_load(filename);
        return _x;
      end
      else if( mode == "wf" ) begin
        let _x <- mkbram_2rw_wf_load(filename);
        return _x;
      end
      else begin
        let _x <- mkbram_2rw_rf_load(filename);
        return _x;
      end
    end
    else begin
      if (mode == "nc") begin
        let _x <- mkbram_2rw_nc();
        return _x;
      end
      else if( mode == "wf" ) begin
        let _x <- mkbram_2rw_wf();
        return _x;
      end
      else begin
        let _x <- mkbram_2rw_rf();
        return _x;
      end
    end
  
  endmodule: mkbram_2rw
  
  interface Ifc_mem_config2rw#( numeric type n_entries, numeric type datawidth, numeric type banks);
    interface Ifc_mem_config1rw#(n_entries, datawidth, banks) p1;
    interface Ifc_mem_config1rw#(n_entries, datawidth, banks) p2;
  endinterface
  
  module mkmem_config2rw#(parameter Bool ramreg, parameter Bool bypass, parameter String mode)
                                                  (Ifc_mem_config2rw#(n_entries, datawidth,  banks))
    provisos(
             Div#(datawidth, banks, bpb), 
             Mul#(bpb, banks, datawidth),
             Add#(a__, bpb, datawidth)
    );
    let v_bpb=valueOf(bpb);
    

    Ifc_bram_2rw#(TLog#(n_entries), bpb, n_entries) ram [valueOf(banks)];
    Reg#(Bit#(bpb)) rg_output_p1[valueOf(banks)][2];
    Reg#(Bit#(bpb)) rg_output_p2[valueOf(banks)][2];
    Reg#(Bit#(TLog#(n_entries))) rg_write_index <- mkReg(0);
    Reg#(Bit#(TLog#(n_entries))) rg_read_index <- mkReg(0);
    Reg#(Bit#(bpb)) rg_write_data[valueOf(banks)] ;
    for(Integer i=0;i<valueOf(banks);i=i+1) begin
      ram[i]<-mkbram_2rw(tagged None, mode);
      rg_output_p1[i] <- mkCReg(2,0);
      rg_output_p2[i] <- mkCReg(2,0);
      rg_write_data[i] <- mkReg(0);
    end

    for(Integer i=0;i<valueOf(banks);i=i+1)begin
      rule capture_output_p1(!ramreg);
        if((rg_read_index == rg_write_index) && bypass) begin
          rg_output_p1[i][0] <= rg_write_data[i];
        end
        else
          rg_output_p1[i][0]<=ram[i].response_a;
      endrule
      rule capture_output_reg_p1(ramreg);
        if((rg_read_index == rg_write_index) && bypass) begin
          rg_output_p1[i][1] <= rg_write_data[i];
        end
        else
          rg_output_p1[i][1]<=ram[i].response_a;
      endrule
      rule capture_output_p2(!ramreg);
        rg_output_p2[i][0]<=ram[i].response_b;
      endrule
      rule capture_output_reg_p2(ramreg);
        rg_output_p2[i][1]<=ram[i].response_b;
      endrule
    end

    interface p1 = interface Ifc_mem_config1rw
      method Action request(Bit#(1) we, Bit#(TLog#(n_entries)) index, Bit#(datawidth) data, 
                          Bit#(banks) bank_en);
        for(Integer i=0;i<valueOf(banks);i=i+1) begin
          if(bank_en[i] == 1)
            ram[i].request_a(we, index, data[i*v_bpb+v_bpb-1:i*v_bpb]);
        end
        if(we == 0) begin
          rg_read_index <= index;
        end
      endmethod
      method Bit#(datawidth) read_response;
        Bit#(datawidth) data_resp=0;
        for(Integer i=0;i<valueOf(banks);i=i+1)begin
          data_resp[i*v_bpb+v_bpb-1 : i*v_bpb]=rg_output_p1[i][1];
        end
        return data_resp;
      endmethod
    endinterface;
    interface p2 = interface Ifc_mem_config1rw
      method Action request(Bit#(1) we, Bit#(TLog#(n_entries)) index, Bit#(datawidth) data, 
                          Bit#(banks) bank_en);
        for(Integer i=0;i<valueOf(banks);i=i+1) begin
          if(bank_en[i] == 1) begin
            ram[i].request_b(we, index, data[i*v_bpb+v_bpb-1:i*v_bpb]);
            if(we == 1)
              rg_write_data[i] <= data[i*v_bpb+v_bpb-1:i*v_bpb];
          end
        end
        if(we == 1) begin
          rg_write_index <= index;
        end
      endmethod
      method Bit#(datawidth) read_response;
        Bit#(datawidth) data_resp=0;
        for(Integer i=0;i<valueOf(banks);i=i+1)begin
          data_resp[i*v_bpb+v_bpb-1 : i*v_bpb]=rg_output_p2[i][1];
        end
        return data_resp;
      endmethod
    endinterface;
  endmodule
  
  interface Ifc_mem_config2rw_ecc#( numeric type n_entries, numeric type datawidth, numeric type banks);
    interface Ifc_mem_config1rw_ecc#(n_entries, datawidth, banks) p1;
    interface Ifc_mem_config1rw_ecc#(n_entries, datawidth, banks) p2;
  endinterface
  
  module mkmem_config2rw_ecc#(parameter Bool ramreg, parameter Bool bypass, parameter String mode)
                                                  (Ifc_mem_config2rw_ecc#(n_entries, datawidth,  banks))
    provisos(
             Div#(datawidth, banks, bpb), 
             Mul#(bpb, banks, datawidth),
             Add#(a__, bpb, datawidth),
             Add#(2, TLog#(bpb), ecc_size),
             Add#(b__, 2, TMul#(2, banks)),
             Add#(TLog#(bpb), c__, 6),
             Add#(d__, bpb, 64)

             // required by bsc
             ,Add#(e__, ecc_size, TMul#(banks, ecc_size))
    );
    let v_bpb=valueOf(bpb);
    let v_banks = valueOf(banks);
    let v_ecc_size = valueOf(ecc_size);
    
    Ifc_bram_2rw#(TLog#(n_entries), TAdd#(bpb,ecc_size), n_entries) ram_single [valueOf(banks)];

    Reg#(Bit#(bpb)) rg_output_p1[valueOf(banks)][2];
    Reg#(Bit#(1)) rg_output_sed_p1 [v_banks][2];
    Reg#(Bit#(1)) rg_output_ded_p1 [v_banks][2];
    Reg#(Bit#(ecc_size)) rg_output_chparity_p1 [v_banks][2];
    Reg#(Bit#(ecc_size)) rg_output_stparity_p1 [v_banks][2];

    Reg#(Bit#(bpb)) rg_output_p2[valueOf(banks)][2];
    Reg#(Bit#(1)) rg_output_sed_p2 [v_banks][2];
    Reg#(Bit#(1)) rg_output_ded_p2 [v_banks][2];
    Reg#(Bit#(ecc_size)) rg_output_chparity_p2 [v_banks][2];
    Reg#(Bit#(ecc_size)) rg_output_stparity_p2 [v_banks][2];

    Reg#(Bit#(TLog#(n_entries))) rg_write_index <- mkReg(0);
    Reg#(Bit#(TLog#(n_entries))) rg_read_index <- mkReg(0);
    Reg#(Bit#(bpb)) rg_write_data[valueOf(banks)] ;

    for(Integer i=0;i<valueOf(banks);i=i+1) begin
      ram_single[i]<-mkbram_2rw(tagged None, mode);

      rg_output_p1[i] <- mkCReg(2,0);
      rg_output_sed_p1[i] <- mkCReg(2,0);
      rg_output_ded_p1[i] <- mkCReg(2,0);
      rg_output_chparity_p1[i] <- mkCReg(2,0);
      rg_output_stparity_p1[i] <- mkCReg(2,0);

      rg_output_p2[i] <- mkCReg(2,0);
      rg_output_sed_p2[i] <- mkCReg(2,0);
      rg_output_ded_p2[i] <- mkCReg(2,0);
      rg_output_chparity_p2[i] <- mkCReg(2,0);
      rg_output_stparity_p2[i] <- mkCReg(2,0);

      rg_write_data[i] <- mkReg(0);
    end

    for(Integer i=0;i<valueOf(banks);i=i+1)begin
      rule capture_output_p1(!ramreg);

        let resp = ram_single[i].response_a;
        Bit#(bpb) data = truncateLSB(resp);
        Bit#(ecc_size) parity = truncate(resp);
        let {check_parity, sed_ded} = fn_ecc_detect(data,parity);
        if((rg_read_index == rg_write_index) && bypass) begin
          data = rg_write_data[i];
          sed_ded = 0;
        end

        rg_output_p1[i][0] <= data;
        rg_output_sed_p1[i][0] <= sed_ded[1];
        rg_output_ded_p1[i][0] <= sed_ded[0];
        rg_output_chparity_p1[i][0] <= check_parity;
        rg_output_stparity_p1[i][0] <= parity;
      endrule
      rule capture_output_reg_p1(ramreg);
        let resp = ram_single[i].response_a;
        Bit#(bpb) data = truncateLSB(resp);
        Bit#(ecc_size) parity = truncate(resp);
        let {check_parity, sed_ded} = fn_ecc_detect(data,parity);
        if((rg_read_index == rg_write_index) && bypass) begin
          data = rg_write_data[i];
          sed_ded = 0;
        end

        rg_output_p1[i][1] <= data;
        rg_output_sed_p1[i][1] <= sed_ded[1];
        rg_output_ded_p1[i][1] <= sed_ded[0];
        rg_output_chparity_p1[i][1] <= check_parity;
        rg_output_stparity_p1[i][1] <= parity;
      endrule
      rule capture_output_p2(!ramreg);

        let resp = ram_single[i].response_b;
        Bit#(bpb) data = truncateLSB(resp);
        Bit#(ecc_size) parity = truncate(resp);
        let {check_parity, sed_ded} = fn_ecc_detect(data,parity);

        rg_output_p2[i][0] <= data;
        rg_output_sed_p2[i][0] <= sed_ded[1];
        rg_output_ded_p2[i][0] <= sed_ded[0];
        rg_output_chparity_p2[i][0] <= check_parity;
        rg_output_stparity_p2[i][0] <= parity;
      endrule
      rule capture_output_reg_p2(ramreg);
        let resp = ram_single[i].response_b;
        Bit#(bpb) data = truncateLSB(resp);
        Bit#(ecc_size) parity = truncate(resp);
        let {check_parity, sed_ded} = fn_ecc_detect(data,parity);

        rg_output_p2[i][1] <= data;
        rg_output_sed_p2[i][1] <= sed_ded[1];
        rg_output_ded_p2[i][1] <= sed_ded[0];
        rg_output_chparity_p2[i][1] <= check_parity;
        rg_output_stparity_p2[i][1] <= parity;
      endrule
    end

    interface p1 = interface Ifc_mem_config1rw_ecc
      method Action request(Bit#(1) we, Bit#(TLog#(n_entries)) index, Bit#(datawidth) data, 
                          Bit#(banks) bank_en);
        for(Integer i=0;i<valueOf(banks);i=i+1) begin
          if(bank_en[i] == 1)
            ram_single[i].request_a(we, index, data[i*v_bpb+v_bpb-1:i*v_bpb]);
        end
        if(we == 0) begin
          rg_read_index <= index;
        end
      endmethod
      method Bit#(datawidth) read_response;
        Bit#(datawidth) data_resp=0;
        for(Integer i=0;i<valueOf(banks);i=i+1)begin
          data_resp[i*v_bpb+v_bpb-1 : i*v_bpb]=rg_output_p1[i][1];
        end
        return data_resp;
      endmethod
      method Bit#(banks) read_sed;
        Bit#(banks) ecc_sed_resp = 0;
        for(Integer i=0;i<valueOf(banks);i=i+1)begin
          ecc_sed_resp[i] = rg_output_sed_p1[i][1];
        end
        return ecc_sed_resp;
      endmethod
      method Bit#(banks) read_ded;
        Bit#(banks) ecc_ded_resp = 0;
        for(Integer i=0;i<valueOf(banks);i=i+1)begin
          ecc_ded_resp[i] = rg_output_ded_p1[i][1];
        end
        return ecc_ded_resp;
      endmethod
      method Bit#(TMul#(banks,ecc_size)) check_parity;
        Bit#(TMul#(banks,ecc_size)) _t=?;
        for (Integer i = 0; i< v_banks; i = i + 1) begin
          _t[i*v_ecc_size + v_ecc_size -1:i*v_ecc_size] = rg_output_chparity_p1[i][1];
        end
        return _t;
      endmethod
      method Bit#(TMul#(banks,ecc_size)) stored_parity;
        Bit#(TMul#(banks,ecc_size)) _t=?;
        for (Integer i = 0; i< v_banks; i = i + 1) begin
          _t[i*v_ecc_size + v_ecc_size -1:i*v_ecc_size] = rg_output_stparity_p1[i][1];
        end
        return _t;
      endmethod
    endinterface;
    interface p2 = interface Ifc_mem_config1rw_ecc
      method Action request(Bit#(1) we, Bit#(TLog#(n_entries)) index, Bit#(datawidth) data, 
                          Bit#(banks) bank_en);
        if(we == 1) begin
          rg_write_index <= index;
        end
        for(Integer i=0;i<valueOf(banks);i=i+1) begin
          Bit#(bpb) lv_data = data[i*v_bpb+v_bpb-1:i*v_bpb];
          Bit#(ecc_size) lv_ecc = fn_ecc_encode(lv_data);
          if(bank_en[i] == 1) begin
            ram_single[i].request_b(we, index, {lv_data,lv_ecc});
            if(we == 1)
              rg_write_data[i] <= data[i*v_bpb+v_bpb-1:i*v_bpb];
          end
        end
      endmethod
      method Bit#(datawidth) read_response;
        Bit#(datawidth) data_resp=0;
        for(Integer i=0;i<valueOf(banks);i=i+1)begin
          data_resp[i*v_bpb+v_bpb-1 : i*v_bpb]=rg_output_p2[i][1];
        end
        return data_resp;
      endmethod
      method Bit#(banks) read_sed;
        Bit#(banks) ecc_sed_resp = 0;
        for(Integer i=0;i<valueOf(banks);i=i+1)begin
          ecc_sed_resp[i] = rg_output_sed_p2[i][1];
        end
        return ecc_sed_resp;
      endmethod
      method Bit#(banks) read_ded;
        Bit#(banks) ecc_ded_resp = 0;
        for(Integer i=0;i<valueOf(banks);i=i+1)begin
          ecc_ded_resp[i] = rg_output_ded_p2[i][1];
        end
        return ecc_ded_resp;
      endmethod
      method Bit#(TMul#(banks,ecc_size)) check_parity;
        Bit#(TMul#(banks,ecc_size)) _t=?;
        for (Integer i = 0; i< v_banks; i = i + 1) begin
          _t[i*v_ecc_size + v_ecc_size -1:i*v_ecc_size] = rg_output_chparity_p2[i][1];
        end
        return _t;
      endmethod
      method Bit#(TMul#(banks,ecc_size)) stored_parity;
        Bit#(TMul#(banks,ecc_size)) _t=?;
        for (Integer i = 0; i< v_banks; i = i + 1) begin
          _t[i*v_ecc_size + v_ecc_size -1:i*v_ecc_size] = rg_output_stparity_p2[i][1];
        end
        return _t;
      endmethod
    endinterface;
  endmodule
  
  interface Ifc_mem_config1rw_ecc#( numeric type n_entries, 
                                    numeric type datawidth, 
                                    numeric type banks);
    method Action request(Bit#(1) we, Bit#(TLog#(n_entries)) index, Bit#(datawidth) data, 
                          Bit#(banks) bank_en);
    method Bit#(datawidth) read_response;
    method Bit#(banks) read_sed;
    method Bit#(banks) read_ded;
    method Bit#(TMul#(banks,TAdd#(2,TLog#(TDiv#(datawidth,banks))))) check_parity;
    method Bit#(TMul#(banks,TAdd#(2,TLog#(TDiv#(datawidth,banks))))) stored_parity;
  endinterface
  
  module mkmem_config1rw_ecc#(parameter Bool ramreg, parameter String mode)(Ifc_mem_config1rw_ecc#(n_entries, datawidth,  banks))
    provisos(
             Div#(datawidth, banks, bpb), 
             Mul#(bpb, banks, datawidth),
             Add#(a__, bpb, datawidth),
             Add#(2, TLog#(bpb), ecc_size),
             Add#(b__, 2, TMul#(2, banks)),
             Add#(TLog#(bpb), c__, 6),
             Add#(d__, bpb, 64)

             // required by bsc
             ,Add#(e__, ecc_size, TMul#(banks, ecc_size))
    );
    let v_bpb=valueOf(bpb);
    let v_banks = valueOf(banks);
    let v_ecc_size = valueOf(ecc_size);

    Ifc_bram_1rw#(TLog#(n_entries), TAdd#(bpb,ecc_size), n_entries) ram_single [valueOf(banks)];

    Reg#(Bit#(bpb)) rg_output_data [v_banks][2];
    Reg#(Bit#(1)) rg_output_sed [v_banks][2];
    Reg#(Bit#(1)) rg_output_ded [v_banks][2];
    Reg#(Bit#(ecc_size)) rg_output_chparity [v_banks][2];
    Reg#(Bit#(ecc_size)) rg_output_stparity [v_banks][2];

    for(Integer i=0;i<valueOf(banks);i=i+1) begin
      ram_single[i]<-mkbram_1rw(tagged None, mode);
      rg_output_data[i] <- mkCReg(2,0);
      rg_output_sed[i] <- mkCReg(2,0);
      rg_output_ded[i] <- mkCReg(2,0);
      rg_output_chparity[i] <- mkCReg(2,0);
      rg_output_stparity[i] <- mkCReg(2,0);
    end

    for(Integer i=0;i<valueOf(banks);i=i+1)begin
      rule capture_output(!ramreg);
        let resp = ram_single[i].response;
        Bit#(bpb) data = truncateLSB(resp);
        rg_output_data[i][0] <= data;

        Bit#(ecc_size) parity = truncate(resp);
        let {check_parity, sed_ded} = fn_ecc_detect(data,parity);
        rg_output_sed[i][0] <= sed_ded[1];
        rg_output_ded[i][0] <= sed_ded[0];
        rg_output_chparity[i][0] <= check_parity;
        rg_output_stparity[i][0] <= parity;
      endrule
      rule capture_output_reg(ramreg);
        let resp = ram_single[i].response;
        Bit#(bpb) data = truncateLSB(resp);
        rg_output_data[i][1] <= data;

        Bit#(ecc_size) parity = truncate(resp);
        let {check_parity, sed_ded} = fn_ecc_detect(data,parity);
        rg_output_sed[i][1] <= sed_ded[1];
        rg_output_ded[i][1] <= sed_ded[0];
        rg_output_chparity[i][1] <= check_parity;
        rg_output_stparity[i][1] <= parity;
      endrule
    end

    method Action request(Bit#(1) we, Bit#(TLog#(n_entries)) index, Bit#(datawidth) data, 
                          Bit#(banks) bank_en);
      for(Integer i=0;i<valueOf(banks);i=i+1) begin
        Bit#(bpb) lv_data = data[i*v_bpb+v_bpb-1:i*v_bpb];
        Bit#(ecc_size) lv_ecc = fn_ecc_encode(lv_data);
        if(bank_en[i] == 1)
          ram_single[i].request(we, index, {lv_data,lv_ecc});
      end
    endmethod
    method Bit#(datawidth) read_response;
      Bit#(datawidth) data_resp=0;
      for(Integer i=0;i<valueOf(banks);i=i+1)begin
        data_resp[i*v_bpb+v_bpb-1 : i*v_bpb]=rg_output_data[i][1];
      end
      return data_resp;
    endmethod
    method Bit#(banks) read_sed;
      Bit#(banks) ecc_sed_resp = 0;
      for(Integer i=0;i<valueOf(banks);i=i+1)begin
        ecc_sed_resp[i] = rg_output_sed[i][1];
      end
      return ecc_sed_resp;
    endmethod
    method Bit#(banks) read_ded;
      Bit#(banks) ecc_ded_resp = 0;
      for(Integer i=0;i<valueOf(banks);i=i+1)begin
        ecc_ded_resp[i] = rg_output_ded[i][1];
      end
      return ecc_ded_resp;
    endmethod
    method Bit#(TMul#(banks,ecc_size)) check_parity;
      Bit#(TMul#(banks,ecc_size)) _t=?;
      for (Integer i = 0; i< v_banks; i = i + 1) begin
        _t[i*v_ecc_size + v_ecc_size -1:i*v_ecc_size] = rg_output_chparity[i][1];
      end
      return _t;
    endmethod
    method Bit#(TMul#(banks,ecc_size)) stored_parity;
      Bit#(TMul#(banks,ecc_size)) _t=?;
      for (Integer i = 0; i< v_banks; i = i + 1) begin
        _t[i*v_ecc_size + v_ecc_size -1:i*v_ecc_size] = rg_output_stparity[i][1];
      end
      return _t;
    endmethod
  endmodule

  interface Ifc_mem_config1rw#( numeric type n_entries, numeric type datawidth, numeric type banks);
    method Action request(Bit#(1) we, Bit#(TLog#(n_entries)) index, Bit#(datawidth) data, 
                          Bit#(banks) bank_en);
    method Bit#(datawidth) read_response;
  endinterface
  
  module mkmem_config1rw#(parameter Bool ramreg, parameter String mode)
    (Ifc_mem_config1rw#(n_entries, datawidth,  banks))
    provisos(
             Div#(datawidth, banks, bpb), 
             Mul#(bpb, banks, datawidth),
             Add#(a__, bpb, datawidth)
    );
    let v_bpb=valueOf(bpb);
    

    Ifc_bram_1rw#(TLog#(n_entries), bpb, n_entries) ram_single [valueOf(banks)];
    Reg#(Bit#(bpb)) rg_output[valueOf(banks)][2];
    for(Integer i=0;i<valueOf(banks);i=i+1) begin
      ram_single[i]<-mkbram_1rw(tagged None, mode);
      rg_output[i] <- mkCReg(2,0);
    end

    for(Integer i=0;i<valueOf(banks);i=i+1)begin
      rule capture_output(!ramreg);
        rg_output[i][0]<=ram_single[i].response;
      endrule
      rule capture_output_reg(ramreg);
        rg_output[i][1]<=ram_single[i].response;
      endrule
    end

    method Action request(Bit#(1) we, Bit#(TLog#(n_entries)) index, Bit#(datawidth) data, 
                          Bit#(banks) bank_en);
      for(Integer i=0;i<valueOf(banks);i=i+1) begin
        if(bank_en[i] == 1)
          ram_single[i].request(we, index, data[i*v_bpb+v_bpb-1:i*v_bpb]);
      end
    endmethod
    method Bit#(datawidth) read_response;
      Bit#(datawidth) data_resp=0;
      for(Integer i=0;i<valueOf(banks);i=i+1)begin
        data_resp[i*v_bpb+v_bpb-1 : i*v_bpb]=rg_output[i][1];
      end
      return data_resp;
    endmethod
  endmodule

  interface Ifc_mem_config1r1w#( numeric type n_entries, numeric type datawidth, numeric type banks);
    method Action write(Bit#(1) we, Bit#(TLog#(n_entries)) index, Bit#(datawidth) data, 
                                                                              Bit#(banks)  bank_en);
    method Action read(Bit#(TLog#(n_entries)) index);
    method Bit#(datawidth) read_response;
  endinterface
  
  module mkmem_config1r1w#(parameter Bool ramreg, parameter Bool bypass)
                                                  (Ifc_mem_config1r1w#(n_entries, datawidth,  banks))
    provisos(
             Div#(datawidth, banks, bpb), 
             Mul#(bpb, banks, datawidth),
             Add#(a__, bpb, datawidth)
    );
    let v_bpb=valueOf(bpb);
    

    Ifc_bram_1r1w#(TLog#(n_entries), bpb, n_entries) ram_double [valueOf(banks)];
    Reg#(Bit#(bpb)) rg_output[valueOf(banks)][2];
    Reg#(Bit#(TLog#(n_entries))) rg_write_index <- mkReg(0);
    Reg#(Bit#(TLog#(n_entries))) rg_read_index <- mkReg(0);
    Reg#(Bit#(bpb)) rg_write_data[valueOf(banks)] ;
    for(Integer i=0;i<valueOf(banks);i=i+1) begin
      ram_double[i]<-mkbram_1r1w(tagged None);
      rg_output[i] <- mkCReg(2,0);
      rg_write_data[i] <- mkReg(0);
    end

    for(Integer i=0;i<valueOf(banks);i=i+1)begin
      rule capture_output(!ramreg);
        if((rg_read_index == rg_write_index) && bypass) begin
          rg_output[i][0] <= rg_write_data[i];
        end
        else
          rg_output[i][0]<=ram_double[i].response;
      endrule
      rule capture_output_reg(ramreg);
        if((rg_read_index == rg_write_index) && bypass) begin
          rg_output[i][1] <= rg_write_data[i];
        end
        else
          rg_output[i][1]<=ram_double[i].response;
      endrule
    end

    method Action write(Bit#(1) we, Bit#(TLog#(n_entries)) index, Bit#(datawidth) data, 
                                                                              Bit#(banks)  bank_en);
      for(Integer i=0;i<valueOf(banks);i=i+1) begin
        if(bank_en[i] == 1) begin
          ram_double[i].write(data[i*v_bpb+v_bpb-1:i*v_bpb], index, we);
          rg_write_data[i] <= data[i*v_bpb+v_bpb-1:i*v_bpb];
        end
      end
        rg_write_index <= index;
    endmethod
    method Action read(Bit#(TLog#(n_entries)) index);
      for(Integer i=0;i<valueOf(banks);i=i+1) begin
        ram_double[i].read(index);
      end
      rg_read_index <= index;
    endmethod
    method Bit#(datawidth) read_response;
      Bit#(datawidth) data_resp=0;
      for(Integer i=0;i<valueOf(banks);i=i+1)begin
        data_resp[i*v_bpb+v_bpb-1 : i*v_bpb]=rg_output[i][1];
      end
      return data_resp;
    endmethod
  endmodule
endpackage:mem_config

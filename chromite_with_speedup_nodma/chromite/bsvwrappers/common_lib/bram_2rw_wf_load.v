// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 
// Copyright (c) 2000-2011 Bluespec, Inc.

module bram_2rw_wf_load(
             clka,
             ena,
             wea,
             addra,
             dina,
             douta,
             clkb,
             enb,
             web,
             addrb,
             dinb,
             doutb
             );

   parameter FILENAME = "";
   parameter                      ADDR_WIDTH = 1;
   parameter                      DATA_WIDTH = 1;
   parameter                      MEMSIZE    = 1;

   input                          clka;
   input                          ena;
   input                          wea;
   input [ADDR_WIDTH-1:0]         addra;
   input [DATA_WIDTH-1:0]         dina;
   output [DATA_WIDTH-1:0]        douta;

   input                          clkb;
   input                          enb;
   input                          web;
   input [ADDR_WIDTH-1:0]         addrb;
   input [DATA_WIDTH-1:0]         dinb;
   output [DATA_WIDTH-1:0]        doutb;

   (* RAM_STYLE = "BLOCK" *)
   reg [DATA_WIDTH-1:0]           ram[0:MEMSIZE-1];
   reg [DATA_WIDTH-1:0]           out_reg_a;
   reg [DATA_WIDTH-1:0]           out_reg_b;

   // synopsys translate_off
   integer                        i;
   initial 
   begin : init_rom_block
     $readmemh(FILENAME, ram, 0, MEMSIZE-1);
   end

   initial
   begin : init_block
      for (i = 0; i < MEMSIZE; i = i + 1) begin
         ram[i] = { ((DATA_WIDTH+1)/2) { 2'b10 } };
      end
      out_reg_a  = { ((DATA_WIDTH+1)/2) { 2'b10 } };
      out_reg_b  = { ((DATA_WIDTH+1)/2) { 2'b10 } };
   end
   // synopsys translate_on

   always @(posedge clka) begin
      if (ena) begin
         if (wea) begin
            ram[addra] <= dina;
            out_reg_a  <= dina;
         end
         else begin
            out_reg_a <= ram[addra];
         end
      end
   end

   // Output driver
   assign douta=out_reg_a;
   
   always @(posedge clkb) begin
      if (enb) begin
         if (web) begin
            ram[addrb] <= dinb;
            out_reg_b  <= dinb;
         end
         else begin
            out_reg_b <= ram[addrb];
         end
      end
   end

   // Output driver
   assign doutb=out_reg_b;

endmodule

// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 
// Copyright (c) 2000-2011 Bluespec, Inc.

module bram_1rw_nc(
             clka,
             ena,
             wea,
             addra,
             dina,
             douta
             );

   parameter                      ADDR_WIDTH = 1;
   parameter                      DATA_WIDTH = 1;
   parameter                      MEMSIZE    = 1;

   input                          clka;
   input                          ena;
   input                          wea;
   input [ADDR_WIDTH-1:0]         addra;
   input [DATA_WIDTH-1:0]         dina;
   output [DATA_WIDTH-1:0]        douta;

   (* RAM_STYLE = "BLOCK" *)
   reg [DATA_WIDTH-1:0]           ram[0:MEMSIZE-1];
   reg [DATA_WIDTH-1:0]           out_reg;

   // synopsys translate_off
   integer                        i;
   initial
   begin : init_block
      for (i = 0; i < MEMSIZE; i = i + 1) begin
         ram[i] = { ((DATA_WIDTH+1)/2) { 2'b10 } };
      end
      out_reg  = { ((DATA_WIDTH+1)/2) { 2'b10 } };
   end
   // synopsys translate_on

   always @(posedge clka) begin
      if (ena) begin
         if (wea) begin
            ram[addra] <= dina;
         end
         else begin
            out_reg <= ram[addra];
         end
      end
   end

   // Output driver
   assign douta=out_reg;

endmodule

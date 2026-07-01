// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details 

module brambe_1rw_rf_load(
             clka,
             ena,
             wea,
             addra,
             dina,
             douta
             );

   parameter                      FILENAME   = "";
   parameter                      ADDR_WIDTH = 1;
   parameter                      DATA_WIDTH = 8;
   parameter                      MEMSIZE    = 1;

   input                          clka;
   input                          ena;
   input [ADDR_WIDTH-1:0]         addra;
   input [DATA_WIDTH-1:0]         dina;
   input [DATA_WIDTH/8-1:0]       wea;
   output [DATA_WIDTH-1:0]        douta;

   (* RAM_STYLE = "BLOCK" *)
   reg [DATA_WIDTH-1:0]           ram[0:MEMSIZE-1];
   reg [DATA_WIDTH-1:0]           out_reg;

   // synopsys translate_off
   integer                        j;
   initial
   begin : init_block
      out_reg  = { ((DATA_WIDTH+1)/2) { 2'b10 } };
   end
   // synopsys translate_on
   initial
   begin : init_rom_block
     $readmemh(FILENAME, ram, 0, MEMSIZE-1);
   end
   
   generate
      genvar i;
      for(i = 0; i < DATA_WIDTH/8 ; i = i + 1) begin: porta_we
         always @(posedge clka) begin
            if (ena) begin
               if (wea[i]) begin
                  ram[addra][((i+1)*8)-1 : i*8] <= dina[((i+1)*8)-1 : i*8];
               end
            end
         end
      end      
   endgenerate

   always @ (posedge clka) begin
      if(ena) begin
          out_reg <= ram[addra];
      end
   end

   // Output driver
   assign douta=out_reg;

endmodule



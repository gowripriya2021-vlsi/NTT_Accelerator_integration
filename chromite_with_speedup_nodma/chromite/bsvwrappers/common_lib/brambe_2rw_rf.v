// Copyright (c) InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details
module brambe_2rw_rf(
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

   parameter                      ADDR_WIDTH = 1;
   parameter                      DATA_WIDTH = 8;
   parameter                      MEMSIZE    = 1;
   
   input                          clka;
   input                          ena;
   input [DATA_WIDTH/8-1:0]       wea;
   input [ADDR_WIDTH-1:0]         addra;
   input [DATA_WIDTH-1:0]         dina;
   output [DATA_WIDTH-1:0]        douta;

   input                          clkb;
   input                          enb;
   input [DATA_WIDTH/8-1:0]       web;
   input [ADDR_WIDTH-1:0]         addrb;
   input [DATA_WIDTH-1:0]         dinb;
   output [DATA_WIDTH-1:0]        doutb;

   (* RAM_STYLE = "BLOCK" *)
   reg [DATA_WIDTH-1:0]           ram[0:MEMSIZE-1];
   reg [DATA_WIDTH-1:0]           out_reg_a;
   reg [DATA_WIDTH-1:0]           out_reg_b;

   // synopsys translate_off
   initial
   begin : init_block
      out_reg_a  = { ((DATA_WIDTH+1)/2) { 2'b10 } };
      out_reg_b  = { ((DATA_WIDTH+1)/2) { 2'b10 } };
   end
   // synopsys translate_on
   
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
          out_reg_a <= ram[addra];
      end
   end
   
   generate
      genvar j;
      for(j = 0; j < DATA_WIDTH/8 ; j = j + 1) begin: portb_we
         always @(posedge clkb) begin
            if (enb) begin
               if (web[j]) begin
                  ram[addrb][((j+1)*8)-1 : j*8] <= dinb[((j+1)*8)-1 : j*8];
               end
            end
         end
      end      
   endgenerate

   always @ (posedge clkb) begin
      if(enb) begin
          out_reg_b <= ram[addrb];
      end
   end
   // Output driver
   assign douta=out_reg_a;
   assign doutb=out_reg_b;

endmodule



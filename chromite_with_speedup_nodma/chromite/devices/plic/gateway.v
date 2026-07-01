// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd.
// see LICENSE.incore for more details on licensing terms
/*
Author: Babu P S , babu.ps@incoresemi.com
Created on: Monday 17 May 2021 03:56:16 PM IST

*/

`ifdef BSV_ASSIGNMENT_DELAY
`else
  `define BSV_ASSIGNMENT_DELAY
`endif

`ifdef BSV_POSITIVE_RESET
  `define BSV_RESET_VALUE 1'b1
  `define BSV_RESET_EDGE posedge
`else
  `define BSV_RESET_VALUE 1'b0
  `define BSV_RESET_EDGE negedge
`endif

module src_latch(RST, EN, ACTV_LOW, D_IN, Q_OUT) ;
    parameter lwidth = 1;
    parameter init = { lwidth {1'b0}} ;

    input  RST;
    input  [lwidth - 1 : 0]  ACTV_LOW;
    input  [lwidth - 1 : 0]  EN;
    input  [lwidth - 1 : 0]  D_IN;
    wire   [lwidth - 1 : 0]  XOR_OUT;
    output [lwidth - 1 : 0]  Q_OUT;
    reg    [lwidth - 1 : 0]  Q_OUT;

    assign XOR_OUT = D_IN ^ ACTV_LOW ;

    always@* begin // Latch is intended Here
        if (RST == `BSV_RESET_VALUE) begin
            Q_OUT <= `BSV_ASSIGNMENT_DELAY init;
        end
        else begin
            if (EN == 1)
                Q_OUT <= `BSV_ASSIGNMENT_DELAY XOR_OUT;
        end
    end

`ifdef BSV_NO_INITIAL_BLOCKS
`else
   initial begin
      Q_OUT = {((lwidth + 1)/2){2'b10}} ;
   end
`endif

endmodule

module interpt_latch(RST, EN, D_IN, CLR, Q_OUT) ;
    parameter iwidth = 1;
    parameter init = { iwidth {1'b0}} ;

    input  RST;
    input  [iwidth - 1 : 0]  EN;
    input  [iwidth - 1 : 0]  D_IN;
    input  [iwidth - 1 : 0]  CLR;
    output [iwidth - 1 : 0]  Q_OUT;
    reg    [iwidth - 1 : 0]  Q_OUT;

    always@* begin // Latch is intended Here
        if (RST == `BSV_RESET_VALUE || (CLR == 1)) begin
            Q_OUT <= `BSV_ASSIGNMENT_DELAY init;
        end
        else begin
            if (EN == 1)
                Q_OUT <= `BSV_ASSIGNMENT_DELAY D_IN;
        end
    end

`ifdef BSV_NO_INITIAL_BLOCKS
`else
   initial begin
      Q_OUT = {((iwidth + 1)/2){2'b10}} ;
   end
`endif

endmodule

// Interrupt Gateway with asynchronous reset
module gateway(Q_OUT, RST, SRC, ACTV_LOW, CLK_BIT, COMPLETE `ifdef gateway_le_detect , L0E1 `endif );

    parameter width = 1;
    parameter init = { width {1'b0}} ;

    input  RST;
    input  [width - 1 : 0]  ACTV_LOW;
    input  [width - 1 : 0]  CLK_BIT;
    input  [width - 1 : 0]  COMPLETE;
`ifdef gateway_le_detect
    input  [width - 1 : 0]  L0E1;
`endif //LE_DETECT
    input  [width - 1 : 0]  SRC;
    output [width - 1 : 0]  Q_OUT;

    wire [width - 1 : 0]    SRC_D0;
`ifdef gateway_le_detect
    wire [width - 1 : 0]    SRC_D1;
`endif //LE_DETECT
    wire [width - 1 : 0]    SRC_D2;
    reg  [width - 1 : 0]     Q_OUT;

    generate
      genvar ii;
      for(ii = 0; ii < width ; ii= ii+ 1) begin : Gateway
        src_latch l1(.RST(RST), .EN(CLK_BIT[ii]), .ACTV_LOW(ACTV_LOW[ii]), .D_IN(SRC[ii]), .Q_OUT(SRC_D0[ii]));
`ifdef gateway_le_detect
        assign l0e1[ii] = (L0E1[ii]) ? (SRC[ii] & ~SRC_D0[ii]) : (SRC_D0[ii]);
        src_latch l2(.RST(RST), .EN(CLK_BIT[ii]), .D_IN(l0e1[ii]), .Q_OUT(SRC_D1[ii]));
        interpt_latch l3(.RST(RST), .EN(SRC_D1[ii]), .D_IN(1'b1), .CLR(COMPLETE[ii]), .Q_OUT(SRC_D2[ii]));
`else
        interpt_latch l3(.RST(RST), .EN(SRC_D0[ii]), .D_IN(1'b1), .CLR(COMPLETE[ii]), .Q_OUT(SRC_D2[ii]));
`endif //LE_DETECT

      end
    endgenerate

    always@* begin
      Q_OUT <= SRC_D2;
    end


`ifdef BSV_NO_INITIAL_BLOCKS
`else
   initial begin
      Q_OUT = {((width + 1)/2){2'b10}} ;
   end
`endif

endmodule

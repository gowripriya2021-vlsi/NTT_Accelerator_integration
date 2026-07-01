/*============================================================================

This Verilog source file is part of the Berkeley HardFloat IEEE Floating-Point
Arithmetic Package, Release 1, by John R. Hauser.

Copyright 2019 The Regents of the University of California.  All rights
reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
    this list of conditions, and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions, and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

 3. Neither the name of the University nor the names of its contributors may
    be used to endorse or promote products derived from this software without
    specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS "AS IS", AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, ARE
DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=============================================================================*/

/*----------------------------------------------------------------------------
*----------------------------------------------------------------------------*/

`include "params.vi"

module
    countLeadingZeros#(parameter integer inWidth = 1, parameter integer countWidth = 1 
        /* ,parameter integer variant = 0) ( */
    )(input [(inWidth - 1):0] in, output [(countWidth - 1):0] count
    );
    
    /* localparam HARDFLOAT = 0; */
    /* localparam MUXED = 1; */
    /* localparam PE = 2; */

    /* if(variant == HARDFLOAT) */
    `ifdef CLZ_HF
        wire [(inWidth - 1):0] reverseIn;
        reverse#(inWidth) reverse_in(in, reverseIn);
        wire [inWidth:0] oneLeastReverseIn =
            {1'b1, reverseIn} & ({1'b0, ~reverseIn} + 1);
        genvar ix;
        generate
            for (ix = 0; ix <= inWidth; ix = ix + 1) begin :Bit
                wire [(countWidth - 1):0] countSoFar;
                if (ix == 0) begin
                    assign countSoFar = 0;
                end else begin
                    assign countSoFar =
                        Bit[ix - 1].countSoFar | (oneLeastReverseIn[ix] ? ix : 0);
                    if (ix == inWidth) assign count = countSoFar;
                end
            end
        endgenerate
    `else 
    `ifdef CLZ_PE
        wire [(inWidth - 1):0] reverseIn;
        wire no1 = |in;
        wire [(countWidth-1):0] intCount;
        if((1<<countWidth) == inWidth)
            prio_enc#(countWidth) enc(.x(in),.msb(intCount));
        else
            prio_enc#(countWidth) enc(.x({in,1'b1,0}),.msb(intCount));
        assign count = (no1)?((1<<countWidth)-1)-intCount:0;
    `else
        /* `ifdef CLZ_MUXED */
        /* else if (variant == MUXED) */
        function automatic [countWidth-1 : 0] fn_clz(input [inWidth-1:0] val, i);
            begin
                if(i==0)
                    fn_clz = ((val[0])?inWidth-1:0);
                else 
                    fn_clz = ((val[i])?inWidth-i-1:fn_clz(val,i-1));
            end
        endfunction
        assign count = fn_clz(in,inWidth-1);
    `endif
    `endif

endmodule



module prio_enc #(
  parameter WIDTH_LOG = 4
) (x, msb);

localparam WIDTH = 1 << WIDTH_LOG;
localparam HI = WIDTH - 1;

input [HI:0] x;

`ifdef FAST_1

// This seems to compile to most cost-efficient
// implementation across all toolchains.

output reg [WIDTH_LOG - 1:0] msb;

integer i, width;
reg [HI:0] part;

always @* begin
  msb = 0;
  part = x;
  for (i = WIDTH_LOG - 1; i >= 0; i = i - 1) begin
    width = 1 << i;
    if (|(part >> width))
      msb[i] = 1;
    // Hopefully synthesizer understands that 'part' is shrinking...
    part = msb[i] ? part >> width : part & ((1'd1 << width) - 1'd1);
  end
end

`else

// The most low-level implementation. Surprinsingly it's not always
// the fastest...

output [WIDTH_LOG - 1:0] msb;

wire [WIDTH_LOG*WIDTH - 1:0] ors;
assign ors[WIDTH_LOG*WIDTH - 1:(WIDTH_LOG - 1)*WIDTH] = x;

genvar w, i;
integer j;

generate
  for (w = WIDTH_LOG - 1; w >= 0; w = w - 1) begin
    assign msb[w] = |ors[w*WIDTH + 2*(1 << w) - 1:w*WIDTH + (1 << w)];
    if (w > 0) begin
      assign ors[(w - 1)*WIDTH + (1 << w) - 1:(w - 1)*WIDTH] = msb[w] ? ors[w*WIDTH + 2*(1 << w) - 1:w*WIDTH + (1 << w)] : ors[w*WIDTH + (1 << w) - 1:w*WIDTH];
    end
  end
endgenerate

`endif

endmodule
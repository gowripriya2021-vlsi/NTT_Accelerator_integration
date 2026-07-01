/*
Author: Sugandha Tiwari
Description: FMA Module using Hardfloat
*/

module mulAdd#(parameter integer expWidth = 3, parameter integer sigWidth = 3) (
        clk,
        control,
        op,
        a,
        b,
        c,
        roundingMode,
        out,
        exceptionFlags
    );
    
    input clk;
    input control;
    input [1:0] op;
    input [(expWidth + sigWidth-1):0] a;
    input [(expWidth + sigWidth-1):0] b;
    input [(expWidth + sigWidth-1):0] c;
    input [2:0] roundingMode;
    output [(expWidth + sigWidth-1):0] out;
    output [4:0] exceptionFlags;
    
    wire [(expWidth + sigWidth):0] recA, recB, recC, recOut;
    
    fNToRecFN#(expWidth, sigWidth) fNToRecFN_a(a, recA);
    fNToRecFN#(expWidth, sigWidth) fNToRecFN_b(b, recB);
    fNToRecFN#(expWidth, sigWidth) fNToRecFN_c(c, recC);
    
    mulAddRecFN#(expWidth, sigWidth) mulAddRecFN(control, op, recA, recB, recC, roundingMode, recOut, exceptionFlags);
    recFNToFN#(expWidth, sigWidth) recFNToFN(recOut, out);
    
endmodule

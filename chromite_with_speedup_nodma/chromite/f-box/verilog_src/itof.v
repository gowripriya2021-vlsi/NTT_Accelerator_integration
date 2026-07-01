/*
Author: Sugandha Tiwari
Description: Int to Float Module using Hardfloat
*/

module itof#(parameter integer expWidth = 3, parameter integer sigWidth = 3, parameter integer intWidth = 1) (
        clk,
        control,
        a,
        roundingMode,
        signedOut,
        out,
        exceptionFlags
    );
    
    input clk;
    input control;
    input [intWidth-1:0] a;
    input [2:0] roundingMode;
    input signedOut;
    output [(expWidth + sigWidth-1):0] out;
    output [4:0] exceptionFlags;
    
    wire [(expWidth + sigWidth):0] recOut;

    iNToRecFN#(intWidth, expWidth, sigWidth) iNToRecFN(control, signedOut, a, roundingMode, recOut, exceptionFlags);
    
    recFNToFN#(expWidth, sigWidth) recFNToFN(recOut, out);
    
endmodule

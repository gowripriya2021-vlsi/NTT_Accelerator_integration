/*
Author: Sugandha Tiwari
Description: Float to Int Module using Hardfloat
*/

module ftoi#(parameter integer expWidth = 3, parameter integer sigWidth = 3, parameter integer intWidth = 1) (
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
    input [(expWidth + sigWidth-1):0] a;
    input [2:0] roundingMode;
    input signedOut;
    output [intWidth-1:0] out;
    output [2:0] exceptionFlags;
    
    wire [(expWidth + sigWidth):0] recA;
    
    fNToRecFN#(expWidth, sigWidth) fNToRecFN_a(a, recA);
    
    recFNToIN#(expWidth, sigWidth, intWidth) recFNToIN(control, recA, roundingMode, signedOut, out, exceptionFlags);
    
endmodule

/*
Author: Sugandha Tiwari
Description: Div and Sqrt Module using Hardfloat
*/

module div_sqrt#(parameter integer expWidth = 3, parameter integer sigWidth = 3) (
            nReset,
            clock,
            control,
            inReady,
            inValid,
            sqrtOp,
            a,
            b,
            roundingMode,
            outValid,
            sqrtOpOut,
            out,
            exceptionFlags
    );
        
    input nReset;
    input clock;
    input control;
    output inReady;
    input inValid;
    input sqrtOp;
    input [(expWidth + sigWidth-1):0] a;
    input [(expWidth + sigWidth-1):0] b;
    input [2:0] roundingMode;
    output outValid;
    output sqrtOpOut;
    output [(expWidth + sigWidth-1):0] out;
    output [4:0] exceptionFlags;
    
    wire [(expWidth + sigWidth):0] recA, recB, recOut;
    
    fNToRecFN#(expWidth, sigWidth) fNToRecFN_a(a, recA);
    fNToRecFN#(expWidth, sigWidth) fNToRecFN_b(b, recB);
    
    divSqrtRecFN_small#(expWidth, sigWidth, 0)
        divSqrtRecFN(
            nReset,
            clock,
            control,
            inReady,
            inValid,
            sqrtOp,
            recA,
            recB,
            roundingMode,
            outValid,
            sqrtOpOut,
            recOut,
            exceptionFlags
        );
        
    recFNToFN#(expWidth, sigWidth) recFNToFN(recOut, out);
    
endmodule

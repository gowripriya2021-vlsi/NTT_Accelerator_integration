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

`include "HardFloat_consts.vi"
`include "HardFloat_specialize.vi"

/*----------------------------------------------------------------------------
*----------------------------------------------------------------------------*/

module
    mulAddRecFNToRaw_preMul#(
        parameter integer expWidth = 3, parameter integer sigWidth = 3
    ) (
        control,
        op,
        a,
        b,
        c,
        roundingMode,
        mulAddA,
        mulAddB,
        mulAddC,
        intermed_compactState,
        intermed_sExp,
        intermed_CDom_CAlignDist,
        intermed_highAlignedSigC
    );
`include "HardFloat_localFuncs.vi"
    input [(`floatControlWidth - 1):0] control;
    input [1:0] op;
    input [(expWidth + sigWidth):0] a;
    input [(expWidth + sigWidth):0] b;
    input [(expWidth + sigWidth):0] c;
    input [2:0] roundingMode;
    output [(sigWidth - 1):0] mulAddA;
    output [(sigWidth - 1):0] mulAddB;
    output [(sigWidth*2 - 1):0] mulAddC;
    output [5:0] intermed_compactState;
    output signed [(expWidth + 1):0] intermed_sExp;
    output [(clog2(sigWidth + 1) - 1):0] intermed_CDom_CAlignDist;
    output [(sigWidth + 1):0] intermed_highAlignedSigC;

    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    localparam prodWidth = sigWidth*2;
    localparam sigSumWidth = sigWidth + prodWidth + 3;
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire isNaNA, isInfA, isZeroA, signA;
    wire signed [(expWidth + 1):0] sExpA;
    wire [sigWidth:0] sigA;
    recFNToRawFN#(expWidth, sigWidth)
        recFNToRawFN_a(a, isNaNA, isInfA, isZeroA, signA, sExpA, sigA);
    wire isSigNaNA;
    isSigNaNRecFN#(expWidth, sigWidth) isSigNaN_a(a, isSigNaNA);
    wire isNaNB, isInfB, isZeroB, signB;
    wire signed [(expWidth + 1):0] sExpB;
    wire [sigWidth:0] sigB;
    recFNToRawFN#(expWidth, sigWidth)
        recFNToRawFN_b(b, isNaNB, isInfB, isZeroB, signB, sExpB, sigB);
    wire isSigNaNB;
    isSigNaNRecFN#(expWidth, sigWidth) isSigNaN_b(b, isSigNaNB);
    wire isNaNC, isInfC, isZeroC, signC;
    wire signed [(expWidth + 1):0] sExpC;
    wire [sigWidth:0] sigC;
    recFNToRawFN#(expWidth, sigWidth)
        recFNToRawFN_c(c, isNaNC, isInfC, isZeroC, signC, sExpC, sigC);
    wire isSigNaNC;
    isSigNaNRecFN#(expWidth, sigWidth) isSigNaN_c(c, isSigNaNC);
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire signProd = signA ^ signB ^ op[1];
    wire signed [(expWidth + 2):0] sExpAlignedProd =
        sExpA + sExpB + (-(1<<expWidth) + sigWidth + 3);
    wire doSubMags = signProd ^ signC ^ op[0];
    wire opSignC = signProd ^ doSubMags;
    wire roundingMode_min = (roundingMode == `round_min);
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire signed [(expWidth + 2):0] sNatCAlignDist = sExpAlignedProd - sExpC;
    wire [(expWidth + 1):0] posNatCAlignDist =
        sNatCAlignDist[(expWidth + 1):0];
    wire isMinCAlign = isZeroA || isZeroB || (sNatCAlignDist < 0);
    wire CIsDominant =
        !isZeroC && (isMinCAlign || (posNatCAlignDist <= sigWidth));
    wire signed [(expWidth + 1):0] sExpSum =
        CIsDominant ? sExpC : sExpAlignedProd - sigWidth;
    wire [(clog2(sigSumWidth) - 1):0] CAlignDist =
        isMinCAlign ? 0
            : (posNatCAlignDist < sigSumWidth - 1)
                  ? posNatCAlignDist[(clog2(sigSumWidth) - 1):0]
                  : sigSumWidth - 1;
    wire signed [(sigSumWidth + 2):0] extComplSigC =
        {doSubMags ? ~sigC : sigC, {(sigSumWidth - sigWidth + 2){doSubMags}}};
    wire [(sigSumWidth + 1):0] mainAlignedSigC = extComplSigC>>>CAlignDist;
    localparam CGrainAlign = (sigSumWidth - sigWidth - 1) & 3;
    wire [(sigWidth + CGrainAlign):0] grainAlignedSigC = sigC<<CGrainAlign;
    wire [(sigWidth + CGrainAlign)/4:0] reduced4SigC;
    compressBy4#(sigWidth + 1 + CGrainAlign)
        compressBy4_sigC(grainAlignedSigC, reduced4SigC);
    localparam CExtraMaskHiBound = (sigSumWidth - 1)/4;
    localparam CExtraMaskLoBound = (sigSumWidth - sigWidth - 1)/4;
    wire [(CExtraMaskHiBound - CExtraMaskLoBound - 1):0] CExtraMask;
    lowMaskHiLo#(clog2(sigSumWidth) - 2, CExtraMaskHiBound, CExtraMaskLoBound)
        lowMask_CExtraMask(CAlignDist[(clog2(sigSumWidth) - 1):2], CExtraMask);
    wire reduced4CExtra = |(reduced4SigC & CExtraMask);
    wire [(sigSumWidth - 1):0] alignedSigC =
        {mainAlignedSigC>>3,
         doSubMags ? (&mainAlignedSigC[2:0]) && !reduced4CExtra
             : (|mainAlignedSigC[2:0]) || reduced4CExtra};
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire isNaNAOrB = isNaNA || isNaNB;
    wire isNaNAny = isNaNAOrB || isNaNC;
    wire isInfAOrB = isInfA || isInfB;
    wire invalidProd = (isInfA && isZeroB) || (isZeroA && isInfB);
    wire notSigNaN_invalidExc =
        invalidProd || (!isNaNAOrB && isInfAOrB && isInfC && doSubMags);
    wire invalidExc =
        isSigNaNA || isSigNaNB || isSigNaNC || notSigNaN_invalidExc;
    wire notNaN_addZeros = (isZeroA || isZeroB) && isZeroC;
    wire specialCase = isNaNAny || isInfAOrB || isInfC || notNaN_addZeros;
    wire specialNotNaN_signOut =
        (isInfAOrB && signProd) || (isInfC && opSignC)
            || (notNaN_addZeros && !roundingMode_min && signProd && opSignC)
            || (notNaN_addZeros && roundingMode_min && (signProd || opSignC));
`ifdef HardFloat_propagateNaNPayloads
    wire signNaN;
    wire [(sigWidth - 2):0] fractNaN;
    propagateFloatNaN_mulAdd#(sigWidth)
        propagateNaN(
            control,
            op,
            isNaNA,
            signA,
            sigA[(sigWidth - 2):0],
            isNaNB,
            signB,
            sigB[(sigWidth - 2):0],
            invalidProd,
            isNaNC,
            signC,
            sigC[(sigWidth - 2):0],
            signNaN,
            fractNaN
        );
    wire isNaNOut = isNaNAny || notSigNaN_invalidExc;
    wire special_signOut =
        isNaNAny || notSigNaN_invalidExc ? signNaN : specialNotNaN_signOut;
`else
    wire special_signOut = specialNotNaN_signOut;
`endif
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    assign mulAddA = sigA;
    assign mulAddB = sigB;
    assign mulAddC = alignedSigC[prodWidth:1];
    assign intermed_compactState =
        {specialCase,
         invalidExc          || (!specialCase && signProd      ),
`ifdef HardFloat_propagateNaNPayloads
         isNaNOut            || (!specialCase && doSubMags     ),
`else
         isNaNAny            || (!specialCase && doSubMags     ),
`endif
         isInfAOrB || isInfC || (!specialCase && CIsDominant   ),
         notNaN_addZeros     || (!specialCase && alignedSigC[0]),
         special_signOut};
    assign intermed_sExp = sExpSum;
    assign intermed_CDom_CAlignDist = CAlignDist[(clog2(sigWidth + 1) - 1):0];
    assign intermed_highAlignedSigC =
`ifdef HardFloat_propagateNaNPayloads
         isNaNOut ? fractNaN :
`endif
          alignedSigC[(sigSumWidth - 1):(prodWidth + 1)];

endmodule

/*----------------------------------------------------------------------------
*----------------------------------------------------------------------------*/
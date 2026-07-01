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
    mulAddRecFNToRaw_postMul#(parameter integer expWidth = 3, parameter integer sigWidth = 3) (
        intermed_compactState,
        intermed_sExp,
        intermed_CDom_CAlignDist,
        intermed_highAlignedSigC,
        mulAddResult,
        roundingMode,
        invalidExc,
        out_isNaN,
        out_isInf,
        out_isZero,
        out_sign,
        out_sExp,
        out_sig
    );
`include "HardFloat_localFuncs.vi"
    input [5:0] intermed_compactState;
    input signed [(expWidth + 1):0] intermed_sExp;
    input [(clog2(sigWidth + 1) - 1):0] intermed_CDom_CAlignDist;
    input [(sigWidth + 1):0] intermed_highAlignedSigC;
    input [sigWidth*2:0] mulAddResult;
    input [2:0] roundingMode;
    output invalidExc;
    output out_isNaN;
    output out_isInf;
    output out_isZero;
    output out_sign;
    output signed [(expWidth + 1):0] out_sExp;
    output [(sigWidth + 2):0] out_sig;

    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    localparam prodWidth = sigWidth*2;
    localparam sigSumWidth = sigWidth + prodWidth + 3;
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire specialCase     = intermed_compactState[5];
    assign invalidExc    = specialCase && intermed_compactState[4];
    assign out_isNaN     = specialCase && intermed_compactState[3];
    assign out_isInf     = specialCase && intermed_compactState[2];
    wire notNaN_addZeros = specialCase && intermed_compactState[1];
    wire signProd        = intermed_compactState[4];
    wire doSubMags       = intermed_compactState[3];
    wire CIsDominant     = intermed_compactState[2];
    wire bit0AlignedSigC = intermed_compactState[1];
    wire special_signOut = intermed_compactState[0];
`ifdef HardFloat_propagateNaNPayloads
    wire [(sigWidth - 2):0] fractNaN = intermed_highAlignedSigC;
`endif
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire opSignC = signProd ^ doSubMags;
    wire [(sigWidth + 1):0] incHighAlignedSigC = intermed_highAlignedSigC + 1;
    wire [(sigSumWidth - 1):0] sigSum =
        {mulAddResult[prodWidth] ? incHighAlignedSigC
             : intermed_highAlignedSigC,
         mulAddResult[(prodWidth - 1):0],
         bit0AlignedSigC};
    wire roundingMode_min = (roundingMode == `round_min);
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire CDom_sign = opSignC;
    wire signed [(expWidth + 1):0] CDom_sExp = intermed_sExp - doSubMags;
    wire [(sigWidth*2 + 1):0] CDom_absSigSum =
        doSubMags ? ~sigSum[(sigSumWidth - 1):(sigWidth + 1)]
            : {1'b0, intermed_highAlignedSigC[(sigWidth + 1):sigWidth],
                   sigSum[(sigSumWidth - 3):(sigWidth + 2)]};
    wire CDom_absSigSumExtra =
        doSubMags ? !(&sigSum[sigWidth:1]) : |sigSum[(sigWidth + 1):1];
    wire [(sigWidth + 4):0] CDom_mainSig =
        (CDom_absSigSum<<intermed_CDom_CAlignDist)>>(sigWidth - 3);
    wire [((sigWidth | 3) - 1):0] CDom_grainAlignedLowSig =
        CDom_absSigSum[(sigWidth - 1):0]<<(~sigWidth & 3);
    wire [sigWidth/4:0] CDom_reduced4LowSig;
    compressBy4#(sigWidth | 3)
        compressBy4_CDom_absSigSum(
            CDom_grainAlignedLowSig, CDom_reduced4LowSig);
    wire [(sigWidth/4 - 1):0] CDom_sigExtraMask;
    lowMaskLoHi#(clog2(sigWidth + 1) - 2, 0, sigWidth/4)
        lowMask_CDom_sigExtraMask(
            intermed_CDom_CAlignDist[(clog2(sigWidth + 1) - 1):2],
            CDom_sigExtraMask
        );
    wire CDom_reduced4SigExtra = |(CDom_reduced4LowSig & CDom_sigExtraMask);
    wire [(sigWidth + 2):0] CDom_sig =
        {CDom_mainSig>>3,
         (|CDom_mainSig[2:0]) || CDom_reduced4SigExtra || CDom_absSigSumExtra};
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire notCDom_signSigSum = sigSum[prodWidth + 3];
    wire [(prodWidth + 2):0] notCDom_absSigSum =
        notCDom_signSigSum ? ~sigSum[(prodWidth + 2):0]
            : sigSum[(prodWidth + 2):0] + doSubMags;
    wire [(prodWidth + 2)/2:0] notCDom_reduced2AbsSigSum;
    compressBy2#(prodWidth + 3)
        compressBy2_notCDom_absSigSum(
            notCDom_absSigSum, notCDom_reduced2AbsSigSum);
    wire [(clog2(prodWidth + 4) - 2):0] notCDom_normDistReduced2;
    countLeadingZeros#((prodWidth + 2)/2 + 1, clog2(prodWidth + 4) - 1)
        countLeadingZeros_notCDom(
            notCDom_reduced2AbsSigSum, notCDom_normDistReduced2);
    wire [(clog2(prodWidth + 4) - 1):0] notCDom_nearNormDist =
        notCDom_normDistReduced2<<1;
    wire signed [(expWidth + 1):0] notCDom_sExp =
        intermed_sExp - notCDom_nearNormDist;
    wire [(sigWidth + 4):0] notCDom_mainSig =
        ({1'b0, notCDom_absSigSum}<<notCDom_nearNormDist)>>(sigWidth - 1);
    wire [(((sigWidth/2 + 1) | 1) - 1):0] CDom_grainAlignedLowReduced2Sig =
        notCDom_reduced2AbsSigSum[sigWidth/2:0]<<((sigWidth/2) & 1);
    wire [(sigWidth + 2)/4:0] notCDom_reduced4AbsSigSum;
    compressBy2#((sigWidth/2 + 1) | 1)
        compressBy2_notCDom_reduced2AbsSigSum(
            CDom_grainAlignedLowReduced2Sig, notCDom_reduced4AbsSigSum);
    wire [((sigWidth + 2)/4 - 1):0] notCDom_sigExtraMask;
    lowMaskLoHi#(clog2(prodWidth + 4) - 2, 0, (sigWidth + 2)/4)
        lowMask_notCDom_sigExtraMask(
            notCDom_normDistReduced2[(clog2(prodWidth + 4) - 2):1],
            notCDom_sigExtraMask
        );
    wire notCDom_reduced4SigExtra =
        |(notCDom_reduced4AbsSigSum & notCDom_sigExtraMask);
    wire [(sigWidth + 2):0] notCDom_sig =
        {notCDom_mainSig>>3,
         (|notCDom_mainSig[2:0]) || notCDom_reduced4SigExtra};
    wire notCDom_completeCancellation =
        (notCDom_sig[(sigWidth + 2):(sigWidth + 1)] == 0);
    wire notCDom_sign =
        notCDom_completeCancellation ? roundingMode_min
            : signProd ^ notCDom_signSigSum;
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    assign out_isZero =
        notNaN_addZeros || (!CIsDominant && notCDom_completeCancellation);
    assign out_sign =
           ( specialCase                 && special_signOut)
        || (!specialCase &&  CIsDominant && CDom_sign      )
        || (!specialCase && !CIsDominant && notCDom_sign   );
    assign out_sExp = CIsDominant ? CDom_sExp : notCDom_sExp;
`ifdef HardFloat_propagateNaNPayloads
    assign out_sig =
        out_isNaN ? {1'b1, fractNaN, 2'b00}
            : CIsDominant ? CDom_sig : notCDom_sig;
`else
    assign out_sig = CIsDominant ? CDom_sig : notCDom_sig;
`endif

endmodule

/*----------------------------------------------------------------------------
*----------------------------------------------------------------------------*/

module
    mulAddRecFNToRaw#(parameter integer expWidth = 3, parameter integer sigWidth = 3) (
        input [(`floatControlWidth - 1):0] control,
        input [1:0] op,
        input [(expWidth + sigWidth):0] a,
        input [(expWidth + sigWidth):0] b,
        input [(expWidth + sigWidth):0] c,
        input [2:0] roundingMode,
        output invalidExc,
        output out_isNaN,
        output out_isInf,
        output out_isZero,
        output out_sign,
        output signed [(expWidth + 1):0] out_sExp,
        output [(sigWidth + 2):0] out_sig
    );
`include "HardFloat_localFuncs.vi"

    wire [(sigWidth - 1):0] mulAddA, mulAddB;
    wire [(sigWidth*2 - 1):0] mulAddC;
    wire [5:0] intermed_compactState;
    wire signed [(expWidth + 1):0] intermed_sExp;
    wire [(clog2(sigWidth + 1) - 1):0] intermed_CDom_CAlignDist;
    wire [(sigWidth + 1):0] intermed_highAlignedSigC;
    mulAddRecFNToRaw_preMul#(expWidth, sigWidth)
        mulAddToRaw_preMul(
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
    wire [sigWidth*2:0] mulAddResult = mulAddA * mulAddB + mulAddC;
    mulAddRecFNToRaw_postMul#(expWidth, sigWidth)
        mulAddToRaw_postMul(
            intermed_compactState,
            intermed_sExp,
            intermed_CDom_CAlignDist,
            intermed_highAlignedSigC,
            mulAddResult,
            roundingMode,
            invalidExc,
            out_isNaN,
            out_isInf,
            out_isZero,
            out_sign,
            out_sExp,
            out_sig
        );

endmodule

/*----------------------------------------------------------------------------
*----------------------------------------------------------------------------*/
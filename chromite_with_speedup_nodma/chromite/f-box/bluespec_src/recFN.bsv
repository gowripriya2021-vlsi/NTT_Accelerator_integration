/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Mon Feb 14, 2022 09:50:22 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
 */
package recFN;

  `include "fconsts.defines"
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import resize     :: *;

  // Type definition for Recoded format. The expwidth and sigwidth should be specified as per the
  // values in IEEE 754 format. For example for SP: expwidth=8 and sigwidth=24(this also includes
  // the sign bit)
  typedef Bit#(TAdd#(1,TAdd#(expwidth,sigwidth))) 
    Recfmt#(numeric type expwidth, numeric type sigwidth);

  // Enum for rounding modes.
  typedef enum{Rm_near_even=0 , Rm_min_mag=1 , Rm_min=2, Rm_max=3, Rm_near_max_mag=4 ,Rm_odd=6 } Rm 
    deriving (Bits, Eq, FShow);

  // Enum for the operation which needs to be performed in case of CVT operations from/to Int.
  typedef enum{RV64D,RV32D,RV32F,RV64F} Config deriving (Bits, Eq, FShow);

  // Enum for cvt/mv operations which specify the target precision.
  typedef enum{F=0,D} Precision deriving(Bits, Eq, FShow);

  // Custom structure to store deconstructed floating point numbers.
  typedef struct{
    Bit#(1) sign;
    Bit#(TAdd#(expwidth,2)) exp;
    Bit#(TAdd#(sigwidth,1)) sig;
    Bit#(1) isNan;
    Bit#(1) isInf;
    Bit#(1) isZero;
  } Raw_fn#(numeric type expwidth, numeric type sigwidth) deriving (Bits, Eq, FShow);

  /*doc:func: Function which returns the value 1 in recoded format for all precisions. */
  function Recfmt#(expwidth,sigwidth) get_1();
    Bit#(TSub#(sigwidth,1)) mant = 0;
    Bit#(TAdd#(expwidth,1)) exp = fromInteger(valueof(TExp#(expwidth)));
    return {1'b0,exp,mant};
  endfunction

  /*doc:func: Function which returns the cNaN value in recoded format for all precisions. */
  function Recfmt#(expwidth,sigwidth) get_cnan();
    let lv_expwidth = valueof(expwidth);
    let lv_sigwidth = valueof(sigwidth);
    let lv_flen = lv_expwidth+lv_sigwidth;
    Recfmt#(expwidth,sigwidth) temp = 0;
    temp[lv_flen-1] = 1;
    temp[lv_flen-2] = 1;
    temp[lv_flen-3] = 1;
    temp[lv_sigwidth-2] = 1;
    return temp;
  endfunction

  /*doc:func: Function which performs the fsgnj operations of the RISCV spec on Recoded FP values.
   *currently supports only F & D.*/
  function Recfmt#(expwidth,sigwidth) fsgnj_recfn(
    Recfmt#(expwidth,sigwidth) rs1,
    Recfmt#(expwidth,sigwidth) rs2, 
    Precision mode, Bit#(2) op) provisos(
    Add#(expwidth,sigwidth,flen)
    );
    let lv_flen = valueof(flen);
    let out = rs1;
    Bit#(1) sign1;
    Bit#(1) sign2;
    Bit#(1) temp;
    if(lv_flen == 64 && mode == F) begin
      sign1 = out[32];
      sign2 = rs2[32];
    end
    else begin
      sign1 = out[lv_flen];
      sign2 = rs2[lv_flen];
    end
    case (op)
      0: temp = sign2;
      1: temp = ~sign2;
      default: temp = sign1 ^ sign2;
    endcase
    if(lv_flen==64 && mode == F)
      out[32] = temp;
    else
      out[lv_flen] = temp;
    return out;
  endfunction

  /*doc:func: Function which takes a FP value in Recoded format and returns the deconstructed value.
   * This function works for all precisions.*/
  function Raw_fn#(expwidth,sigwidth) recfn_to_rawfn(Recfmt#(expwidth,sigwidth) in) provisos(
    );
    
    Bit#(1) sign = resizeLSB(in);

    Bit#(TAdd#(expwidth,sigwidth)) lv_lsb = resize(in);

    Bit#(TAdd#(expwidth,1)) sexp = resizeLSB(lv_lsb);

    Bit#(TSub#(sigwidth,1)) fract = truncate(lv_lsb);
    
    Bit#(3) flag = resizeLSB(sexp);
    Bit#(1) sp = pack(flag[2:1] == 'b11);
    
    Bit#(1) zero = pack(flag == 0);

    return Raw_fn{
      sign: sign,
      exp: resize(sexp),
      sig: {1'b0,~zero,fract},
      isNan: sp & flag[0],
      isInf: sp & ~flag[0],
      isZero: zero
    };
  endfunction

  /*doc:func: This function performs the minmax operation of the RISCV spec on FP values in
   * Recoded format. Currently only supports SP(F) and DP(D). */
  function Tuple2#(Recfmt#(expwidth,sigwidth),Bit#(5)) fminmax_recfn(
    Recfmt#(expwidth,sigwidth) a,
    Recfmt#(expwidth,sigwidth) b,
    Precision p,
    // 1 - max 0 - min
    Bit#(1) min_max
  ) provisos(
      Add#(sigwidth,expwidth,flen),
      Add#(32, a__, TAdd#(sigwidth, expwidth)),
      Add#(32, d__, TAdd#(expwidth, sigwidth))
  );
    let lv_flen = valueof(flen);
    let lv_sigwidth = valueof(sigwidth);
    Raw_fn#(expwidth,sigwidth) raw_a;
    Raw_fn#(expwidth,sigwidth) raw_b;
    Recfmt#(expwidth,sigwidth) nan = 0;
    // Deconstruct based on input configuration and operation precision
    if(lv_flen >32 && p == F) begin
      Recfmt#(8,24) lv_a = truncate(a);
      Recfmt#(8,24) lv_b = truncate(b);
      Raw_fn#(8,24) lv_raw_a = recfn_to_rawfn(lv_a);
      Raw_fn#(8,24) lv_raw_b = recfn_to_rawfn(lv_b);
      raw_a = Raw_fn{
        sign: lv_raw_a.sign,
        exp: resize(lv_raw_a.exp),
        sig: resize(lv_raw_a.sig)<<29,
        isNan: lv_raw_a.isNan,
        isInf: lv_raw_a.isInf,
        isZero: lv_raw_a.isZero
      };
      raw_b = Raw_fn{
        sign: lv_raw_b.sign,
        exp: resize(lv_raw_b.exp),
        sig: resize(lv_raw_b.sig)<<29,
        isNan: lv_raw_b.isNan,
        isInf: lv_raw_b.isInf,
        isZero: lv_raw_b.isZero
      };
      Bit#(33) lv_nan = 0;
      lv_nan[31] = 1;
      lv_nan[30] = 1;
      lv_nan[29] = 1;
      lv_nan[22] = 1;
      nan = {maxBound, lv_nan};
    end
    else begin
      raw_a = recfn_to_rawfn(a);
      raw_b = recfn_to_rawfn(b);
      nan[lv_flen-1] = 1;
      nan[lv_flen-2] = 1;
      nan[lv_flen-3] = 1;
      nan[lv_sigwidth-2] = 1;
    end
    // Test if exponents are equal
    Bit#(1) eq_exp = pack(raw_a.exp == raw_b.exp);
    // Test if magniture of a is less than b
    Bit#(1) lt_mag = pack( (raw_a.exp < raw_b.exp) || (eq_exp == 1 && (raw_a.sig < raw_b.sig))); 
    // Check if output is nan
    Bool out_is_nan = unpack(raw_a.isNan & raw_b.isNan);
    // Check if output should be a based on the values. If either of the inputs are NaN, the ouput
    // is the non-NaN input regardless of the operation.
    Bool out_is_a = unpack(unpack(raw_a.isZero & raw_b.isZero) ? (raw_a.sign & ~raw_b.sign) ^ min_max :
                      ~raw_a.isNan & (raw_b.isNan | (min_max ^ (unpack(raw_a.sign ^ raw_b.sign) ?
                      raw_a.sign : raw_a.sign ^ lt_mag))));


    Bit#(5) flags = 0;
    // Set INV flag
    flags[4] = (raw_a.isNan & ~raw_a.sig[lv_sigwidth-2]) | (raw_b.isNan & ~raw_b.sig[lv_sigwidth-2]);
    return tuple2(
      ((out_is_nan) ? nan : ((out_is_a) ? a : b) ),flags);
  endfunction

  /*doc:func: Performs the fclass function mentioned in the riscv spec on Recoded format values.
   * Currently supports only SP(F) and DP(D) values.*/
  function Bit#(xlen) fclass_recfn(Recfmt#(expwidth,sigwidth) src, Precision mode) provisos(
    Add#(a__,10,xlen),
    Add#(expwidth,sigwidth,flen)
      );
    let lv_flen = valueof(flen);
    let lv_xlen = valueof(xlen);
    let lv_expwidth = valueof(expwidth);
    let lv_sigwidth = valueof(sigwidth);
    Bit#(3) flags;
    Bit#(1) sign;
    Bit#(1) msb_fract;
    Bit#(1) fract_0;
    Bit#(1) is_subnorm;
    if(lv_flen == 64 && mode == F) begin
      flags[0] = src[29];
      flags[1] = src[30];
      flags[2] = src[31];
      sign = src[32];
      msb_fract = src[22];
      fract_0 = |src[22:0];
      Bit#(9) exp = src[31:23];
      Bit#(9) s_exp = unpack(exp);
      Bit#(9) cmp = fromInteger(valueof(TAdd#(TExp#(7),2)));
      is_subnorm = pack(s_exp < cmp);
    end
    else begin
      Bit#(TAdd#(expwidth,1)) exp = src[lv_flen-1:lv_sigwidth-1];
      flags[0] = src[lv_flen-3];
      flags[1] = src[lv_flen-2];
      flags[2] = src[lv_flen-1];
      sign = src[lv_flen];
      msb_fract = src[lv_sigwidth-2];
      Bit#(TSub#(sigwidth,1)) lv_fract = src[lv_sigwidth-2:0];
      fract_0 = |lv_fract;
      Bit#(TAdd#(expwidth,1)) s_exp = unpack(exp);
      Bit#(TAdd#(expwidth,1)) cmp = fromInteger(valueof(TAdd#(TExp#(TSub#(expwidth,1)),2)));
      is_subnorm = pack(s_exp < cmp);
    end
    Bit#(xlen) lv_out = 0;
    Bit#(1) sp = flags[1] & flags[2];
    Bit#(1) is_0 = ~flags[0] & ~flags[1] & ~flags[2] & ~fract_0;
    Bit#(1) is_nan = sp & flags[0] & fract_0;
    // -inf
    lv_out[0] = sp & ~flags[0] & sign;
    // neg norm
    lv_out[1] = ~is_subnorm & sign & ~sp;
    // neg subnorm
    lv_out[2] = is_subnorm & ~is_0 & sign;
    // -0
    lv_out[3] = is_0 & sign;
    // +0
    lv_out[4] = is_0 & ~sign;
    // + subnorm
    lv_out[5] = is_subnorm & ~is_0 & ~sign;
    // + norm
    lv_out[6] = ~is_subnorm & ~sign & ~sp;
    // + inf
    lv_out[7] = sp & ~flags[0] & ~sign;
    // sig nan
    lv_out[8] = is_nan & ~msb_fract;
    // q nan
    lv_out[9] = is_nan & msb_fract;
    return lv_out;
  endfunction

  /*doc:func: Function which converts from Recoded format to IEEE format. This function doesn't
   * handle NaN boxed values and other flags. This is just a blind conversion function.*/
  function Bit#(flen) recfn_to_fn(Recfmt#(expwidth,sigwidth) in)
    provisos(
      Add#(sigwidth,expwidth,flen),
      Add#(expwidth,1,rec_expwidth),
      /* Log#(sigwidth,normwidth), */
      Add#(1, a__, TAdd#(sigwidth, expwidth)),
      /* Add#(1, b__, TAdd#(sigwidth, TAdd#(sigwidth, expwidth))), */
      Add#(1, c__, TAdd#(expwidth, sigwidth))

    );
    let lv_flen = valueof(flen);
    let lv_expwidth = valueof(expwidth);
    let lv_sigwidth = valueof(sigwidth);
    Bit#(TAdd#(rec_expwidth,1)) normexp = fromInteger(valueof(TAdd#(TExp#(TSub#(expwidth,1)),2)));
    let raw = recfn_to_rawfn(in);
    Bit#(1) isSubnormal = pack(raw.exp < normexp);
    let denormshift = normexp - raw.exp;
    Bit#(expwidth) expout = truncate((unpack(isSubnormal)?0:(raw.exp-normexp+1) 
                                  | (unpack(raw.isNan | raw.isInf)?maxBound:0)));
    Bit#(TSub#(sigwidth,1)) fractout = truncate(unpack(isSubnormal)?raw.sig >> denormshift : 
                                        unpack(raw.isInf) ? 0 : raw.sig);
    return {raw.sign,expout,fractout};
  endfunction

  /*doc:func; A function to convert from IEEE format to Recoded format. This function does not
   * handler NaN boxing and other cases required for using recoded format internally. This is just a
   * blind conversion function.*/
  function Recfmt#(expwidth,sigwidth) fn_to_recfn(Bit#(flen) in) provisos(
    Add#(expwidth,sigwidth,flen),
    Add#(expwidth,1,rec_expwidth),
    Add#(1, flen, TAdd#(sigwidth, b__)),
    Add#(2, c__, expwidth),
    Add#(2, rec_expwidth, TAdd#(expwidth, d__))
  );
    let lv_flen = valueof(flen);
    let lv_expwidth = valueof(expwidth);
    let lv_sigwidth = valueof(sigwidth);
    Bit#(1) sign = resizeLSB(in);
    Bit#(expwidth) expin = truncateLSB(in<<1);
    Bit#(TSub#(sigwidth,1)) fractin = truncate(in);

    let exp_0 = expin == 0;
    let fract_0 = fractin == 0;
    let normdist = pack(countZerosMSB(fractin));

    let subnormfract = fractin << normdist << 1;

    Bit#(rec_expwidth) bias = fromInteger(valueof(TSub#(TExp#(TAdd#(expwidth,1)),1)));

    Bit#(rec_expwidth) normexp = fromInteger(valueof(TExp#(TSub#(expwidth,1))));

    Bit#(rec_expwidth) adjustedExp = (exp_0?resize(normdist)^(bias):resize(expin)) + 
                                        (normexp | (exp_0?2:1));

    let is_0 = exp_0 && fract_0;

    Bit#(2) _temp = resizeLSB(adjustedExp);
    let is_sp = _temp == 'b11;

    Bit#(TAdd#(expwidth,1)) exp;

    Bit#(TSub#(expwidth,2)) lv_temp = truncate(adjustedExp);

    exp = zeroExtend(lv_temp);

    exp[lv_expwidth:lv_expwidth-2] = 
      (is_sp ? {2'b11,pack(!fract_0)}:(is_0?0:resizeLSB(adjustedExp)));
    return {sign,exp,(exp_0?subnormfract:fractin)};

  endfunction

  /*doc:func: This function performs the fcvt.*.X/L conversions into Recoded format. Handles
   * nanboxing by default, but doesnt set special flags. Currently supports RV[64/32]F[D]. A merged
   * and optimised implementation of the hardfloat iNToRecFN module. */
  function ActionValue#(Tuple2#(Recfmt#(expwidth,sigwidth),Bit#(5))) in_to_recfn(
      Bit#(1) op_signed,
      Bit#(xlen) in,
      Rm rm, Config cfg) provisos(
      Add#(expwidth,sigwidth,flen),
      Add#(g__, 32, xlen),
      Max#(xlen,TAdd#(sigwidth,2),int_sigwidth),
      Add#(xlen, i__, int_sigwidth),
      Add#(32, m__, TAdd#(sigwidth, expwidth)),
      Add#(32, m__, TAdd#(expwidth,sigwidth))
      );
    actionvalue
    let lv_expwidth = valueof(expwidth);
    let lv_sigwidth = valueof(sigwidth);
    let lv_flen = valueof(flen);
    let lv_xlen = valueof(xlen);
    let lv_intsigwidth = valueof(int_sigwidth);
    Bit#(xlen) corrected_in = in;
    if(lv_xlen > 32 && (cfg == RV32F || cfg == RV32D))
      corrected_in = unpack(op_signed) ? signExtend(in[31:0]) : zeroExtend(in[31:0]);
    Bit#(1) sign = op_signed & corrected_in[lv_xlen-1];
    Bit#(1) round_mag_up = ((pack(rm == Rm_min)&sign)|(pack(rm==Rm_max)&~sign));
    let absin = sign==1 ? -corrected_in : corrected_in;
    Bit#(TLog#(xlen)) adj = resize(pack(countZerosMSB(absin)));
    Bit#(int_sigwidth) sig;
    sig = {absin, 0} << adj;
    Bit#(1) iszero = ~sig[lv_intsigwidth-1];
    Bit#(TAdd#(TLog#(xlen),2)) sexp = {2'b10, ~adj}; 

    // Round and set exception
    Bit#(1) invalid_exc = 0;
    Bit#(1) infinite_exc = 0;
    Bit#(1) isNan = 0;
    Bit#(1) isInf = 0;

    // 0
    Bit#(1) isNanout = invalid_exc | (~infinite_exc & isNan);

    `define offset_xlen fromInteger(valueof(TExp#(TAdd#(1,TLog#(xlen)))))
    `define offset_32 fromInteger(valueof(TExp#(TAdd#(1,TLog#(32)))))
    `define base_expwidth fromInteger(valueof(TExp#(expwidth)))
    `define base_f fromInteger(valueof(TExp#(8)))

    Bit#(TAdd#(expwidth,1)) sadj_exp; 
    Bit#(TAdd#(expwidth,1)) t1; 
    Bit#(TAdd#(expwidth,1)) t2; 
    // in expwidth = log(xlen) + 1
    if(lv_flen > 32 && (cfg == RV32F || cfg == RV64F))
      t1 = `base_f;
    else
      t1 = `base_expwidth;
    t2 = `offset_xlen;

    sadj_exp = resize(sexp) + t1 - t2;
    Bit#(TAdd#(sigwidth,3)) adj_sig;
    if(lv_flen>32 && (cfg == RV32F || cfg == RV64F)) begin
      Bit#(TSub#(int_sigwidth,25)) lv_lsb = truncate(sig);
      Bit#(25) lv_msb = resizeLSB(sig);
      adj_sig = resize({lv_msb,|lv_lsb}) << (lv_sigwidth+2-26) ;
    end
    else begin
      Bit#(TSub#(int_sigwidth,TAdd#(sigwidth,1))) lv_lsb = truncate(sig);
      Bit#(TAdd#(sigwidth,1)) lv_msb = resizeLSB(sig);
      adj_sig = resize({lv_msb,|lv_lsb});
    end
    Bit#(1) sh_sig_down1 = 0;
    Bit#(TSub#(sigwidth,1)) fract_out;
    Bit#(TAdd#(expwidth,1)) out_exp;

    Bit#(1) common_overflow = 0;
    Bit#(1) common_totalUnderflow = 0;
    Bit#(1) common_underflow = 0;
    Bit#(1) common_inexact;


    if(lv_flen>32 && cfg == RV32D) begin
      Bit#(TAdd#(sigwidth,1)) lv_temp = truncateLSB(adj_sig);
      fract_out = truncate(lv_temp);
      out_exp = sadj_exp;
      common_inexact = 0;
    end
    else begin
      // 011
      Bit#(TAdd#(sigwidth,3)) round_mask = {0,sh_sig_down1,2'b11};
      // 001 110
      Bit#(TAdd#(sigwidth,3)) sh_round_mask = {0,sh_sig_down1,1'b1};
      // 011 & 110
      Bit#(TAdd#(sigwidth,3)) round_pos_mask = {0,1'b1,1'b0};
      Bit#(sigwidth) lv_msb = truncateLSB(adj_sig);
      Bit#(3) lv_lsb;
      Bit#(TAdd#(sigwidth,2)) incr_val;
      Bit#(1) ubr_round_pos_bit;
      Bit#(1) ubr_anyround;
      if(lv_flen>32 && (cfg == RV32F || cfg == RV64F)) begin
        lv_lsb = adj_sig[31:29];
        round_mask = resize({sh_sig_down1,2'b11,29'b0}); 
        sh_round_mask = resize({sh_sig_down1,1'b1,29'b0});
        round_pos_mask = resize({1'b1,30'b0});
        incr_val = resize({1'b1,29'b0});
        ubr_round_pos_bit = adj_sig[30];
        ubr_anyround = |(adj_sig[30:29]);
      end
      else begin
        lv_lsb = truncate(adj_sig);
        round_mask = resize({sh_sig_down1,2'b11});
        sh_round_mask = resize({sh_sig_down1,1'b1});
        round_pos_mask = resize({1'b1,1'b0});
        incr_val = 1;
        ubr_round_pos_bit = adj_sig[1];
        ubr_anyround = |(adj_sig[1:0]);
      end

      Bit#(1) round_pos_bit = lv_lsb[1];
      Bit#(1) round_extra = lv_lsb[0];
      Bit#(1) any_round = round_pos_bit | round_extra;
      Bit#(1) roundincr = (pack(rm == Rm_near_even || rm == Rm_near_max_mag) & round_pos_bit) |
                                                                      (round_mag_up & any_round);
      Bit#(TAdd#(sigwidth,2)) lv_adj_sig = {1'b0,truncateLSB(adj_sig)};
      Bit#(TAdd#(sigwidth,2)) lv_rmask_rs1 = truncateLSB(round_mask);
      Bit#(TAdd#(sigwidth,2)) lv_rmask_rs2 = {1'b0,truncateLSB(round_mask)};
      Bit#(TAdd#(sigwidth,2)) lv_rpmask_rs1 = truncateLSB(round_pos_mask);
      Bit#(TAdd#(sigwidth,2)) rounded_sig = (roundincr == 1) ? 
                            ((lv_adj_sig | lv_rmask_rs2)+incr_val) & 
                              ~((rm==Rm_near_even && round_pos_bit == 1 && unpack(~round_extra)) ?
                                lv_rmask_rs1 : 0) 
                              : (lv_adj_sig & ~lv_rmask_rs2) |( (rm==Rm_odd && any_round == 1)?
                                lv_rpmask_rs1 : 0);
      Bit#(2) lv_rval = truncateLSB(rounded_sig);
      Bit#(TAdd#(expwidth,2)) rounded_exp = {1'b0,sadj_exp} + zeroExtend(lv_rval);
      out_exp = truncate(rounded_exp);
      fract_out = truncate(rounded_sig);
      
      Bit#(1) unr_round_incr = (pack(rm==Rm_near_even || rm == Rm_near_max_mag)&ubr_round_pos_bit)
                                    | (round_mag_up & ubr_anyround);
      Bit#(1) round_carry = rounded_sig[lv_sigwidth];
      common_inexact = any_round;

      common_overflow = 0;
    end

    // 0
    Bit#(1) notnan_sp_out = infinite_exc | isInf;
    // 1
    Bit#(1) commoncase = ~isNanout & ~notnan_sp_out & ~iszero;
    // 0
    Bit#(1) overflow = commoncase & common_overflow;
    // 0
    Bit#(1) underflow = commoncase & common_underflow;
    // 0
    Bit#(1) inexact = overflow | (commoncase & common_inexact);
    Bit#(1) overflow_roundup = pack(rm==Rm_near_even || rm == Rm_near_max_mag ||
                                          unpack(round_mag_up));
    // 0
    Bit#(1) pegmin_nz_out = commoncase & common_totalUnderflow & (round_mag_up | pack(rm==Rm_odd));
    // 0
    Bit#(1) pegmax_finite_out = overflow & ~overflow_roundup;
    // 0
    Bit#(1) notnan_inf_out = notnan_sp_out | (overflow & overflow_roundup);
    
    Bit#(1) signout = sign;

    Bit#(TAdd#(expwidth,1)) exp_mask = (lv_flen>32 && (cfg == RV32F || cfg == RV64F)) ?7<<6: 7<<fromInteger(lv_expwidth-2); 

    Bit#(TAdd#(expwidth,1)) expout = out_exp & ~(iszero==1 ? exp_mask:0);

    Bit#(5) exceptionFlags = {invalid_exc,infinite_exc,overflow,underflow,inexact};

    Recfmt#(expwidth,sigwidth) outval;

    if(lv_flen>32 && (cfg == RV32F || cfg == RV64F)) begin
      Bit#(23) fract = resizeLSB(fract_out);
      Bit#(9) exp = resize(expout);
      outval = {maxBound,signout,exp,fract};
    end
    else
      outval = {sign,expout,fract_out};

    return tuple2(outval,exceptionFlags);
    endactionvalue
  endfunction

  /*doc:func: This function converts from a floating point number in recoded format to an integer
   * value. Currently supports RV[64/32]F[D]. A merged and optimised implementation of the 
   * hardfloat recFNToIN module. */
  function ActionValue#(Tuple2#(Bit#(xlen),Bit#(3))) recfn_to_in(Recfmt#(expwidth,sigwidth) in,
      Bit#(3) rm_in, Config cfg, Bit#(1) op_signed) provisos(
      Add#(expwidth,sigwidth,flen),
      Add#(2, a__, xlen)
      );
    actionvalue
    let lv_expwidth = valueof(expwidth);
    let lv_sigwidth = valueof(sigwidth);
    let lv_flen = valueof(flen);
    let lv_xlen = valueof(xlen);
    Rm rm = unpack(rm_in);
    Bit#(TAdd#(expwidth,2)) sexp;
    Bit#(1) isNan;
    Bit#(1) isInf;
    Bit#(1) isZero;
    Bit#(1) sign;
    Bit#(TAdd#(sigwidth,1)) sig;
    Bit#(1) special;
    Bit#(1) jbe1;
    Bit#(1) ge1_edge_over;
    Bit#(1) ge_pexp;
    Bit#(1) eq_pexp_iw2;
    Bit#(1) ge1;
    Integer out_len = 
      ((cfg == RV32F || (cfg == RV32D && lv_flen == 64)) && lv_xlen>32)? 32 : lv_xlen;
    if((cfg == RV64F || cfg == RV32F) && lv_flen==64) begin
      sexp = resize(in[31:23]);
      special = pack(sexp[8:7] == 'b11);
      isNan = special & sexp[6];
      isInf = special & ~sexp[6];
      isZero = pack(sexp[8:6]==0);
      Bit#(23) _temp = resize(in);
      sig = resize({~isZero,_temp}) << (lv_sigwidth-24);
      sign = in[32];
      jbe1 = ~sexp[8] & (&sexp[7:0]);
      ge1_edge_over = pack(sexp[7:0] == fromInteger(out_len-1));
      ge_pexp = pack(sexp[7:0] >= fromInteger(out_len));
      eq_pexp_iw2 = pack(sexp[7:0] == fromInteger(out_len-2));
      ge1 = sexp[8];
    end
    else begin
      Bit#(TAdd#(expwidth,1)) exp_temp = resizeLSB(in<<1);
      sexp = resize(exp_temp);
      special = sexp[lv_expwidth]&sexp[lv_expwidth-1]; // equivalent to == 'b11
      isNan = special & sexp[lv_expwidth-2];
      isInf = special & ~sexp[lv_expwidth-2];
      isZero = ~sexp[lv_expwidth] & ~sexp[lv_expwidth-2] & ~sexp[lv_expwidth-1];
      Bit#(TSub#(sigwidth,1)) _temp= resize(in);
      sig = {1'b0,~isZero,_temp};
      Bit#(expwidth) lv_exp = truncate(sexp);
      jbe1 = ~sexp[lv_expwidth] & (&lv_exp);
      sign = in[lv_flen];
      ge1_edge_over = pack(lv_exp == fromInteger(out_len-1));
      ge_pexp = pack(lv_exp >= fromInteger(out_len));
      eq_pexp_iw2 = pack(lv_exp == fromInteger(out_len-2));
      ge1 = sexp[lv_expwidth];
    end
    Bit#(TLog#(xlen)) lv_lsb_sexp = resize(sexp);
    Bit#(expwidth) shamt = (ge1==1)?resize(lv_lsb_sexp):0;
    Bit#(TSub#(sigwidth,1)) lv_lsb_sig = truncate(sig);
    Bit#(xlen) zeroes = 0;
    Bit#(TAdd#(xlen,sigwidth)) shiftedsig = {0,ge1,lv_lsb_sig} << shamt;
    Bit#(TSub#(sigwidth,2)) lv_lsb_shiftedsig = truncate(shiftedsig);
    Bit#(TSub#(TAdd#(xlen,sigwidth),TSub#(sigwidth,2))) lv_temp_lsb = resizeLSB(shiftedsig);
    Bit#(TAdd#(xlen,1)) lv_msb_shiftedsig = resize(lv_temp_lsb);
    Bit#(TAdd#(xlen,2)) alignedsig = {lv_msb_shiftedsig, |lv_lsb_shiftedsig};
    Bit#(xlen) unroundedint = truncateLSB(alignedsig);
    Bit#(1) common_inexact = (ge1==1)?|alignedsig[1:0]:~isZero;
    Bit#(1) incr_near_even = pack(rm == Rm_near_even) & ((ge1 & alignedsig[1] & 
                                (alignedsig[0] | alignedsig[2])) | (jbe1 & |alignedsig[1:0]));
    Bit#(1) incr_near_maxmag = pack(rm == Rm_near_max_mag) & ((ge1 & alignedsig[1]) | jbe1);
    Bit#(1) round_incr = incr_near_even | incr_near_maxmag | 
                          (pack(rm==Rm_min||rm==Rm_odd) & (sign & common_inexact)) |
                          (pack(rm==Rm_max) & (~sign & common_inexact ));
    Bit#(xlen) compint = (sign==1) ? ~unroundedint : unroundedint;
    Bit#(xlen) roundedint = (round_incr ^ sign)==1 ? compint + 1 : compint;
    roundedint[0] = roundedint[0] | (pack(rm == Rm_odd) & common_inexact);
    Bit#(TSub#(xlen,2)) lv_lsb_unroundedint = truncate(unroundedint);
    Bit#(1) roundCarry2 = (&lv_lsb_unroundedint) & round_incr;
    Bit#(1) common_overflow = ge1==1 ? 
          (ge_pexp|
            (op_signed==1?
              (sign==1?
                ge1_edge_over & ((|lv_lsb_unroundedint|unroundedint[lv_xlen-2])|round_incr)
                : ge1_edge_over | ((eq_pexp_iw2)&roundCarry2))
              : sign |(ge1_edge_over & unroundedint[lv_xlen-2])&roundCarry2))
          : ~op_signed & sign & round_incr;

    // IEEE doesnt distinguish between overflow and NV flags for cvt to int.
    // This particular snippet is different from the implementation of hardfloat to ensure
    // compliance to RISCV exception values
    Bit#(1) invalid_exc = isNan | isInf | common_overflow;
    Bit#(1) overflow = 0;
    Bit#(1) inexact = ~invalid_exc & ~common_overflow & common_inexact;
    
    Bit#(1) _temp = (isNan | ~sign);
    Bit#(TSub#(xlen,1)) _all1= signExtend(_temp);
    Bit#(xlen) excOut = resize({op_signed ^ _temp, _all1}); 
    
    Bit#(32) excOut_32 = {op_signed ^ _temp, signExtend(_temp)};
    Bit#(64) excOut_64 = resize(excOut_32);

    if(lv_xlen>32 && (cfg == RV32D || cfg == RV32F)) 
      excOut = resize(excOut_64);

    Bit#(xlen) retval = (invalid_exc | common_overflow)==1 ? excOut : roundedint;

    if(lv_xlen>32 && (cfg == RV32D || cfg == RV32F)) begin
      Bit#(32) _tret = resize(retval);
      Bit#(64) _tret2 = signExtend(_tret);
      retval = resize(_tret2);
    end

    return tuple2(retval,{invalid_exc,overflow,inexact});    
  endactionvalue
  endfunction

  interface Ifc_roundRawFNToRecFN#(numeric type expWidth,
    numeric type sigWidth,
    numeric type options);
    (*always_enabled*)
    method Bit#(TAdd#(1,TAdd#(sigWidth,expWidth))) out();
    (*always_enabled*)
    method Bit#(5) exceptionFlags();
    (*always_ready*)
    method Action request(Bit#(`control) control,Bit#(1) invalidExc,Bit#(1) infiniteExc,Bit#(1) in_isNaN,Bit#(1) in_isInf,Bit#(1) in_isZero,Bit#(1) in_sign,Bit#(TAdd#(expWidth,2)) in_sExp,Bit#(TAdd#(sigWidth,3)) in_sig,Bit#(3) roundingMode);
  endinterface: Ifc_roundRawFNToRecFN

  import "BVI" roundRawFNToRecFN=
  module mk_roundRawFNToRecFN(Ifc_roundRawFNToRecFN#(expWidth,sigWidth,options));
    default_clock clk();
    default_reset rstn();
    
    parameter expWidth = valueOf(expWidth);
    parameter sigWidth = valueOf(sigWidth);
    parameter options = valueOf(options);
    method out out() ;
    method exceptionFlags exceptionFlags() ;
    method request(control,invalidExc,infiniteExc,in_isNaN,in_isInf,in_isZero,in_sign,in_sExp,in_sig,roundingMode)  enable((*inhigh*) en_request);
    schedule (out,exceptionFlags,request) CF (out,exceptionFlags);
    path(control,out);
    path(control,exceptionFlags);
    path(invalidExc,out);
    path(invalidExc,exceptionFlags);
    path(infiniteExc,out);
    path(infiniteExc,exceptionFlags);
    path(in_isNaN,out);
    path(in_isNaN,exceptionFlags);
    path(in_isInf,out);
    path(in_isInf,exceptionFlags);
    path(in_isZero,out);
    path(in_isZero,exceptionFlags);
    path(in_sign,out);
    path(in_sign,exceptionFlags);
    path(in_sExp,out);
    path(in_sExp,exceptionFlags);
    path(in_sig,out);
    path(in_sig,exceptionFlags);
    path(roundingMode,out);
    path(roundingMode,exceptionFlags);
  endmodule: mk_roundRawFNToRecFN

  interface Ifc_recFNToRawFN#(numeric type expWidth,
    numeric type sigWidth);
    (*always_ready*)
    method Action request(Bit#(TAdd#(1,TAdd#(sigWidth,expWidth))) in);
    (*always_enabled*)
    method Bit#(1) isNan();
    (*always_enabled*)
    method Bit#(1) isInf();
    (*always_enabled*)
    method Bit#(1) isZero();
    (*always_enabled*)
    method Bit#(1) sign();
    (*always_enabled*)
    method Bit#(TAdd#(expWidth,2)) sExp();
    (*always_enabled*)
    method Bit#(TAdd#(sigWidth,1)) sig();
  endinterface: Ifc_recFNToRawFN

  import "BVI" recFNToRawFN=
  module mk_recFNToRawFN(Ifc_recFNToRawFN#(expWidth,sigWidth));
    default_clock clk();
    default_reset rstn();
    
    parameter expWidth = valueOf(expWidth);
    parameter sigWidth = valueOf(sigWidth);
    method request(in)  enable((*inhigh*) en_request);
    method isNan isNan() ;
    method isInf isInf() ;
    method isZero isZero() ;
    method sign sign() ;
    method sExp sExp() ;
    method sig sig() ;
    schedule (isNan,isInf,isZero,sign,sExp,sig,request) CF (isNan,isInf,isZero,sign,sExp,sig);
    path(in,isNan);
    path(in,isInf);
    path(in,isZero);
    path(in,sign);
    path(in,sExp);
    path(in,sig);
  endmodule: mk_recFNToRawFN

  interface Ifc_fNToRecFN#(numeric type expWidth,
    numeric type sigWidth);
    (*always_ready*)
    method Action request(Bit#(TAdd#(sigWidth,expWidth)) in);
    (*always_enabled*)
    method Bit#(TAdd#(1,TAdd#(sigWidth,expWidth))) out();
  endinterface: Ifc_fNToRecFN

  import "BVI" fNToRecFN=
  module mk_fNToRecFN(Ifc_fNToRecFN#(expWidth,sigWidth));
    default_clock clk();
    default_reset rstn();
    
    parameter expWidth = valueOf(expWidth);
    parameter sigWidth = valueOf(sigWidth);
    method request(in)  enable((*inhigh*) en_request);
    method out out() ;
    schedule (request,out) CF (out);
    path(in,out);
  endmodule: mk_fNToRecFN

  interface Ifc_recFNToFN#(numeric type expWidth,
    numeric type sigWidth);
    (*always_ready*)
    method Action request(Bit#(TAdd#(1,TAdd#(sigWidth,expWidth))) in);
    (*always_enabled*)
    method Bit#(TAdd#(sigWidth,expWidth)) out();
  endinterface: Ifc_recFNToFN

  import "BVI" recFNToFN=
  module mk_recFNToFN(Ifc_recFNToFN#(expWidth,sigWidth));
    default_clock clk();
    default_reset rstn();
    
    parameter expWidth = valueOf(expWidth);
    parameter sigWidth = valueOf(sigWidth);
    method request(in)  enable((*inhigh*) en_request);
    method out out() ;
    schedule (request,out) CF (out);
    path(in,out);
  endmodule: mk_recFNToFN

  interface Ifc_recFNToIN#(numeric type expWidth,
    numeric type sigWidth,
    numeric type intWidth);
    (*always_ready*)
    method Action request(Bit#(`control) control,Bit#(TAdd#(1,TAdd#(sigWidth,expWidth))) in,Bit#(3) roundingMode,Bit#(1) signedOut);
    (*always_enabled*)
    method Bit#(intWidth) out();
    (*always_enabled*)
    method Bit#(3) intExceptionFlags();
  endinterface: Ifc_recFNToIN

  import "BVI" recFNToIN=
  module mk_recFNToIN(Ifc_recFNToIN#(expWidth,sigWidth,intWidth));
    default_clock clk();
    default_reset rstn();
    
    parameter expWidth = valueOf(expWidth);
    parameter sigWidth = valueOf(sigWidth);
    parameter intWidth = valueOf(intWidth);
    method request(control,in,roundingMode,signedOut)  enable((*inhigh*) en_request);
    method out out() ;
    method intExceptionFlags intExceptionFlags() ;
    schedule (out,intExceptionFlags,request) CF (out,intExceptionFlags);
    path(control,out);
    path(control,intExceptionFlags);
    path(in,out);
    path(in,intExceptionFlags);
    path(roundingMode,out);
    path(roundingMode,intExceptionFlags);
    path(signedOut,out);
    path(signedOut,intExceptionFlags);
  endmodule: mk_recFNToIN

  interface Ifc_iNToRecFN#(numeric type expWidth,
    numeric type sigWidth,
    numeric type intWidth);
    (*always_ready*)
    method Action request(Bit#(`control) control,Bit#(1) signedIn,Bit#(intWidth) in,Bit#(3) roundingMode);
    (*always_enabled*)
    method Bit#(TAdd#(1,TAdd#(sigWidth,expWidth))) out();
    (*always_enabled*)
    method Bit#(5) exceptionFlags();
  endinterface: Ifc_iNToRecFN

  import "BVI" iNToRecFN=
  module mk_iNToRecFN(Ifc_iNToRecFN#(expWidth,sigWidth,intWidth));
    default_clock clk();
    default_reset rstn();
    
    parameter expWidth = valueOf(expWidth);
    parameter sigWidth = valueOf(sigWidth);
    parameter intWidth = valueOf(intWidth);
    method request(control,signedIn,in,roundingMode)  enable((*inhigh*) en_request);
    method out out() ;
    method exceptionFlags exceptionFlags() ;
    schedule (out,exceptionFlags,request) CF (out,exceptionFlags);
    path(control,out);
    path(control,exceptionFlags);
    path(signedIn,out);
    path(signedIn,exceptionFlags);
    path(in,out);
    path(in,exceptionFlags);
    path(roundingMode,out);
    path(roundingMode,exceptionFlags);
  endmodule: mk_iNToRecFN

  interface Ifc_recFNToRecFN#(numeric type inExpWidth,
    numeric type inSigWidth,
    numeric type outExpWidth,
    numeric type outSigWidth);
    (*always_ready*)
    method Action request(Bit#(`control) control,Bit#(TAdd#(1,TAdd#(inSigWidth,inExpWidth))) in,Bit#(3) roundingMode);
    (*always_enabled*)
    method Bit#(TAdd#(1,TAdd#(outSigWidth,outExpWidth))) out();
    (*always_enabled*)
    method Bit#(5) exceptionFlags();
  endinterface: Ifc_recFNToRecFN

  import "BVI" recFNToRecFN=
  module mk_recFNToRecFN(Ifc_recFNToRecFN#(inExpWidth,inSigWidth,outExpWidth,outSigWidth));
    default_clock clk();
    default_reset rstn();
    
    parameter inExpWidth = valueOf(inExpWidth);
    parameter inSigWidth = valueOf(inSigWidth);
    parameter outExpWidth = valueOf(outExpWidth);
    parameter outSigWidth = valueOf(outSigWidth);
    method request(control,in,roundingMode)  enable((*inhigh*) en_request);
    method out out() ;
    method exceptionFlags exceptionFlags() ;
    schedule (out,exceptionFlags,request) CF (out,exceptionFlags);
    path(control,out);
    path(control,exceptionFlags);
    path(in,out);
    path(in,exceptionFlags);
    path(roundingMode,out);
    path(roundingMode,exceptionFlags);
  endmodule: mk_recFNToRecFN
  interface Ifc_compareRecFN#(numeric type expWidth,
    numeric type sigWidth);
    (*always_ready*)
    method Action request(Bit#(TAdd#(1,TAdd#(expWidth,sigWidth))) a,Bit#(TAdd#(1,TAdd#(expWidth,sigWidth))) b,Bit#(1) signaling);
    (*always_enabled*)
    method Bit#(1) lt();
    (*always_enabled*)
    method Bit#(1) eq();
    (*always_enabled*)
    method Bit#(1) gt();
    (*always_enabled*)
    method Bit#(1) unordered();
    (*always_enabled*)
    method Bit#(5) exceptionFlags();
  endinterface: Ifc_compareRecFN

  import "BVI" compareRecFN=
  module mk_compareRecFN(Ifc_compareRecFN#(expWidth,sigWidth));
    default_clock clk();
    default_reset rstn();
    
    parameter expWidth = valueOf(expWidth);
    parameter sigWidth = valueOf(sigWidth);
    method request(a,b,signaling)  enable((*inhigh*) en_request);
    method lt lt() ;
    method eq eq() ;
    method gt gt() ;
    method unordered unordered() ;
    method exceptionFlags exceptionFlags() ;
    schedule (request,lt,eq,gt,unordered,exceptionFlags) CF (request,lt,eq,gt,unordered,exceptionFlags);
  endmodule: mk_compareRecFN

  interface Ifc_divSqrtRecFN_small#(numeric type expWidth,
    numeric type sigWidth);
    (*always_ready*)
    method Action request(Bit#(`control) control,Bit#(1) sqrtOp,Bit#(TAdd#(1,TAdd#(expWidth,sigWidth))) a,Bit#(TAdd#(1,TAdd#(expWidth,sigWidth))) b,Bit#(3) roundingMode);
    (*always_enabled*)
    method Bit#(1) inReady();
    (*always_enabled*)
    method Bit#(1) outValid();
    (*always_enabled*)
    method Bit#(1) sqrtOpOut();
    (*always_enabled*)
    method Bit#(TAdd#(1,TAdd#(expWidth,sigWidth))) out();
    (*always_enabled*)
    method Bit#(5) exceptionFlags();
  endinterface: Ifc_divSqrtRecFN_small

  import "BVI" divSqrtRecFN_small=
  module mk_divSqrtRecFN_small(Ifc_divSqrtRecFN_small#(expWidth,sigWidth));
    default_clock clk_clock;
    default_reset rst_nReset;
    input_clock clk_clock(clock) <- exposeCurrentClock;
    input_reset rst_nReset (nReset) clocked_by(clk_clock) <- exposeCurrentReset;
    
    parameter expWidth = valueOf(expWidth);
    parameter sigWidth = valueOf(sigWidth);
    method request(control,sqrtOp,a,b,roundingMode)  enable(inValid);
    method inReady inReady() ;
    method outValid outValid() ;
    method sqrtOpOut sqrtOpOut() ;
    method out out() ;
    method exceptionFlags exceptionFlags() ;
    schedule (inReady,out,outValid,sqrtOpOut,exceptionFlags) SB (request);
    schedule (inReady,out,outValid,sqrtOpOut,exceptionFlags) CF (inReady,out,outValid,sqrtOpOut,exceptionFlags);
    schedule (request) C (request);
  endmodule: mk_divSqrtRecFN_small
endpackage: recFN

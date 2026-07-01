/* 
see LICENSE.incore
see LICENSE.iitm

Author: Shubham Roy
Email id: shubham.roy@incoresemi.com
Details:implemetation of replacement policies of tlb

--------------------------------------------------------------------------------------------------
*/
package replacement_tlb;
`ifdef async_reset
  import RegOverrides  :: *;
`endif
  import Vector::*;
  import LFSR::*;
  import Assert::*;

  function Bit#(m) reSize (Bit#(n) din) provisos( Add#(m,n,mn) );
    Bit#(mn) x = zeroExtend(din);
    return truncate(x);
  endfunction:reSize

  interface Ifc_replace#(numeric type sets, numeric type ways);
    /*doc:method: it suggest which line to replace given the set and valid in lines in the set */
    method ActionValue#(Bit#(TLog#(TMax#(1,ways)))) line_replace (Bit#(TLog#(TMax#(1,sets))) index, Bit#(ways) valid);
    /*doc:method: it update the set based on the hit does not have major significance in random replacement */
    method Action update_set (Bit#(TLog#(TMax#(1,sets))) index, Bit#(TLog#(TMax#(1,ways))) way);
    /*doc:method: it resets */
    method Action reset_repl;
  endinterface

  module mkreplace#(parameter Bit#(2) alg)(Ifc_replace#(sets,ways));

    let v_ways = valueOf(ways);
    let v_sets = valueOf(sets);
    staticAssert(alg==0,"Invalid replacement Algorithm");
    if (v_sets == 0) begin
      method ActionValue#(Bit#(TLog#(TMax#(1,ways)))) line_replace (Bit#(TLog#(TMax#(1,sets))) index, Bit#(ways) valid);
        noAction;
        return ?;
      endmethod

      /*doc:method: it update the set based on the hit does not have major significance in random replacement */
      method Action update_set (Bit#(TLog#(TMax#(1,sets))) index, Bit#(TLog#(TMax#(1,ways))) way);
        noAction;
      endmethod
      /*doc:method: it resets */
      method Action reset_repl;
        noAction;
      endmethod
    end
    else if(alg == 0)begin // RANDOM
      LFSR#(Bit#(4)) random <- mkLFSR_4();
      Reg#(Bool) rg_init <- mkReg(True);
      rule initialize_lfsr(rg_init);
        random.seed(1);
        rg_init<=False;
      endrule

      method ActionValue#(Bit#(TLog#(TMax#(1,ways)))) line_replace (Bit#(TLog#(TMax#(1,sets))) index, Bit#(ways) valid);
          if (&(valid)==1 )begin // if all lines are valid 
            return reSize(random.value());
          end
          else begin // if any line is not valid
            Bit#(TLog#(TMax#(1,ways))) temp=0;
            for(Bit#(TAdd#(1,TLog#(TMax#(1,ways)))) i=0;i<fromInteger(v_ways);i=i+1) begin
              if(valid[i]==0)begin
                temp=truncate(i);
              end
            end
            return temp;
          end
      endmethod
      method Action update_set (Bit#(TLog#(TMax#(1,sets))) index, Bit#(TLog#(TMax#(1,ways))) way);
        random.next();
      endmethod
      method Action reset_repl;
        random.seed(1);
      endmethod
    end
  endmodule
endpackage

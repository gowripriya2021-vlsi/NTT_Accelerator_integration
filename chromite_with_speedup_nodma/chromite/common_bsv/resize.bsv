/*
  Copyright (c) 2022 Incore Semiconductors Pvt. Ltd. All Rights Reserved. See LICENSE.incore for more details.
  Created On:  Fri May 06, 2022 11:37:33 
  Author(s): 
  - S Pawan Kumar <pawan.kumar@incoresemi.com> gitlab: @pawks github: @pawks
 */
package resize;
  /*
    Provisos less function to truncate/zeroExtend a value automatically
    based on input and output sizes.
  */
  function Bit#(m) resize(Bit#(n) x) provisos(Add#(m,n,mn));
    Bit#(mn) _temp = zeroExtend(x);
    return truncate(_temp);
  endfunction
  /*
    Provisos less function to truncate if input size is greater than 
    output size, otherwise the function extends the value with 1's.
   */
  function Bit#(m) resize_max(Bit#(n) x) provisos(Add#(m,n,mn));
    Bit#(mn) _temp = {maxBound,x};
    return truncate(_temp);
  endfunction
  /*
    Provisos less function to truncateLSB or add 0's on the LSB side based on input and output
    sizes.
  */
  function Bit#(m) resizeLSB(Bit#(n) x) provisos(Add#(m,n,mn));
    Bit#(mn) _temp = zeroExtend(reverseBits(x));
    return reverseBits(truncate(_temp));
  endfunction
endpackage

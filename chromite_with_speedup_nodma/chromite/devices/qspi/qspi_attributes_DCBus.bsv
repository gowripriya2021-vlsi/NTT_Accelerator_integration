// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Thursday 23 April 2020 05:30:48 PM IST

*/

package qspi_attributes_DCBus;
  import DCBus::*;
  import Reserved::*;

  typedef struct{
    Bit#(1) ddrm;
    Bit#(1) dhhc;
    Bit#(1) dummy_bit;
    Bit#(1) sioo;
    Bit#(2) fmode;
    Bit#(2) dmode;
    Bit#(1) dummy_confirmation;
    Bit#(5) dcyc;
    Bit#(2) absize;
    Bit#(2) abmode;
    Bit#(2) adsize;
    Bit#(2) admode;
    Bit#(2) imode;
    Bit#(8) instruction;
  } CCRReg deriving(Bits, Eq, FShow);

  typedef struct{
    Bit#(8) prescaler;
    Bit#(1) pmm;
    Bit#(1) apms;
    ReservedZero#(1) cr_res1;
    Bit#(1) toie;
    Bit#(1) smie;
    Bit#(1) ftie;
    Bit#(1) tcie;
    Bit#(1) teie;
    ReservedZero#(4) cr_res2;
    Bit#(4) fthres;
    Bit#(1) fsel;
    Bit#(1) dfm;
    ReservedZero#(1) cr_res3;
    Bit#(1) sshift;
    Bit#(1) tcen;
    Bit#(1) dmaen;
    Bit#(1) abort;
    Bit#(1) en;
  } CRReg deriving(Bits, Eq, FShow);

  typedef struct{
    ReservedZero#(27) fcr_res1;
    Bit#(1) ctof;
    Bit#(1) csmf;
    ReservedZero#(1) fcr_res2;
    Bit#(1) ctcf;
    Bit#(1) ctef;
  } FCRReg deriving(Bits, Eq, FShow);


  /*doc:module: Conditional Read-write CR register
  Action on Read : None // Action on Write : None // Condition on Read : None // Condition on Write : Yes*/
  //-------------------------------------------------------------------------------------------------------
  module regCRRWCond#(DCRAddr#(aw,o) attr, CRReg reset, Bool a)(IWithDCBus#(DCBus#(aw, dw), Reg#(CRReg)))
    provisos (
      Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
      Add#(a__, o, aw),
      Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
      Add#(dw, b__, 64), // bus side data should be <= 64
      Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
      Add#(e__, TDiv#(dw, 8), 8)
    );

    Reg#(CRReg) x();
    mkReg#(reset) inner_reg(x);
    PulseWire wr_written <- mkPulseWire;

    interface DCBus dcbus;
      method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
        Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
        Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
        Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
        if ((req_index == reg_index) && perm) begin
          let {succ, temp} <- fn_adjust_write(addr, data, strobe, pack(x), attr.min, attr.max, attr.mask);
          CRReg lv_x= x;
          if(succ) begin
            if(a) begin
              lv_x.prescaler  = temp[31:24];
              lv_x.pmm        = temp[23];
              lv_x.apms       = temp[22];
              lv_x.fsel       = temp[7];
              lv_x.dfm        = temp[6];
              lv_x.sshift     = temp[4];
              lv_x.tcen       = temp[3];
            end
            lv_x.toie         = temp[20];
            lv_x.smie         = temp[19];
            lv_x.ftie         = temp[18];
            lv_x.tcie         = temp[17];
            lv_x.teie         = temp[16];
            lv_x.fthres       = temp[11:8];
            lv_x.dmaen        = temp[2];
            lv_x.abort        = temp[1];
            lv_x.en           = temp[0];
            wr_written.send;
          end
          x<= lv_x;
          return succ;
        end
        else
          return False;
      endmethod:write

      method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
        Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
        Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
        Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
        if ((req_index == reg_index) && perm) begin
          let temp = fn_adjust_read(addr, size, pack(x), attr.min, attr.max, attr.mask );
          return temp;
        end
        else
          return tuple2(False, 0);
      endmethod:read
    endinterface:dcbus
    interface Reg device;
      method Action _write (value);
        if (!wr_written) x <= value;
      endmethod:_write
      method _read = x._read;
    endinterface
  endmodule:regCRRWCond

  // A wrapper to provide just a normal Reg interface and automatically
  // add the DCBus interface to the collection. This is the module used
  // in designs (as a normal register would be used).
  module [ModWithDCBus#(aw, dw)] mkDCBRegCRRWCond#(DCRAddr#(aw,o) attr, CRReg x, Bool a)(Reg#(CRReg))
    provisos (
      Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
      Add#(a__, o, aw),
      Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
      Add#(dw, b__, 64), // bus side data should be <= 64
      Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
      Add#(e__, TDiv#(dw, 8), 8)

    );
    let ifc();
    collectDCBusIFC#(regCRRWCond(attr, x, a)) _temp(ifc);
    return(ifc);
  endmodule:mkDCBRegCRRWCond


  /*doc:module: Read Write Conditional -CCREffect register
  Action on Read : None // Action on Write : Yes // Condition on Read : None // Condition on Write : Yes*/
  //------------------------------------------------------------------------------------------------------
  module regRWCondCCRe#(DCRAddr#(aw,o) attr, CCRReg reset, Action _act1, Action _act2, Bool c)(IWithDCBus#(DCBus#(aw, dw), Reg#(CCRReg)))
    provisos (

      Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
      Add#(a__, o, aw),
      Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
      Add#(dw, b__, 64), // bus side data should be <= 64
      Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
      Add#(e__, TDiv#(dw, 8), 8)
    );

    Reg#(CCRReg) x();
    mkReg#(reset) inner_reg(x);
    PulseWire wr_written <- mkPulseWire;

    interface DCBus dcbus;
      method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
        Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
        Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
        Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
        if ((req_index == reg_index) && perm) begin
          let {succ, temp} <- fn_adjust_write(addr, data, strobe, pack(x), attr.min, attr.max, attr.mask);
          if(succ && c) begin
            x <= unpack(temp);
            wr_written.send;
            if(temp[11:10]==0 && (temp[27:26] == 'b00 || temp[27:26]=='b01 || temp[25:24]=='b0) && temp[9:8]!=0) begin
              _act1;
            end
            if(temp[27:26]=='b11) //Memory Mapped Mode
              _act2;
          end
          return (succ && c);
        end
        else
          return False;
      endmethod:write

      method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
        Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
        Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
        Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
        if ((req_index == reg_index) && perm) begin
          let temp = fn_adjust_read(addr, size, pack(x), attr.min, attr.max, attr.mask );
          return temp;
        end
        else
          return tuple2(False, 0);
      endmethod:read
    endinterface:dcbus

    interface Reg device;
      method Action _write (value);
        if (!wr_written) x <= value;
      endmethod:_write

      method _read = x._read;
    endinterface
  endmodule:regRWCondCCRe

  // A wrapper to provide just a normal Reg interface and automatically
  // add the DCBus interface to the collection. This is the module used
  // in designs (as a normal register would be used).
  module [ModWithDCBus#(aw, dw)] mkDCBRegRWCondCCRe#(DCRAddr#(aw,o) attr, CCRReg x, Action _act1, Action _act2, Bool c)(Reg#(CCRReg))
    provisos (

      Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
      Add#(a__, o, aw),
      Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
      Add#(dw, b__, 64), // bus side data should be <= 64
      Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
      Add#(e__, TDiv#(dw, 8), 8)
    );
    let ifc();
    collectDCBusIFC#(regRWCondCCRe(attr, x, _act1, _act2, c)) _temp(ifc);
    return(ifc);
  endmodule:mkDCBRegRWCondCCRe

  /*doc:module: Write Only-Clear SideEffect register
  Action on Read : None // Action on Write : Yes // Condition on Read : None // Condition on Write : None */
  //---------------------------------------------------------------------------------------------------------
  module regWOCSe#(DCRAddr#(aw,o) attr, FCRReg reset, Action _act1, Action _act2, Action _act3, Action _act4, Action _act5) (IWithDCBus#(DCBus#(aw, dw), Reg#(FCRReg)))
    provisos (
      Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
      Add#(a__, o, aw),
      Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
      Add#(dw, b__, 64), // bus side data should be <= 64
      Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
      Add#(e__, TDiv#(dw, 8), 8)
    );
    Reg#(FCRReg) x();
    mkReg#(reset) inner_reg(x);
    PulseWire written <- mkPulseWire;
    interface DCBus dcbus;
      method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
        Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
        Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
        Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
        if ((req_index == reg_index) && perm) begin
          let {succ, temp} <- fn_adjust_write(addr, data, strobe, pack(x), attr.min, attr.max, attr.mask);
          if(succ) begin x <= unpack(temp); // give cbus write priority over device write.
            if(temp[0] == 1) begin
              _act1;
            end
            if(temp[1] == 1) begin
              _act2;
              _act3;
            end
            if(temp[3] == 1) begin
              _act4;
            end
            if(temp[4] == 1) begin
              _act5;
            end
            written.send;
          end
          return succ;
        end
        else
        return False;
      endmethod:write
      method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
        return tuple2(False,0);
      endmethod:read
    endinterface:dcbus

    interface Reg device;
      method Action _write (value);
        if (!written) x <= value;
      endmethod:_write
      method _read = x._read;
    endinterface
  endmodule:regWOCSe

  // A wrapper to provide just a normal Wire interface and automatically
  // add the CBus interface to the collection. This is the module used
  // in designs (as a normal register would be used).
  module [ModWithDCBus#(aw, dw)] mkDCBRegWOCSe#(DCRAddr#(aw,o) attr, FCRReg x, Action _act1, Action _act2, Action _act3, Action _act4, Action _act5)(Reg#(FCRReg))
    provisos (
      Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
      Add#(a__, o, aw),
      Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
      Add#(dw, b__, 64), // bus side data should be <= 64
      Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
      Add#(e__, TDiv#(dw, 8), 8)
    );
    let ifc();
    collectDCBusIFC#(regWOCSe(attr, x, _act1, _act2, _act3, _act4, _act5)) _temp(ifc);
    return(ifc);
  endmodule: mkDCBRegWOCSe


// ------------------------------  Read-write Conditional register ------------------------------------
//Action on Read : None // Action on Write : None // Condition on Read : None // Condition on Write : Yes
//-----------------------------------------------------------------------------------------------------
module regRWCond#(DCRAddr#(aw,o) attr, r reset, Bool a)(IWithDCBus#(DCBus#(aw, dw), Reg#(r)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );

  Reg#(r) x();
  mkReg#(reset) inner_reg(x);
  PulseWire written <- mkPulseWire;

  interface DCBus dcbus;
    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
      if ((req_index == reg_index) && perm) begin
        let {succ, temp} <- fn_adjust_write(addr, data, strobe, pack(x), attr.min, attr.max, attr.mask);
        if (a && succ) begin
          x<= unpack(temp); written.send;  // give cbus write priority over device _write.
        end
        return succ;
      end
      else
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
      if ((req_index == reg_index) && perm) begin
        let temp = fn_adjust_read(addr, size, pack(x), attr.min, attr.max, attr.mask );
        return temp;
      end
      else
        return tuple2(False, 0);
    endmethod:read
  endinterface:dcbus
  interface Reg device;
    method Action _write (value);
      if (!written) x <= value;
    endmethod:_write
    method _read = x._read;
  endinterface
endmodule:regRWCond

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithDCBus#(aw, dw)] mkDCBRegRWCond#(DCRAddr#(aw,o) attr, r x, Bool a)(Reg#(r))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(regRWCond(attr, x, a)) _temp(ifc);
  return(ifc);
endmodule:mkDCBRegRWCond

// ------------------------------ Conditional Read-write Side-effect register ------------------------------------
//Action on Read : None // Action on Write : Yes // Condition on Read : None // Condition on Write : Yes
//----------------------------------------------------------------------------------------------------------------
module regRWCondSe#(DCRAddr#(aw,o) attr, r reset, Action _act1, Bool a)(IWithDCBus#(DCBus#(aw, dw), Reg#(r)))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );

  Reg#(r) x();
  mkReg#(reset) inner_reg(x);
  PulseWire written <- mkPulseWire;

  interface DCBus dcbus;
    method ActionValue#(Bool) write(Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strobe, DCBusXperm wperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.wr_perm == PvU) || (wperm >= attr.wr_perm));
      if ((req_index == reg_index) && perm) begin
        let {succ, temp} <- fn_adjust_write(addr, data, strobe, pack(x), attr.min, attr.max, attr.mask);
        if(succ && a) begin x<= unpack(temp);
          written.send;
          _act1;
        end
        return (succ);
      end
      else
        return False;
    endmethod:write

    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(TSub#(aw,o)) req_index = truncateLSB(addr);
      Bit#(TSub#(aw,o)) reg_index = truncateLSB(attr.addr);
      Bool perm = ((attr.rd_perm == PvU) || (rperm >= attr.rd_perm));
      if ((req_index == reg_index) && perm) begin
        let temp = fn_adjust_read(addr, size, pack(x), attr.min, attr.max, attr.mask );
        return temp;
      end
      else
        return tuple2(False, 0);
    endmethod:read
  endinterface:dcbus

  interface Reg device;
    method Action _write (value);
      if (!written) x <= value;
    endmethod:_write

    method _read = x._read;
  endinterface
endmodule:regRWCondSe

// A wrapper to provide just a normal Reg interface and automatically
// add the CBus interface to the collection. This is the module used
// in designs (as a normal register would be used).
module [ModWithDCBus#(aw, dw)] mkDCBRegRWCondSe#(DCRAddr#(aw,o) attr, r x, Action _act1, Bool a)(Reg#(r))
  provisos (
    Add#(TSub#(2, TLog#(TDiv#(dw, 8))), d__, o),
    Bits#(r, m),
    Add#(a__, o, aw),
    Mul#(TDiv#(dw, 8), 8, dw), // bus-side data-width should be multiples of 8
    Mul#(TDiv#(m, 8), 8, m), // register data-width should be multiples of 8
    Add#(dw, b__, 64), // bus side data should be <= 64
    Add#(m, c__, 64),  // register data should be <= 64
    Add#(TExp#(TLog#(dw)),0,dw), // bus-side should be a power of 2.
    Add#(TExp#(TLog#(m)),0,m), // register side should be a power of 2
    Add#(e__, TDiv#(dw, 8), 8)
  );
  let ifc();
  collectDCBusIFC#(regRWCondSe(attr, x, _act1, a)) _temp(ifc);
  return(ifc);
endmodule:mkDCBRegRWCondSe

endpackage

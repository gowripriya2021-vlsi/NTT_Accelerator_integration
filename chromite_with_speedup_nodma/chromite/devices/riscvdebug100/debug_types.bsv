// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Saturday 17 April 2021 05:30:14 PM

*/
package debug_types ;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import DefaultValue :: * ;
import Reserved     :: * ;
import Vector       :: * ;
import axi4         :: * ;

import GetPut       :: * ;

`include "debug.defines"
  //Integer baseAddress;
  //Integer nprogbuf;
  //Integer nabstractdata;
  //Integer maxsbsize;
  //Bool    supportquickaccess;
  //Bool    supporthartarray;
  //Integer    nhaltgroups;
  //Bool    hartresets;
  //Integer implicitebreak;
  //Bool    authentication;
interface Ifc_debug_dtm;
  interface Put#(Bit#(`DMI_REQ_SZ)) putCommand;// 7 (ABITS) + 32 + 2
  interface Get#(Bit#(`DMI_RESP_SZ)) getResponse;
endinterface: Ifc_debug_dtm

interface Ifc_hart_side#(numeric type ncomponents);
  method Bit#(ncomponents) mv_hartmask;
  method Bit#(ncomponents) mv_hartreset;
  method Bit#(ncomponents) mv_harthaltreq;
  method Action ma_havereset (Bit#(ncomponents) resetack);
  method Action ma_debugenable (Bit#(ncomponents) _debugenable);
  method Bit#(1) mv_hasel;
  method Bit#(10) mv_hartsel;
endinterface: Ifc_hart_side

interface Ifc_debug#( numeric type nprogbuf,
                      numeric type nabstractdata,
                      numeric type ncomponents,
                      numeric type wd_id
                   );
  interface Ifc_axi4_master#(wd_id, `paddr, `debug_bus_sz, 0) debug_master;
  interface Ifc_debug_dtm dtm_access;
  interface Reset ifc_dm_reset;
  method Bit#(1) mv_ndm_reset;
  interface Ifc_hart_side#(ncomponents) hartside;
endinterface:Ifc_debug


function Bit#(m) resize (Bit#(n) din) provisos( Add#(m,n,mn) );
  Bit#(mn) x = zeroExtend(din);
  return truncate(x);
endfunction:resize
typedef struct{
  ReservedZero#(6) reserved;
  Bit#(1) resume;
  Bit#(1) go;
} Flags deriving(Bits, FShow, Eq);

typedef struct{
  ReservedZero#(8) zero1;
  Bit#(4) nscratch;
  ReservedZero#(3) zero2;
  Bit#(1) dataaccess;
  Bit#(4) datasize;
  Bit#(12) dataaddr;
} HartInfo deriving(Bits, FShow, Eq);

function Bit#(20) fn_j_imm(Bit#(21) offset);
  return {offset[20],offset[10:1],offset[11],offset[19:12]};
endfunction

// Debug module system bus access type
typedef enum {Access8Bit, 
              Access16Bit, 
              Access32Bit, 
              Access64Bit, 
              Access128Bit} DMAccessType deriving(Bits, FShow, Eq);

// Debug module abstract command error types
typedef enum {Success = 0, 
              ErrBusy = 1, 
              ErrNotSupported = 2,
              ErrException =3, 
              ErrHaltResume = 4, 
              ErrBus = 5,
              ErrOther = 7} DMAbstractCmdErr deriving(Bits, FShow, Eq);

// Debug Module abstract command types
typedef enum {AccessRegister=0, QuickAccess=1} DMAbstractCmd deriving(Bits, FShow, Eq);

// Debug Module system bus access error types
typedef enum {SbSuccess = 0, 
              SbTimeout=1, 
              SbBadAddr=2, 
              SbAlignment=3,
              SbSizeErr=4,
              SbOther=7} SBErr deriving(Eq, FShow, Bits);

// Access Register Command Control fields
typedef struct{
  ReservedZero#(1) zero1;
  Bit#(3) aarsize;
  Bit#(1) aarpostincrement;
  Bit#(1) postexec;
  Bit#(1) transfer;
  Bit#(1) write;
  Bit#(16) regno;
} AccessReg deriving(Bits, FShow, Eq);

// top level debug module configuration parameters
typedef struct{
  Integer baseAddress;
  Integer maxsbsize;
  Bool    supportquickaccess;
  Bool    supporthartarray;
  Integer nhaltgroups;
  Bool    hartresets;
  Integer implicitebreak;
  Bool    authentication;
} DMConfig deriving(Eq);

instance DefaultValue#(DMConfig);
  defaultValue = DMConfig{baseAddress : 0, 
                          maxsbsize : 32,
                          supportquickaccess : True,
                          supporthartarray : False,
                          nhaltgroups : 1,
                          hartresets : True,
                          implicitebreak : 1,
                          authentication : False};
endinstance

function Reg#(t) w1notifyConditionalReg(Reg#(t) r, Wire#(Bool) w, Bool condition)
    provisos(Literal#(t), Eq#(t));
  return (interface Reg;
    method t _read = 0;
    method Action _write(t x);
    if (x == 1 && condition)
      w._write(True);
    endmethod
  endinterface);
endfunction: w1notifyConditionalReg

function Reg#(t) w1notifyReg(Reg#(t) r, Wire#(Bool) w)
    provisos(Literal#(t), Eq#(t));
  return (interface Reg;
    method t _read = 0;
    method Action _write(t x);
    if (x == 1)
      w._write(True);
    endmethod
  endinterface);
endfunction: w1notifyReg

function Reg#(t) warznotifyReg(Reg#(t) r, Wire#(Bool) w, Wire#(t) wval)
    provisos(Literal#(t), Eq#(t));
  return (interface Reg;
    method t _read = 0;
    method Action _write(t x);
      w._write(True);
      wval._write(x);
      r._write(x);
    endmethod
  endinterface);
endfunction:warznotifyReg

function Reg#(Bit#(n)) hartselloReg(Reg#(Bit#(n)) r, Integer ncomponents);
  return (interface Reg;
    method Bit#(n) _read = ncomponents>1?r._read: 0;
    method Action _write(Bit#(n) w);
      if(ncomponents> 1)
        r._write(w);
    endmethod
  endinterface);
endfunction: hartselloReg

function Reg#(Bit#(1)) haselReg(Reg#(Bit#(1)) r, Integer ncomponents);
  return (interface Reg;
    method Bit#(1) _read = ncomponents>1?r._read:0;
    method Action _write( Bit#(1) w);
      if(ncomponents>1)
        r._write(w);
    endmethod
  endinterface);
endfunction:haselReg

function Reg#(t) w1cReg(Reg#(t) r)
  provisos(Bitwise#(t));
  return (interface Reg;
    method t _read = r._read;
    method Action _write( t w);
      r._write(~w&r._read);
    endmethod
  endinterface);
endfunction

function Reg#(t) notifyWrReg(Reg#(t) r, Wire#(Bool) w, Wire#(t) wval)
  provisos(Bitwise#(t));
  return (interface Reg;
    method t _read = r._read;
    method Action _write( t x);
      w._write(True);
      wval._write(x);
    endmethod
  endinterface);
endfunction

endpackage: debug_types


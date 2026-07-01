// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Saturday 17 April 2021 05:26:57 PM

*/
package debug;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import ConcatReg    :: * ;
import ConfigReg    :: * ;
import DReg         :: * ;
import Assert       :: * ;
import DefaultValue :: * ;
import Clocks       :: * ;
import GetPut       :: * ;
import BUtils       :: * ;
import Memory       :: * ;


import debug_types  :: * ;
import apb          :: * ;
import axi4l        :: * ;
import axi4         :: * ;
import DCBus        :: * ;
import Memory       :: * ;
import Semi_FIFOF   :: * ;

typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_debug#(nprogbuf, nabstractdata, ncomponents, wd_id))
    Ifc_debug_apb#(type aw, type dw, type uw, numeric type nprogbuf, numeric type nabstractdata,
          numeric type ncomponents, numeric type wd_id);
typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Ifc_debug#(nprogbuf, nabstractdata, ncomponents, wd_id))
    Ifc_debug_axi4l#(type aw, type dw, type uw, numeric type nprogbuf, numeric type nabstractdata,
          numeric type ncomponents, numeric type wd_id);

typedef IWithSlave#(Ifc_axi4_slave#(iw, aw, dw, uw), Ifc_debug#(nprogbuf, nabstractdata, ncomponents, wd_id))
    Ifc_debug_axi4#(type iw, type aw, type dw, type uw, numeric type nprogbuf, numeric type nabstractdata,
          numeric type ncomponents, numeric type wd_id);

`include "Logger.bsv"
`include "debug.defines"

/*// the following is required because control is updated by both.
(*conflict_free="rl_set_busy, dtm_access_putCommand_put"*)
// the following is required because sb read/write respons both update sberr and sbbusy. However,
// both can never fire in the same cycle
(*conflict_free="rl_sba_read_response,rl_sba_write_response"*)
// the following is required they both update sbbusy,sberr. However, only one of them can take
// effect on either registers in a single cycle.
(*conflict_free="rl_sba_request,dtm_access_putCommand_put"*)
(*conflict_free="rl_sba_read_response,dtm_access_putCommand_put"*)
(*conflict_free="rl_sba_write_response,dtm_access_putCommand_put"*)

// the following both rules/methods update the abstract data and program buffer but should never
// happen simultaneously
(*conflict_free="rl_bus_write,dtm_access_putCommand_put"*)*/
module [Module] mkdebug#(parameter DMConfig cfg)(IWithDCBus#(DCBus#(aw,dw), Ifc_debug#( nprogbuf,
                                                    nabstractdata, ncomponents, wd_id)))
  provisos(
    Add#(TLog#(ncomponents), __a, 10), // This indicates that hartsello can't cross 10-bits. which is fair assumption as this point
    Add#(__b, TLog#(TDiv#(TMax#(ncomponents, 32), 32)), 32) // for size of hawindowsel
    ,Add#(TMax#(1, TLog#(ncomponents)), __c, 10) // hartsello can't be more than 10bits
    ,Add#(__d, TLog#(ncomponents), 12), // there can be only 0x800-0x400 flags. Hence only so many harts supported

    Add#(h__, 32, dw),
    Add#(a__, 12, aw),
    Add#(8, b__, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(c__, 2, aw),
    Add#(dw, d__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(e__, TDiv#(dw, 8), 8),
    Mul#(32, f__, dw),
    Add#(4, g__, TDiv#(dw, 8))
  );

  let v_nprogbuf           =valueOf(nprogbuf);
  let v_nabstractdata      =valueOf(nabstractdata);
  let v_ncomponents        =valueOf(ncomponents);
  let numhaltedstatus = ((v_ncomponents-1)/32) + 1;

  staticAssert(v_nprogbuf <= 16, "\nDEBUG: Max Progbuf size is 16");
  staticAssert(v_nabstractdata <=12, "\nDEBUG: Max Abstract Data words is 12");

  Bool atzero = (cfg.baseAddress == 0);
  Integer nAbstractInstr = (atzero)?2:5;
  Integer ndscratch = (atzero)?1:2;

  // These are used by the ROM.
  `define PROGBUF   fromInteger(`DATA) - fromInteger(v_nprogbuf*4) - fromInteger(4*cfg.implicitebreak)
  `define IMPEBREAK fromInteger(`DATA - 4)
  `define ABSTRACT  `PROGBUF - fromInteger(nAbstractInstr*4)

//  `define JWHERETO  {fromInteger(`ABSTRACT-`WHERETO),12'h6f}
  Integer nslices = ((v_ncomponents-1)/`WINDOWSZ)+1;
  // --------------------------------------- Reset generation ------------------------------------
  Clock curr_clk <- exposeCurrentClock;                                  // current default clock
  Reset curr_reset<-exposeCurrentReset;                                  // current default reset
  MakeResetIfc dmactive_reset <-mkReset(0,False,curr_clk);            // create a new reset for curr_clk
  Reset  dm_reset <- mkResetEither(dmactive_reset.new_rst,curr_reset);     // OR default and new_rst
  // ----------------------------------------------------------------------------------------------
  
  Reg#(Maybe#(Bit#(34))) dmi_response <- mkReg(tagged Invalid);
  Vector#(29,Bit#(32)) vrom;
  vrom[0] = 'h00c0006f;
  vrom[1] = 'h0600006f;
  vrom[2] = 'h0380006f;
  vrom[3] = 'h0ff0000f;
  vrom[4] = 'h7b241073;
  vrom[5] = 'hf1402473;
  vrom[6] = 'h10802023;
  vrom[7] = 'h40044403;
  vrom[8] = 'h00147413;
  vrom[9] = 'h02041463;
  vrom[10] = 'hf1402473;
  vrom[11] = 'h40044403;
  vrom[12] = 'h00247413;
  vrom[13] = 'h02041863;
  vrom[14] = 'h00000013;
  vrom[15] = 'hfd9ff06f;
  vrom[16] = 'h7b202473;
  vrom[17] = 'h10002623;
  vrom[18] = 'h00100073;
  vrom[19] = 'hf1402473;
  vrom[20] = 'h10802223;
  vrom[21] = 'h7b202473;
  vrom[22] = 'h0ff0000f;
  vrom[23] = 'h0000100f;
  vrom[24] = 'h30000067;
  vrom[25] = 'hf1402473;
  vrom[26] = 'h10802423;
  vrom[27] = 'h7b202473;
  vrom[28] = 'h7b200073;

  Reg#(Bit#(32)) v_abstract_reg[nAbstractInstr];
  for (Integer i = 0; i<nAbstractInstr; i = i + 1) begin
    v_abstract_reg[i] <- mkReg(`NOP, reset_by dm_reset);
  end
  
  Ifc_axi4_master_xactor#(wd_id, `paddr, `debug_bus_sz, 0) master_xactor <- mkaxi4_master_xactor(defaultValue, reset_by dm_reset);

  function Bit#(32) genLoads(AccessReg cntrl);
    Bit#(32) instruction;
    instruction[6:0] = `Load_op; // opcode
    instruction[11:7] = cntrl.regno[4:0];//rd
    instruction[14:12] = cntrl.aarsize;// funct3
    instruction[19:15] = atzero? 0 : cntrl.regno[0]==1?8:9;// rs1
    instruction[31:20] = atzero? `DATA : ((`DATA - 'h800) & 'hfff);//imm
    return instruction;
  endfunction: genLoads
  
  function Bit#(32) genStores(AccessReg cntrl);
    Bit#(32) instruction;
    Bit#(12) offset = atzero?`DATA: ((`DATA - 'h800)&'hfff);
    instruction[6:0] = `Store_op; // opcode
    instruction[11:7] = offset[4:0];//imm-lo
    instruction[14:12] = cntrl.aarsize;// funct3
    instruction[19:15] = atzero? 0 : cntrl.regno[0]==1?8:9;// rs1
    instruction[24:20] = cntrl.regno[4:0];// rs2
    instruction[31:25] = truncateLSB(offset);//imm-hi
    return instruction;
  endfunction: genStores
  
  function Bit#(32) genCSR(AccessReg cntrl);
    Bit#(32) instruction;
    instruction[6:0] = `CSRRW_op; // opcode
    instruction[11:7] = cntrl.regno[0]==1?8:9;//rd
    instruction[14:12] = 'b001;// funct3
    instruction[19:15] = cntrl.regno[0]==1?8:9;// rs1
    instruction[31:20] = 'h7b3;//imm-hi
    return instruction;
  endfunction: genCSR

  // -------------------------------------- DMCONTROL ---------------------------------------------
  //TODO: assert that while writing to resumereq, hartreset, ackhavereset, setresethaltreq and
  //clresethaltreq, a max of one bit is set.

  Reg#(Bit#(1)) haltreq           <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) resumereq         <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) hartreset         <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) ackhavereset      <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) ackunavail        <- mkReg(0, reset_by dm_reset); // We may not support this. TODO
  ConfigReg#(Bit#(1)) hasel       <- mkConfigReg(0, reset_by dm_reset);
  ConfigReg#(Bit#(TMax#(1,TLog#(ncomponents)))) _hartsello        <- mkConfigReg(0, reset_by dm_reset);
  ConfigReg#(Bit#(TMax#(1,TLog#(ncomponents)))) hartsello   = hartselloReg(_hartsello, v_ncomponents);
  Reg#(Bit#(10)) hartselhi        = readOnlyReg(0); // 2^20 is just obnoxious. simple opt here.
  Reg#(Bit#(1)) setkeepalive      = readOnlyReg(0); // we do not support this feature
  Reg#(Bit#(1)) clrkeepalive      = readOnlyReg(0); // we do not support this feature
  Reg#(Bit#(1)) setresethaltreq   <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) clrresethaltreq   <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) ndmreset          <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) dmactive          <- mkReg(0);

  Wire#(Bool) wr_haltreq_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_resumereq_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_ackhavereset_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_ackunavail_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_clrresethaltreq_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_setresethaltreq_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_clrkeepalive_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_setkeepalive_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bit#(1)) wr_hatreq_wrval <- mkDWire(0, reset_by dm_reset);

  Reg#(Bit#(32)) dmcontrol = concatReg15(warznotifyReg(haltreq, wr_haltreq_wren, wr_hatreq_wrval), 
                                         w1notifyConditionalReg(resumereq, wr_resumereq_wren, True), 
                                         hartreset, 
                                         w1notifyReg(ackhavereset, wr_ackhavereset_wren),
                                         w1notifyReg(ackunavail, wr_ackunavail_wren),
                                         haselReg(hasel, v_ncomponents),
                                         readOnlyReg(0), // this is required is hartsello requires less than 10 bits
                                         hartsello,
                                         hartselhi,
                                         w1notifyReg(setkeepalive, wr_setkeepalive_wren),
                                         w1notifyReg(clrkeepalive, wr_clrkeepalive_wren),
                                         w1notifyReg(setresethaltreq, wr_setresethaltreq_wren),
                                         w1notifyReg(clrresethaltreq, wr_clrresethaltreq_wren),
                                         ndmreset,
                                         dmactive
                                      );
  // ----------------------------------------------------------------------------------------------
  // -------------------------------------- DMSTATUS ----------------------------------------------
  Reg#(Bit#(1)) ndmresetpending <- mkReg(0);
  Reg#(Bit#(1)) stickyunavail   = readOnlyReg(0);
  Reg#(Bit#(1)) impebreak       = readOnlyReg(fromInteger(cfg.implicitebreak));
  Reg#(Bit#(1)) allhavereset    <- mkReg(0);
  Reg#(Bit#(1)) anyhavereset    <- mkReg(0);
  Reg#(Bit#(1)) allresumeack    <- mkReg(1);
  Reg#(Bit#(1)) anyresumeack    <- mkReg(1);
  Reg#(Bit#(1)) allnonexistent  <- mkReg(0);
  Reg#(Bit#(1)) anynonexistent  <- mkReg(0);
  Reg#(Bit#(1)) allunavail      <- mkReg(0);
  Reg#(Bit#(1)) anyunavail      <- mkReg(0);
  Reg#(Bit#(1)) allrunning      <- mkReg(1);
  Reg#(Bit#(1)) anyrunning      <- mkReg(1);
  Reg#(Bit#(1)) allhalted       <- mkReg(0);
  Reg#(Bit#(1)) anyhalted       <- mkReg(0);
  Reg#(Bit#(1)) authenticated   <- mkReg(1); // TODO How do we want to authenticate ?
  Reg#(Bit#(1)) authbusy        <- mkReg(0);
  Reg#(Bit#(1)) hasresethaltreq <- mkReg(1);
  Reg#(Bit#(1)) confstrptrvalid <- mkReg(0);
  Reg#(Bit#(4)) version         <- mkReg(3);

  Reg#(Bit#(32)) dmstatus = concatReg22( readOnlyReg(7'd0), readOnlyReg(ndmresetpending), 
                                       readOnlyReg(stickyunavail  ), 
                                       readOnlyReg(impebreak      ), 
                                       readOnlyReg(2'd0),
                                       readOnlyReg(allhavereset   ), 
                                       readOnlyReg(anyhavereset   ), 
                                       readOnlyReg(allresumeack   ), 
                                       readOnlyReg(anyresumeack   ), 
                                       readOnlyReg(allnonexistent ), 
                                       readOnlyReg(anynonexistent ), 
                                       readOnlyReg(allunavail     ), 
                                       readOnlyReg(anyunavail     ), 
                                       readOnlyReg(allrunning     ), 
                                       readOnlyReg(anyrunning     ), 
                                       readOnlyReg(allhalted      ), 
                                       readOnlyReg(anyhalted      ), 
                                       readOnlyReg(authenticated  ), 
                                       readOnlyReg(authbusy       ), 
                                       readOnlyReg(hasresethaltreq), 
                                       readOnlyReg(confstrptrvalid), 
                                       readOnlyReg(version        ));
  
  // ----------------------------------------------------------------------------------------------
  // -------------------------------------- HARTINFO ----------------------------------------------
  Reg#(HartInfo) v_hartinfo_reg [v_ncomponents];
  for (Integer i = 0; i<v_ncomponents; i = i + 1) begin
    v_hartinfo_reg[i] <- mkReg(reset_by dm_reset, HartInfo{nscratch:fromInteger(ndscratch),
                                       dataaccess: 1, zero1:?, zero2:?,
                                       datasize: fromInteger(v_nabstractdata),
                                       dataaddr: fromInteger(`DATA)});
  end
  // ----------------------------------------------------------------------------------------------
  // ------------------------------------ HART WINDOW[SEL] ----------------------------------------
  Reg#(Bit#(TLog#(TDiv#(TMax#(ncomponents,`WINDOWSZ),`WINDOWSZ))))  hawindowsel <- mkReg(0);
  // ----------------------------------------------------------------------------------------------

  // ----------------------------- Hart selection logic -------------------------------------------
  ConfigReg#(Bit#(ncomponents)) hamask      <- mkConfigReg(0, reset_by dm_reset);
  Reg#(Bit#(ncomponents)) hahaltreq   <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(ncomponents)) haresetreq  <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(ncomponents)) haresumereq <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(ncomponents)) hahavereset[2] <- mkCReg(2,0, reset_by dm_reset);

  Wire#(Bit#(ncomponents)) wr_debug_enable <- mkWire();

  Reg#(Bit#(ncomponents)) hahalted <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(ncomponents)) haresumeack <- mkReg(0, reset_by dm_reset);
 
  Wire#(Bool) wr_harthalting_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bit#(ncomponents)) wr_harthalting_id <- mkDWire(0,reset_by dm_reset);

  Wire#(Bool) wr_hartgoing_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bit#(ncomponents)) wr_hartgoing_ind <- mkDWire(0, reset_by dm_reset);

  Wire#(Bool) wr_hartresuming_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bit#(ncomponents)) wr_hartresuming_ind <- mkDWire(0, reset_by dm_reset);

  Wire#(Bool) wr_exception_wren <- mkDWire(False, reset_by dm_reset);

  Vector#(TAdd#(1,TDiv#(TSub#(ncomponents,1),32)), Wire#(Bit#(32))) haltedstatus <- replicateM(mkWire(reset_by dm_reset));
  // ----------------------------------------------------------------------------------------------
  // ---------------------------------------- ABSTRACTCS -----------------------------------------
  Reg#(Bit#(5)) progbufsize = readOnlyReg(fromInteger(v_nprogbuf));
  Reg#(Bit#(1)) busy        <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) relaxedpriv <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(3)) cmderr      <- mkReg(0, reset_by dm_reset); 
  Reg#(Bit#(4)) datacount   = readOnlyReg(fromInteger(v_nabstractdata));

  Wire#(Bool) wr_cmderr_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bit#(3)) wr_cmderr_wrval <- mkDWire(reset_by dm_reset, ?);

  Reg#(Bit#(32)) abstractcs = concatReg8 ( readOnlyReg(3'd0),
                                              progbufsize,
                                              readOnlyReg(11'd0),
                                              readOnlyReg(busy),
                                              relaxedpriv,
                                              notifyWrReg(cmderr, wr_cmderr_wren, wr_cmderr_wrval),
                                              readOnlyReg(4'd0),
                                              datacount);
  /*doc:wire: */
  Wire#(Bool) wr_errbusy <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_errnotsupported <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_errexception <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_errhaltresume <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_errbus <- mkDWire(False, reset_by dm_reset);
  Wire#(Bool) wr_errother <- mkDWire(False, reset_by dm_reset);
  // ----------------------------------------------------------------------------------------------
  // ----------------------------------ABSTRACT Command -------------------------------------------
  ConfigReg#(Bit#(8))  cmdtype <- mkConfigReg(0, reset_by dm_reset);
  ConfigReg#(Bit#(24)) control <- mkConfigReg(0, reset_by dm_reset);

  Wire#(Bool)    wr_cmdtype_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bit#(8)) wr_cmdtype_wrval <- mkDWire(reset_by dm_reset,?);
  Wire#(Bool)    wr_control_wren <- mkDWire(False, reset_by dm_reset);
  Wire#(Bit#(24)) wr_control_wrval <- mkDWire(reset_by dm_reset, ?);

  Reg#(Bit#(32)) command = concatReg2( warznotifyReg(cmdtype, wr_cmdtype_wren, wr_cmdtype_wrval),
                                       warznotifyReg(control, wr_control_wren, wr_control_wrval)
                                      );
  // ----------------------------------------------------------------------------------------------
  // ----------------------------------------Abstract Auto-----------------------------------------
  Reg#(Bit#(nabstractdata)) autoexecdata <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(TSub#(12,nabstractdata))) z1 = readOnlyReg(0);
  Reg#(Bit#(nprogbuf)) autoexecprogbuf <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(TSub#(16,nprogbuf))) z2 = readOnlyReg(0);
  Reg#(Bit#(32)) abstractauto = concatReg5(z2, autoexecprogbuf, readOnlyReg(4'd0), z1, autoexecdata);
  // ----------------------------------------------------------------------------------------------
  // ---------------------------------------- System Bus Access Control/Status --------------------
  Reg#(Bit#(3)) sbversion = readOnlyReg(1);
  Reg#(Bit#(1)) sbbusyerror <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) sbbusy <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) sbreadonaddr <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(3)) sbaccess <- mkReg(2, reset_by dm_reset);
  Reg#(Bit#(1)) sbautoincrement <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(1)) sbreadondata <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(3)) sberr <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(7)) sbasize = readOnlyReg(`paddr);
  Reg#(Bit#(1)) sbaccess128 = readOnlyReg(pack(`debug_bus_sz >= 128));
  Reg#(Bit#(1)) sbaccess64 = readOnlyReg(pack(`debug_bus_sz >= 64));
  Reg#(Bit#(1)) sbaccess32 = readOnlyReg(pack(`debug_bus_sz >= 32));
  Reg#(Bit#(1)) sbaccess16 = readOnlyReg(1);
  Reg#(Bit#(1)) sbaccess8 = readOnlyReg(1);
  Reg#(Bit#(32)) sbcs = concatReg15 (sbversion, 
                                    readOnlyReg(6'd0),
                                    w1cReg(sbbusyerror),
                                    readOnlyReg(sbbusy),
                                    sbreadonaddr,
                                    sbaccess,
                                    sbautoincrement,
                                    sbreadondata,
                                    w1cReg(sberr),
                                    sbasize,
                                    sbaccess128,
                                    sbaccess64,
                                    sbaccess32,
                                    sbaccess16,
                                    sbaccess8);
  Reg#(Bool) rg_sbread_en <- mkReg(False,reset_by dm_reset);
  Reg#(Bool) rg_sbwrite_en <- mkReg(False,reset_by dm_reset);
  // ----------------------------------------------------------------------------------------------
  // ---------------------------------- SBADDR/DATA -----------------------------------------------
  Reg#(Bit#(32)) sbaddress0 <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(32)) sbaddress1 <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(32)) sbaddress2 <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(32)) sbaddress3 <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(32)) sbdata0 <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(32)) sbdata1 <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(32)) sbdata2 <- mkReg(0, reset_by dm_reset);
  Reg#(Bit#(32)) sbdata3 <- mkReg(0, reset_by dm_reset);
  // ----------------------------------------------------------------------------------------------

  // declare array of programbuffers
  Reg#(Bit#(32)) v_progbuf_reg[v_nprogbuf];
  for (Integer i = 0; i<v_nprogbuf; i = i + 1) begin
    v_progbuf_reg[i] <- mkReg('h00000013, reset_by dm_reset);
  end
  
  // declare array of data register
  Reg#(Bit#(32)) v_data_reg[v_nabstractdata];
  for (Integer i = 0; i<v_nabstractdata; i = i + 1) begin
    v_data_reg[i] <- mkReg(0, reset_by dm_reset);
  end

  Reg#(Flags) v_flags [v_ncomponents];
  for (Integer i = 0; i<v_ncomponents; i = i + 1) begin
    v_flags[i] <- mkReg(unpack(0), reset_by dm_reset);
  end

  //-------------------- local variables ----------------------------------------------------

  Bit#(TMax#(1,TLog#(ncomponents))) lv_selected_hart = hartsello;
  Bit#(ncomponents) lv_finalhamask = (hasel==0? 0 : hamask) ;
  lv_finalhamask[lv_selected_hart] = 1;

  // ------------------- Rules ----------------------------------
`ifdef simulate
  Reg#(Bool) rg_init <- mkReg(False);
  /*doc:rule: */
  rule rl_loggers(!rg_init);
    rg_init <= True;
    `logLevel( debug, 0, $format("DEBUG: ABSTRACT:%h PROGBUF:%h WHERETO:%h DATA:%h", `ABSTRACT, `PROGBUF,`WHERETO,`DATA))
  endrule
`endif

  /*doc:rule: */
  rule rl_set_haltedstatus;
    for (Integer i = 0; i<numhaltedstatus; i = i + 1) begin
      haltedstatus[i] <= resize(hahalted >> i*32);
    end
  endrule:rl_set_haltedstatus

  /*doc:rule: This rule will assert the dmactive_reset signal when dmactive register is low*/
  rule rl_dmactive_reset(dmactive == 0);
   dmactive_reset.assertReset;
  endrule: rl_dmactive_reset

  /*doc:rule: */
  rule rl_set_clr_haltreq(wr_haltreq_wren);
    Bit#(ncomponents) lv_hahaltreq=hahaltreq;
    for (Integer i = 0; i<v_ncomponents; i = i + 1) begin
      if ( (hartsello == fromInteger(i)) || (hasel==1 && hamask[i]==1))
        lv_hahaltreq[i] = wr_hatreq_wrval;
    end
    hahaltreq<=lv_hahaltreq;
  endrule: rl_set_clr_haltreq

  /*doc:rule: */
  rule rl_set_halted;
    if (wr_harthalting_wren)
      hahalted <=  hahalted | wr_harthalting_id;
    else if (wr_hartresuming_wren)
      hahalted <= hahalted & ~(wr_hartresuming_ind);
    else 
      hahalted <= hahalted;
  endrule: rl_set_halted

  /*doc:rule: */
  rule rl_set_resumereq_resumeack;
    Bit#(ncomponents) lv_resumereq = haresumereq;
    Bit#(ncomponents) lv_resumeack = haresumeack;
    if (wr_hartresuming_wren)
      lv_resumereq = lv_resumereq & ~(wr_hartresuming_ind);
    if (wr_resumereq_wren)
      lv_resumereq = lv_resumereq | lv_finalhamask;

    if (wr_resumereq_wren)
      haresumeack <= ~lv_resumereq & ~lv_finalhamask;
    else
      haresumeack <= ~lv_resumereq;
    haresumereq <= lv_resumereq;
    `logLevel( debug, 0, $format("DEBUG: ResumeREQ:%h haresumeack:%h",haresumereq,haresumeack))
  endrule:rl_set_resumereq_resumeack

  /*doc:rule: */
  rule rl_set_hartreset;
    Bit#(ncomponents) lv_haresetreq = haresetreq;
    for (Integer i = 0; i<v_ncomponents; i = i + 1) begin
      if ( (hartsello == fromInteger(i)) || (hasel==1 && hamask[i]==1) )  begin
        lv_haresetreq[i] = hartreset;
      end
    end
    haresetreq<= lv_haresetreq;
  endrule:rl_set_hartreset

  /*doc:rule: */
  rule rl_clr_havereset(wr_ackhavereset_wren);
    Bit#(ncomponents) lv_hahaveresets=hahavereset[1];
    for (Integer i = 0; i<v_ncomponents; i = i + 1) begin
      if ( (hartsello == fromInteger(i)) || (hasel==1 && hamask[i]==1) )  begin
        lv_hahaveresets[i] = 0;
        `logLevel( debug, 0, $format("DEBUG: Acknowledging Havereset for hart:%d",i))
      end
    end
    hahavereset[1] <= lv_hahaveresets;
  endrule:rl_clr_havereset

  /*doc:rule: */
  rule rl_set_cmderr;
    if (wr_errbusy)
      cmderr <= pack(ErrBusy);
    else if (wr_errnotsupported)
      cmderr <= pack(ErrNotSupported);
    else if (wr_errexception)
      cmderr <= pack(ErrException);
    else if (wr_errhaltresume)
      cmderr <= pack(ErrHaltResume);
    else if (wr_errbus)
      cmderr <= pack(ErrBus);
    else if (wr_cmderr_wren) // when debugger writes a 1 clear the bit
      cmderr <= cmderr & ~(wr_cmderr_wrval);
  endrule: rl_set_cmderr

  /*doc:rule: */
  rule rl_set_busy;
    if (wr_cmdtype_wren) begin
      busy <= 1;
      `logLevel( debug, 0, $format("DEBUG: Setting ABCTS busy to 1"))
    end
    else if (busy == 1 && v_flags[hartsello].go==0 && wr_harthalting_id[hartsello]==1 && wr_harthalting_wren) begin
      busy <= 0;
      `logLevel( debug, 0, $format("DEBUG: Abstract cmd over."))
      AccessReg access_cntrl = unpack(control);
      if (cmdtype == 0 && access_cntrl.aarpostincrement==1) begin
        access_cntrl.regno = access_cntrl.regno + 1;
        control <= pack(access_cntrl);
      end 
    end
    // below we check for an exception. We don't need to check ids here because only the selected
    // hart for command can be writing to this. Anyone else writing to _exception can never happen.
    else if (busy ==1 && wr_exception_wren) begin
      busy <= 0;
      wr_errexception <= True;
      `logLevel( debug, 0, $format("DEBUG: Abstract cmd faced exception"))
    end
  endrule: rl_set_busy

  /*doc:rule: */
  rule rl_upd_flags;
    Bit#(1) lv_go = v_flags[hartsello].go;
    if (wr_cmdtype_wren && wr_cmdtype_wrval == 0) begin// go abstract command
      lv_go = 1;
      `logLevel( debug, 0, $format("DEBUG: Setting go flag"))
    end
    else if (wr_hartgoing_wren) begin // this wire is set when GOING is written by hart.
      lv_go = 0;
      `logLevel( debug, 0, $format("DEBUG: Resetting go flag"))
    end
    for (Integer i = 0; i<v_ncomponents; i = i + 1) begin
      if (hartsello == fromInteger(i))
        v_flags[i] <= Flags{go: lv_go, resume: haresumereq[i], reserved:?};
      else
        v_flags[i].resume <= haresumereq[i];
    end
  endrule:rl_upd_flags

  /*doc:rule: */
  rule rl_set_abstract_instructions(wr_cmdtype_wren && wr_cmdtype_wrval==0);
    AccessReg lv_control = unpack(wr_control_wrval);
    if (nAbstractInstr==2) begin
      v_abstract_reg[0] <= lv_control.transfer==1? 
                          lv_control.write==1? genLoads(lv_control): genStores(lv_control): `NOP; 
      v_abstract_reg[1] <= lv_control.postexec==1? `NOP : `EBREAK ;
    end
    else begin
      v_abstract_reg[0] <= lv_control.transfer==1 && lv_control.aarsize != 2? `ADDIW : `NOP;
      v_abstract_reg[1] <= genCSR(lv_control);
      v_abstract_reg[2] <= lv_control.transfer==1? 
                          lv_control.write==1? genLoads(lv_control): genStores(lv_control): `NOP; 
      v_abstract_reg[3] <= genCSR(lv_control);
      v_abstract_reg[4] <= lv_control.postexec==1? `NOP : `EBREAK ;
    end
  endrule:rl_set_abstract_instructions

  /*doc:rule: */
  rule rl_drive_dmstatus;
    // only hartser can be nonexistent
    Bit#(1) lv_anynonexistent = pack(hartsello >= fromInteger(v_ncomponents));
    Bit#(1) lv_allnonexistent = pack(hartsello >= fromInteger(v_ncomponents)) & ~(|lv_finalhamask);
    if (lv_allnonexistent == 0) begin // if atleast some are existent
      anyunavail <= |(~wr_debug_enable & lv_finalhamask);
      anyhalted <= |(wr_debug_enable & hahalted & lv_finalhamask);
      anyrunning <= |(wr_debug_enable & ~hahalted & lv_finalhamask);
      anyhavereset <= |(hahavereset[1] & lv_finalhamask); 
      anyresumeack <= |(haresumeack & lv_finalhamask);
      if(lv_anynonexistent == 0) begin // if all existent then try setting all* regs
        allunavail <= &(~wr_debug_enable | ~lv_finalhamask);
        allhalted <= &( (wr_debug_enable & hahalted) | ~lv_finalhamask);
        allrunning <= &( (wr_debug_enable & ~hahalted) | ~lv_finalhamask);
        allhavereset <= &(hahavereset[1] | ~lv_finalhamask);
        allresumeack <= &(haresumeack | ~lv_finalhamask);
      end
    end
  endrule:rl_drive_dmstatus
  // ------------------------------------------------------------

  // -------------------------------------- System Bus Access  ------------------------------------
  /*doc:rule: */
  rule rl_sba_request( (rg_sbread_en || rg_sbwrite_en) && sbbusy == 1);
    Bit#(`paddr) address = resize({sbaddress3,sbaddress2,sbaddress1,sbaddress0});
    SBErr lv_err = SbSuccess;
    // check for ailgnment
    if ( (sbaccess==1 && address[0] != 0) ||
          (sbaccess == 2 && address[1:0] != 0) ||
          (sbaccess ==3 && address[2:0] != 0) ) begin
      lv_err = SbAlignment;
    end
    // check if legal size access
    if ( (sbaccess==0 && sbaccess8 != 1) ||
         (sbaccess==1 && sbaccess16 != 1) ||
         (sbaccess==2 && sbaccess32 != 1) ||
         (sbaccess==3 && sbaccess64 != 1) ||
         (sbaccess==4 && sbaccess128 != 1) ) begin
       lv_err = SbSizeErr;
    end

    // Generate write data and write strobe
    Bit#(`debug_bus_sz) writedata=0;
    Bit#(TDiv#(`debug_bus_sz,8)) writestrb = 0;
    Bit#(TLog#(TDiv#(`debug_bus_sz,8))) shamt = truncate(address);
    case (sbaccess)
      0: begin writedata = duplicate(sbdata0[7:0]); writestrb = 'b1<<shamt; end
      1: begin writedata = duplicate(sbdata0[15:0]); writestrb = 'b11 << shamt; end
      2: begin writedata = duplicate(sbdata0); writestrb = 'b1111 << shamt ; end
    `ifdef RV64
      3: begin writedata = duplicate({sbdata1,sbdata0}); writestrb = 'b11111111 << shamt; end
    `endif
    endcase

    if (lv_err == SbSuccess) begin
      Axi4_rd_addr#(wd_id, `paddr, 0) read_request = Axi4_rd_addr{araddr: truncate(address),aruser: 0, 
                                      arlen : 0, arsize: unpack(sbaccess), arburst: 0,
                                      arid  : 0, arprot:'d3};
      Axi4_wr_addr#(wd_id, `paddr, 0) wr_addr_request = Axi4_wr_addr{awaddr: truncate(address),awuser: 0, 
                                      awlen : 0, awsize: unpack(sbaccess), awburst: 0,
                                      awid  : 0, awprot:'d3};
      Axi4_wr_data#(`debug_bus_sz, 0) wr_data_request = Axi4_wr_data{ wdata: writedata, wstrb: writestrb, wlast: True};
      if (rg_sbread_en ) begin
        master_xactor.fifo_side.i_rd_addr.enq(read_request);
        rg_sbread_en <= False;
        `logLevel( debug, 0, $format("DEBUG: SBA Read:",fshow(read_request)))
      end
      else if (rg_sbwrite_en) begin
        rg_sbwrite_en <= False;
        master_xactor.fifo_side.i_wr_addr.enq(wr_addr_request);
        master_xactor.fifo_side.i_wr_data.enq(wr_data_request);
        `logLevel( debug, 0, $format("DEBUG: SBA WriteR:",fshow(wr_addr_request)))
        `logLevel( debug, 0, $format("DEBUG: SBA WriteD:",fshow(wr_data_request)))
      end
    end
    else begin
      `logLevel( debug, 0, $format("DEBUG: SBA request detected error: ",fshow(lv_err)))
      sbbusy <= 0;
      sberr <= pack(lv_err);
    end
    
  endrule:rl_sba_request

  /*doc:rule: */
  rule rl_sba_read_response(sbbusy==1 && !rg_sbwrite_en && !rg_sbread_en);
    Bit#(`paddr) address = resize({sbaddress3,sbaddress2,sbaddress1,sbaddress0});
    let response <- pop_o(master_xactor.fifo_side.o_rd_data);
    sbbusy <= 0;
    `logLevel( debug, 0, $format("DEBUG: SBA Response: ",fshow(response)))
    if (response.rresp == axi4_resp_decerr) begin
      sberr <= pack(SbBadAddr);
    end
    else if (response.rresp == axi4_resp_slverr) begin
      sberr <= pack(SbOther);
    end
    else begin
      sberr <= pack(SbSuccess);
      Bit#(`debug_bus_sz) data = response.rdata;
      Bit#(TLog#(TDiv#(`debug_bus_sz,8))) shamt = truncate(address);
      data = data >> {shamt,3'b0};
      sbdata0 <= resize(data);
      if (`debug_bus_sz > 32)
        sbdata1 <= resize(data >> 32);
      if (`debug_bus_sz > 32)
        sbdata2 <= resize(data >> 64);
      if (`debug_bus_sz > 32)
        sbdata3 <= resize(data >> 96);
      if (sbautoincrement == 1) begin
        Bit#(4) increment = 'b1 << sbaccess;
        address = address + zeroExtend(increment);
        `logLevel( debug, 0, $format("DEBUG: New autoinrement address: %h",address))
        sbaddress0 <= resize(address);
        if (`paddr > 32)
          sbaddress1 <= resize(address >> 32);
        if (`paddr > 64)
          sbaddress2 <= resize(address >> 64);
        if (`paddr > 96)
          sbaddress3 <= resize(address >> 96);
      end
    end
  endrule: rl_sba_read_response

  /*doc:rule: */
  rule rl_sba_write_response(sbbusy == 1 && !rg_sbwrite_en && !rg_sbread_en);
    Bit#(`paddr) address = resize({sbaddress3,sbaddress2,sbaddress1,sbaddress0});
    let response <- pop_o(master_xactor.fifo_side.o_wr_resp);
    sbbusy <= 0;
    if (response.bresp == axi4_resp_decerr) begin
      sberr <= pack(SbBadAddr);
    end
    else if (response.bresp == axi4_resp_slverr) begin
      sberr <= pack(SbOther);
    end
    else begin
      sberr <= pack(SbSuccess);
      if (sbautoincrement == 1) begin
        Bit#(4) increment = 'b1 << sbaccess;
        address = address + zeroExtend(increment);
        `logLevel( debug, 0, $format("DEBUG: New autoinrement address: %h",address))
        sbaddress0 <= resize(address);
        if (`paddr > 32)
          sbaddress1 <= resize(address >> 32);
        if (`paddr > 64)
          sbaddress2 <= resize(address >> 64);
        if (`paddr > 96)
          sbaddress3 <= resize(address >> 96);
      end
    end
  endrule:rl_sba_write_response
  // ----------------------------------------------------------------------------------------------


  interface dcbus = interface DCBus
    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(12) offset = truncate(addr);
      Bit#(dw) data = 0;
      Bool succ = True;
      `logLevel( debug, 0, $format("DEBUG: DCREAD addr:%h offset:%h ncomponents:%d size:",addr,
      offset, v_ncomponents, fshow(size)))
      if (offset == `IMPEBREAK) begin // reading implicit ebreak
        data = cfg.implicitebreak==1? duplicate(`EBREAK) : duplicate(`NOP) ;
      end
      else if (offset == `WHERETO) begin // read jump to abstract
        Bit#(21) _off = fromInteger(`ABSTRACT-`WHERETO);
        data = duplicate({fn_j_imm(_off),12'h6f});
        `logLevel( debug, 0, $format("DEBUG: Reading WHERETO:DASM(0x%h)",data[31:0]))
      end
      else if (offset >= `ABSTRACT && offset < `PROGBUF && size == Sz4) begin // read abstract command registers
        Bit#(1) index = truncate((offset - `ABSTRACT)>>2);
        `logLevel( debug, 0, $format("DEBUG: Abstract offset:%h Abstract:%h index:%d",offset,
        `ABSTRACT, index))
        data = duplicate(v_abstract_reg[index]);
        `logLevel( debug, 0, $format("DEBUG: Reading abstract insn:DASM(0x%h)",v_abstract_reg[index]))
      end
      else if (offset >= `FLAGS && offset < (`FLAGS + fromInteger(v_ncomponents)) 
            && offset < 'h800) begin// TODO extend this for multicore
        Bit#(TLog#(ncomponents)) index = truncate(offset);
        data = duplicate(pack(v_flags[index]));
        `logLevel( debug, 0, $format("DEBUG: Reading Flags:%h",data))
      end
      else if (offset >= `DATA && offset <= (`DATA + fromInteger(v_nabstractdata*4))) begin
        Bit#(TLog#(nabstractdata)) index = resize(offset-fromInteger(`DATA)>>2);
        data = duplicate(v_data_reg[index]);
        if (size == Sz8)
          data[63:32] = v_data_reg[index+1];
      end
      else if (offset >= `PROGBUF && offset <= (`PROGBUF + fromInteger(v_nprogbuf*4))) begin
        Bit#(TLog#(nabstractdata)) index = resize(offset-fromInteger(`PROGBUF)>>2);
        data = duplicate(v_progbuf_reg[index]);
        if (size == Sz8)
          data[63:32] = v_progbuf_reg[index+1];
        `logLevel( debug, 0, $format("DEBUG: Reading Progbuf insn:DASM(0x%h)",v_progbuf_reg[index]))
      end
      else if (offset >= `ROMBASE && offset <= (`ROMBASE + 116) && size == Sz4) begin
        Bit#(5) index = truncate((offset - `ROMBASE)>>2);
        data = duplicate(vrom[index]);
        `logLevel( debug, 0, $format("DEBUG: Reading ROM insn:DASM(0x%h)",vrom[index]))
      end
      else
        `logLevel( debug, 0, $format("DEBUG: READING UNKNOWN REGION"))
      // Note succ has to be always true because accessing other regions shuold return a 0 without
      // failure.
      return tuple2(succ,data);
    endmethod
    
    method ActionValue#(Bool) write (Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strb, DCBusXperm wperm);
      `logLevel( debug, 1, $format("DEBUG: WrReq: Addr:%h data:%h Strb:%b Perm:",addr, data, strb, fshow(wperm)))
      Bit#(12) offset = truncate(addr);
      Bit#(ncomponents) val = 0;
      val[data] = 1;
      let size = strb2size_2(strb);
      Bool succ = True;
      if (offset == `HALTED) begin // hart is halted
        wr_harthalting_wren <= True;
        wr_harthalting_id <= val;
        `logLevel( debug, 0, $format("DEBUG: Hart-%d is halting now",data))
      end
      else if (offset == `GOING) begin // hart is going
        wr_hartgoing_wren <= True;
        wr_hartgoing_ind <= val;
        `logLevel( debug, 0, $format("DEBUG: Hart-%d is going to perform Abstract op",data))
      end
      else if (offset == `RESUMING) begin // hart is resuming
        wr_hartresuming_wren <= True;
        wr_hartresuming_ind <= val;
        `logLevel( debug, 0, $format("DEBUG: Hart-%d is resuming",data))
      end
      else if (offset == `EXCEPTION) begin // hart has reached exception
        wr_exception_wren<= True;
        `logLevel( debug, 0, $format("DEBUG: Halt generated exception"))
      end
      else if (offset >= `DATA && offset <= (`DATA + fromInteger(v_nabstractdata*4))) begin
        Bit#(TLog#(nabstractdata)) index = resize(offset-fromInteger(`DATA)>>2);
        v_data_reg[index] <= updateDataWithMask(v_data_reg[index],truncate(data),truncate(strb));
        if (size==Sz8)
          v_data_reg[index+1] <= updateDataWithMask(v_data_reg[index+1],truncateLSB(data),truncateLSB(strb));
      end
      else if (offset >= `PROGBUF && offset <= (`PROGBUF + fromInteger(v_nprogbuf*4))) begin
        Bit#(TLog#(nabstractdata)) index = resize(offset-fromInteger(`PROGBUF)>>2);
        v_progbuf_reg[index] <= updateDataWithMask(v_progbuf_reg[index],truncate(data),truncate(strb));
        if (size==Sz8)
          v_progbuf_reg[index+1] <= updateDataWithMask(v_progbuf_reg[index+1],truncateLSB(data),truncateLSB(strb));
      end
      else 
        succ = False;
      return succ;
    endmethod
  endinterface;


  interface device = interface Ifc_debug
    interface debug_master = master_xactor.axi4_side;
    interface ifc_dm_reset = dm_reset;
    interface dtm_access = interface Ifc_debug_dtm
      interface putCommand = interface Put
        method Action put (Bit#(`DMI_REQ_SZ) req)if (!isValid(dmi_response)); 
          Bit#(2)  dmi_op   = req[1:0];
          Bit#(32) dmi_data = req[33:2];
          Bit#(7) dmi_addr = req[40:34];
          // Catch Busy/Access Violations
          Bit#(32) dmi_response_data = 0;
          Bit#(2)  dmi_response_status = 0; // dmi_response_status 0=> ok , 2=> operation failed
          if (dmi_op == 2)begin // write operation
            `logLevel( debug, 0, $format("DEBUG: DMI Write@%h %h:",dmi_addr, dmi_data))
            case(dmi_addr)
              `Dmcontrol    : begin `logLevel( debug, 0, $format("DEBUG: Writing DMCONTROL")) dmcontrol <= dmi_data; end
              `Dmstatus     : dmstatus <= dmi_data;
              `Hartinfo     : v_hartinfo_reg[hartsello] <= unpack(dmi_data);
              `Hawindowsel  : hawindowsel <=  truncate(dmi_data);
              `Hawindow     : begin 
                let slice = {hasel,5'd0};
                Bit#(ncomponents) mask = resize(32'hFFFFFFFF) << slice;
                Bit#(ncomponents) data = resize(dmi_data) << slice;
                hamask <= (hamask & ~mask ) | (data & mask);
              end
              `Abstractcs   : begin 
                wr_errbusy <= (cmderr == 0 && busy == 1);
                abstractcs <= dmi_data;
              end
              `Command      : begin
                wr_errbusy <= (cmderr == 0 && busy == 1);
                AccessReg lv_control = unpack(dmi_data[23:0]);
                if (cmderr == 0 && busy == 0) begin // writes only take effect if cmderr. else ignored
                  if (dmi_data[31:24] != 0) // TODO: quick access and access memory not supported
                    wr_errnotsupported <= True;
                  else if (lv_control.regno < 'h1000 || lv_control.regno > 'h101f)
                    wr_errnotsupported <= True;
                `ifdef RV32
                  else if (lv_control.aarsize != 2)
                    wr_errnotsupported <= True;
                `elsif RV64
                  else if (lv_control.aarsize != 2 && lv_control.aarsize != 3)
                    wr_errnotsupported <= True;
                `endif
                  else if (hahalted[hartsello]!=1) // access only happens when hart is halted
                    wr_errhaltresume <= True;
                  else  begin
                    command <= dmi_data;
                    `logLevel( debug, 0, $format("DEBUG: Writing to Command Register"))
                  end
                end
              end
              `Abstractauto : begin
                wr_errbusy <= (cmderr == 0 && busy == 1);
              end
              `Confstrptr0, `Confstrptr1, `Confstrptr2, 
              `Confstrptr3, `Nextdm, `Haltsum2, `Haltsum3 : begin end
              `Sbcs : if (sbbusy==0 && sbbusyerror ==0) sbcs <= dmi_data;
              `Sbaddress0: begin
                if (sbbusy==1)
                    sbbusyerror <=1;
                else if (sbasize>0) begin
                  sbaddress0 <= dmi_data;
                  if (sberr == 0 && sbbusyerror == 0 && sbreadonaddr == 1) begin
                    rg_sbread_en <= True;
                    sbbusy <= 1;
                  end
                end
              end
              // TODO: if a register is non-existent shuold we generate sbbusyerror. What about dmi_response_status
              `Sbaddress1: if (sbbusy==1) sbbusyerror <=1;  else if(sbasize>32) sbaddress1 <= dmi_data;
              `Sbaddress2: if (sbbusy==1) sbbusyerror <=1;  else if(sbasize>65)  sbaddress2 <= dmi_data;
              `Sbaddress3: if (sbbusy==1) sbbusyerror <=1;  else if(sbasize>96) sbaddress3 <= dmi_data;
              `Sbdata0: begin
                if (sbbusy==1)
                    sbbusyerror <=1;
                else if (sbcs[4:0] != 0 && sbbusy ==0 && sbbusyerror == 0) begin
                  sbdata0 <= dmi_data;
                  rg_sbwrite_en <= True;
                  sbbusy <= 1;
                end
              end
              `Sbdata1: if (sbbusy==1) sbbusyerror <= 1; else if (sbcs[4:3]!=0) sbdata1 <= dmi_data;
              `Sbdata2: if (sbbusy==1) sbbusyerror <= 1; else if (sbcs[4] == 1) sbdata2 <= dmi_data;
              `Sbdata3: if (sbbusy==1) sbbusyerror <= 1; else if (sbcs[4]==1) sbdata3 <= dmi_data;
              default: begin // either data, progbuf or unknown
                if (dmi_addr >= `Data0 && dmi_addr <= (`Data0 + fromInteger(v_nabstractdata)) 
                                      && v_nabstractdata>0) begin
                  if(busy == 0)
                    v_data_reg[dmi_addr-`Data0] <= dmi_data;
                  wr_errbusy <= (cmderr == 0 && busy == 1);
                  // the following logic is meant to trigger command again when autoexec bits are set.
                  if (autoexecdata[dmi_addr-`Data0]==1)begin
                    wr_cmdtype_wren <= True;
                    wr_control_wren <= True;
                    wr_cmdtype_wrval <= cmdtype;
                    wr_control_wrval <= control;
                  end
                end
                else if (dmi_addr >= `Progbuf0 && dmi_addr <= (`Progbuf0 + fromInteger(v_nprogbuf)) 
                                              && v_nprogbuf > 0) begin
                  v_progbuf_reg[dmi_addr-`Progbuf0] <= dmi_data;
                  wr_errbusy <= (cmderr == 0 && busy == 1);
                  // the following logic is meant to trigger command again when autoexec bits are set.
                  if (autoexecprogbuf[dmi_addr-`Progbuf0]==1)begin
                    wr_cmdtype_wren <= True;
                    wr_control_wren <= True;
                    wr_cmdtype_wrval <= cmdtype;
                    wr_control_wrval <= control;
                  end
                end
                else 
                  dmi_response_status = 2;
              end
            endcase
          end
          else if (dmi_op == 1) begin // read operation
            case(dmi_addr)
              `Dmcontrol    : dmi_response_data = dmcontrol;
              `Dmstatus     : dmi_response_data = dmstatus;
              `Hartinfo     : dmi_response_data = pack(v_hartinfo_reg[hartsello]);
              `Hawindowsel  : dmi_response_data = zeroExtend(hawindowsel);
              `Hawindow     : begin 
                let slice = {hasel,5'd0};
                dmi_response_data = resize(hamask >> slice);
              end
              `Abstractcs   : begin 
                dmi_response_data = abstractcs;
              end
              `Command      : begin
                dmi_response_data = command;
              end
              `Abstractauto : begin
                dmi_response_data = abstractauto;
              end
              `Confstrptr0, `Confstrptr1, `Confstrptr2, 
              `Confstrptr3, `Nextdm, `Haltsum2, `Haltsum3 : begin end
              `Sbcs : dmi_response_data = sbcs;
              `Haltsum0: dmi_response_data = ((hartsello >> 5)>fromInteger(numhaltedstatus))?
                                            haltedstatus[hartsello>>5]:0;
              `Haltsum1: dmi_response_data = fold( \| , readVReg(haltedstatus));
              `Sbaddress0: dmi_response_data = sbaddress0;
              `Sbaddress1: dmi_response_data = sbaddress1;
              `Sbaddress2: dmi_response_data = sbaddress2;
              `Sbaddress3: dmi_response_data = sbaddress3;
              `Sbdata0: begin
                if (sbbusy==1)
                    sbbusyerror <=1;
                else if (sbcs[4:0]!=0) begin
                  dmi_response_data = sbdata0;
                  if (sberr == 0 && sbbusyerror == 0 && sbreadondata == 1) begin
                    rg_sbread_en <= True;
                    sbbusy <= 1;
                  end
                end
              end
              `Sbdata1: if (sbbusy==1) sbbusyerror <= 1; else if (sbcs[4:3]!=0) dmi_response_data = sbdata1;
              `Sbdata2: if (sbbusy==1) sbbusyerror <= 1; else if (sbcs[4] == 1) dmi_response_data = sbdata2;
              `Sbdata3: if (sbbusy==1) sbbusyerror <= 1; else if (sbcs[4] == 1) dmi_response_data = sbdata3;
              default: begin // either data, progbuf or unknown
                if (dmi_addr >= `Data0 && dmi_addr <= (`Data0 + fromInteger(v_nabstractdata)) 
                                      && v_nabstractdata>0) begin
                  dmi_response_data = v_data_reg[dmi_addr-`Data0];
                  wr_errbusy <= (cmderr == 0 && busy == 1);
                  // the following logic is meant to trigger command again when autoexec bits are set.
                  if (autoexecdata[dmi_addr-`Data0]==1)begin
                    wr_cmdtype_wren <= True;
                    wr_control_wren <= True;
                    wr_cmdtype_wrval <= cmdtype;
                    wr_control_wrval <= control;
                  end
                end
                else if (dmi_addr >= `Progbuf0 && dmi_addr <= (`Progbuf0 + fromInteger(v_nprogbuf)) 
                                              && v_nprogbuf > 0) begin
                  dmi_response_data = v_progbuf_reg[dmi_addr-`Progbuf0];
                  wr_errbusy <= (cmderr == 0 && busy == 1);
                  // the following logic is meant to trigger command again when autoexec bits are set.
                  if (autoexecprogbuf[dmi_addr-`Progbuf0]==1)begin
                    wr_cmdtype_wren <= True;
                    wr_control_wren <= True;
                    wr_cmdtype_wrval <= cmdtype;
                    wr_control_wrval <= control;
                  end
                end
                else 
                  dmi_response_status = 2;
              end
            endcase
            `logLevel( debug, 0, $format("DEBUG: DMI Read@%h %h:",dmi_addr, dmi_response_data))
          end
          dmi_response <= tagged Valid ({dmi_response_data,dmi_response_status});
        endmethod
      endinterface;
      interface getResponse = interface Get
        method ActionValue#(Bit#(34)) get() if (isValid(dmi_response));
          dmi_response <= tagged Invalid;
          return validValue(dmi_response);
        endmethod
      endinterface;
    endinterface;
    interface hartside = interface Ifc_hart_side
      method mv_hartmask = lv_finalhamask;
      method mv_harthaltreq = hahaltreq;
      method mv_hartreset = haresetreq;
      method mv_hasel = hasel;
      method mv_hartsel = zeroExtend(hartsello);
      method Action ma_havereset(Bit#(ncomponents) resetack);
        hahavereset[0] <= hahavereset[0] | resetack;
        if (resetack != 0)
          `logLevel( debug, 0, $format("DEBUG: Resetack:%h",resetack))
      endmethod
      method Action ma_debugenable (Bit#(ncomponents) _debugenable);
        wr_debug_enable <= _debugenable;
      endmethod
    endinterface;
    method mv_ndm_reset = ndmreset;
  endinterface;

//  typedef PROGBUFBase - nAbstractInstr*4 ABSTRACT;

endmodule: mkdebug

// the following is required because control is updated by both.
(*conflict_free="debugger_rl_set_busy, device_dtm_access_putCommand_put"*)
// the following is required because sb read/write respons both update sberr and sbbusy. However,
// both can never fire in the same cycle
(*conflict_free="debugger_rl_sba_read_response,debugger_rl_sba_write_response"*)
// the following is required they both update sbbusy,sberr. However, only one of them can take
// effect on either registers in a single cycle.
(*conflict_free="debugger_rl_sba_request,device_dtm_access_putCommand_put"*)
(*conflict_free="debugger_rl_sba_read_response,device_dtm_access_putCommand_put"*)
(*conflict_free="debugger_rl_sba_write_response,device_dtm_access_putCommand_put"*)

// the following both rules/methods update the abstract data and program buffer but should never
// happen simultaneously
(*conflict_free="debugger_rl_pop_apb_req,device_dtm_access_putCommand_put"*)
module [Module] mkdebug_apb#(parameter DMConfig cfg, parameter Integer base, Clock debug_clk, Reset debug_rst)
(Ifc_debug_apb#(aw, dw, uw, nprogbuf, nabstractdata, ncomponents, wd_id))
  provisos(
    Add#(TLog#(ncomponents), __a, 10), // This indicates that hartsello can't cross 10-bits. which is fair assumption as this point
    Add#(__b, TLog#(TDiv#(TMax#(ncomponents, 32), 32)), 32) // for size of hawindowsel
    ,Add#(TMax#(1, TLog#(ncomponents)), __c, 10) // hartsello can't be more than 10bits
    ,Add#(__d, TLog#(ncomponents), 12), // there can be only 0x800-0x400 flags. Hence only so many harts supported

    Add#(h__, 32, dw),
    Add#(a__, 12, aw),
    Add#(8, b__, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(c__, 2, aw),
    Add#(dw, d__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(e__, TDiv#(dw, 8), 8),
    Mul#(32, f__, dw),
    Add#(4, g__, TDiv#(dw, 8))
  );
  let device = mkdebug(cfg, clocked_by debug_clk, reset_by debug_rst);
  Ifc_debug_apb#(aw, dw, uw, nprogbuf, nabstractdata, ncomponents, wd_id) debugger <-
      dc2apb(device, base, debug_clk, debug_rst);
  return debugger;
endmodule:mkdebug_apb

// the following is required because control is updated by both.
(*conflict_free="debugger_rl_set_busy, device_dtm_access_putCommand_put"*)
// the following is required because sb read/write respons both update sberr and sbbusy. However,
// both can never fire in the same cycle
(*conflict_free="debugger_rl_sba_read_response,debugger_rl_sba_write_response"*)
// the following is required they both update sbbusy,sberr. However, only one of them can take
// effect on either registers in a single cycle.
(*conflict_free="debugger_rl_sba_request,device_dtm_access_putCommand_put"*)
(*conflict_free="debugger_rl_sba_read_response,device_dtm_access_putCommand_put"*)
(*conflict_free="debugger_rl_sba_write_response,device_dtm_access_putCommand_put"*)

// the following both rules/methods update the abstract data and program buffer but should never
// happen simultaneously
(*conflict_free="debugger_rl_axi4l_wr_req,device_dtm_access_putCommand_put"*)
module [Module] mkdebug_axi4l#(parameter DMConfig cfg, parameter Integer base, Clock debug_clk, Reset debug_rst)
(Ifc_debug_axi4l#(aw, dw, uw, nprogbuf, nabstractdata, ncomponents, wd_id))
  provisos(
    Add#(TLog#(ncomponents), __a, 10), // This indicates that hartsello can't cross 10-bits. which is fair assumption as this point
    Add#(__b, TLog#(TDiv#(TMax#(ncomponents, 32), 32)), 32) // for size of hawindowsel
    ,Add#(TMax#(1, TLog#(ncomponents)), __c, 10) // hartsello can't be more than 10bits
    ,Add#(__d, TLog#(ncomponents), 12), // there can be only 0x800-0x400 flags. Hence only so many harts supported

    Add#(h__, 32, dw),
    Add#(a__, 12, aw),
    Add#(8, b__, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(c__, 2, aw),
    Add#(dw, d__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(e__, TDiv#(dw, 8), 8),
    Mul#(32, f__, dw),
    Add#(4, g__, TDiv#(dw, 8))
  );
  let device = mkdebug(cfg, clocked_by debug_clk, reset_by debug_rst);
  Ifc_debug_axi4l#(aw, dw, uw, nprogbuf, nabstractdata, ncomponents, wd_id) debugger <-
      dc2axi4l(device, base, debug_clk, debug_rst);
  return debugger;
endmodule:mkdebug_axi4l
endpackage: debug


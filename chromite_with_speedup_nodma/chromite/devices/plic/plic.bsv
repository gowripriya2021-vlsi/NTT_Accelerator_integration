// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
      : Babu P S
Created on: Saturday 25 April 2020 08:58:16 AM IST

*/
package plic ;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import ConfigReg    :: * ;
import DReg         :: * ;

`include "Logger.bsv"
import Semi_FIFOF   :: * ;
import apb          :: * ;
import axi4l        :: * ;
import DCBus        :: * ;
import Memory       :: * ;

typedef IWithSlave#(Ifc_apb_slave#(aw, dw, uw), Ifc_plic#(sources, targets, maxpriority))
    Ifc_plic_apb#(type aw, type dw, type uw, numeric type sources, numeric type targets,
          numeric type maxpriority);
typedef IWithSlave#(Ifc_axi4l_slave#(aw, dw, uw), Ifc_plic#(sources, targets, maxpriority))
    Ifc_plic_axi4l#(type aw, type dw, type uw, numeric type sources, numeric type targets,
          numeric type maxpriority);

interface Ifc_irq_sources;
  (*always_ready, always_enabled*)
  (*prefix=""*)
  method Action m_irq((*port="irq"*)Bool i);
endinterface:Ifc_irq_sources

interface Ifc_plic #( numeric type sources,
                      numeric type targets,
                      numeric type maxpriority
                    );
  (*always_ready*)
  interface Vector#(targets, Bool) sb_to_targets;
  (*always_ready, always_enabled, prefix=""*)
  method Action sb_frm_gateway((*port="sb_frm_gateway"*) Bit#(sources) irq);
  method Action show_PLIC_state;
  (*always_enabled, prefix=""*)
  method Bit#(sources) sb_to_gateway;
endinterface:Ifc_plic

typedef 10 Max_source_wd;
typedef 5  Max_target_wd;

module [Module] mkplic(IWithDCBus#(DCBus#(aw,dw),
                                   Ifc_plic#(sources, targets, maxpriority)) )
  provisos(
    Add#(1,sources,nsources),
    Add#(nsources, _a, 1024),             // max sources is 1024
    Max#(TLog#(nsources),1, lg_nsources), // log of sources
    Max#(TLog#(maxpriority),1,lg_priority),  // log of priority
    Max#(TLog#(targets), 1,lg_targets),  // log of targets
    Add#(_b, lg_nsources, 10),

    Add#(h__, 10, dw),
    Add#(a__, 26, aw),
    Add#(8, b__, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(c__, 2, aw),
    Add#(dw, d__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(e__, TDiv#(dw, 8), 8),
    Add#(f__, lg_priority, 32),
    Bits#(UInt#(TLog#(nsources)), lg_nsources),
    Add#(g__, 1, lg_priority)
  );

  let v_nsources = valueOf(nsources);
  let v_targets = valueOf(targets);
  let v_maxpriority = valueOf(maxpriority);

  Vector#( nsources, Reg#(Bit#(lg_priority))) vrg_source_priority  <- replicateM(mkReg(0));
  Vector#( nsources, Reg#(Bool) )             vrg_source_pending    <- replicateM(mkConfigReg(False));
  Vector#( targets, Vector#( nsources, Reg#(Bool) ))
                                              v_target_ie <- replicateM(replicateM(mkReg(False))) ;
  Vector#( targets, Reg#(Bit#(lg_priority))) v_target_threshold <- replicateM(mkReg('1));

  Vector#( nsources, ConfigReg#(Bool) )      v_reg_source_busy  <- replicateM(mkConfigReg(False));
  Vector#( nsources, Reg#(bit) )              v_reg_source_complete  <- replicateM(mkDReg(0));
  Vector#( targets, ConfigReg#(Bit#(lg_nsources))) v_target_servicing <- replicateM(mkConfigReg(0));

  function Tuple2 #(Bit #(lg_priority), Bit #(lg_nsources))
                    fn_target_max_prio_and_max_id (Bit #(Max_target_wd)  target_id);

    // we set the default prioritiy of each interrupt to 0 if the source is not pending or if the
    // target has disabled it
    Vector#( nsources, Bit#(lg_priority)) lv_prios;
    for (Integer i = 0; i< v_nsources; i = i + 1) begin
      lv_prios[i] = signExtend(pack(v_target_ie[target_id][i])) &
                    signExtend(pack(vrg_source_pending[i])) &
                    vrg_source_priority[i];
    end

    // find the max priority by folding from 0th element to N and using the max operation
    Bit #(lg_priority)  max_prio = fold(max , lv_prios);
    let                 max_id   = fromMaybe(0,findElem(max_prio, lv_prios));


    /*Bit #(lg_priority)  max_prio = 0;
    Bit #(lg_nsources)  max_id   = 0;
    // Note: source_ids begin at 1, not 0.
    for (Integer source_id = 1; source_id < v_nsources; source_id = source_id + 1)
      if (   vrg_source_pending [source_id] && (vrg_source_priority [source_id] > max_prio)
                                       && (v_target_ie [target_id][source_id])) begin
        max_id   = fromInteger (source_id);
        max_prio = vrg_source_priority[source_id];
      end*/
    return tuple2 (max_prio, pack(max_id));
  endfunction:fn_target_max_prio_and_max_id

  function Action fa_show_PLIC_state;
    action
    `ifdef plic_verbose
      $display ("----------------");
      $write ("Src IPs  :");
      for (Integer source_id = 0; source_id < v_nsources; source_id = source_id + 1)
        $write (" %0d", pack (vrg_source_pending [source_id]));
      $display ("");

      $write ("Src Prios:");
      for (Integer source_id = 0; source_id < v_nsources; source_id = source_id + 1)
         $write (" %0d", vrg_source_priority [source_id]);
      $display ("");

      $write ("Src busy :");
      for (Integer source_id = 0; source_id < v_nsources; source_id = source_id + 1)
         $write (" %0d", pack (v_reg_source_busy [source_id]));
      $display ("");

      for (Integer target_id = 0; target_id < v_targets; target_id = target_id + 1) begin
         $write ("T %0d IEs  :", target_id);
         for (Integer source_id = 0; source_id < v_nsources; source_id = source_id + 1)
            $write (" %0d", v_target_ie [target_id][source_id]);
         match { .max_prio, .max_id } = fn_target_max_prio_and_max_id (fromInteger (target_id));
         $display (" MaxPri %0d, Thresh %0d, MaxId %0d, Svcing %0d",
             max_prio, v_target_threshold [target_id], max_id, v_target_servicing [target_id]);
      end
    `endif
     endaction
  endfunction

  // ================================================================
  // Creator of each target interface

  function Bool fn_mk_target_ifc (Integer target_id);
    match { .max_prio, .max_id } = fn_target_max_prio_and_max_id (fromInteger (target_id));
    Bool eip = (max_prio > v_target_threshold[target_id]);
    return eip;
  endfunction:fn_mk_target_ifc

  interface dcbus = interface DCBus
    method ActionValue#(Tuple2#(Bool,Bit#(dw))) read(Bit#(aw) addr, AccessSize size, DCBusXperm rperm);
      Bit#(26) offset = truncate(addr);
      Bool success = False;
      Bit#(dw) rdata = 0; // return data;
      `logLevel( plic, 0, $format("PLIC: Rd offset:%h sz:",offset,fshow(size)))
      let rd_perm = PvU; // = attr.rd_perm;
      Bool perm = ((rd_perm == PvU) || (rperm >= rd_perm));
      if((offset < 'h1000) && perm) begin// source priorities
        Bit#(Max_source_wd) src_id = truncate(offset[11:2]); // source is after lower 2 bits
        Bit#(32) _t=  zeroExtend(vrg_source_priority[src_id]);
        {success, rdata} = fn_adjust_read(addr, size, _t, Sz1, Sz4, 2'b11);
        // ensure source ids within the instantiated number of sources
        if( src_id > 0 && src_id <= fromInteger(v_nsources-1) ) begin
          success = success ;
        end
      end

      else if (('h1000 <= offset && offset < 'h2000) && perm) begin // source IPs

        // since ips are stored 32-sources per 4 bytes, we multiply by 32 to get the base id first
        Bit#(Max_source_wd) src_base = truncate({addr[11:0],5'h0});

        // function to correctly detect pending interrups within the base-id block
        // TODO: wouldn't a simple zeroExtend vrg_source_pending >> src_base work?
        function Bool fn_ip_source_id (Integer source_id_offset);
          let src_id = src_base + fromInteger (source_id_offset);
          Bool ip_source_id = (  (src_id <= fromInteger (v_nsources-1)) ? vrg_source_pending [src_id]
                                                                   : False);
          return ip_source_id;
        endfunction:fn_ip_source_id

        if(src_base <= fromInteger (v_nsources-1)) begin
          Bit #(32) v_ip = pack (genWith  (fn_ip_source_id));
          {success, rdata} = fn_adjust_read(addr, size, v_ip, Sz1, Sz4, 2'b11);
        end
      end

      else if (('h2000 <= offset && offset < 'h3000) && perm) begin // source IEs.
        Bit#(Max_target_wd) target_id = truncate(offset[11:7]);
        Bit#(Max_source_wd) src_base  = truncate({offset[6:2],5'h0});

        `logLevel( plic, 0, $format("PLIC: IEs:target_id:%d src_base:%d v_nsources:%d v_targets:%d",
          target_id,src_base, v_nsources, v_targets))

        function Bool fn_ie_source_id (Integer source_id_offset);
          let source_id = fromInteger (source_id_offset) + src_base;
          return (  (source_id <= fromInteger (v_nsources - 1))? v_target_ie[target_id][source_id]
                                                             : False);
        endfunction:fn_ie_source_id

          Bit #(32) v_ie = pack (genWith  (fn_ie_source_id));
          {success, rdata} = fn_adjust_read(addr, size, v_ie, Sz1, Sz4, 2'b11);
      end

      else if (('h200000 <= offset && offset <= 'h3FFFFFF) && perm) begin // contexts
        Bit#(Max_target_wd) target_id = truncate(offset[25:12]);
        if(offset[11:0] == 0) begin // priority threshold registers per context
          if( target_id <= fromInteger(v_targets-1)) begin
            Bit#(32) _t = zeroExtend(v_target_threshold[target_id]);
            {success, rdata} = fn_adjust_read(addr, size, _t, Sz1, Sz4, 2'b11);
          end
        end
        else if(offset[11:0] == 4) begin // claim/complete register per context
          match { .max_prio, .max_id } = fn_target_max_prio_and_max_id (target_id);
          Bool eip = (max_prio > v_target_threshold [target_id]);
          if( target_id <= fromInteger(v_targets - 1)) begin
            if (v_target_servicing[target_id] == 0) begin
              success = True;
              if (max_id != 0 ) begin
                vrg_source_pending [max_id] <= False;
                v_reg_source_busy [max_id] <= True;
                  v_target_servicing [target_id] <= truncate(max_id);
                rdata = reSize(max_id);
                `logLevel( plic, 0, $format("PLIC: Claiming interrupt-src:%d for target-id:%d",
                                                                                  max_id, target_id))
              end
	          end
            // error
          end
        end
      end

      return tuple2(success, rdata);
    endmethod: read

    method ActionValue#(Bool) write (Bit#(aw) addr, Bit#(dw) data, Bit#(TDiv#(dw,8)) strb, DCBusXperm wperm);
      Bit#(26) offset = truncate(addr);
      Bool success = False;
      Bit#(32) _temp = 0;
      `logLevel( plic, 0, $format("PLIC: Wr offset:%h data:%h strb:%h",offset, data, strb))
      let wr_perm = PvU; //attr.wr_perm;
      Bool perm = ((wr_perm == PvU) || (wperm >= wr_perm));
      if((offset < 'h1000 ) && perm) begin// source priorities
        Bit#(Max_source_wd) src_id = truncate(offset[11:2]); // source is after lower 2 bits
        `logLevel( plic, 0, $format("PLIC: WrPrio src_id:%d",src_id))
        // ensure source ids within the instantiated number of sources
        if( src_id <= fromInteger(v_nsources-1) ) begin
          _temp = zeroExtend(vrg_source_priority[src_id]);
          {success, _temp} <- fn_adjust_write(addr, data, strb, _temp, Sz1, Sz4, 2'b11);
        if(success && src_id > 0) vrg_source_priority[src_id] <= truncate(_temp);
        end
      end
      // source IPs are read-only so skipping their address map

      // source IEs
      else if(( 'h2000 <= offset && offset < 'h3000) && perm) begin
        Bit#(Max_target_wd) target_id = truncate(offset[11:7]);
        Bit#(Max_source_wd) src_base  = truncate({offset[6:2],5'h0});
        `logLevel( plic, 0, $format("PLIC: WrIEs:target_id:%d src_base:%d v_nsources:%d v_targets:%d",
          target_id,src_base, v_nsources, v_targets))
          success = True;
          let _data = updateDataWithMask(0, data, strb);
          for (Bit #(Max_source_wd)  k = 0; k < 32; k = k + 1) begin
            Bit #(Max_source_wd)  source_id = src_base + k;
            if (source_id <= fromInteger (v_nsources - 1)) begin
              v_target_ie[target_id][source_id] <= unpack(reSize(_data[k]));
          end
        end
      end

      // thresholds
      else if(('h200000 <= offset && offset <= 'h3FFFFFF) && perm) begin // contexts
        Bit#(Max_target_wd) target_id = truncate(offset[25:12]);
        if(offset[11:0] == 0) begin // priority threshold registers per context
          if(target_id <= fromInteger(v_targets-1)) begin
            _temp = zeroExtend(v_target_threshold[target_id]);
            {success, _temp} <- fn_adjust_write(addr, data, strb, _temp, Sz1, Sz4, 2'b11);
            if(success) v_target_threshold[target_id] <= truncate(_temp);
          end
        end
        else if(offset[11:0] == 4) begin // claim/complete register per context
          Bit #(Max_source_wd)  source_id = zeroExtend (v_target_servicing [target_id]);
          if(target_id <= fromInteger(v_targets -1) ) begin
            if(v_reg_source_busy[source_id])begin
              v_reg_source_busy[source_id] <= False;
              v_reg_source_complete[source_id] <= 1;
              v_target_servicing[target_id] <= 0;
              success = True;
            end
          end
        end
      end
      return success;
    endmethod:write
  endinterface;
  interface device = interface Ifc_plic
    // sources
    method Action sb_frm_gateway(Bit#(sources) irq);
      for (Integer i = 0; i<valueOf(sources); i = i + 1) begin
        if (! v_reg_source_busy [i+1]) begin
          vrg_source_pending[i+1] <= unpack(irq[i]);
        end
      end
    endmethod

    method Bit#(sources) sb_to_gateway;
      return truncateLSB(pack(readVReg(v_reg_source_complete)));
    endmethod

    // targets
    interface  sb_to_targets = genWith  (fn_mk_target_ifc);
    method Action show_PLIC_state;
      fa_show_PLIC_state;
    endmethod
  endinterface;
endmodule:mkplic

module [Module] mkplic_apb#(parameter Integer base, Clock plic_clk, Reset plic_rst)
(Ifc_plic_apb#(aw, dw, uw, sources, targets, maxpriority))
  provisos(
    Add#(1,sources,nsources),
    Add#(nsources, _a, 1024),             // max sources is 1024
    Max#(TLog#(nsources),1, lg_nsources), // log of sources
    Max#(TLog#(maxpriority),1,lg_priority),  // log of priority
    Max#(TLog#(targets), 1,lg_targets),  // log of targets
    Add#(_b, lg_nsources, 10),

    Add#(h__, 10, dw),
    Add#(a__, 26, aw),
    Add#(8, b__, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(c__, 2, aw),
    Add#(dw, d__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(e__, TDiv#(dw, 8), 8),

    Add#(f__, lg_priority, 32),
    Bits#(UInt#(TLog#(nsources)), lg_nsources),
    Add#(g__, 1, lg_priority)
  );
  let device = mkplic(clocked_by plic_clk, reset_by plic_rst);
  Ifc_plic_apb#(aw, dw, uw, sources, targets, maxpriority) plic <-
      dc2apb(device, base, plic_clk, plic_rst);
  return plic;
endmodule:mkplic_apb
module [Module] mkplic_axi4l#(parameter Integer base, Clock plic_clk, Reset plic_rst)
(Ifc_plic_axi4l#(aw, dw, uw, sources, targets, maxpriority))
  provisos(
    Add#(1,sources,nsources),
    Add#(nsources, _a, 1024),             // max sources is 1024
    Max#(TLog#(nsources),1, lg_nsources), // log of sources
    Max#(TLog#(maxpriority),1,lg_priority),  // log of priority
    Max#(TLog#(targets), 1,lg_targets),  // log of targets
    Add#(_b, lg_nsources, 10),

    Add#(h__, 10, dw),
    Add#(a__, 26, aw),
    Add#(8, b__, dw),         // data atleast 8 bits
    Mul#(TDiv#(dw,8),8, dw), // dw is a proper multiple of 8 bits
    Add#(c__, 2, aw),
    Add#(dw, d__, 64),
    Add#(TExp#(TLog#(dw)),0,dw),
    Add#(e__, TDiv#(dw, 8), 8),

    Add#(f__, lg_priority, 32),
    Bits#(UInt#(TLog#(nsources)), lg_nsources),
    Add#(g__, 1, lg_priority)
  );
  let device = mkplic(clocked_by plic_clk, reset_by plic_rst);
  Ifc_plic_axi4l#(aw, dw, uw, sources, targets, maxpriority) plic <-
      dc2axi4l(device, base, plic_clk, plic_rst);
  return plic;
endmodule:mkplic_axi4l

endpackage: plic


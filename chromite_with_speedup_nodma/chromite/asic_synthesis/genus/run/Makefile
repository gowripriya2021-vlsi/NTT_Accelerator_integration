default: synth
	
.PHONY: synth
synth:
	genus -execute 'set user_tcl $(user_tcl); set pd_input_tcl $(pd_tcl)' -abort_on_error\
		-overwrite -wait 30 -no_gui -files ../scripts/syn_genus_basic.tcl | tee log

.PHONY: clean
clean:
	rm -rf rpt out fv genus.log* genus.cmd* log

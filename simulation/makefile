# SPDX-License-Identifier: MPL-2.0
#
# Copyright 2024 Beijing ESWIN Computing Technology Co., Ltd.  
#
TOP=plic_tb
ARB_TOP=plic_arb_tb

OUTBIN=./${TOP}.simv

all: $(OUTBIN)
	bsub -Is  "vlogan -full64 -kdb +v2k +libext+.v+ +cli +lint=TFIPC-L -override_timescale=1ns/10ps -sverilog  -file plic.flist ../source/tb/plic_tb.sv  ../source/tb/plic_arb_tb.sv"
	bsub -Is  "vcs -full64 -kdb -debug_access+all  -lca -o $(OUTBIN)  -override_timescale=1ps/1fs ${TOP}  +error+100 +lint=TFIPC-L -l elaborate.log"

arb_tb: $(OUTBIN)
	bsub -Is  "vlogan -full64 -kdb +v2k +libext+.v+ +cli +lint=TFIPC-L -override_timescale=1ns/10ps -sverilog -file plic_common.flist  -file plic.flist ../source/tb/plic_tb.sv  ../source/tb/plic_arb_tb.sv"
	bsub -Is  "vcs -full64 -kdb -debug_access+all  -lca -o $(OUTBIN)  -override_timescale=1ps/1fs ${ARB_TOP}  +error+100 +lint=TFIPC-L -l elaborate.log"


run:
	bsub -Is  $(OUTBIN) -ucli -do wave.tcl +fsdb+delta +fsdbfile+${TOP}.fsdb  | tee run.log  &

arb_run:
	bsub -Is  $(OUTBIN) -ucli -do arb_wave.tcl +fsdb+delta +fsdbfile+${ARB_TOP}.fsdb  | tee run.log  &


wave:
	bsub -Is  verdi -simflow -ssf  ${TOP}.fsdb  &
arb_wave:
	bsub -Is  verdi -simflow -ssf  ${ARB_TOP}.fsdb  &

verdi:
	bsub -Is  verdi -nologo -simflow -work work -top ${TOP} 

clean:
	
	@rm -rf vc_hdrs.h ucli.key *.log 
	@rm -rf dump* verdi* 
	@rm -rf 64 AN.DB csrc work.lib++
	@rm -rf ${TOP}.sim* novas* *.fsdb

.PHONY: $(OUTBIN)

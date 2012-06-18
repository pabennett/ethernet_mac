# vhdl files
FILES = source/*.vhd
VHDLEX = .vhd
 
# testbench
TESTBENCHPATH = simulation/${TESTBENCH}$(VHDLEX)
 
#GHDL CONFIG
GHDL_CMD = ghdl
GHDL_FLAGS  = --ieee=synopsys --warn-no-vital-generic
 
SIMDIR = simulation/libs
# Simulation break condition
#GHDL_SIM_OPT = --assert-level=error
GHDL_SIM_OPT = --stop-time=1ms
 
WAVEFORM_VIEWER = gtkwave
 
all: compile run view
 
new :
	echo "Setting up project ${PROJECT}"
	mkdir source simulation synthesis $(SIMDIR)
 
compile :
ifeq ($(strip $(TESTBENCH)),)
		@echo "TESTBENCH not set. Use TESTBENCH=value to set it."
		@exit 2
endif                                                                                             
 
	mkdir -p $(SIMDIR)
	$(GHDL_CMD) -i $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work $(TESTBENCHPATH) $(FILES)
	$(GHDL_CMD) -m  $(GHDL_FLAGS) --workdir=$(SIMDIR) --work=work $(TESTBENCH)
	@mv $(TESTBENCH) $(SIMDIR)/$(TESTBENCH)                                                                                
 
run :
	@$(SIMDIR)/$(TESTBENCH) $(GHDL_SIM_OPT) --vcdgz=$(SIMDIR)/$(TESTBENCH).vcdgz                                      
 
view :
	gunzip --stdout $(SIMDIR)/$(TESTBENCH).vcdgz | $(WAVEFORM_VIEWER) --vcd                                               
 
clean :
	$(GHDL_CMD) --clean --workdir=$(SIMDIR)

#!/bin/sh
set -e

verilator --cc -Wall -Mdir obj_dir -public ../rtl/tl45_core/tl45_prefetch.sv
verilator --cc -Wall -Mdir obj_dir -public ../rtl/tl45_core/tl45_comp.sv

cd obj_dir

make -f Vtl45_prefetch.mk
make -f Vtl45_comp.mk



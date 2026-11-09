#!/bin/bash
# reprog.sh - load the bitstream into the FPGA's SRAM again (= a reset of the board, for runs without S1)
cd "$(dirname "$0")/../gowin" && /tools/Gowin/Programmer/bin/programmer_cli --device GW1NR-9C --run 2 --frequency 1MHz --fsFile "$PWD/impl/pnr/r5_tang.fs" 2>&1 | grep -E 'Finished|rror' ; sleep 1

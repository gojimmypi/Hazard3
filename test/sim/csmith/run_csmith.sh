#!/bin/bash

mkdir -p tmp
mkdir -p saved

TB=../tb_verilator/tb

while true; do
	SEED=$(date +%N)
	APP=test_${SEED}
	SRC=tmp/${APP}.c
	echo "Generating ${SRC}..."
	echo '#include "tb_cxxrtl_io.h"' > ${SRC}
	echo '#define printf tb_printf' >> ${SRC}
	csmith --concise --no-argc --seed ${SEED} >> ${SRC}
	echo "Compiling ${SRC}..."
	make SRCS="../common/init.S ${SRC}" APP=${APP} bin &> tmp/${APP}_compile.log
	echo "Running ${SRC} on reference simulator..."
	if ../rvcpp/rvcpp --cycles 10000000 --bin tmp/${APP}.bin | grep checksum > tmp/${APP}_ref.log; then
		echo "Running ${SRC} on hardware simulator..."
		# Set a higher limit for cycle count as the reference sim is fixed at 1 IPC
		 ${TB} --cycles 20000000 --bin tmp/${APP}.bin | grep checksum > tmp/${APP}_hw.log
		 if ! diff tmp/${APP}_ref.log tmp/${APP}_hw.log; then
		 	echo "Mismatch! Saving ${SRC}."
		 	cp ${SRC} saved/${APP}.c
		 else
		 	echo "Compare OK."
		 fi
	else
		echo "Timed out or crashed in reference simulator, skipping..."
	fi
done

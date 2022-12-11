#!/bin/bash

make clean
make

retVal=$?
if [ $retVal -ne 0 ]; then
    echo "Error"
    exit $retVal
fi

ls tmp/wolfssl_test.bin -al

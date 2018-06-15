#!/bin/bash

set -e
set -x

OUTPUT_DIR=$1
KEY_DIR=`readlink -e $2`
ITS_FILE=`readlink -e $3`
UBOOT_DIR=`pwd`/../u-boot-artik

ITS_NAME=$(basename "$ITS_FILE")

# create initrd.gz from uInitrd
dd if=$INITRD of=$OUTPUT_DIR/initrd.gz bs=1 skip=64

cp $ITS_FILE $OUTPUT_DIR
pushd $OUTPUT_DIR
./mkimage -f $ITS_NAME $FIT_IMAGE
./mkimage -k $KEY_DIR -r -F -K u-boot.dtb $FIT_IMAGE

# Copy verified boot files to original files
cat u-boot.bin u-boot.dtb > u-boot-dtb.bin
cp params_vboot.bin params.bin
cp params_recovery_vboot.bin params_recovery.bin
cp params_sdvboot.bin params_sdboot.bin

popd

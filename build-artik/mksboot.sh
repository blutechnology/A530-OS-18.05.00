#!/bin/bash

#code signer v2.4
CODE_SIGNER="$PREBUILT_DIR/client"
CRT_PEM="$PREBUILT_DIR/client1.cert.pem"
IP_FILE="$PREBUILT_DIR/codesigner_ip"

# Sanity check
[ -e $CODE_SIGNER ] || exit 0
[ -e $CRT_PEM ] || exit 0
[ -e $IP_FILE ] || exit 0

IP_ADDR=`cat $IP_FILE`

#u-boot infomation
UBOOT_NAME=u-boot.bin
UBOOT_DTB_NAME=u-boot-dtb.bin
UBOOT_PADD_NAME=u-boot-dtb_padd.bin
UBOOT_TARGET_BIN=sboot-dtb.bin

#bl2 information
BL2_NAME=espresso3250-spl.bin
BL2_TARGET_BIN=sespresso3250-spl.bin

OUTPUT_DIR=$1

U_BOOT_SIZE_KB=1024
SIG_SIZE_B=256

U_BOOT_SIZE_B=`expr $U_BOOT_SIZE_KB \* 1024`
U_BOOT_PADD_B=`expr $U_BOOT_SIZE_B \- 256`

pushd $OUTPUT_DIR

#Add Zero Padding
#---------------------------------------------
#u-boot: Add padding(0x00) to u-boot image.
if [ -e $UBOOT_DTB_NAME ]; then
	# prefer to use u-boot-dtb.bin over u-boot.bin
	cp $UBOOT_DTB_NAME $UBOOT_PADD_NAME
else
	cp $UBOOT_NAME $UBOOT_PADD_NAME
fi
truncate -s $U_BOOT_PADD_B $UBOOT_PADD_NAME
#--------------------------------------------

#Add Signature
#------------------------------------------------------------------------------------------------------------
#u-boot: Add signature(256B) to the end of input binary.
$CODE_SIGNER -ip $IP_ADDR -crt $CRT_PEM -bin $UBOOT_PADD_NAME -out $UBOOT_TARGET_BIN

#bl2: Add signature(256B) to the end of input binary.
$CODE_SIGNER -ip $IP_ADDR -crt $CRT_PEM -bin $BL2_NAME -out $BL2_TARGET_BIN
#------------------------------------------------------------------------------------------------------------

cp $UBOOT_TARGET_BIN $UBOOT_NAME
if [ -f "$UBOOT_PADD_NAME" ]; then
	rm -rf $UBOOT_PADD_NAME
fi
if [ -f "$UBOOT_TARGET_BIN" ]; then
	rm -rf $UBOOT_TARGET_BIN
fi

cp $BL2_TARGET_BIN $BL2_NAME
if [ -f "$BL2_TARGET_BIN" ]; then
	rm -rf $BL2_TARGET_BIN
fi

popd

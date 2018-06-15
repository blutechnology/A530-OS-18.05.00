#!/bin/bash

set -e

SDBOOT_IMAGE=false
KMS_PREBUILT_DIR=
KMS_TARGET_DIR=

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-b [TARGET_BOARD] Target board ex) -b artik710|artik530|artik5|artik10"
	echo "--kms-prebuilt-dir	Signed binaries directory"
	echo "--kms-out-dir			Signed output directory"

	exit 0
}

parse_options()
{
	for opt in "$@"
	do
		case "$opt" in
			-h|--help)
				print_usage
				shift ;;
			-b)
				TARGET_BOARD="$2"
				shift ;;
			--kms-prebuilt-dir)
				KMS_PREBUILT_DIR=`readlink -e "$2"`
				shift
				shift ;;
			--kms-target-dir)
				KMS_TARGET_DIR=`readlink -e "$2"`
				shift ;;
		esac
	done
}

die() {
	if [ -n "$1" ]; then echo $1; fi
	exit 1
}

s5p6818_sdboot_gen()
{
	cp $KMS_PREBUILT_DIR/bl1-*.img $KMS_TARGET_DIR
	cp $PREBUILT_DIR/fip-loader-*.img $TARGET_DIR
	cp $PREBUILT_DIR/partmap_emmc.txt $TARGET_DIR
	cp $KMS_PREBUILT_DIR/fip-secure.img-signed $KMS_TARGET_DIR
	cp $KMS_PREBUILT_DIR/${UBOOT_IMAGE}-signed $KMS_TARGET_DIR

	if [ "$OTA" == "true" ]; then
		cp $PREBUILT_DIR/partmap_emmc_ota.txt $TARGET_DIR/partmap_emmc.txt
		cp $PREBUILT_DIR/flag.img $TARGET_DIR
	fi

	dd conv=notrunc if=$KMS_TARGET_DIR/bl1-sdboot.img of=$IMG_NAME bs=512 seek=$BL1_OFFSET
	dd conv=notrunc if=$TARGET_DIR/fip-loader-sd.img of=$IMG_NAME bs=512 seek=$BL2_OFFSET
	dd conv=notrunc if=$KMS_TARGET_DIR/fip-secure.img-signed of=$IMG_NAME bs=512 seek=$TZSW_OFFSET
	dd conv=notrunc if=$KMS_TARGET_DIR/${UBOOT_IMAGE}-signed of=$IMG_NAME bs=512 seek=$UBOOT_OFFSET
	dd conv=notrunc if=$TARGET_DIR/$PARAMS_NAME of=$IMG_NAME bs=512 seek=$ENV_OFFSET
}

s5p4418_sdboot_gen()
{
	cp $PREBUILT_DIR/bl1-*.img $TARGET_DIR
	cp $KMS_PREBUILT_DIR/loader-*.img $KMS_TARGET_DIR
	cp $PREBUILT_DIR/partmap_emmc.txt $TARGET_DIR
	cp $KMS_PREBUILT_DIR/bl_mon.img-signed $KMS_TARGET_DIR
	cp $KMS_PREBUILT_DIR/secureos.img-signed $KMS_TARGET_DIR
	cp $KMS_PREBUILT_DIR/${UBOOT_IMAGE}-signed $KMS_TARGET_DIR

	if [ "$OTA" == "true" ]; then
		cp $PREBUILT_DIR/partmap_emmc_ota.txt $TARGET_DIR/partmap_emmc.txt
		cp $PREBUILT_DIR/flag.img $TARGET_DIR
	fi

	dd conv=notrunc if=$TARGET_DIR/bl1-sdboot.img of=$IMG_NAME bs=512 seek=$BL1_OFFSET
	dd conv=notrunc if=$KMS_TARGET_DIR/loader-sd.img of=$IMG_NAME bs=512 seek=$LOADER_OFFSET
	dd conv=notrunc if=$KMS_TARGET_DIR/bl_mon.img-signed of=$IMG_NAME bs=512 seek=$BLMON_OFFSET

	if [ "$SECURE_BOOT" == "enable" ]; then
		dd conv=notrunc if=$KMS_TARGET_DIR/secureos.img-signed of=$IMG_NAME bs=512 seek=$SECOS_OFFSET
	fi

	dd conv=notrunc if=$KMS_TARGET_DIR/${UBOOT_IMAGE}-signed of=$IMG_NAME bs=512 seek=$UBOOT_OFFSET
	dd conv=notrunc if=$TARGET_DIR/$PARAMS_NAME of=$IMG_NAME bs=512 seek=$ENV_OFFSET
}

exynos_sdboot_gen()
{
	cp $PREBUILT_DIR/bl1.bin $TARGET_DIR/
	cp $TARGET_DIR/$UBOOT_SPL $TARGET_DIR/bl2.bin
	cp $PREBUILT_DIR/tzsw.bin $TARGET_DIR/

	dd conv=notrunc if=$TARGET_DIR/bl1.bin of=$IMG_NAME bs=512 seek=$BL1_OFFSET
	dd conv=notrunc if=$TARGET_DIR/bl2.bin of=$IMG_NAME bs=512 seek=$BL2_OFFSET
	dd conv=notrunc if=$TARGET_DIR/$UBOOT_IMAGE of=$IMG_NAME bs=512 seek=$UBOOT_OFFSET
	dd conv=notrunc if=$TARGET_DIR/tzsw.bin of=$IMG_NAME bs=512 seek=$TZSW_OFFSET
	dd conv=notrunc if=$TARGET_DIR/$PARAMS_NAME of=$IMG_NAME bs=512 seek=$ENV_OFFSET
}

trap 'error ${LINENO} ${?}' ERR
parse_options "$@"

SCRIPT_DIR=`dirname "$(readlink -f "$0")"`
if [ "$TARGET_BOARD" == "" ]; then
	print_usage
else
	if [ "$TARGET_DIR" == "" ]; then
		. $SCRIPT_DIR/config/$TARGET_BOARD.cfg
	fi
fi

SD_BOOT_SZ=`expr $ENV_OFFSET + 32`

if [ "$UBOOT_IMAGE" == "u-boot.bin" ]; then
	[ -e $KMS_PREBUILT_DIR/u-boot-dtb.bin-signed ] && UBOOT_IMAGE="u-boot-dtb.bin"
fi
test -e $KMS_PREBUILT_DIR/${UBOOT_IMAGE}-signed || die

case "$CHIP_NAME" in
	s5p6818)
		test -e $KMS_PREBUILT_DIR/bl1-sdboot.img || die
		test -e $PREBUILT_DIR/fip-loader-sd.img || die
		test -e $KMS_PREBUILT_DIR/fip-secure.img-signed || die
		test -e $KMS_PREBUILT_DIR/${UBOOT_IMAGE}-signed || die
		;;
	s5p4418)
		test -e $PREBUILT_DIR/bl1-sdboot.img || die
		test -e $KMS_PREBUILT_DIR/loader-sd.img || die
		test -e $KMS_PREBUILT_DIR/bl_mon.img-signed || die
		test -e $KMS_PREBUILT_DIR/secureos.img-signed || die
		test -e $KMS_PREBUILT_DIR/${UBOOT_IMAGE}-signed || die

		;;
	*)
		test -e $PREBUILT_DIR/bl1.bin || die
		test -e $TARGET_DIR/$UBOOT_SPL || die
		test -e $PREBUILT_DIR/tzsw.bin || die
		;;
esac

PARAMS_NAME="params_recovery.bin"

test -e $TARGET_DIR/$PARAMS_NAME || die

IMG_NAME=sd_boot.img

test -d ${TARGET_DIR} || mkdir -p ${TARGET_DIR}

pushd ${TARGET_DIR}

dd if=/dev/zero of=$IMG_NAME bs=512 count=$SD_BOOT_SZ

case "$CHIP_NAME" in
	s5p6818)
		s5p6818_sdboot_gen ;;
	s5p4418)
		s5p4418_sdboot_gen ;;
	*)
		exynos_sdboot_gen ;;
esac

PARAMS_NAME="params_sdboot.bin"
cp $IMG_NAME sd_boot_sdboot.img

dd conv=notrunc if=$TARGET_DIR/$PARAMS_NAME of=sd_boot_sdboot.img bs=512 seek=$ENV_OFFSET

sync

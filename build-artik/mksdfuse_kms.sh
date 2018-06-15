#!/bin/bash

set -x
set -e

SDBOOT_IMAGE=false

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-b [TARGET_BOARD]	Target board ex) -b artik710|artik530|artik5|artik10"
	echo "--kms-prebuilt-dir	Signed binaries directory"
	echo "--kms-target-dir			Signed output directory"
	echo "-m		Generate sd boot image"

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
				KMS_PREBUILT_DIR="$2"
				shift ;;
			--kms-target-dir)
				KMS_TARGET_DIR="$2"
				shift ;;
			-m)
				SDBOOT_IMAGE=true
				shift ;;
			*)
				shift ;;
		esac
	done
}

die() {
	if [ -n "$1" ]; then echo $1; fi
	exit 1
}

check_exist() {
	local filename=$1
	local i=0

	while [ ! -e $filename ]
	do
		if [ $i -ge 100 ]
		then
			echo "$filename is not exist. Please check the result of kpartx"
			exit -1
		fi

		sleep 0.1
		let i=i+1
	done
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

if $SDBOOT_IMAGE; then
	SD_BOOT=sd_boot_sdboot.img
else
	SD_BOOT=sd_boot.img
fi

test -e $TARGET_DIR/boot.img || exit 0
test -e $TARGET_DIR/$SD_BOOT || exit 0
test -e $TARGET_DIR/params.bin || exit 0
test -e $TARGET_DIR/rootfs.tar.gz || exit 0
test -e $TARGET_DIR/modules.img || exit 0

BUILD_VERSION=`cat $TARGET_DIR/artik_release | grep BUILD_VERSION | cut -d'=' -f2`
BUILD_DATE=`cat $TARGET_DIR/artik_release | grep BUILD_DATE | cut -d'=' -f2`

BOOT_SIZE_SECTOR=$((BOOT_SIZE << 11))
MODULE_SIZE_SECTOR=$((MODULE_SIZE << 11))

BOOT_START_SECTOR=$((SKIP_BOOT_SIZE << 11))
BOOT_END_SECTOR=$(expr $BOOT_START_SECTOR + $BOOT_SIZE_SECTOR - 1)

MODULE_START_OFFSET=$(expr $BOOT_SIZE + $SKIP_BOOT_SIZE)
MODULE_START_SECTOR=$(expr $BOOT_END_SECTOR + 1)
MODULE_END_SECTOR=$(expr $MODULE_START_SECTOR + $MODULE_SIZE_SECTOR - 1)

ROOTFS_START_SECTOR=$(expr $MODULE_END_SECTOR + 1)

#Partition For OTA
EXT_PART_PAD=2048
FLAG_START_SECTOR_OTA=$((SKIP_BOOT_SIZE << 11))
FLAG_SIZE_SECTOR=$(expr 128 \* 2)
FLAG_END_SECTOR_OTA=$(expr $FLAG_START_SECTOR_OTA + $FLAG_SIZE_SECTOR - 1)

BOOT_START_SECTOR_OTA=$(expr $FLAG_END_SECTOR_OTA + 1)
BOOT_END_SECTOR_OTA=$(expr $BOOT_START_SECTOR_OTA + $BOOT_SIZE_SECTOR - 1)

BOOT0_START_SECTOR_OTA=$(expr $BOOT_END_SECTOR_OTA + 1)
BOOT0_END_SECTOR_OTA=$(expr $BOOT0_START_SECTOR_OTA + $BOOT_SIZE_SECTOR - 1)

EXT_START_SECTOR_OTA=$(expr $BOOT0_END_SECTOR_OTA + 1)
MODULES_START_SECTOR_OTA=$(expr $EXT_START_SECTOR_OTA + $EXT_PART_PAD)
MODULES_END_SECTOR_OTA=$(expr $MODULES_START_SECTOR_OTA + $MODULE_SIZE_SECTOR - 1)

MODULES0_START_SECTOR_OTA=$(expr $MODULES_END_SECTOR_OTA + $EXT_PART_PAD + 1)
MODULES0_END_SECTOR_OTA=$(expr $MODULES0_START_SECTOR_OTA + $MODULE_SIZE_SECTOR - 1)

ROOTFS_START_SECTOR_OTA=$(expr $MODULES0_END_SECTOR_OTA + $EXT_PART_PAD + 1)

repartition() {
fdisk $1 << __EOF__
n
p
1
$BOOT_START_SECTOR
$BOOT_END_SECTOR

n
p
2
$MODULE_START_SECTOR
$MODULE_END_SECTOR

n
p
3
$ROOTFS_START_SECTOR

w
__EOF__
}

repartition_ota() {
fdisk $1 << __EOF__
n
p
1
$FLAG_START_SECTOR_OTA
$FLAG_END_SECTOR_OTA

n
p
2
$BOOT_START_SECTOR_OTA
$BOOT_END_SECTOR_OTA

n
p
3
$BOOT0_START_SECTOR_OTA
$BOOT0_END_SECTOR_OTA

n
e
$EXT_START_SECTOR_OTA


n
$MODULES_START_SECTOR_OTA
$MODULES_END_SECTOR_OTA

n
$MODULES0_START_SECTOR_OTA
$MODULES0_END_SECTOR_OTA

n
$ROOTFS_START_SECTOR_OTA


w
__EOF__
}

gen_image()
{
	if $SDBOOT_IMAGE; then
		IMG_NAME=${TARGET_BOARD}_kms_sdcard-${BUILD_VERSION}-${BUILD_DATE}.img
		ROOTFS_SIZE=`gzip -l $TARGET_DIR/rootfs.tar.gz | grep rootfs | awk '{ print $2 }'`
		ROOTFS_GAIN=800
	else
		IMG_NAME=${TARGET_BOARD}_kms_sdfuse-${BUILD_VERSION}-${BUILD_DATE}.img
		ROOTFS_SIZE=`stat -c%s $TARGET_DIR/rootfs.tar.gz`
		ROOTFS_GAIN=200
	fi

	ROOTFS_SZ=$((ROOTFS_SIZE >> 20))
	if [ "$OTA" == "true" ] && [ "$SDBOOT_IMAGE" == "true" ]; then
		TOTAL_SZ=`expr $BOOT_SIZE + $BOOT_SIZE + $MODULE_SIZE + $MODULE_SIZE + $ROOTFS_SZ + $ROOTFS_GAIN + 2`

		dd if=/dev/zero of=$IMG_NAME bs=1M count=$TOTAL_SZ
		dd conv=notrunc if=$TARGET_DIR/$SD_BOOT of=$IMG_NAME bs=512
		sync

		repartition_ota $IMG_NAME
	else
		TOTAL_SZ=`expr $ROOTFS_SZ + $BOOT_SIZE + $MODULE_SIZE + 2 + $ROOTFS_GAIN`

		dd if=/dev/zero of=$IMG_NAME bs=1M count=$TOTAL_SZ
		dd conv=notrunc if=$TARGET_DIR/$SD_BOOT of=$IMG_NAME bs=512
		sync

		repartition $IMG_NAME
	fi
	sync;sync;sync
}

install_output()
{
	sudo kpartx -a -v ${IMG_NAME}

	if [ "$OTA" == "true" ] && [ "$SDBOOT_IMAGE" == "true" ]; then
		LOOP_ROOTFS=`sudo kpartx -l ${IMG_NAME} | awk '{ print $1 }' | awk 'NR == 7'`

		sudo su -c "dd conv=notrunc if=$TARGET_DIR/flag.img of=$IMG_NAME \
			bs=512 seek=$FLAG_START_SECTOR_OTA count=$FLAG_SIZE_SECTOR"
		sudo su -c "dd conv=notrunc if=$TARGET_DIR/boot.img of=$IMG_NAME \
			bs=512 seek=$BOOT_START_SECTOR_OTA count=$BOOT_SIZE_SECTOR"
		sudo su -c "dd conv=notrunc if=$TARGET_DIR/modules.img of=$IMG_NAME \
			bs=512 seek=$MODULES_START_SECTOR_OTA count=$MODULE_SIZE_SECTOR"
	else
		LOOP_ROOTFS=`sudo kpartx -l ${IMG_NAME} | awk '{ print $1 }' | awk 'NR == 3'`
		sudo su -c "dd conv=notrunc if=$TARGET_DIR/boot.img of=$IMG_NAME 	\
			bs=1M seek=$SKIP_BOOT_SIZE count=$BOOT_SIZE"

		sudo su -c "dd conv=notrunc if=$TARGET_DIR/modules.img of=$IMG_NAME	\
			bs=1M seek=$MODULE_START_OFFSET count=$MODULE_SIZE"
	fi

	check_exist /dev/mapper/${LOOP_ROOTFS}

	sudo su -c "mkfs.ext4 -F -b 4096 -L rootfs /dev/mapper/${LOOP_ROOTFS}"

	test -d mnt || mkdir mnt

	sudo su -c "mount /dev/mapper/${LOOP_ROOTFS} mnt"
	sync

	if $SDBOOT_IMAGE; then
		sudo su -c "tar xf $TARGET_DIR/rootfs.tar.gz -C mnt"
		sudo su -c "sed -i 's/mmcblk0p/mmcblk1p/g' mnt/etc/fstab"
		sudo su -c "cp artik_release mnt/etc/"
		sudo su -c "touch mnt/.need_sd_resize"
	else
		case "$CHIP_NAME" in
		s5p6818)
			sudo su -c "cp $KMS_TARGET_DIR/bl1-emmcboot.img mnt"
			sudo su -c "cp $TARGET_DIR/fip-loader-emmc.img mnt"
			sudo su -c "cp $KMS_TARGET_DIR/fip-secure.img-signed mnt/fip-secure.img"
			sudo su -c "cp $KMS_TARGET_DIR/fip-nonsecure.img-signed mnt/fip-nonsecure.img"
			sudo su -c "cp $TARGET_DIR/partmap_emmc.txt mnt"
			;;
		s5p4418)
			sudo su -c "cp $TARGET_DIR/bl1-emmcboot.img mnt"
			sudo su -c "cp $KMS_TARGET_DIR/loader-emmc.img mnt"
			sudo su -c "cp $KMS_TARGET_DIR/bl_mon.img-signed mnt/bl_mon.img"
			sudo su -c "cp $KMS_TARGET_DIR/secureos.img-signed mnt/secureos.img"
			sudo su -c "cp $KMS_TARGET_DIR/bootloader.img-signed mnt/bootloader.img"
			sudo su -c "cp $TARGET_DIR/partmap_emmc.txt mnt"
			;;
		*)
			sudo su -c "cp $TARGET_DIR/bl1.bin mnt"
			sudo su -c "cp $TARGET_DIR/bl2.bin mnt"
			sudo su -c "cp $TARGET_DIR/u-boot.bin mnt"
			sudo su -c "cp $TARGET_DIR/tzsw.bin mnt"
			;;
		esac
		if [ "$OTA" == "true" ]; then
			sudo su -c "cp $TARGET_DIR/flag.img mnt"
		fi

		sudo su -c "cp $TARGET_DIR/params.bin mnt"
		sudo su -c "cp $TARGET_DIR/boot.img mnt"
		sudo su -c "cp $TARGET_DIR/modules.img mnt"
		sudo su -c "cp $TARGET_DIR/rootfs.tar.gz mnt"
		[ -e $TARGET_DIR/artik_release ] && sudo su -c "cp $TARGET_DIR/artik_release mnt"
	fi
	sync;sync
	sudo umount mnt
	sudo kpartx -d ${IMG_NAME}

	rm -rf mnt
}

pushd ${TARGET_DIR}

gen_image
install_output

popd

ls -al ${TARGET_DIR}/${IMG_NAME}

echo "Done"

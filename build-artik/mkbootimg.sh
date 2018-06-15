#!/bin/bash

set -e

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-b [TARGET_BOARD]	Target board ex) -b artik710|artik530|artik5|artik10"

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
			--vboot)
				VERIFIED_BOOT="true"
				shift ;;
		esac
	done
}

die() {
	if [ -n "$1" ]; then echo $1; fi
	exit 1
}

gen_boot_image()
{
	if [ "$BOOT_PART_TYPE" == "vfat" ]; then
		dd if=/dev/zero of=boot.img bs=1M count=$BOOT_SIZE
		sudo sh -c "mkfs.vfat -n boot boot.img"
	fi
}

install_boot_image()
{
	test -d mnt || mkdir mnt

	if [ "$VERIFIED_BOOT" == "true" ]; then
		install -m 664 $TARGET_DIR/$FIT_IMAGE mnt
		# only for ARTIK-520 which FIT does not contain the ramdisk (should be removed)
		install -m 664 $TARGET_DIR/$RAMDISK_NAME mnt
	else
		install -m 664 $TARGET_DIR/$KERNEL_IMAGE mnt
		install -m 664 $TARGET_DIR/$KERNEL_DTB mnt
		install -m 664 $TARGET_DIR/$RAMDISK_NAME mnt
	fi

	if [ "$OVERLAY" == "true" ]; then
		test -d mnt/overlays || mkdir mnt/overlays
		install -m 644 $TARGET_DIR/$KERNEL_DTBO mnt/overlays
	fi

	if [ "$BOOT_PART_TYPE" == "vfat" ]; then
		test -d boot_mnt || mkdir boot_mnt
		sudo mount -o loop boot.img boot_mnt
		sudo cp -rf mnt/* boot_mnt/
		sync; sync;
		sudo umount boot_mnt
		rm -rf boot_mnt
	else
		make_ext4fs -b 4096 -L boot -l ${BOOT_SIZE}M boot.img mnt
	fi

	rm -rf mnt
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

test -e $TARGET_DIR/$KERNEL_IMAGE || die "not found"
test -e $INITRD || die "not found"

cp $INITRD $TARGET_DIR/$RAMDISK_NAME

pushd $TARGET_DIR

gen_boot_image
install_boot_image

popd

#!/bin/bash

set -e

FULL_BUILD=false
VERIFIED_BOOT=false
SECURE_BOOT=false
VBOOT_KEYDIR=
VBOOT_ITS=
SKIP_CLEAN=
SKIP_FEDORA_BUILD=
SKIP_UBUNTU_BUILD=
BUILD_CONF=
WITH_E2E=
PREBUILT_VBOOT_DIR=
PREBUILT_REPO_OPT=
DEPLOY=false
OS_NAME=fedora
KMS_PREBUILT_DIR=false
KMS_TARGET_DIR=false

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-c/--config       Config file path to build ex) -c config/artik5.cfg"
	echo "-v/--fullver      Pass full version name like: -v A50GC0E-3AF-01030"
	echo "-d/--date		Release date: -d 20150911.112204"
	echo "-m/--microsd	Make a microsd bootable image"
	echo "-u/--url		Specify an url for downloading rootfs"
	echo "-C		fed-artik-build configuration file"
	echo "--full-build	Full build with generating fedora rootfs"
	echo "--ubuntu		Ubuntu rootfs build"
	echo "--local-rootfs	Copy fedora rootfs from local file instead of downloading"
	echo "--vboot		Generated verified boot image"
	echo "--vboot-keydir	Specify key directoy for verified boot"
	echo "--vboot-its	Specify its file for verified boot"
	echo "--sboot		Generated signed boot image"
	echo "--skip-clean	Skip fedora local repository clean"
	echo "--skip-fedora-build	Skip fedora build"
	echo "--use-prebuilt-repo	Use prebuilt repository"
	echo "--skip-ubuntu-build	Skip ubuntu build"
	echo "--with-e2e	Include E2E packages"
	echo "--prebuilt-vboot	Specify prebuilt directory path for vboot"
	echo "--kms-prebuilt-dir	Signed binaries directory"
	echo "--kms-target-dir			Previous output directory"
	echo "--deploy-all	Deploy release"
	exit 0
}

error()
{
	JOB="$0"              # job name
	LASTLINE="$1"         # line of error occurrence
	LASTERR="$2"          # error code
	echo "ERROR in ${JOB} : line ${LASTLINE} with exit code ${LASTERR}"
	exit 1
}

parse_options()
{
	for opt in "$@"
	do
		case "$opt" in
			-h|--help)
				print_usage
				shift ;;
			-c|--config)
				CONFIG_FILE="$2"
				shift ;;
			-v|--fullver)
				BUILD_VERSION="$2"
				shift ;;
			-d|--date)
				BUILD_DATE="$2"
				shift ;;
			-m|--microsd)
				MICROSD_IMAGE=-m
				shift ;;
			-u|--url)
				SERVER_URL="-s $2"
				shift ;;
			-C)
				BUILD_CONF="-C $2"
				shift ;;
			--full-build)
				FULL_BUILD=true
				shift ;;
			--local-rootfs)
				LOCAL_ROOTFS="$2"
				shift ;;
			--sboot)
				SECURE_BOOT=true
				shift ;;
			--with-e2e)
				WITH_E2E=--with-e2e
				shift ;;
			--vboot)
				VERIFIED_BOOT=true
				shift ;;
			--vboot-keydir)
				VBOOT_KEYDIR="$2"
				shift ;;
			--vboot-its)
				VBOOT_ITS="$2"
				shift ;;
			--skip-clean)
				SKIP_CLEAN=--skip-clean
				shift ;;
			--skip-fedora-build)
				SKIP_FEDORA_BUILD=--skip-build
				shift ;;
			--skip-ubuntu-build)
				SKIP_UBUNTU_BUILD=--skip-build
				shift ;;
			--use-prebuilt-repo)
				PREBUILT_REPO_OPT="--use-prebuilt-repo $2"
				shift ;;
			--prebuilt-vboot)
				PREBUILT_VBOOT_DIR=`readlink -e "$2"`
				shift ;;
			--kms-prebuilt-dir)
				KMS_PREBUILT_DIR=`readlink -e "$2"`
				shift ;;
			--kms-target-dir)
				KMS_TARGET_DIR=`readlink -e "$2"`
				shift ;;
			--deploy-all)
				DEPLOY=true
				shift ;;
			--ubuntu)
				OS_NAME=ubuntu
				shift ;;
			*)
				shift ;;
		esac
	done
}

print_not_found()
{
	echo -e "\e[1;31mERROR: cannot find ${1}\e[0m"
	echo -e "\e[1;31mBuild process has been terminated since the mandatory security binaries do not exist in your source code.\e[0m"
	echo -e "\e[1;31mPlease download those files from artik.io with SLA agreement to continue to build.\e[0m"
	echo -e "\e[1;31mOnce you download those files, please locate them to the following path."
	echo -e ""
	echo -e "\e[1;31m1. secureos.img or fip-secure.img\e[0m"
	echo -e "\e[1;31m   copy to ../boot-firmwares-${TARGET_BOARD}/\e[0m"
	echo -e "\e[1;31m2. ${TARGET_BOARD}_codesigner"
	echo -e "\e[1;31m   copy to ../boot-firmwares-${TARGET_BOARD}/\e[0m"
	echo -e "\e[1;31m3. deb files\e[0m"
	echo -e "\e[1;31m   copy to ../ubuntu-build-service/prebuilt/${ARCH}/${TARGET_BOARD}/\e[0m"
}

check_restrictive_pkg()
{
	if [ "${TARGET_BOARD: -1}" == "s" ]; then
		test ! -d $UBUNTU_MODULE_DEB_DIR && mkdir -p $UBUNTU_MODULE_DEB_DIR

		if [ -d "$SECURE_PREBUILT_DIR" ]; then
			cp -f $SECURE_PREBUILT_DIR/${TARGET_BOARD}_codesigner $PREBUILT_DIR
			cp -f $SECURE_PREBUILT_DIR/${SECURE_OS_FILE} $PREBUILT_DIR
			cp -f $SECURE_PREBUILT_DIR/debs/*.deb $UBUNTU_MODULE_DEB_DIR
		fi
		RESTRICTIVE_PKG_LIST=`cat config/${TARGET_BOARD}_secure.list`
		for l in $RESTRICTIVE_PKG_LIST
		do
			if [ ! -f $l ]; then
				if $FULL_BUILD; then
					print_not_found $l
					exit 1
				else
					if [ "${l##*.}" == "deb" ]; then
						continue
					else
						print_not_found $l
						exit 1
					fi
				fi
			fi
		done
	fi
}

package_check()
{
	command -v $1 >/dev/null 2>&1 || { echo >&2 "${1} not installed. Please install \"sudo apt-get install $2\""; exit 1; }
}

gen_artik_release()
{
	upper_model=$(echo -n ${TARGET_BOARD} | awk '{print toupper($0)}')
	if [ "$ARTIK_RELEASE_LEGACY" != "1" ]; then
		cat > $TARGET_DIR/artik_release << __EOF__
OFFICIAL_VERSION=${OFFICIAL_VERSION}
BUILD_VERSION=${BUILD_VERSION}
BUILD_DATE=${BUILD_DATE}
BUILD_UBOOT=
BUILD_KERNEL=
MODEL=${upper_model}
WIFI_FW=${WIFI_FW}
BT_FW=${BT_FW}
ZIGBEE_FW=${ZIGBEE_FW}
SE_FW=${SE_FW}
__EOF__
	else
		cat > $TARGET_DIR/artik_release << __EOF__
OFFICIAL_VERSION=${OFFICIAL_VERSION}
RELEASE_VERSION=${BUILD_VERSION}
RELEASE_DATE=${BUILD_DATE}
RELEASE_UBOOT=
RELEASE_KERNEL=
MODEL=${upper_model}
WIFI_FW=${WIFI_FW}
BT_FW=${BT_FW}
ZIGBEE_FW=${ZIGBEE_FW}
SE_FW=${SE_FW}
__EOF__
	fi
}

trap 'error ${LINENO} ${?}' ERR
parse_options "$@"

package_check curl curl
package_check kpartx kpartx
package_check make_ext4fs android-tools-fsutils
package_check arm-linux-gnueabihf-gcc gcc-arm-linux-gnueabihf

if [ "$CONFIG_FILE" != "" ]
then
	. $CONFIG_FILE
fi

check_restrictive_pkg

if [ "$BUILD_DATE" == "" ]; then
	BUILD_DATE=`date +"%Y%m%d.%H%M%S"`
fi

if [ "$BUILD_VERSION" == "" ]; then
	BUILD_VERSION=UNRELEASED
fi

export BUILD_DATE=$BUILD_DATE
export BUILD_VERSION=$BUILD_VERSION

export TARGET_DIR=$TARGET_DIR/$BUILD_VERSION/$BUILD_DATE
export VERIFIED_BOOT=$VERIFIED_BOOT

sudo ls > /dev/null 2>&1

mkdir -p $TARGET_DIR

gen_artik_release

if [ "$KMS_PREBUILT_DIR" == "false" ]; then

if [ "$PREBUILT_VBOOT_DIR" == "" ]; then
	./build_uboot.sh
	./build_kernel.sh --kernel-headers

	if $VERIFIED_BOOT ; then
		if [ "$VBOOT_ITS" == "" ]; then
			VBOOT_ITS=$PREBUILT_DIR/kernel_fit_verify.its
		fi
		if [ "$VBOOT_KEYDIR" == "" ]; then
			echo "Please specify key directory using --vboot-keydir"
			exit 0
		fi
		./mkvboot.sh $TARGET_DIR $VBOOT_KEYDIR $VBOOT_ITS
	fi
else
	find $PREBUILT_VBOOT_DIR -maxdepth 1 -type f -exec cp -t $TARGET_DIR {} +
fi

if $SECURE_BOOT ; then
	./mksboot.sh $TARGET_DIR
fi

./mksdboot.sh

./mkbootimg.sh

if $FULL_BUILD ; then
	if [ "$BASE_BOARD" != "" ]; then
		OS_TARGET_BOARD=$BASE_BOARD
	else
		OS_TARGET_BOARD=$TARGET_BOARD
	fi

	OS_OUTPUT_NAME=${OS_NAME}-arm-$OS_TARGET_BOARD-rootfs-$BUILD_VERSION-$BUILD_DATE
	if [ "$OS_NAME" == "ubuntu" ]; then
		# Build kernel debian package
		fakeroot -u ./build_kernel_dpkg.sh -o $TARGET_DIR/debs

		BUILD_ARCH=$ARCH
		if [ "$BUILD_ARCH" == "arm" ]; then
			BUILD_ARCH=armhf
		fi
		if [ "$UBUNTU_MODULE_DEB_DIR" != "" ]; then
			PREBUILT_MODULE_OPT="--prebuilt-module-dir $UBUNTU_MODULE_DEB_DIR"
		fi
		UBUNTU_IMG_DIR=../ubuntu-build-service/xenial-${BUILD_ARCH}-${OS_TARGET_BOARD}
		./build_ubuntu.sh -p ${UBUNTU_PACKAGE_FILE} \
			--ubuntu-name $OS_OUTPUT_NAME \
			$PREBUILT_REPO_OPT \
			$PREBUILT_MODULE_OPT \
			$WITH_E2E \
			--arch $BUILD_ARCH --chroot xenial-amd64-${BUILD_ARCH} \
			--dest-dir $TARGET_DIR $SKIP_UBUNTU_BUILD \
			--prebuilt-dir ../ubuntu-build-service/prebuilt/$BUILD_ARCH \
			--img-dir $UBUNTU_IMG_DIR \
			-b ${TARGET_BOARD}
	else
		if [ "$FEDORA_PREBUILT_RPM_DIR" != "" ]; then
			PREBUILD_ADD_CMD="-r $FEDORA_PREBUILT_RPM_DIR"
		fi
		./build_fedora.sh $BUILD_CONF -o $TARGET_DIR -b $OS_TARGET_BOARD \
			-p $FEDORA_PACKAGE_FILE -n $OS_OUTPUT_NAME $SKIP_CLEAN $SKIP_FEDORA_BUILD \
			-k fedora-arm-${OS_TARGET_BOARD}.ks \
			$PREBUILD_ADD_CMD
	fi

	MD5_SUM=$(md5sum $TARGET_DIR/${OS_OUTPUT_NAME}.tar.gz | awk '{print $1}')
	OS_TARBALL=${OS_OUTPUT_NAME}-${MD5_SUM}.tar.gz
	mv $TARGET_DIR/${OS_OUTPUT_NAME}.tar.gz $TARGET_DIR/$OS_TARBALL
	cp $TARGET_DIR/$OS_TARBALL $TARGET_DIR/rootfs.tar.gz
else
	if [ "$LOCAL_ROOTFS" == "" ]; then
		./release_rootfs.sh -b $TARGET_BOARD $SERVER_URL
	else
		cp $LOCAL_ROOTFS $TARGET_DIR/rootfs.tar.gz
	fi
fi

./mksdfuse.sh $MICROSD_IMAGE
if $DEPLOY; then
	mkdir $TARGET_DIR/sdboot
	./mksdfuse.sh -m
	mv $TARGET_DIR/${TARGET_BOARD}_sdcard-*.img $TARGET_DIR/sdboot
fi

./mkrootfs_image.sh $TARGET_DIR

if [ -e $PREBUILT_DIR/flash_all_by_fastboot.sh ]; then
	cp $PREBUILT_DIR/flash_all_by_fastboot.sh $TARGET_DIR
	[ -e $PREBUILT_DIR/partition.txt ] && cp $PREBUILT_DIR/partition.txt $TARGET_DIR
else
	cp flash_all_by_fastboot.sh $TARGET_DIR
fi

if [ -e $PREBUILT_DIR/usb_recovery_${TARGET_BOARD}.sh ]; then
	cp $PREBUILT_DIR/usb_recovery_${TARGET_BOARD}.sh $TARGET_DIR
fi

if [ -e $PREBUILT_DIR/usb-downloader ]; then
	cp $PREBUILT_DIR/usb-downloader $TARGET_DIR
	cp $PREBUILT_DIR/nsih-${TARGET_BOARD}.txt $TARGET_DIR
	cp $PREBUILT_DIR/usb_recovery.sh $TARGET_DIR
fi

#For ARTIK711s
if [ -e $PREBUILT_DIR/usb_to_sd_boot.sh ]; then
	cp $PREBUILT_DIR/usb_to_sd_boot.sh $TARGET_DIR
fi

cp expand_rootfs.sh $TARGET_DIR

if [ -e $PREBUILT_DIR/$TARGET_BOARD/u-boot-recovery.bin ]; then
	cp $PREBUILT_DIR/$TARGET_BOARD/u-boot-recovery.bin $TARGET_DIR
fi

if [ "$BUILD_VERSION" != "UNRELEASED" ]; then
	./release_bsp_source.sh -b $TARGET_BOARD -v $BUILD_VERSION -d $BUILD_DATE
fi

ls -al $TARGET_DIR

echo "ARTIK release information"
cat $TARGET_DIR/artik_release

else
	export TARGET_DIR=$KMS_TARGET_DIR

	test ! -d $KMS_TARGET_DIR/signed && mkdir $KMS_TARGET_DIR/signed
	./mksdboot_kms.sh --kms-prebuilt-dir $KMS_PREBUILT_DIR --kms-target-dir $KMS_TARGET_DIR/signed
	./mksdfuse_kms.sh --kms-prebuilt-dir $KMS_PREBUILT_DIR --kms-target-dir $KMS_TARGET_DIR/signed
	./mksdfuse_kms.sh -m --kms-prebuilt-dir $KMS_PREBUILT_DIR --kms-target-dir $KMS_TARGET_DIR/signed

	mv $TARGET_DIR/${TARGET_BOARD}_kms_sd*.img $KMS_TARGET_DIR/signed
fi

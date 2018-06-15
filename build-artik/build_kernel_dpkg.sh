#!/bin/bash

set -e

package_check()
{
	command -v $1 >/dev/null 2>&1 || { echo >&2 "${1} not installed. Aborting."; exit 1; }
}

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-b [TARGET_BOARD]	Target board ex) -b artik710|artik530|artik5|artik10"
	echo "-o [DEB_OUT_DIR]	Output directory to move debian package"

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
			-o)
				DEB_OUT_DIR=`readlink -m "$2"`
				shift ;;
			*)
				shift ;;
		esac
	done
}

create_package() {
	local pname="$1" pdir="$2" sdir="$3"

	mkdir -m 755 -p "$pdir/DEBIAN"
	mkdir -p "$pdir/usr/share/doc/$pname"
	cp $sdir/debian/copyright "$pdir/usr/share/doc/$pname/"
	cp $sdir/debian/changelog "$pdir/usr/share/doc/$pname/changelog.Debian"
	gzip -9 "$pdir/usr/share/doc/$pname/changelog.Debian"
	sh -c "cd '$pdir'; find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
		| xargs -r0 md5sum > DEBIAN/md5sums"

	# Fix ownership and permissions
	chown -R root:root "$pdir"
	chmod -R go-w "$pdir"

	# Create the package
	dpkg-gencontrol $forcearch -Vkernel:debarch="${debarch}" -p$pname -P"$pdir"
	dpkg --build "$pdir" ..
}

set_debarch() {
	# Attempt to find the correct Debian architecture
	case "$ARCH" in
	arm64)
		debarch=arm64 ;;
	arm*)
		debarch=armhf ;;
	esac
	forcearch="-DArchitecture=$debarch"
}

gen_meta_package() {
	set_debarch
	sed -e "s/@ARTIK@/${TARGET_BOARD}/g" \
		-e "s/@PACKAGEVERSION@/${PKG_VER}/g" \
		-e "s/@DISTRIBUTION@/xenial/g" \
		-e "s/@DATE@/${PKG_DATE}/g" \
		$SRC_ROOT/changelog.in > $DEB_DIR/changelog
	sed -e "s/@ARTIK@/${TARGET_BOARD}/g" \
		-e "s/@PACKAGEVERSION@/${PKG_VER}/g" \
		-e "s/@DISTRIBUTION@/xenial/g" \
		-e "s/@DATE@/${PKG_DATE}/g" \
		-e "s/@KERNEL_RELEASE@/${KERNEL_RELEASE}/g" \
		$SRC_ROOT/control.in > $DEB_DIR/control

	cp ${KERNEL_DIR}/COPYING $DEB_DIR/copyright
}

gen_kernel_headers_package() {
	# generate kernel header package
	kernel_headers_dir="$DEB_DIR/hdrtmp"
	rm -rf $kernel_headers_dir
	mkdir -p $kernel_headers_dir
	tar xf $TARGET_DIR/linux-${TARGET_BOARD}-kernel-headers-${KERNEL_RELEASE}.tar.gz \
		-C $kernel_headers_dir
	mkdir -p $kernel_headers_dir/DEBIAN
	cp $SRC_ROOT/control-scripts/kernel-headers/* $kernel_headers_dir/DEBIAN
	create_package linux-${TARGET_BOARD}-kernel-headers $kernel_headers_dir $DEB_ROOT
}

gen_kernel_image_package() {
	# generate kernel image package
	kernel_image_dir="$DEB_DIR/tmp"
	rm -rf $kernel_image_dir
	mkdir -p $kernel_image_dir
	tar xf $TARGET_DIR/linux-${TARGET_BOARD}-modules-${KERNEL_RELEASE}.tar.gz \
		-C $kernel_image_dir
	mkdir -p $kernel_image_dir/boot
	cp ${TARGET_DIR}/$KERNEL_IMAGE $kernel_image_dir/boot
	cp -f ${TARGET_DIR}/*.dtb $kernel_image_dir/boot
	[ -d ${TARGET_DIR}/overlays ] && cp -r ${TARGET_DIR}/overlays $kernel_image_dir/boot
	mkdir -p $kernel_image_dir/DEBIAN
	cp $SRC_ROOT/control-scripts/kernel-image/* $kernel_image_dir/DEBIAN
	create_package linux-${TARGET_BOARD}-image $kernel_image_dir $DEB_ROOT
}

gen_kernel_dbg_package() {
	# generate kernel debug package
	dbg_dir="$DEB_DIR/dbgtmp"
	rm -rf $dbg_dir
	mkdir -p $dbg_dir
	tar xf $TARGET_DIR/linux-${TARGET_BOARD}-modules-${KERNEL_RELEASE}-dbg.tar.gz \
		-C $dbg_dir
	mkdir -p $dbg_dir/usr/lib/debug/boot/
	cp $TARGET_DIR/vmlinux $dbg_dir/usr/lib/debug/boot/
	create_package linux-${TARGET_BOARD}-image-dbg $dbg_dir $DEB_ROOT
}

trap 'error ${LINENO} ${?}' ERR
parse_options "$@"

SCRIPT_DIR=`dirname "$(readlink -f "$0")"`
if [ "$TARGET_BOARD" == "" ]; then
	print_usage
else
	if [ "$KERNEL_DIR" == "" ]; then
		if [[ $TARGET_BOARD != *_ubuntu ]]; then
			TARGET_BOARD=${TARGET_BOARD}_ubuntu
		fi
		. $SCRIPT_DIR/config/${TARGET_BOARD}.cfg
	fi
fi

test -d $TARGET_DIR || mkdir -p $TARGET_DIR

package_check dpkg-gencontrol
package_check dpkg

SRC_ROOT=$(pwd)/debian.kernel
DEB_ROOT=$TARGET_DIR/debian.kernel
DEB_DIR=$DEB_ROOT/debian
mkdir -p $DEB_ROOT
rm -rf $DEB_ROOT/*
mkdir -p $DEB_DIR
if [ "$BUILD_DATE" == "" ]; then
	BUILD_DATE=`date +"%Y%m%d.%H%M%S"`
fi
OFFICIAL_VER=$(echo $OFFICIAL_VERSION | cut -d'_' -f 3)
KERNEL_RELEASE=$(cat ${KERNEL_DIR}/include/config/kernel.release 2> /dev/null)
KERNEL_VER=$(echo $KERNEL_RELEASE | awk -F - '{ print $1 }')
PKG_VER=${KERNEL_VER}-${OFFICIAL_VER}.${BUILD_DATE}
PKG_DATE=$(date -R)

# generate changelog, control file
gen_meta_package

pushd $DEB_ROOT

gen_kernel_headers_package
gen_kernel_image_package
gen_kernel_dbg_package

if [ "$DEB_OUT_DIR" != "" ]; then
	mkdir -p $DEB_OUT_DIR
	mv $TARGET_DIR/linux*.deb $DEB_OUT_DIR
fi

popd

rm -rf $DEB_ROOT

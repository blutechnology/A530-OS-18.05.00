#!/bin/bash

set -e

KERNEL_RELEASE=
BUILD_KERNEL_HEADERS=false

package_check()
{
	command -v $1 >/dev/null 2>&1 || { echo >&2 "${1} not installed. Aborting."; exit 1; }
}

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-b [TARGET_BOARD]	Target board ex) -b artik710|artik530|artik5|artik10"
	echo "--kernel-headers	Generate kernel headers tarball"

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
			--kernel-headers)
				BUILD_KERNEL_HEADERS=true
				shift ;;
		esac
	done
}

build()
{
	make distclean
	make $KERNEL_DEFCONFIG
	make $KERNEL_IMAGE -j$JOBS EXTRAVERSION="-$BUILD_VERSION"
	make $BUILD_DTB EXTRAVERSION="-$BUILD_VERSION"
	make modules EXTRAVERSION="-$BUILD_VERSION" -j$JOBS
}

build_modules()
{
	KERNEL_RELEASE=$(cat include/config/kernel.release 2> /dev/null)
	OBJCOPY=${CROSS_COMPILE}objcopy

	tmpdir=$TARGET_DIR/modules
	mkdir -p $tmpdir
	make modules_install INSTALL_MOD_PATH=$TARGET_DIR/modules

	rm -f $tmpdir/lib/modules/$KERNEL_RELEASE/build
	rm -f $tmpdir/lib/modules/$KERNEL_RELEASE/source
	rm -fr $tmpdir/lib/firmware

	dbg_dir=$TARGET_DIR/modules_debug
	mkdir -p $dbg_dir
	for module in $(find $tmpdir/lib/modules/ -name *.ko -printf '%P\n'); do
		module=lib/modules/$module
		mkdir -p $(dirname $dbg_dir/usr/lib/debug/$module)
		# only keep debug symbols in the debug file
		$OBJCOPY --only-keep-debug $tmpdir/$module $dbg_dir/usr/lib/debug/$module
		# strip original module from debug symbols
		$OBJCOPY --strip-debug $tmpdir/$module
		# then add a link to those
		$OBJCOPY --add-gnu-debuglink=$dbg_dir/usr/lib/debug/$module $tmpdir/$module
	done

	make_ext4fs -b 4096 -L modules \
		-l ${MODULE_SIZE}M ${TARGET_DIR}/modules.img \
		${TARGET_DIR}/modules/lib/modules/
}

build_kernel_header()
{
	kernel_headers_dir=$TARGET_DIR/kernel_headers
	[ -d "$kernel_headers_dir" ] || rm -rf $kernel_headers_dir
	hdrsrcfiles_list=$TARGET_DIR/hdrsrcfiles
	hdrobjfiles_list=$TARGET_DIR/hdrobjfiles
	# Build kernel header package
	find . -name Makefile\* -o -name Kconfig\* -o -name \*.pl > "$hdrsrcfiles_list"
	find arch/$ARCH/include include scripts -type f >> "$hdrsrcfiles_list"
	find arch/$ARCH -name module.lds -o -name Kbuild.platforms -o -name Platform >> "$hdrsrcfiles_list"
	find $(find arch/$ARCH -name include -o -name scripts -type d) -type f >> "$hdrsrcfiles_list"
	find arch/$ARCH/include Module.symvers include scripts -type f >> "$hdrobjfiles_list"
	destdir=$kernel_headers_dir/usr/src/linux-headers-$KERNEL_RELEASE
	mkdir -p "$destdir"
	tar -c -f - -T - < "$hdrsrcfiles_list" | (cd $destdir; tar -xf -)
	tar -c -f - -T - < "$hdrobjfiles_list" | (cd $destdir; tar -xf -)
	cp .config $destdir/.config # copy .config manually to be where it's expected to be
	mkdir -p "$kernel_headers_dir/lib/modules/$KERNEL_RELEASE/"
	ln -sf "/usr/src/linux-headers-$KERNEL_RELEASE" "$kernel_headers_dir/lib/modules/$KERNEL_RELEASE/build"
	rm -f "$hdrsrcfiles_list" "$hdrobjfiles_list"
}

install_output()
{
	tmpdir=$TARGET_DIR/modules
	dbg_dir=$TARGET_DIR/modules_debug
	kernel_headers_dir=$TARGET_DIR/kernel_headers

	cp arch/$ARCH/boot/$KERNEL_IMAGE $TARGET_DIR
	cp $DTB_PREFIX_DIR/$KERNEL_DTB $TARGET_DIR
	cp vmlinux $TARGET_DIR

	if [ "$OVERLAY" == "true" ]; then
		mkdir -p $TARGET_DIR/overlays
		cp $DTB_PREFIX_DIR/$KERNEL_DTBO $TARGET_DIR/overlays
	fi

	pushd $tmpdir
	tar zcf $TARGET_DIR/linux-${TARGET_BOARD}-modules-${KERNEL_RELEASE}.tar.gz *
	popd
	rm -fr $tmpdir

	pushd $dbg_dir
	tar zcf $TARGET_DIR/linux-${TARGET_BOARD}-modules-${KERNEL_RELEASE}-dbg.tar.gz *
	popd
	rm -fr $dbg_dir

	if $BUILD_KERNEL_HEADERS; then
		pushd $kernel_headers_dir
		tar zcf $TARGET_DIR/linux-${TARGET_BOARD}-kernel-headers-${KERNEL_RELEASE}.tar.gz *
		popd
		rm -fr $kernel_headers_dir
	fi
}

gen_version_info()
{
	if [ -e $TARGET_DIR/artik_release ]; then
		sed -i "s/_KERNEL=.*/_KERNEL=${KERNEL_RELEASE}/" $TARGET_DIR/artik_release
	fi
}

trap 'error ${LINENO} ${?}' ERR
parse_options "$@"

SCRIPT_DIR=`dirname "$(readlink -f "$0")"`
if [ "$TARGET_BOARD" == "" ]; then
	print_usage
else
	if [ "$KERNEL_DIR" == "" ]; then
		. $SCRIPT_DIR/config/$TARGET_BOARD.cfg
	fi
fi

test -d $TARGET_DIR || mkdir -p $TARGET_DIR

pushd $KERNEL_DIR

package_check ${CROSS_COMPILE}gcc
package_check make_ext4fs

build
build_modules
if $BUILD_KERNEL_HEADERS; then
	build_kernel_header
fi
install_output
gen_version_info

popd

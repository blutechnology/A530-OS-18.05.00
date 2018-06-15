#!/bin/bash

set -e

TARGET_DIR=
TARGET_BOARD=
TARGET_PACKAGE=
FEDORA_NAME=
PREBUILT_RPM_DIR=
SKIP_BUILD=false
SKIP_CLEAN=false
KICKSTART_FILE=../spin-kickstarts/fedora-arm-artik.ks
KICKSTART_DIR=../spin-kickstarts
BUILDCONFIG=

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-o		Target directory"
	echo "-b		Target board"
	echo "-p		Target package file"
	echo "-n		Output name"
	echo "-r		Prebuilt rpm directory"
	echo "-k		Kickstart file"
	echo "-K		Kickstart directory"
	echo "-C conf		Build configurations(If not specified, use default .fed-artik-build.conf"
	echo "--skip-build	Skip package build"
	echo "--skip-clean	Skip local repository clean-up"
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
			-n)
				FEDORA_NAME="$2"
				shift ;;
			-o)
				TARGET_DIR=`readlink -e "$2"`
				shift ;;
			-p)
				TARGET_PACKAGE=`readlink -e "$2"`
				shift ;;
			-r)
				PREBUILT_RPM_DIR=`readlink -e "$2"`
				shift ;;
			-k)
				KICKSTART_FILE="$2"
				shift ;;
			-K)
				KICKSTART_DIR=`readlink -e "$2"`
				shift ;;
			-C)
				BUILDCONFIG=`readlink -e "$2"`
				shift ;;
			--skip-build)
				SKIP_BUILD=true
				shift ;;
			--skip-clean)
				SKIP_CLEAN=true
				shift ;;
			*)
				shift ;;
		esac
	done
}

package_check()
{
	command -v $1 >/dev/null 2>&1 || { echo >&2 "${1} not installed. Aborting."; exit 1; }
}

build_package()
{
	local pkg=$1

	pushd ../$pkg
	echo "Build $pkg.."
	fed-artik-build $BUILD_CONF
	popd
}

package_check fed-artik-creator

parse_options "$@"

if [ "$BUILDCONFIG" != "" ]; then
	BUILD_CONF="-C $BUILDCONFIG"
else
	BUILD_CONF=""
fi

if ! $SKIP_CLEAN; then
	echo "Clean up local repository..."
	fed-artik-build $BUILD_CONF --clean-repos-and-exit
fi

if [ "$PREBUILT_RPM_DIR" != "" ]; then
	echo "Copy prebuilt rpms into prebuilt directory"
	fed-artik-creator $BUILD_CONF --copy-rpm-dir $PREBUILT_RPM_DIR
fi

if ! $SKIP_BUILD; then
	FEDORA_PACKAGES=`cat $TARGET_PACKAGE`

	for pkg in $FEDORA_PACKAGES
	do
		build_package $pkg
	done
fi

fed-artik-creator $BUILD_CONF --copy-rpm-dir $KICKSTART_DIR/prebuilt

if [ "$FEDORA_NAME" != "" ]; then
	fed-artik-creator $BUILD_CONF --copy-kickstart-dir $KICKSTART_DIR \
		--ks-file $KICKSTART_DIR/$KICKSTART_FILE -o $TARGET_DIR \
		--output-file $FEDORA_NAME
else
	fed-artik-creator $BUILD_CONF --copy-kickstart-dir $KICKSTART_DIR \
		--ks-file $KICKSTART_DIR/$KICKSTART_FILE -o $TARGET_DIR
fi

echo "A new fedora image has been created"

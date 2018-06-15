#!/bin/bash

set -e

BUILD_VERSION=latest
BUILD_DATE=`date +"%Y%m%d.%H%M%S"`

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-b [TARGET_BOARD]	Target board ex) -b artik710|artik530|artik5|artik10"
	echo "-v/--fullver      Pass full version name like: -v A50GC0E-3AF-01030"

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
			-v|--fullver)
				BUILD_VERSION="$2"
				shift ;;
			-d|--date)
				BUILD_DATE="$2"
				shift ;;
			*)
				shift ;;
		esac
	done
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
OUTPUT_DIR=$TARGET_DIR/bsp_sources
test -d $OUTPUT_DIR || mkdir -p $OUTPUT_DIR

if [ "$BUILD_VERSION" == "latest" ]; then
	TAG=HEAD
else
	TAG=submit/$TARGET_BOARD/$BUILD_VERSION/$BUILD_DATE
fi

release_source()
{
	src_dir=$1

	pushd $src_dir > /dev/null

	SRC_NAME=$(basename `pwd`)

	echo "Archiving $SRC_NAME"

	if [ "$TAG" != "HEAD" ]; then
		tag=`git tag | grep $TAG` || true
		if [ "$tag" == "" ]; then
			TAG=HEAD
		fi
	fi

	git archive --format=tar.gz --prefix=$SRC_NAME/ $TAG \
		> $OUTPUT_DIR/$SRC_NAME-$BUILD_VERSION.tar.gz

	EXPORT_SRCS=("${EXPORT_SRCS[@]}" "$SRC_NAME-$BUILD_VERSION.tar.gz")

	popd > /dev/null
}

list_source()
{
	for src in "${EXPORT_SRCS[@]}"
	do
		ls -1 $OUTPUT_DIR/$src
	done
}

release_source $UBOOT_DIR
release_source $KERNEL_DIR
release_source $SCRIPT_DIR
release_source $PREBUILT_DIR

list_source

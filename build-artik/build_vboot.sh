#!/bin/bash

set -e

print_usage() {
	cat <<EOF
	usage: ${0##*/}

	-h              Print this help message
	-v		Pass full version name like: -v A50GC0E-3AF-01030
	-o [OUTPUT_DIR]	Output directory
	-b [TARGET_BOARD]	Target board ex) -b artik5 | artik520s
	--vboot-keydir	Specify key directoy for verified boot
	--vboot-its	Specify its file for verified boot
EOF
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
			-v)
				BUILD_VER="$2"
				shift ;;
			-o)
				RESULT_DIR=`readlink -e "$2"`
				shift ;;
			-b)
				TARGET_BOARD="$2"
				shift ;;
			--vboot-keydir)
				VBOOT_KEYDIR="$2"
				shift ;;
			--vboot-its)
				VBOOT_ITS="$2"
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
	if [ "$UBOOT_DIR" == "" ]; then
		. $SCRIPT_DIR/config/$TARGET_BOARD.cfg
	fi
fi

if [ "$VBOOT_KEYDIR" == "" ]; then
	echo "Please specify key directory using --vboot-keydir"
	exit 0
fi

if [ "$RESULT_DIR" != "" ]; then
	export TARGET_DIR=$RESULT_DIR
fi

export BUILD_VER=$BUILD_VER

echo "Clean up $TARGET_DIR"
rm -f $TARGET_DIR/* || true

[ -e $TARGET_DIR/artik_release ] || cp $PREBUILT_DIR/artik_release $TARGET_DIR

./build_uboot.sh
./build_kernel.sh

if [ "$VBOOT_ITS" == "" ]; then
	VBOOT_ITS=$PREBUILT_DIR/kernel_fit_verify.its
fi

./mkvboot.sh $TARGET_DIR $VBOOT_KEYDIR $VBOOT_ITS

echo "Build output: $TARGET_DIR"
ls -1 $TARGET_DIR

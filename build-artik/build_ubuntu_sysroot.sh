#!/bin/bash

set -e

BUILDCONFIG=
SBUILD_CONF=~/.sbuildrc
PORT=
SKIP_BUILD=false
PREBUILT_REPO_DIR=

print_usage()
{
	echo "-h/--help         Show help options"
	echo "-p|--package	Target package file"
	echo "-c/--config       Config file path to build ex) -c config/artik5.cfg"
	echo "--chroot		Chroot name"
	echo "-C|--sbuild-conf	Sbuild configuration path"
	echo "-s|--server-port	Server port"
	echo "--skip-build	Skip package build"
	echo "--use-prebuilt-repo	Use prebuilt repository"
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
			-c|--config)
                                CONFIG_FILE="$2"
                                shift ;;
			--chroot)
				CHROOT="$2"
				shift ;;
			-C|--sbuild-conf)
				SBUILD_CONF=`readlink -e "$2"`
				shift ;;
			-s|--server-port)
				PORT="$2"
				shift ;;
			--skip-build)
				SKIP_BUILD=true
				shift ;;
			--use-prebuilt-repo)
				PREBUILT_REPO_DIR=`readlink -e "$2"`
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

gen_ubuntu_meta()
{
	where=$(readlink -e $1)
	origin=$2
	label=$3

	pushd $where
	apt-ftparchive sources . \
		| tee "$where"/Sources \
		| gzip -9 > "$where"/Sources.gz

	apt-ftparchive packages "$where" \
		| sed "s@$where@@" \
		| tee "$where"/Packages \
		| gzip -9 > "$where"/Packages.gz

	# sponge comes from moreutils
	apt-ftparchive \
		-o"APT::FTPArchive::Release::Origin=$origin" \
		-o"APT::FTPArchive::Release::Label=$label" \
		-o"APT::FTPArchive::Release::Codename=$where" release "$where" \
		| sponge "$where"/Release
	popd
}

move_build_output()
{
	where=$(readlink -e $1)
	set +e
	mv *.build *.changes *.dsc *.deb *.ddeb *.tar.* *.udeb $where
}

start_local_server()
{
	where=$(readlink -e $1)
	port=$2

	pushd $where
	gen_ubuntu_meta $where artik-local repo
	python3 -m http.server $port --bind 127.0.0.1&
	SERVER_PID=$!
	popd
}

stop_local_server()
{
	kill -9 $SERVER_PID
}

build_package()
{
	local pkg=$1
	local dest_dir=$2
	if [ "$JOBS" == "" ]; then
		JOBS=`getconf _NPROCESSORS_ONLN`
	fi

	if [ -d $pkg ]; then
		debian_dir=`find ./$pkg -name "debian" -type d`
		if [ -d $debian_dir ]; then
			pushd $debian_dir/../
			echo "Build $pkg.."

			SBUILD_CONFIG=$SBUILD_CONF sbuild --chroot $CHROOT \
				--host $BUILD_ARCH \
				--extra-repository="deb [trusted=yes] http://localhost:$PORT ./" \
				--anything-failed-commands="touch $dest_dir/.build_failed" \
				--dpkg-source-opts="-I.git*" \
				-j$JOBS --verbose
			popd
			move_build_output $dest_dir
			gen_ubuntu_meta $dest_dir artik-local repo
			if [ -e $dest_dir/.build_failed ]; then
				abnormal_exit
				exit -1
			fi
		fi
	fi
}

abnormal_exit()
{
	if [ "$SERVER_PID" != "" ]; then
		kill -9 $SERVER_PID
	fi
	if [ -e "${TARGET_DIR}/debs/.build_failed" ]; then
		rm -f $TARGET_DIR/debs/.build_failed
	fi
}

error()
{
	JOB="$0"              # job name
	LASTLINE="$1"         # line of error occurrence
	LASTERR="$2"          # error code
	echo "ERROR in ${JOB} : line ${LASTLINE} with exit code ${LASTERR}"
	exit 1
}

find_unused_port()
{
	read LOWERPORT UPPERPORT < /proc/sys/net/ipv4/ip_local_port_range
	while :
	do
		PORT="`shuf -i $LOWERPORT-$UPPERPORT -n 1`"
		ss -lpn | grep -q ":$PORT " || break
	done
}

restrictive_pkg_check()
{
        if [ -d "$SECURE_PREBUILT_DIR" ]; then
		test ! -d $UBUNTU_MODULE_DEB_DIR && mkdir -p $UBUNTU_MODULE_DEB_DIR
                cp -f $SECURE_PREBUILT_DIR/debs/*.deb $UBUNTU_MODULE_DEB_DIR
        fi
}

gen_artik_release()
{
        upper_model=$(echo -n ${TARGET_BOARD} | awk '{print toupper($0)}')
	cat > $TARGET_DIR/artik_sysroot_release << __EOF__
OFFICIAL_VERSION=${OFFICIAL_VERSION}
BUILD_VERSION=${BUILD_VERSION}
BUILD_DATE=${BUILD_DATE}
MODEL=${upper_model}
__EOF__
}

change_symlink_path()
{
	pushd $TARGET_DIR
	symlink_sysroot=$(sudo find rootfs/ -type l -lname '/*')

	for file in $symlink_sysroot
	do
		link=$(ls -l $file | awk '{print $11}')
		tmp=(`echo $file | tr "/" "\n"`)
		i=$((${#tmp[@]}-2))
		if [ $i -eq 0 ]; then
			link='.'$link
		elif [ $i -gt 0 ]; then
			link='..'$link
		fi
		link=$(seq -s../ $i | tr -d '[:digit:]')$link
		sudo rm -rf $file
		sudo ln -s $link $file
	done
	popd
}

trap abnormal_exit INT ERR
trap 'error ${LINENO} ${?}' ERR

package_check sbuild sponge python3

parse_options "$@"

if [ "$CONFIG_FILE" != "" ]
then
        . $CONFIG_FILE
fi

if [ "$BUILD_DATE" == "" ]; then
        BUILD_DATE=`date +"%Y%m%d.%H%M%S"`
fi

if [ "$BUILD_VERSION" == "" ]; then
        BUILD_VERSION="UNRELEASED"
fi

export BUILD_DATE=$BUILD_DATE
export BUILD_VERSION=$BUILD_VERSION

export TARGET_DIR=$TARGET_DIR/$BUILD_VERSION/$BUILD_DATE

BUILD_ARCH=$ARCH
if [ "$BUILD_ARCH" == "arm" ]; then
	BUILD_ARCH="armhf"
fi

if [ "$PORT" == "" ]; then
	find_unused_port
fi

mkdir -p $TARGET_DIR

gen_artik_release

[ -d $TARGET_DIR/debs ] || mkdir -p $TARGET_DIR/debs

if [ "$PREBUILT_REPO_DIR" != "" ]; then
	cp -rf $PREBUILT_REPO_DIR/* $TARGET_DIR/debs
fi

restrictive_pkg_check

start_local_server $TARGET_DIR/debs $PORT

UBUNTU_PACKAGES=`cat ${UBUNTU_PACKAGE_FILE}`

pushd ../

if ! $SKIP_BUILD; then
	for pkg in $UBUNTU_PACKAGES
	do
		build_package $pkg $TARGET_DIR/debs
	done
fi

popd

PREBUILT_DIR=../ubuntu-build-service/prebuilt/$BUILD_ARCH

if [ -d $PREBUILT_DIR ]; then
	echo "Copy prebuilt packages"
	cp -f $PREBUILT_DIR/*.deb $TARGET_DIR/debs
	gen_ubuntu_meta $TARGET_DIR/debs artik-local repo
fi

if [ "$UBUNTU_MODULE_DEB_DIR" != "" ]; then
        echo "Copy prebuilt packages"
        cp -f $UBUNTU_MODULE_DEB_DIR/*.deb $TARGET_DIR/debs
        gen_ubuntu_meta $TARGET_DIR/debs artik-local repo
fi

IMG_DIR=../ubuntu-build-service/xenial-${BUILD_ARCH}-${TARGET_BOARD}
UBUNTU_NAME=SYSROOT-ubuntu-arm-$TARGET_BOARD-rootfs-$BUILD_VERSION-$BUILD_DATE

if [ "$IMG_DIR" != "" ]; then
	echo "An ubuntu image generation starting..."
	pushd $IMG_DIR
	make clean
	BUILD_SYSROOT=true PORT=$PORT ./configure
	make IMAGEPREFIX=$UBUNTU_NAME
	mv $UBUNTU_NAME* $TARGET_DIR
fi

mkdir -p $TARGET_DIR/rootfs
sudo tar zxf $TARGET_DIR/${UBUNTU_NAME}.tar.gz -C $TARGET_DIR/rootfs
sudo mv $TARGET_DIR/artik_sysroot_release $TARGET_DIR/rootfs/
sync

change_symlink_path

sudo tar zcf $TARGET_DIR/${UBUNTU_NAME}.tar.gz -C $TARGET_DIR/rootfs .
sudo tar --exclude=usr/lib/python2.7 --exclude=usr/lib/python3.5 -zcf $TARGET_DIR/${UBUNTU_NAME}-IDE.tar.gz -C $TARGET_DIR/rootfs usr/include usr/lib lib

sudo rm -rf $TARGET_DIR/rootfs

stop_local_server

cat > $TARGET_DIR/install_sysroot.sh << __EOF__
#!/bin/sh

uudecode \$0
read -r -p "Install Path: " INSTALL_PATH
export INSTALL_PATH=\$(readlink -f "\$INSTALL_PATH")
mkdir -p \$INSTALL_PATH/BUILDROOT
sudo tar zxf $UBUNTU_NAME.tar.gz -C \$INSTALL_PATH/BUILDROOT
sudo rm -f $UBUNTU_NAME.tar.gz
__EOF__

if [ "$ARCH" == "arm" -o "$ARCH" == "armhf" ]; then
cat >> $TARGET_DIR/install_sysroot.sh << __EOF__
cat > \$INSTALL_PATH/sysroot_env << __EOF__
export PATH=:$PATH
export PKG_CONFIG_SYSROOT_DIR=\$INSTALL_PATH/BUILDROOT
export PKG_CONFIG_PATH=\$INSTALL_PATH/BUILDROOT/usr/lib/pkgconfig:\$INSTALL_PATH/BUILDROOT/usr/share/pkgconfig:\$INSTALL_PATH/BUILDROOT/usr/lib/arm-linux-gnueabihf/pkgconfig
export CC="arm-linux-gnueabihf-gcc --sysroot=\$INSTALL_PATH/BUILDROOT"
export LD="arm-linux-gnueabihf-ld --sysroot=\$INSTALL_PATH/BUILDROOT"
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
export TOOLCHAIN_FILE=\$INSTALL_PATH/toolchain.arm.cmake
IN__EOF__
cat > \$INSTALL_PATH/toolchain.arm.cmake << __EOF__
SET(CMAKE_SYSTEM_NAME Linux)
SET(CMAKE_SYSTEM_PROCESSOR arm)
SET(CMAKE_C_COMPILER /usr/bin/arm-linux-gnueabihf-gcc)
SET(CMAKE_CXX_COMPILER /usr/bin/arm-linux-gnueabihf-g++)
SET(CMAKE_LINKER /usr/bin/arm-linux-gnueabihf-ld)
SET(CMAKE_NM /usr/bin/arm-linux-gnueabihf-nm)
SET(CMAKE_OBJCOPY /usr/bin/arm-linux-gnueabihf-objcopy)
SET(CMAKE_OBJDUMP /usr/bin/arm-linux-gnueabihf-objdump)
SET(CMAKE_RANLIB /usr/bin/arm-linux-gnueabihf-ranlib)

SET(CMAKE_FIND_ROOT_PATH
	$ENV{PKG_CONFIG_SYSROOT_DIR}
)

SET(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
SET(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

SET(CMAKE_SYSROOT
	$ENV{PKG_CONFIG_SYSROOT_DIR}
)
IN__EOF__

echo "Sysroot in extracted on \$INSTALL_PATH/sysroot_env\""
echo "Please run \"source \$INSTALL_PATH/sysroot_env\" before compile."

exit
__EOF__
elif [ "$ARCH" == "aarch64" -o "$ARCH" == "arm64" ]; then
cat >> $TARGET_DIR/install_sysroot.sh << __EOF__
cat > \$INSTALL_PATH/sysroot_env << __EOF__
export PATH=:$PATH
export PKG_CONFIG_SYSROOT_DIR=\$INSTALL_PATH/BUILDROOT
export PKG_CONFIG_PATH=\$INSTALL_PATH/BUILDROOT/usr/lib/pkgconfig:\$INSTALL_PATH/BUILDROOT/usr/share/pkgconfig:\$INSTALL_PATH/BUILDROOT/usr/lib/aarch64-linux-gnu/pkgconfig
export CC="aarch64-linux-gnu-gcc --sysroot=\$INSTALL_PATH/BUILDROOT"
export LD="aarch64-linux-gnu-ld --sysroot=\$INSTALL_PATH/BUILDROOT"
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export TOOLCHAIN_FILE=\$INSTALL_PATH/toolchain.aarch64.cmake
IN__EOF__
cat > \$INSTALL_PATH/toolchain.aarch64.cmake << __EOF__
SET(CMAKE_SYSTEM_NAME Linux)
SET(CMAKE_SYSTEM_PROCESSOR aarch64)
SET(CMAKE_C_COMPILER /usr/bin/aarch64-linux-gnu-gcc)
SET(CMAKE_CXX_COMPILER /usr/bin/aarch64-linux-gnu-g++)
SET(CMAKE_LINKER /usr/bin/aarch64-linux-gnu-ld)
SET(CMAKE_NM /usr/bin/aarch64-linux-gnu-nm)
SET(CMAKE_OBJCOPY /usr/bin/aarch64-linux-gnu-objcopy)
SET(CMAKE_OBJDUMP /usr/bin/aarch64-linux-gnu-objdump)
SET(CMAKE_RANLIB /usr/bin/aarch64-linux-gnu-ranlib)

SET(CMAKE_FIND_ROOT_PATH
	$ENV{PKG_CONFIG_SYSROOT_DIR}
)

SET(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
SET(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

SET(CMAKE_SYSROOT
	$ENV{PKG_CONFIG_SYSROOT_DIR}
)
IN__EOF__

echo "Sysroot in extracted on \$INSTALL_PATH/sysroot_env\""
echo "Please run \"source \$INSTALL_PATH/sysroot_env\" before compile."

exit
__EOF__
fi

sed -i -e "s/IN__EOF__/__EOF__/g" $TARGET_DIR/install_sysroot.sh

uuencode $TARGET_DIR/$UBUNTU_NAME.tar.gz $UBUNTU_NAME.tar.gz >> $TARGET_DIR/install_sysroot.sh
chmod 755 $TARGET_DIR/install_sysroot.sh


echo "A new Ubuntu sysroot has been created"

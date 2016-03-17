#!/bin/bash
#
#===============================================================================
# Filename:  protobuf-build.sh
# Author:    Viktor Pogrebniak
# Copyright: (c) 2016 Viktor Pogrebniak
# License:   BSD 3-clause license
#===============================================================================
#
# Builds a protobuf library for the iPhone.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using protobuf in Xcode
# less painful.
#
# To configure the script, define:
#    IPHONE_SDKVERSION: iPhone SDK version (e.g. 8.0)
#
#===============================================================================

source `dirname $0`/paths-config.sh
source `dirname $0`/get-apple-vars.sh
source `dirname $0`/helpers.sh

CPPSTD=c++11    #c++89, c++99, c++14
STDLIB=libc++   # libstdc++
CC=clang
CXX=clang++
PARALLEL_MAKE=7   # how many threads to build

LIB_NAME=protobuf
REPO_URL=https://github.com/google/protobuf
VERSION_STRING=v3.0.0-beta-2
PROTOBUF_VERSION2=${VERSION_STRING//./_}

#BITCODE="-fembed-bitcode"  # Uncomment this line for Bitcode generation

BUILD_PATH=$COMMON_BUILD_PATH/$LIB_NAME-$VERSION_STRING
IOS_MIN_VERSION=7.0

# build parameters
source `dirname $0`/paths-config.sh
source `dirname $0`/get-apple-vars.sh
source `dirname $0`/helpers.sh

# paths
GIT_REPO_DIR=$TARBALL_DIR/$LIB_NAME-$VERSION_STRING
SRC_FOLDER=$BUILD_PATH/src
PLATFROM_FOLDER=$BUILD_PATH/platform
LOG_DIR=$BUILD_PATH/logs

#TARBALL_NAME=$TARBALL_DIR/$LIB_NAME-$VERSION_STRING.tar.bz2

CFLAGS="-O3 -pipe -fPIC -fcxx-exceptions"
CXXFLAGS="$CFLAGS -std=$CPPSTD -stdlib=$STDLIB $BITCODE"
LIBS="-lc++ -lc++abi"

ARM_DEV_CMD="xcrun --sdk iphoneos"
SIM_DEV_CMD="xcrun --sdk iphonesimulator"
OSX_DEV_CMD="xcrun --sdk macosx"

ARCH_POSTFIX=darwin$OS_RELEASE
PROTOC=${PLATFROM_FOLDER}/x86_64-mac/bin/protoc

# should be called with 2 parameters:
# download_from_git <repo url> <repo name>
function download_from_git
{
	cd $TARBALL_DIR
	if [ ! -d $2 ]; then
		git clone $1 `basename $2`
	else
		cd $2
		git pull
	fi
	cd $2
	git checkout $VERSION_STRING
	done_section "downloading"
}

function invent_missing_headers
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo 'Creating missing headers...'
    cp $XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IPHONE_SDKVERSION}.sdk/usr/include/{crt_externs,bzlib}.h $SRC_FOLDER
}

function create_paths
{
    mkdir -p $LOG_DIR
}

function cleanup
{
	echo 'Cleaning everything after the build...'
	rm -rf $BUILD_PATH/platform
	rm -rf $LOG_DIR
	done_section "cleanup"
}

function automake_run
{
	rm -rf $BUILD_PATH
	cp -r $GIT_REPO_DIR $BUILD_PATH
	create_paths
	cd $BUILD_PATH
	./autogen.sh
	cd $COMMON_BUILD_PATH
}

function build_protoc
{
	cd $BUILD_PATH
	LOG="$LOG_DIR/build-macos.log"
	[ -f Makefile ] && make distclean
	./configure --disable-shared --prefix=${BUILD_PATH}/platform/x86_64-mac "CC=${CC}" "CFLAGS=${CFLAGS} -arch x86_64" "CXX=${CXX}" "CXXFLAGS=${CXXFLAGS} -arch x86_64" "LDFLAGS=${LDFLAGS}" "LIBS=${LIBS}" > "${LOG}" 2>&1
	make >> "${LOG}" 2>&1
	if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while building protoc - Please check ${LOG}"
        exit 1
    fi
    make install
}

# example:
# build_inphone armv7|armv7s|arm64
function build_iphone
{
	local MIN_VERSION_FLAG="-miphoneos-version-min=${IOS_MIN_VERSION}"
	local ARCH_FLAGS="-arch $1 -isysroot ${IPHONEOS_SYSROOT} $MIN_VERSION_FLAG"
	cd $BUILD_PATH
	LOG="$LOG_DIR/build-$1.log"
	[ -f Makefile ] && make distclean
	HOST=$1
	if [ $1 == "arm64" ]; then
		HOST=arm
	else
		HOST=$1-apple-${ARCH_POSTFIX}
	fi
	./configure --build=x86_64-apple-${ARCH_POSTFIX} --host=$HOST --with-protoc=${PROTOC} --disable-shared --prefix=${BUILD_PATH}/platform/$1 "CC=${CC}" "CFLAGS=${CFLAGS} ${ARCH_FLAGS}" "CXX=${CXX}" "CXXFLAGS=${CXXFLAGS} ${ARCH_FLAGS}" LDFLAGS="-arch $1 $MIN_VERSION_FLAG ${LDFLAGS}" "LIBS=${LIBS}" > "${LOG}" 2>&1
	make >> "${LOG}" 2>&1
	if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while building $1 - Please check ${LOG}"
        exit 1
    fi
    make install
	done_section "building $1"
}

function build_simulator
{
	local MIN_VERSION_FLAG="-mios-simulator-version-min=${IOS_MIN_VERSION}"
	local ARCH_FLAGS="-arch x86_64 -isysroot ${IPHONESIMULATOR_SYSROOT} ${MIN_VERSION_FLAG}"
	cd $BUILD_PATH
	LOG="$LOG_DIR/build-$1.log"
	[ -f Makefile ] && make distclean
	./configure --build=x86_64-apple-${ARCH_POSTFIX} --host=x86_64-apple-${ARCH_POSTFIX} --with-protoc=${PROTOC} --disable-shared --prefix=${BUILD_PATH}/platform/x86_64 "CC=${CC}" "CFLAGS=${CFLAGS} ${ARCH_FLAGS}" "CXX=${CXX}" "CXXFLAGS=${CXXFLAGS} ${ARCH_FLAGS}" LDFLAGS="-arch x86_64 $MIN_VERSION_FLAG ${LDFLAGS}" "LIBS=${LIBS}" > "${LOG}" 2>&1
	make >> "${LOG}" 2>&1
	if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while building $1 - Please check ${LOG}"
        exit 1
    fi
    make install
	done_section "building simulator"
}

function package_libraries
{
    cd $BUILD_PATH/platform
    mkdir -p universal/lib
    local FOLDERS=()
    if [ -d x86_64 ]; then FOLDERS+=('x86_64'); fi
    if [ -d i386 ]; then FOLDERS+=('i386'); fi
    if [ -d arm64 ]; then FOLDERS+=('arm64'); fi
    if [ -d armv7 ]; then FOLDERS+=('armv7'); fi
    if [ -d armv7s ]; then FOLDERS+=('armv7s'); fi
    local ALL_LIBS=''
    for i in ${FOLDERS[@]}; do
		ALL_LIBS="$ALL_LIBS $i/lib/libprotobuf.a"
	done
    lipo $ALL_LIBS -create -output universal/lib/libprotobuf.a
    ALL_LIBS=''
    for i in ${FOLDERS[@]}; do
		ALL_LIBS="$ALL_LIBS $i/lib/libprotobuf-lite.a"
	done
    lipo $ALL_LIBS -create -output universal/lib/libprotobuf-lite.a
    done_section "packaging fat lib"
}

# copy_to_sdk universal|armv7|armv7s|arm64|sim
function copy_to_sdk
{
	cd $COMMON_BUILD_PATH
	mkdir -p bin
	mkdir -p include
	cp -r $BUILD_PATH/platform/x86_64-mac/bin/protoc bin
	cp -r $BUILD_PATH/platform/x86_64-mac/include/* include
	
	local ARCHS=('armv7' 'armv7s' 'arm64' 'i386' 'x86_64' 'universal')
	for a in ${ARCHS[@]}; do
		if [ -d $BUILD_PATH/platform/$a ]; then
			mkdir -p lib/$a
			cp -r $BUILD_PATH/platform/$a/lib/* lib/$a
			lipo -info lib/$a/libprotobuf.a
			lipo -info lib/$a/libprotobuf-lite.a
		fi
	done
	done_section "copying into sdk"
}

echo "Library:            $LIB_NAME"
echo "Version:            $VERSION_STRING"
echo "Sources dir:        $SRC_FOLDER"
echo "Build dir:          $BUILD_PATH"
echo "iPhone SDK version: $IPHONE_SDKVERSION"
echo "XCode root:         $XCODE_ROOT"
echo "C compiler:         $CC"
echo "C++ compiler:       $CXX"
if [ -z ${BITCODE} ]; then
    echo "BITCODE EMBEDDED: NO $BITCODE"
else 
    echo "BITCODE EMBEDDED: YES with: $BITCODE"
fi

download_from_git $REPO_URL $GIT_REPO_DIR
# invent_missing_headers
automake_run
build_protoc
build_iphone armv7
build_iphone armv7s
build_iphone arm64
build_simulator
package_libraries
copy_to_sdk
cleanup
echo "Completed successfully"


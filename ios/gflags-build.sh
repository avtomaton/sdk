#!/bin/bash
#
#===============================================================================
# Filename:  gflags-build.sh
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

# build parameters
SCRIPT_DIR=`dirname $0`
source $SCRIPT_DIR/paths-config.sh
source $SCRIPT_DIR/get-apple-vars.sh
source $SCRIPT_DIR/helpers.sh

export XCODE_XCCONFIG_FILE=$SCRIPT_DIR/no-code-sign.xcconfig

CPPSTD=c++11    #c++89, c++99, c++14
STDLIB=libc++   # libstdc++
CC=clang
CXX=clang++
PARALLEL_MAKE=7   # how many threads to build

LIB_NAME=gflags
REPO_URL=https://github.com/gflags/gflags.git
VERSION_STRING=v2.1.2

#BITCODE="-fembed-bitcode"  # Uncomment this line for Bitcode generation

BUILD_PATH=$COMMON_BUILD_PATH/$LIB_NAME-$VERSION_STRING
IOS_MIN_VERSION=7.0

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

# example:
# cmake_run armv7|armv7s|arm64
function cmake_run
{
	mkdir -p $BUILD_PATH
	rm -rf $BUILD_PATH/*
	create_paths
	cd $BUILD_PATH
	cmake -DCMAKE_TOOLCHAIN_FILE=$SCRIPT_DIR/ios-$1.cmake -G Xcode $GIT_REPO_DIR
	cd $COMMON_BUILD_PATH
}

function build_iphone
{
	cd $BUILD_PATH
	LOG="$LOG_DIR/build-$1.log"
	[ -f Makefile ] && make distclean
	# xcodebuild -list -project gflags.xcodeproj
	xcodebuild -target gflags -configuration Release -project gflags.xcodeproj > "${LOG}" 2>&1
	if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while building $1 - Please check ${LOG}"
        exit 1
    fi
    make install
	done_section "building $1"
}

function package_libraries
{
    cd $BUILD_PATH/platform
    mkdir -p universal/lib
    local FOLDERS=()
    if [ -d x86_64-sim ]; then FOLDERS+=('x86_64-sim'); fi
    if [ -d i386-sim ]; then FOLDERS+=('i386-sim'); fi
    if [ -d arm64-ios ]; then FOLDERS+=('arm64-ios'); fi
    if [ -d armv7-ios ]; then FOLDERS+=('armv7-ios'); fi
    if [ -d armv7s-ios ]; then FOLDERS+=('armv7s-ios'); fi
    local ALL_LIBS=''
    for i in ${FOLDERS[@]}; do
		ALL_LIBS="$ALL_LIBS $i/lib/libgflags.a"
	done
    lipo $ALL_LIBS -create -output universal/lib/libgflags.a
    done_section "packaging fat lib"
}

# copy_to_sdk universal|armv7|armv7s|arm64|sim
function copy_to_sdk
{
	cd $COMMON_BUILD_PATH
    mkdir -p bin
    mkdir -p include
    mkdir -p lib/$1
    cp -r $BUILD_PATH/platform/x86_64-mac/include/* include
    cp -r $BUILD_PATH/platform/$1/lib/* lib/$1
    lipo -info lib/$1/libgflags.a
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
cmake_run armv7
build_iphone armv7
package_libraries
copy_to_sdk universal
cleanup
echo "Completed successfully"


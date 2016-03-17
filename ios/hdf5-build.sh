#!/bin/bash
#
#===============================================================================
# Filename:  hdf5-build.sh
# Author:    Viktor Pogrebniak
# Copyright: (c) 2016 Viktor Pogrebniak
# License:   BSD 3-clause license
#===============================================================================
#
# Builds a hdf5 library for the iPhone.
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

LIB_NAME=hdf5
VERSION_STRING=1.8.16

#BITCODE="-fembed-bitcode"  # Uncomment this line for Bitcode generation

SRC_FOLDER=$COMMON_BUILD_PATH/$LIB_NAME-$VERSION_STRING
BUILD_PATH=$SRC_FOLDER/build
IOS_MIN_VERSION=7.0

# paths
HDF5_TARBALL=$TARBALL_DIR/$LIB_NAME-$VERSION_STRING.tar.gz
PLATFROM_FOLDER=$BUILD_PATH/platform
LOG_DIR=$BUILD_PATH/logs

#TARBALL_NAME=$TARBALL_DIR/$LIB_NAME-$VERSION_STRING.tar.bz2

CFLAGS="-O3 -pipe -fPIC -fcxx-exceptions"
CXXFLAGS="$CFLAGS -std=$CPPSTD -stdlib=$STDLIB $BITCODE"
LIBS="-lc++ -lc++abi"

ARM_DEV_CMD="xcrun --sdk iphoneos"
SIM_DEV_CMD="xcrun --sdk iphonesimulator"
OSX_DEV_CMD="xcrun --sdk macosx"

function invent_missing_headers
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo 'Creating missing headers...'
    cp $XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IPHONE_SDKVERSION}.sdk/usr/include/{crt_externs,bzlib}.h $SRC_FOLDER
}

function download_tarball
{
    mkdir -p $TARBALL_DIR
    if [ ! -s $HDF5_TARBALL ]; then
        echo "Downloading $LIB_NAME ${VERSION_STRING}"
        curl -L -o $HDF5_TARBALL http://www.hdfgroup.org/ftp/HDF5/current/src/$LIB_NAME-$VERSION_STRING.tar.gz
    fi
    done_section "download"
}

function unpack_tarball
{
	mkdir -p $COMMON_BUILD_PATH
    [ -f "$HDF5_TARBALL" ] || abort "Source tarball missing."
    rm -rf $SRC_FOLDER
    echo "Unpacking boost into '$SRC_FOLDER'..."
    mkdir -p tmp && cd tmp
    tar -zxvf $HDF5_TARBALL
    if [ ! -d $LIB_NAME-$VERSION_STRING ]; then
        echo "can't find '$LIB_NAME-$VERSION_STRING' in the tarball"
        cd ..
        rm -rf tmp
        exit 1
    fi
    mv $LIB_NAME-$VERSION_STRING $SRC_FOLDER
    cd ..
    rm -rf tmp
    echo "    ...unpacked as '$SRC_FOLDER'"
    done_section "unpack"
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

function cmake_prepare
{
	mkdir -p $BUILD_PATH/osx
	mkdir -p $COMMON_BUILD_PATH/bin
	mv $SRC_FOLDER/examples $SRC_FOLDER/examples-bak
	mv $SRC_FOLDER/test $SRC_FOLDER/test-bak
	mv $SRC_FOLDER/tools $SRC_FOLDER/tools-bak
	
	# create native build for using H5detect, H5make_libsettings
	rm -rf $BUILD_PATH/osx/*
	create_paths
	cd $BUILD_PATH/osx
	cmake -DBUILD_TESTING=OFF -G Xcode $SRC_FOLDER
	# xcodebuild -list -project HDF5.xcodeproj
	xcodebuild -target H5detect -configuration Release -project HDF5.xcodeproj
	xcodebuild -target H5make_libsettings -configuration Release -project HDF5.xcodeproj
	cp $BUILD_PATH/osx/bin/Release/H5detect $COMMON_BUILD_PATH/bin
	cp $BUILD_PATH/osx/bin/Release/H5make_libsettings $COMMON_BUILD_PATH/bin
	
	# apply patch for
	# disabling building H5Detect, H5make_libsettings
	# arm binary will fail on host machine without this step
	cd $SRC_FOLDER
	if [ ! -f src/CMakeLists.txt.bak ]; then
		cp src/CMakeLists.txt src/CmakeLists.txt.bak
		patch src/CMakeLists.txt $SCRIPT_DIR/hdf5detect-disable.patch
	fi
	cd $BUILD_PATH
}

# example:
# cmake_run armv7|armv7s|arm64
function build_iphone
{
	mkdir -p $BUILD_PATH/$1
	rm -rf $BUILD_PATH/$1/*
	create_paths
	cd $BUILD_PATH/$1
	cp $COMMON_BUILD_PATH/bin/H5detect $BUILD_PATH/$1
	cp $COMMON_BUILD_PATH/bin/H5make_libsettings $BUILD_PATH/$1
	cmake -DCMAKE_TOOLCHAIN_FILE=$SCRIPT_DIR/ios-$1.cmake -DCMAKE_INSTALL_PREFIX=./install -DBUILD_TESTING=OFF -G Xcode $SRC_FOLDER
	xcodebuild -target install -configuration Release -project HDF5.xcodeproj
	cd $COMMON_BUILD_PATH
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

unpack_tarball
cmake_prepare
cmake_run armv7
build_iphone armv7
package_libraries
copy_to_sdk universal
cleanup
echo "Completed successfully"


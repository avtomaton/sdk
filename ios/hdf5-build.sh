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

CPPSTD=c++11    #c++89, c++99, c++14
STDLIB=libc++   # libstdc++
CC=clang
CXX=clang++
PARALLEL_MAKE=7   # how many threads to build

LIB_NAME=hdf5
VERSION_STRING=1.8.16

#BITCODE="-fembed-bitcode"  # Uncomment this line for Bitcode generation

SRC_DIR=$COMMON_BUILD_PATH/$LIB_NAME-$VERSION_STRING
BUILD_PATH=$SRC_DIR/build
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
    rm -rf $SRC_DIR
    echo "Unpacking boost into '$SRC_DIR'..."
    mkdir -p tmp && cd tmp
    tar -zxvf $HDF5_TARBALL
    if [ ! -d $LIB_NAME-$VERSION_STRING ]; then
        echo "can't find '$LIB_NAME-$VERSION_STRING' in the tarball"
        cd ..
        rm -rf tmp
        exit 1
    fi
    mv $LIB_NAME-$VERSION_STRING $SRC_DIR
    cd ..
    rm -rf tmp
    echo "    ...unpacked as '$SRC_DIR'"
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
	mv $SRC_DIR/examples $SRC_DIR/examples-bak
	mv $SRC_DIR/test $SRC_DIR/test-bak
	mv $SRC_DIR/tools $SRC_DIR/tools-bak
	
	# create native build for using H5detect, H5make_libsettings
	rm -rf $BUILD_PATH/osx/*
	create_paths
	cd $BUILD_PATH/osx
	cmake -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX=./install -G Xcode $SRC_DIR
	# xcodebuild -list -project HDF5.xcodeproj
	xcodebuild -target H5detect -configuration Release -project HDF5.xcodeproj
	xcodebuild -target H5make_libsettings -configuration Release -project HDF5.xcodeproj
	cp $BUILD_PATH/osx/bin/Release/H5detect $COMMON_BUILD_PATH/bin
	cp $BUILD_PATH/osx/bin/Release/H5make_libsettings $COMMON_BUILD_PATH/bin
}

function patch_sources
{
	# apply patch for
	# disabling building H5Detect, H5make_libsettings
	# arm binary will fail on host machine without this step
	cd $SRC_DIR
	if [ ! -f src/CMakeLists.txt.bak ]; then
		cp src/CMakeLists.txt src/CmakeLists.txt.bak
		cp src/H5private.h src/H5private.h.bak
		cp src/H5FDstdio.c src/H5FDstdio.c.bak
		patch src/CMakeLists.txt $SCRIPT_DIR/hdf5detect-disable.patch
		patch src/H5private.h $SCRIPT_DIR/hdf5-h5private.patch
		patch src/H5FDstdio.c $SCRIPT_DIR/hdf5-h5fdstdio.patch
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
	cmake -DCMAKE_TOOLCHAIN_FILE=$SCRIPT_DIR/ios-$1.cmake -DCMAKE_INSTALL_PREFIX=./install -DBUILD_TESTING=OFF -G Xcode $SRC_DIR
	xcodebuild -target install -configuration Release -project HDF5.xcodeproj
	cd $COMMON_BUILD_PATH
	done_section "building $1"
}

function package_libraries
{
	local ARCHS=('armv7' 'armv7s' 'arm64' 'i386' 'x86_64')
	local TOOL_LIBS=('libhdf5_cpp.a' 'libhdf5_hl_cpp.a' 'libndf5.a' 'libhdf5_hl.a')
	local ALL_LIBS=""

	cd $BUILD_PATH

	# copy bin and includes
	mkdir -p $COMMON_BUILD_PATH/include/hdf5
	mkdir -p $COMMON_BUILD_PATH/share
	for a in ${ARCHS[@]}; do
		if [ -d $BUILD_PATH/$a ]; then
			cp $a/install/include/* $COMMON_BUILD_PATH/include/hdf5
			cp -r $a/install/share/cmake $COMMON_BUILD_PATH/share/
			break
		fi
	done
    
	# copy arch libs and create fat lib
	for ll in ${TOOL_LIBS[@]}; do
		ALL_LIBS=""
		for a in ${ARCHS[@]}; do
			if [ -d $BUILD_PATH/$a ]; then
				mkdir -p $COMMON_BUILD_PATH/lib/$a
				cp $a/install/lib/$ll $COMMON_BUILD_PATH/lib/$a
				ALL_LIBS="$ALL_LIBS $a/install/lib/$ll"
			fi
		done
		lipo $ALL_LIBS -create -output $COMMON_BUILD_PATH/lib/universal/$ll
		lipo -info $COMMON_BUILD_PATH/lib/universal/$ll
	done
	done_section "packaging fat libs"
}

echo "Library:            $LIB_NAME"
echo "Version:            $VERSION_STRING"
echo "Sources dir:        $SRC_DIR"
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
patch_sources
build_iphone armv7
build_iphone arm64
package_libraries
cleanup
echo "Completed successfully"


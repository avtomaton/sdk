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
# iPhone simulator. Then creates a pseudo-framework to make using hdf5 in Xcode
# less painful.
#
#===============================================================================

SCRIPT_DIR=`dirname $0`
source $SCRIPT_DIR/config.sh
source $SCRIPT_DIR/helpers.sh

LIB_NAME=hdf5
VERSION_STRING=1.8.16
TARBALL_FILE=$TARBALL_DIR/$LIB_NAME-$VERSION_STRING.tar.gz

BUILD_DIR=$COMMON_BUILD_DIR/build/$LIB_NAME-$VERSION_STRING

# paths
LOG_DIR=$BUILD_DIR/logs
SRC_DIR=$COMMON_BUILD_DIR/src/$LIB_NAME-$VERSION_STRING

function download_tarball
{
    mkdir -p $TARBALL_DIR
    if [ ! -s $TARBALL_FILE ]; then
        echo "Downloading $LIB_NAME ${VERSION_STRING}"
        curl -L -o $TARBALL_FILE http://www.hdfgroup.org/ftp/HDF5/current/src/$LIB_NAME-$VERSION_STRING.tar.gz
    fi
    done_section "download"
}

function unpack_tarball
{
	if [ -d $SRC_DIR ]; then
		return
	fi

	mkdir -p $BUILD_DIR
	cd $BUILD_DIR
	[ -f "$TARBALL_FILE" ] || abort "Source tarball missing."
	echo "Unpacking boost into '$SRC_DIR'..."
	mkdir -p tmp && cd tmp
	tar -zxvf $TARBALL_FILE
	if [ ! -d $LIB_NAME-$VERSION_STRING ]; then
		echo "can't find '$LIB_NAME-$VERSION_STRING' in the tarball"
		cd ..
		rm -rf tmp
		exit 1
	fi
	mkdir -p $SRC_DIR
	mv $LIB_NAME-$VERSION_STRING/* $SRC_DIR/
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
	rm -rf $BUILD_DIR
	rm -rf $LOG_DIR
	done_section "cleanup"
}

function cmake_prepare
{
	mkdir -p $BUILD_DIR/osx
	mv $SRC_DIR/examples $SRC_DIR/examples-bak
	mv $SRC_DIR/test $SRC_DIR/test-bak
	mv $SRC_DIR/tools $SRC_DIR/tools-bak
	
	# create native build for using H5detect, H5make_libsettings
	rm -rf $BUILD_DIR/osx/*
	create_paths
	cd $BUILD_DIR/osx
	cmake -DBUILD_TESTING=OFF -DCMAKE_INSTALL_PREFIX=./install -G Xcode $SRC_DIR
	# xcodebuild -list -project HDF5.xcodeproj
	xcodebuild -target H5detect -configuration Release -project HDF5.xcodeproj
	xcodebuild -target H5make_libsettings -configuration Release -project HDF5.xcodeproj
	
	mkdir -p $COMMON_BUILD_DIR/bin
	cp $BUILD_DIR/osx/bin/Release/H5detect $COMMON_BUILD_DIR/bin
	cp $BUILD_DIR/osx/bin/Release/H5make_libsettings $COMMON_BUILD_DIR/bin
	done_section "building hdf5 binaries"
}

function patch_sources
{
	# apply patch for
	# disabling building H5Detect, H5make_libsettings
	# arm binary will fail on host machine without this step
	cd $COMMON_BUILD_DIR
	if [ ! -f src/CMakeLists.txt.bak ]; then
		cp $SRC_DIR/src/CMakeLists.txt $SRC_DIR/src/CmakeLists.txt.bak
		cp $SRC_DIR/src/H5private.h $SRC_DIR/src/H5private.h.bak
		cp $SRC_DIR/src/H5FDstdio.c $SRC_DIR/src/H5FDstdio.c.bak
		patch $SRC_DIR/src/CMakeLists.txt $SCRIPT_DIR/hdf5detect-disable.patch
		patch $SRC_DIR/src/H5private.h $SCRIPT_DIR/hdf5-h5private.patch
		patch $SRC_DIR/src/H5FDstdio.c $SCRIPT_DIR/hdf5-h5fdstdio.patch
	fi
	done_section "patching sources"
}

# example:
# cmake_run armv7|armv7s|arm64
function build_iphone
{
	LOG="$LOG_DIR/$LIB_NAME-build-$1.log"

	mkdir -p $BUILD_DIR/$1
	rm -rf $BUILD_DIR/$1/*
	create_paths
	cd $BUILD_DIR/$1
	cp $COMMON_BUILD_DIR/bin/H5detect $BUILD_DIR/$1
	cp $COMMON_BUILD_DIR/bin/H5make_libsettings $BUILD_DIR/$1
	cmake -DCMAKE_TOOLCHAIN_FILE=$POLLY_DIR/ios-$CODE_SIGN-$IOS_VER-$1.cmake -DCMAKE_INSTALL_PREFIX=./install -DBUILD_TESTING=OFF -G Xcode $SRC_DIR

	xcodebuild -target install -configuration Release -project HDF5.xcodeproj > "${LOG}" 2>&1
	if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while building $1 - Please check ${LOG}"
        xcodebuild -list -project HDF5.xcodeproj
        exit 1
    fi
	cd $COMMON_BUILD_DIR
	done_section "building $1"
}

function package_libraries
{
	local ARCHS=('armv7' 'armv7s' 'arm64' 'i386' 'x86_64')
	local TOOL_LIBS=('libhdf5_cpp.a' 'libhdf5_hl_cpp.a' 'libndf5.a' 'libhdf5_hl.a')
	local ALL_LIBS=""

	cd $BUILD_DIR

	# copy bin and includes
	mkdir -p $COMMON_BUILD_DIR/include/hdf5
	mkdir -p $COMMON_BUILD_DIR/share
	for a in ${ARCHS[@]}; do
		if [ -d $BUILD_DIR/$a ]; then
			cp $a/install/include/* $COMMON_BUILD_DIR/include/hdf5
			cp -r $a/install/share/cmake $COMMON_BUILD_DIR/share/
			break
		fi
	done
    
	# copy arch libs and create fat lib
	for ll in ${TOOL_LIBS[@]}; do
		ALL_LIBS=""
		for a in ${ARCHS[@]}; do
			if [ -d $BUILD_DIR/$a ]; then
				mkdir -p $COMMON_BUILD_DIR/lib/$a
				cp $a/install/lib/$ll $COMMON_BUILD_DIR/lib/$a
				ALL_LIBS="$ALL_LIBS $a/install/lib/$ll"
			fi
		done
		lipo $ALL_LIBS -create -output $COMMON_BUILD_DIR/lib/universal/$ll
		lipo -info $COMMON_BUILD_DIR/lib/universal/$ll
	done
	done_section "packaging fat libs"
}

if [ -f $COMMON_BUILD_DIR/lib/universal/libhdf5.a ]; then
	"Assuming $LIB_NAME exists"
	exit 0
fi

echo "Library:            $LIB_NAME"
echo "Version:            $VERSION_STRING"
echo "Sources dir:        $SRC_DIR"
echo "Build dir:          $BUILD_DIR"
echo "iPhone SDK version: $IPHONE_SDKVERSION"
echo "XCode root:         $XCODE_ROOT"
echo "C compiler:         $CC"
echo "C++ compiler:       $CXX"
if [ -z ${BITCODE} ]; then
    echo "BITCODE EMBEDDED: NO $BITCODE"
else 
    echo "BITCODE EMBEDDED: YES with: $BITCODE"
fi

download_tarball
unpack_tarball
cmake_prepare
patch_sources
build_iphone armv7
build_iphone arm64
package_libraries
cleanup
echo "Completed successfully"


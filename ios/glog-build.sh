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

LIB_NAME=glog
REPO_URL=https://github.com/google/glog.git
VERSION_STRING=v0.3.4

#BITCODE="-fembed-bitcode"  # Uncomment this line for Bitcode generation

BUILD_PATH=$COMMON_BUILD_PATH/$LIB_NAME-$VERSION_STRING
IOS_MIN_VERSION=7.0

# paths
GIT_REPO_DIR=$TARBALL_DIR/$LIB_NAME-$VERSION_STRING
SRC_DIR=$GIT_REPO_DIR
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

function create_paths
{
    mkdir -p $LOG_DIR
}

function cleanup
{
	echo 'Cleaning everything after the build...'
	# rm -rf $BUILD_PATH
	rm -rf $LOG_DIR
	done_section "cleanup"
}

# example:
# cmake_run armv7|armv7s|arm64
function build_iphone
{
	LOG="$LOG_DIR/build-$1.log"
	
	mkdir -p $BUILD_PATH/$1
	rm -rf $BUILD_PATH/$1/*
	create_paths
	cd $BUILD_PATH/$1
	cmake -DCMAKE_TOOLCHAIN_FILE=$SCRIPT_DIR/ios-$1.cmake -DCMAKE_PREFIX_INSTALL=./install -G Xcode $SRC_DIR
	
	# xcodebuild -list -project google-glog.xcodeproj
	xcodebuild -target glog -configuration Release -project google-glog.xcodeproj > "${LOG}" 2>&1
	
	if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while building $1 - Please check ${LOG}"
        exit 1
    fi
    done_section "building $1"
    
	cd $COMMON_BUILD_PATH
}

function package_libraries
{
	local ARCHS=('armv7' 'armv7s' 'arm64' 'i386' 'x86_64')
	local TOOL_LIBS=('libglog.a')
	local ALL_LIBS=""
	
	cd $BUILD_PATH

	# copy bin and includes
	mkdir -p $COMMON_BUILD_PATH/include/glog
	cp $SRC_DIR/src/glog/log_severity.h $COMMON_BUILD_PATH/include/glog
	for a in ${ARCHS[@]}; do
		if [ -d $BUILD_PATH/$a ]; then
			cp -r $a/glog/* $COMMON_BUILD_PATH/include/glog
			break
		fi
	done
	
	# copy arch libs and create fat lib
	for ll in ${TOOL_LIBS[@]}; do
		ALL_LIBS=""
		for a in ${ARCHS[@]}; do
			if [ -d $BUILD_PATH/$a ]; then
				mkdir -p $COMMON_BUILD_PATH/lib/$a
				cp $a/Release-iphoneos/$ll $COMMON_BUILD_PATH/lib/$a
				ALL_LIBS="$ALL_LIBS $a/Release-iphoneos/$ll"
			fi
		done
		lipo $ALL_LIBS -create -output $COMMON_BUILD_PATH/lib/universal/$ll
		lipo -info $COMMON_BUILD_PATH/lib/universal/$ll
	done
	done_section "packaging fat libs"
}

echo "Library:            $LIB_NAME"
echo "Version:            $VERSION_STRING"
echo "Repository:         $GIT_REPO_DIR"
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

download_from_git $REPO_URL $GIT_REPO_DIR
build_iphone armv7
build_iphone armv64
package_libraries
cleanup
echo "Completed successfully"


#!/bin/bash
#
#===============================================================================
# Filename:  gflags-build.sh
# Author:    Viktor Pogrebniak
# Copyright: (c) 2016 Viktor Pogrebniak
# License:   BSD 3-clause license
#===============================================================================
#
# Builds a gflags library for the iPhone.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using gflags in Xcode
# less painful.
#
#===============================================================================

SCRIPT_DIR=`dirname $0`
source $SCRIPT_DIR/config.sh
source $SCRIPT_DIR/helpers.sh

LIB_NAME=gflags
VERSION_STRING=v2.1.2
REPO_URL=https://github.com/gflags/gflags.git

BUILD_DIR=$COMMON_BUILD_DIR/build/$LIB_NAME-$VERSION_STRING

# paths
GIT_REPO_DIR=$TARBALL_DIR/$LIB_NAME-$VERSION_STRING
LOG_DIR=$BUILD_DIR/logs
SRC_DIR=$GIT_REPO_DIR

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
	rm -rf $BUILD_DIR
	rm -rf $LOG_DIR
	done_section "cleanup"
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
	cmake -DCMAKE_TOOLCHAIN_FILE=$POLLY_DIR/ios-$CODE_SIGN-$IOS_VER-$1.cmake -DCMAKE_INSTALL_PREFIX=./install -G Xcode $SRC_DIR
	
	# 
	xcodebuild -target install -configuration Release -project gflags.xcodeproj > "${LOG}" 2>&1
	
	if [ $? != 0 ]; then 
		tail -n 100 "${LOG}"
		echo "Problem while building $1 - Please check ${LOG}"
		echo "Xcode project properties:"
		xcodebuild -list -project gflags.xcodeproj
		exit 1
	fi
	done_section "building $1"
	
	cd $COMMON_BUILD_DIR
}

function package_libraries
{
    local ARCHS=('armv7' 'armv7s' 'arm64' 'i386' 'x86_64')
    local TOOL_LIBS=('libgflags.a' 'libgflags_nothreads.a')
    local ALL_LIBS=""
    
    cd $BUILD_DIR

    # copy bin and includes
    for a in ${ARCHS[@]}; do
		if [ -d $BUILD_DIR/$a ]; then
			mkdir -p $COMMON_BUILD_DIR/include
			mkdir -p $COMMON_BUILD_DIR/bin
			cp $a/install/bin/* $COMMON_BUILD_DIR/bin
			cp -r $a/install/include/gflags $COMMON_BUILD_DIR/include/
			break
		fi
	done
    
    # copy arch libs and create fat lib
    for ll in ${TOOL_LIBS[@]}; do
		ALL_LIBS=""
		for a in ${ARCHS[@]}; do
			if [ -d $BUILD_DIR/$a ]; then
				mkdir -p $COMMON_BUILD_DIR/lib/$a
				cp $a/lib/Release/$ll $COMMON_BUILD_DIR/lib/$a
				ALL_LIBS="$ALL_LIBS $a/lib/Release/$ll"
			fi
		done
		lipo $ALL_LIBS -create -output $COMMON_BUILD_DIR/lib/universal/$ll
		lipo -info $COMMON_BUILD_DIR/lib/universal/$ll
	done
    done_section "packaging fat libs"
}

if [ -f $COMMON_BUILD_DIR/lib/universal/libgflags.a ]; then
	echo "Assuming $LIB_NAME exists"
	exit 0
fi

echo "Library:            $LIB_NAME"
echo "Version:            $VERSION_STRING"
echo "Repository:         $GIT_REPO_DIR"
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

download_from_git $REPO_URL $GIT_REPO_DIR
build_iphone armv7
build_iphone arm64
package_libraries
cleanup
echo "Completed successfully"


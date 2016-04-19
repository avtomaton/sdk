#!/bin/bash

source `dirname $0`/config.sh

function abort
{
	echo
	echo "Aborted: $@"
	exit 1
}

function done_section
{
	echo
	echo "-------$1 complete"
	echo
	
	# just in case
	cd $COMMON_BUILD_PATH
}

# should be called with 2 parameters:
# download_from_git <repo url> <repo path> [<branch|tag>]
function download_from_git
{
	parent_folder=`dirname $2`
	mkdir -p $parent_folder
	cd $parent_folder
	if [ ! -d $2 ]; then
		git clone $1 `basename $2`
	else
		cd $2
		git checkout master
		git pull
	fi
	cd $2
	[ $# -gt 2 ] && git checkout $3
	done_section "downloading"
}

function download_cmake_ios_toolchain
{
	if [ ! -f $TARBALL_DIR/ios-cmake.tar.gz ]; then
		curl -o ios-cmake.tar.gz -SL https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/ios-cmake/ios-cmake.tar.gz
	fi
	
	mkdir -p $COMMON_BUILD_PATH/build-tools
	cd $COMMON_BUILD_PATH/build-tools
	tar -zxvf $TARBALL_DIR/ios-cmake.tar.gz
	if [ ! -d ios-cmake ]; then
		abort "Cannot fetch ios-cmake"
		exit 1
	fi
}

# run_cmake_ios <arch> <parameters>
function run_cmake_ios
{
	cmake -DCMAKE_CXX_FLAGS="-arch $ARCH" -DCMAKE_TOOLCHAIN_FILE=$COMMON_BUILD_PATH/build-tools/build-tools/ios-cmake/toolchain/iOS.cmake -DCMAKE_IOS_SDK_ROOT=$IPHONEOS_SYSROOT $1
}

#!/bin/bash

source `dirname $0`/paths-config.sh

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

#!/bin/bash

SCRIPT_DIR=`dirname $0`
source $SCRIPT_DIR/config.sh
source $SCRIPT_DIR/helpers.sh

LIB_NAME=caffe
VERSION_STRING=master
REPO_URL=https://github.com/BVLC/caffe

BUILD_DIR=$COMMON_BUILD_DIR/build/$LIB_NAME-$VERSION_STRING

# build parameters
GIT_REPO_DIR=$TARBALL_DIR/$LIB_NAME
SRC_DIR=$COMMON_BUILD_DIR/src/$LIB_NAME-$VERSION_STRING
LOG_DIR=$BUILD_DIR/logs

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

function copy_sources
{
	rm -rf $SRC_DIR
	cp -av $GIT_REPO_DIR $SRC_DIR
	rm -rf $SRC_DIR/.git
	rm -rf $SRC_DIR/.gitignore
}

function create_paths
{
    mkdir -p $LOG_DIR
}

function patch_sources
{
	# apply patch for
	# disabling cmake find_package functions family
	cd $COMMON_BUILD_DIR
	if [ ! -f $SRC_DIR/cmake/Dependencies.cmake.bak ]; then
		cp $SRC_DIR/cmake/Dependencies.cmake $SRC_DIR/cmake/Dependencies.cmake.bak
		cp $SRC_DIR/cmake/Protobuf.cmake $SRC_DIR/cmake/Protobuf.cmake.bak
		patch $SRC_DIR/cmake/Dependencies.cmake $SCRIPT_DIR/caffe-deps.patch
		patch $SRC_DIR/cmake/Protobuf.cmake $SCRIPT_DIR/caffe-pb.patch
	fi
	cd $BUILD_DIR
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
	cmake -DCMAKE_TOOLCHAIN_FILE=$POLLY_DIR/ios-$CODE_SIGN-$IOS_VER-$1.cmake DCMAKE_INSTALL_PREFIX=./install -DCPU_ONLY=ON -DBUILD_SHARED_LIBS=OFF -DBUILD_python=OFF -DBUILD_python_layer=OFF -DBUILD_docs=OFF -DUSE_OPENCV=OFF -DUSE_LEVELDB=OFF -DUSE_LMDB=OFF -DPROTOC=$COMMON_BUILD_DIR/bin/protoc -DCMAKE_CXX_FLAGS="-I$COMMON_BUILD_DIR/include -I$COMMON_BUILD_DIR/include/hdf5 -I/System/Library/Frameworks/Accelerate.framework/Frameworks/vecLib.framework/Headers" -DCMAKE_EXE_LINKER_FLAGS=-L$COMMON_BUILD_DIR/lib/$1 -G Xcode $SRC_DIR
	
	xcodebuild -target install -configuration Release -project Caffe.xcodeproj > "${LOG}" 2>&1
	
	if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while building $1 - Please check ${LOG}"
        xcodebuild -list -project Caffe.xcodeproj
        exit 1
    fi
    done_section "building $1"
    
	cd $COMMON_BUILD_DIR
}

function package_libraries
{
	local ARCHS=('armv7' 'armv7s' 'arm64' 'i386' 'x86_64')
	local TOOL_LIBS=('libcaffe.a' 'libproto.a')
	local ALL_LIBS=""
	
	cd $BUILD_DIR

	# copy bin and includes
	mkdir -p $COMMON_BUILD_DIR/include
	mkdir -p $COMMON_BUILD_DIR/share
	for a in ${ARCHS[@]}; do
		if [ -d $BUILD_DIR/$a ]; then
			cp -r $a/install/include/caffe $COMMON_BUILD_DIR/include/
			cp -r $a/install/share/Caffe $COMMON_BUILD_DIR/share/
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

$SCRIPT_DIR/boost-build.sh
$SCRIPT_DIR/potobuf-build.sh
$SCRIPT_DIR/gflags-build.sh
$SCRIPT_DIR/glog-build.sh
$SCRIPT_DIR/hdf5-build.sh

download_from_git $REPO_URL $GIT_REPO_DIR
copy_sources
patch_sources
build_iphone armv7
build_iphone arm64
package_libraries

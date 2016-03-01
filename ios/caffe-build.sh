#!/bin/bash

source `dirname $0`/paths-config.sh
source `dirname $0`/get-apple-vars.sh
source `dirname $0`/helpers.sh

LIB_NAME=caffe
REPO_URL=https://github.com/BVLC/caffe
VERSION_STRING=master

BUILD_PATH=$COMMON_BUILD_PATH/$LIB_NAME-$VERSION_STRING
IOS_MIN_VERSION=7.0

# build parameters
GIT_REPO_DIR=$TARBALL_DIR/$LIB_NAME-$VERSION_STRING
SRC_FOLDER=$BUILD_PATH/src
LOG_DIR=$BUILD_PATH/logs

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

function cmake_run
{
	mkdir -p $BUILD_PATH
	rm -rf $BUILD_PATH/*
	create_paths
	cd $BUILD_PATH
	cmake -DCPU_ONLY=ON -DBUILD_SHARED_LIBS=OFF -DBUILD_python=OFF -DBUILD_python_layer=OFF -DBUILD_docs=OFF -DUSE_OPENCV=OFF -DUSE_LEVELDB=OFF -DUSE_LMDB=OFF $GIT_REPO_DIR
	cd $COMMON_BUILD_PATH
}

download_from_git $REPO_URL $GIT_REPO_DIR
cmake_run

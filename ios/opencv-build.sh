#!/bin/bash

SCRIPT_DIR=`dirname $0`
source $SCRIPT_DIR/config.sh
source $SCRIPT_DIR/helpers.sh

LIB_NAME=opencv
VERSION_STRING=3.1.0
TARBALL_FILE=$TARBALL_DIR/$LIB_NAME-$VERSION_STRING.zip
TARBALL_URL=http://sourceforge.net/projects/opencvlibrary/files/opencv-ios/3.1.0/opencv2.framework.zip/download



function download_tarball
{
    mkdir -p $TARBALL_DIR
    if [ ! -f $TARBALL_FILE ]; then
        echo "Downloading $LIB_NAME $VERSION_STRING"
        curl -L -o $TARBALL_FILE $TARBALL_URL
    fi
    done_section "download"
}

function unpack_tarball
{
	if [ -d opencv2.framework ]; then
		return
	fi
	
	mkdir -p frameworks
	[ -f "$TARBALL_FILE" ] || abort "Source tarball missing."
	cd $COMMON_BUILD_DIR/frameworks
	echo "Unpacking opencv ..."
	unzip $TARBALL_FILE
	done_section "unpack"
}

function create_headers
{
	cd $COMMON_BUILD_DIR/include
	ln -s $COMMON_BUILD_DIR/frameworks/opencv2.framework/Headers opencv2
}

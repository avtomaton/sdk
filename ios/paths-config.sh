#!/bin/bash

COMMON_BUILD_DIR=`pwd`
case $COMMON_BUILD_DIR in  
     *\ * )
           echo "Your path contains whitespaces, which is not supported by 'make install'."
           exit 1
          ;;
esac

TARBALL_DIR=$COMMON_BUILD_DIR/downloads

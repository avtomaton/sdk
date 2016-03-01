#!/bin/bash

COMMON_BUILD_PATH=`pwd`
case $COMMON_BUILD_PATH in  
     *\ * )
           echo "Your path contains whitespaces, which is not supported by 'make install'."
           exit 1
          ;;
esac

TARBALL_DIR=$COMMON_BUILD_PATH/downloads

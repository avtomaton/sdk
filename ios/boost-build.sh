#!/bin/bash
#
#===============================================================================
# Filename:  boost-build.sh
# Author:    Pete Goodliffe, Daniel Rosser, Viktor Pogrebniak
# Copyright: (c) Copyright 2009 Pete Goodliffe, 2013-2015 Daniel Rosser, 2016 Viktor Pogrebniak
# License:   Please feel free to use this, with attribution
#===============================================================================
#
# Builds a Boost framework for the iPhone.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using boost in Xcode
# less painful.
#
# To configure the script, define:
#    BOOST_LIBS:        which libraries to build
#
# Then run boost-build.sh from folder in which you want to see your build.
#===============================================================================

SCRIPT_DIR=`dirname $0`
source $SCRIPT_DIR/config.sh
source $SCRIPT_DIR/helpers.sh

LIB_NAME=boost
VERSION_STRING=1.60.0
BOOST_VERSION2=${VERSION_STRING//./_}
TARBALL_URL=http://sourceforge.net/projects/boost/files/boost/${VERSION_STRING}/boost_${BOOST_VERSION2}.tar.bz2/download

BOOST_LIBS="random regex graph random chrono thread signals filesystem system date_time"

EXTRA_CPPFLAGS="-fPIC -DBOOST_SP_USE_SPINLOCK -std=$CPPSTD -stdlib=$STDLIB -miphoneos-version-min=$IOS_MIN_VERSION $BITCODE -fvisibility=hidden -fvisibility-inlines-hidden"

SRC_DIR=$COMMON_BUILD_DIR/src/$LIB_NAME-$VERSION_STRING
BUILD_DIR=$COMMON_BUILD_DIR/build/$LIB_NAME-$VERSION_STRING

LOG_DIR=$BUILD_DIR/logs/
PREFIX_DIR=$BUILD_DIR/ios-prefix

TARBALL_FILE=$TARBALL_DIR/boost_$BOOST_VERSION2.tar.bz2

#===============================================================================
# Functions
#===============================================================================

function cleanup
{
	echo 'Cleaning everything after the build...'
	rm -rf $BUILD_DIR
	done_section "cleanup"
}

function create_paths
{
	mkdir -p $BUILD_DIR
    mkdir -p $LOG_DIR
}

function download_tarball
{
	mkdir -p $TARBALL_DIR
	if [ ! -s $TARBALL_FILE ]; then
		echo "Downloading boost ${VERSION_STRING}"
		curl -L -o $TARBALL_FILE $TARBALL_URL
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
	tar xfj $TARBALL_FILE
	if [ ! -d boost_${BOOST_VERSION2} ]; then
		echo "can't find 'boost_${BOOST_VERSION2}' in the tarball"
		cd ..
		rm -rf tmp
		exit 1
	fi
	mkdir -p $SRC_DIR
	mv boost_${BOOST_VERSION2}/* $SRC_DIR/
	cd ..
	rm -rf tmp
	echo "    ...unpacked as '$SRC_DIR'"
	done_section "unpack"
}

function update_boost
{
    echo "Updating boost into '$SRC_DIR'..."
    local CROSS_TOP_IOS="${XCODE_ROOT}/Platforms/iPhoneOS.platform/Developer"
    local CROSS_SDK_IOS="iPhoneOS${IPHONE_SDKVERSION}.sdk"
    local CROSS_TOP_SIM="${XCODE_ROOT}/Platforms/iPhoneSimulator.platform/Developer"
    local CROSS_SDK_SIM="iPhoneSimulator${IPHONE_SDKVERSION}.sdk"
    local BUILD_TOOLS="${XCODE_ROOT}"
    if [ ! -f $SRC_DIR/tools/build/example/user-config.jam.bk ]; then
		cp $SRC_DIR/tools/build/example/user-config.jam $SRC_DIR/tools/build/example/user-config.jam.bk
		cat >> $SRC_DIR/tools/build/example/user-config.jam <<EOF
using darwin : ${IPHONE_SDKVERSION}~iphone
: $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/$CXX -arch armv7 -arch arm64 $EXTRA_CPPFLAGS "-isysroot ${CROSS_TOP_IOS}/SDKs/${CROSS_SDK_IOS}" -I${CROSS_TOP_IOS}/SDKs/${CROSS_SDK_IOS}/usr/include/
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
: <architecture>arm <target-os>iphone
;
using darwin : ${IPHONE_SDKVERSION}~iphonesim
: $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/$CXX -arch i386 -arch x86_64 $EXTRA_CPPFLAGS "-isysroot ${CROSS_TOP_SIM}/SDKs/${CROSS_SDK_SIM}" -I${CROSS_TOP_SIM}/SDKs/${CROSS_SDK_SIM}/usr/include/
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer
: <architecture>x86 <target-os>iphone
;
EOF
	fi
    done_section "update"
}

function bootstrap_boost
{
    cd $SRC_DIR
    BOOST_LIBS_COMMA=$(echo $BOOST_LIBS | sed -e "s/ /,/g")
    echo "Bootstrapping (with libs $BOOST_LIBS_COMMA)"
    ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA
    done_section "bootstrapping"
}

function build_iphone_boost
{
	mkdir -p $BUILD_DIR
	cd $SRC_DIR
	# Install this one so we can copy the includes for the frameworks...

	set +e    
	echo "------------------"
	LOG="$LOG_DIR/boost-iphone-stage.log"
	echo "Running bjam for iphone-build stage"
	echo "To see status in realtime check:"
	echo " ${LOG}"
	echo "Please stand by..."
	./bjam -j${PARALLEL_MAKE} --build-dir=iphone-build -sBOOST_BUILD_USER_CONFIG=$SRC_DIR/tools/build/example/user-config.jam --stagedir=iphone-build/stage --prefix=$PREFIX_DIR --toolset=darwin-${IPHONE_SDKVERSION}~iphone cxxflags="-miphoneos-version-min=$IOS_MIN_VERSION -stdlib=$STDLIB $BITCODE" variant=release linkflags="-stdlib=$STDLIB" architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static stage > "${LOG}" 2>&1
	if [ $? != 0 ]; then 
		tail -n 100 "${LOG}"
		echo "Problem while Building iphone-build stage - Please check ${LOG}"
		exit 1
	else 
		echo "iphone-build stage successful"
	fi
	echo "------------------"
	LOG="$LOG_DIR/boost-iphone-install.log"
	echo "Running bjam for iphone-build install"
	echo "To see status in realtime check:"
	echo " ${LOG}"
	echo "Please stand by..."
	./bjam -j${PARALLEL_MAKE} --build-dir=iphone-build -sBOOST_BUILD_USER_CONFIG=$SRC_DIR/tools/build/example/user-config.jam --stagedir=iphone-build/stage --prefix=$PREFIX_DIR --toolset=darwin-${IPHONE_SDKVERSION}~iphone cxxflags="-miphoneos-version-min=$IOS_MIN_VERSION -stdlib=$STDLIB $BITCODE" variant=release linkflags="-stdlib=$STDLIB" architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static install > "${LOG}" 2>&1
	if [ $? != 0 ]; then 
		tail -n 100 "${LOG}"
		echo "Problem while Building iphone-build install - Please check ${LOG}"
		exit 1
	else 
		echo "iphone-build install successful"
	fi
	done_section "iOS build"
}

function build_sim_boost
{
	cd $SRC_DIR
	LOG="$LOG_DIR/boost-iphone-simulator-build.log"
	echo "Running bjam for iphone-sim-build "
	echo "To see status in realtime check:"
	echo " ${LOG}"
	echo "Please stand by..."
	./bjam -j${PARALLEL_MAKE} --build-dir=iphonesim-build -sBOOST_BUILD_USER_CONFIG=$SRC_DIR/tools/build/example/user-config.jam --stagedir=iphonesim-build/stage --toolset=darwin-${IPHONE_SDKVERSION}~iphonesim architecture=x86 target-os=iphone variant=release cxxflags="-miphoneos-version-min=$IOS_MIN_VERSION -stdlib=$STDLIB $BITCODE" macosx-version=iphonesim-${IPHONE_SDKVERSION} link=static stage > "${LOG}" 2>&1
	if [ $? != 0 ]; then 
		tail -n 100 "${LOG}"
		echo "Problem while Building iphone-simulator build - Please check ${LOG}"
		exit 1
	else 
		echo "iphone-simulator build successful"
	fi
	done_section "iOS simulator build"
}

function package_libraries
{
	cd $SRC_DIR
	
	#local ARCHS=('armv7' 'armv7s' 'arm64' 'i386' 'x86_64')
	local ARCHS=('armv7' 'arm64' 'i386' 'x86_64')
    
	local IOS_BUILD_DIR=$BUILD_DIR/tmp
	
	for a in ${ARCHS[@]}; do
		mkdir -p $IOS_BUILD_DIR/$a/obj
		mkdir -p $COMMON_BUILD_DIR/lib/$a
	done
	
	ALL_LIBS=""
	echo 'Splitting all existing fat binaries...'
    
	for NAME in $BOOST_LIBS; do
		ALL_LIBS="$ALL_LIBS libboost_$NAME.a"
		for a in ${ARCHS[@]}; do
			if [ ${a:0:3} == 'arm' ]; then
				stage_dir=iphone-build
			else
				stage_dir=iphonesim-build
			fi
			$ARM_DEV_CMD lipo "$stage_dir/stage/lib/libboost_$NAME.a" -thin $a -o $COMMON_BUILD_DIR/lib/$a/libboost_$NAME.a
		done
	done
	echo "Decomposing each architecture's .a files"
	for NAME in $ALL_LIBS; do
		echo "Decomposing $NAME..."
		for a in ${ARCHS[@]}; do
			cd $IOS_BUILD_DIR/$a/obj
			ar -x $COMMON_BUILD_DIR/lib/$a/$NAME
		done
	done
	echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost.a )"
	
	rm $IOS_BUILD_DIR/*/libboost.a

	for a in ${ARCHS[@]}; do
		echo "...$a"
		cd $COMMON_BUILD_DIR/lib/$a
		$ARM_DEV_CMD ar crus libboost.a $IOS_BUILD_DIR/$a/obj/*.o;
	done

	echo "Making fat lib for iOS Boost '$VERSION_STRING'"
	
	mkdir -p $COMMON_BUILD_DIR/lib/universal
	ARCH_LIBS=""
	for a in ${ARCHS[@]}; do
		ARCH_LIBS="$COMMON_BUILD_DIR/lib/$a/libboost.a $ARCH_LIBS"
	done
	lipo -c $ARCH_LIBS -output $COMMON_BUILD_DIR/lib/universal/libboost.a
	rm -rf $IOS_BUILD_DIR
    done_section "fat lib"
}

function copy_headers
{
	mkdir -p $COMMON_BUILD_DIR/include
    echo "------------------"
    echo "Copying Includes to Final Dir $COMMON_BUILD_DIR/include"
    LOG="$LOG_DIR/buildIncludes.log"
    set +e
    cp -r $PREFIX_DIR/include/*  $COMMON_BUILD_DIR/include > "${LOG}" 2>&1
    if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while copying includes - Please check ${LOG}"
        exit 1
    else 
        echo "Copy of Includes successful"
    fi
    done_section "headers copy"
}

#===============================================================================
# Execution starts here
#===============================================================================
if [ -f $COMMON_BUILD_DIR/lib/universal/libboost.a ]; then
	echo "Assuming $LIB_NAME exists"
	exit 0
fi

#cleanEverythingReadyToStart #may want to comment if repeatedly running during dev
#restoreBoost
echo "Boost version:      $VERSION_STRING"
echo "Boost libraries:    $BOOST_LIBS"
echo "Sources dir:        $SRC_DIR"
echo "PREFIX_DIR:         $PREFIX_DIR"
echo "iPhone SDK version: $IPHONE_SDKVERSION"
echo "Xcode root:         $XCODE_ROOT"
echo "Compiler:           $CXX"
if [ -z ${BITCODE} ]; then
    echo "BITCODE EMBEDDED: NO $BITCODE"
else 
    echo "BITCODE EMBEDDED: YES with: $BITCODE"
fi

download_tarball
unpack_tarball
invent_missing_headers $SRC_DIR
create_paths
bootstrap_boost
update_boost
build_iphone_boost
build_sim_boost
package_libraries
copy_headers
cleanup
echo "Completed successfully"

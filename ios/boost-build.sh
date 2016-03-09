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

source `dirname $0`/paths-config.sh
source `dirname $0`/get-apple-vars.sh
source `dirname $0`/helpers.sh

CPPSTD=c++11    #c++89, c++99, c++14
STDLIB=libc++   # libstdc++
COMPILER=clang++
PARALLEL_MAKE=7   # how many threads to make boost with

VERSION_STRING=1.60.0
BOOST_VERSION2=${VERSION_STRING//./_}

#BITCODE="-fembed-bitcode"  # Uncomment this line for Bitcode generation

IOS_MIN_VERSION=7.0

: ${BOOST_LIBS:="random regex graph random chrono thread signals filesystem system date_time"}

: ${EXTRA_CPPFLAGS:="-fPIC -DBOOST_SP_USE_SPINLOCK -std=$CPPSTD -stdlib=$STDLIB -miphoneos-version-min=$IOS_MIN_VERSION $BITCODE -fvisibility=hidden -fvisibility-inlines-hidden"}

BUILD_PATH=$COMMON_BUILD_PATH/boost_$BOOST_VERSION2

BOOST_SRC=$BUILD_PATH/src
LOG_DIR=$BUILD_PATH/logs/
: ${IOSINCLUDEDIR:=$BUILD_PATH/build/libs/boost/include/boost}
: ${PREFIXDIR:=$BUILD_PATH/build/ios/prefix}
: ${OUTPUT_DIR:=$BUILD_PATH/libs/boost/}

BOOST_TARBALL=$TARBALL_DIR/boost_$BOOST_VERSION2.tar.bz2
BOOST_INCLUDE=$BOOST_SRC/boost
#===============================================================================
ARM_DEV_CMD="xcrun --sdk iphoneos"
SIM_DEV_CMD="xcrun --sdk iphonesimulator"
OSX_DEV_CMD="xcrun --sdk macosx"
#===============================================================================
#===============================================================================
# Functions
#===============================================================================

cleanEverythingReadyToStart()
{
    echo 'Cleaning everything before we start to build...'
    cd $BUILD_PATH
    rm -rf iphone-build iphonesim-build osx-build
    rm -rf $PREFIXDIR
    rm -rf $LOG_DIR
    done_section "pre-cleaning"
}
postcleanEverything()
{
	echo 'Cleaning everything after the build...'
	cd $BUILD_PATH
	rm -rf iphone-build iphonesim-build osx-build
	rm -rf $PREFIXDIR
    rm -rf $LOG_DIR
	done_section "cleanup"
}
prepare()
{
    mkdir -p $LOG_DIR
    mkdir -p $OUTPUT_DIR
}
#===============================================================================
downloadBoost()
{
    mkdir -p $TARBALL_DIR
    if [ ! -s $BOOST_TARBALL ]; then
        echo "Downloading boost ${VERSION_STRING}"
        curl -L -o $BOOST_TARBALL http://sourceforge.net/projects/boost/files/boost/${VERSION_STRING}/boost_${BOOST_VERSION2}.tar.bz2/download
    fi
    done_section "download"
}
#===============================================================================
unpackBoost()
{
	mkdir -p $BUILD_PATH
	cd $BUILD_PATH
    [ -f "$BOOST_TARBALL" ] || abort "Source tarball missing."
    rm -rf $BOOST_SRC
    echo "Unpacking boost into '$BOOST_SRC'..."
    mkdir -p tmp && cd tmp
    tar xfj $BOOST_TARBALL
    if [ ! -d boost_${BOOST_VERSION2} ]; then
        echo "can't find 'boost_${BOOST_VERSION2}' in the tarball"
        cd ..
        rm -rf tmp
        exit 1
    fi
    mv boost_${BOOST_VERSION2} $BOOST_SRC
    cd ..
    rm -rf tmp
    echo "    ...unpacked as '$BOOST_SRC'"
    done_section "unpack"
}
#===============================================================================
restoreBoost()
{
    cp $BOOST_SRC/tools/build/example/user-config.jam.bk $BOOST_SRC/tools/build/example/user-config.jam
}
#===============================================================================
updateBoost()
{
    echo "Updating boost into '$BOOST_SRC'..."
    local CROSS_TOP_IOS="${XCODE_ROOT}/Platforms/iPhoneOS.platform/Developer"
    local CROSS_SDK_IOS="iPhoneOS${IPHONE_SDKVERSION}.sdk"
    local CROSS_TOP_SIM="${XCODE_ROOT}/Platforms/iPhoneSimulator.platform/Developer"
    local CROSS_SDK_SIM="iPhoneSimulator${IPHONE_SDKVERSION}.sdk"
    local BUILD_TOOLS="${XCODE_ROOT}"
    if [ ! -f $BOOST_SRC/tools/build/example/user-config.jam.bk ]; then
		cp $BOOST_SRC/tools/build/example/user-config.jam $BOOST_SRC/tools/build/example/user-config.jam.bk
	fi
    cat >> $BOOST_SRC/tools/build/example/user-config.jam <<EOF
using darwin : ${IPHONE_SDKVERSION}~iphone
: $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/$COMPILER -arch armv7 -arch arm64 $EXTRA_CPPFLAGS "-isysroot ${CROSS_TOP_IOS}/SDKs/${CROSS_SDK_IOS}" -I${CROSS_TOP_IOS}/SDKs/${CROSS_SDK_IOS}/usr/include/
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
: <architecture>arm <target-os>iphone
;
using darwin : ${IPHONE_SDKVERSION}~iphonesim
: $XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/$COMPILER -arch i386 -arch x86_64 $EXTRA_CPPFLAGS "-isysroot ${CROSS_TOP_SIM}/SDKs/${CROSS_SDK_SIM}" -I${CROSS_TOP_SIM}/SDKs/${CROSS_SDK_SIM}/usr/include/
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer
: <architecture>x86 <target-os>iphone
;
EOF
    done_section "update"
}
#===============================================================================
inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo Invent missing headers
    cp $XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IPHONE_SDKVERSION}.sdk/usr/include/{crt_externs,bzlib}.h $BOOST_SRC
}
#===============================================================================
bootstrapBoost()
{
    cd $BOOST_SRC
    BOOST_LIBS_COMMA=$(echo $BOOST_LIBS | sed -e "s/ /,/g")
    echo "Bootstrapping (with libs $BOOST_LIBS_COMMA)"
    ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA
    done_section "bootstrapping"
}
#===============================================================================
buildBoostForIPhoneOS()
{
    cd $BOOST_SRC
    # Install this one so we can copy the includes for the frameworks...
    
    set +e    
    echo "------------------"
    LOG="$LOG_DIR/build-iphone-stage.log"
    echo "Running bjam for iphone-build stage"
    echo "To see status in realtime check:"
    echo " ${LOG}"
    echo "Please stand by..."
    ./bjam -j${PARALLEL_MAKE} --build-dir=iphone-build -sBOOST_BUILD_USER_CONFIG=$BOOST_SRC/tools/build/example/user-config.jam --stagedir=iphone-build/stage --prefix=$PREFIXDIR --toolset=darwin-${IPHONE_SDKVERSION}~iphone cxxflags="-miphoneos-version-min=$IOS_MIN_VERSION -stdlib=$STDLIB $BITCODE" variant=release linkflags="-stdlib=$STDLIB" architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static stage > "${LOG}" 2>&1
    if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while Building iphone-build stage - Please check ${LOG}"
        exit 1
    else 
        echo "iphone-build stage successful"
    fi
    echo "------------------"
    LOG="$LOG_DIR/build-iphone-install.log"
    echo "Running bjam for iphone-build install"
    echo "To see status in realtime check:"
    echo " ${LOG}"
    echo "Please stand by..."
    ./bjam -j${PARALLEL_MAKE} --build-dir=iphone-build -sBOOST_BUILD_USER_CONFIG=$BOOST_SRC/tools/build/example/user-config.jam --stagedir=iphone-build/stage --prefix=$PREFIXDIR --toolset=darwin-${IPHONE_SDKVERSION}~iphone cxxflags="-miphoneos-version-min=$IOS_MIN_VERSION -stdlib=$STDLIB $BITCODE" variant=release linkflags="-stdlib=$STDLIB" architecture=arm target-os=iphone macosx-version=iphone-${IPHONE_SDKVERSION} define=_LITTLE_ENDIAN link=static install > "${LOG}" 2>&1
    if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while Building iphone-build install - Please check ${LOG}"
        exit 1
    else 
        echo "iphone-build install successful"
    fi
    doneSection
    echo "------------------"
    LOG="$LOG_DIR/build-iphone-simulator-build.log"
    echo "Running bjam for iphone-sim-build "
    echo "To see status in realtime check:"
    echo " ${LOG}"
    echo "Please stand by..."
    ./bjam -j${PARALLEL_MAKE} --build-dir=iphonesim-build -sBOOST_BUILD_USER_CONFIG=$BOOST_SRC/tools/build/example/user-config.jam --stagedir=iphonesim-build/stage --toolset=darwin-${IPHONE_SDKVERSION}~iphonesim architecture=x86 target-os=iphone variant=release cxxflags="-miphoneos-version-min=$IOS_MIN_VERSION -stdlib=$STDLIB $BITCODE" macosx-version=iphonesim-${IPHONE_SDKVERSION} link=static stage > "${LOG}" 2>&1
    if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while Building iphone-simulator build - Please check ${LOG}"
        exit 1
    else 
        echo "iphone-simulator build successful"
    fi
    done_section "iphone build"
}
#===============================================================================
scrunchAllLibsTogetherInOneLibPerPlatform()
{
	cd $BOOST_SRC
	
	#local ARCHS=('armv7' 'armv7s' 'arm64' 'i386' 'x86_64')
	local ARCHS=('armv7' 'arm64' 'i386' 'x86_64')
    
	local IOS_BUILD_DIR=$BUILD_DIR/tmp
	
	for a in ${ARCHS[@]}; do
		mkdir -p $IOS_BUILD_DIR/$a/obj
		mkdir -p $COMMON_BUILD_PATH/lib/$a
	done
	
	ALL_LIBS=""
	echo 'Splitting all existing fat binaries...'
    
	for NAME in $BOOST_LIBS; do
		ALL_LIBS="$ALL_LIBS libboost_$NAME.a"
		for a in ${ARCHS[@]}; do
			$ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin $a -o $COMMON_BUILD_PATH/lib/$a/libboost_$NAME.a
		done
	done
	echo "Decomposing each architecture's .a files"
	for NAME in $ALL_LIBS; do
		echo "Decomposing $NAME..."
		for a in ${ARCHS[@]}; do
			cd $IOS_BUILD_DIR/$a/obj
			ar -x $COMMON_BUILD_PATH/lib/$a/$NAME
		done
	done
	echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost.a )"
	
	rm $IOS_BUILD_DIR/*/libboost.a

	for a in ${ARCHS[@]}; do
		echo "...$a"
		cd $COMMON_BUILD_PATH/lib/$a
		$ARM_DEV_CMD ar crus libboost.a $IOS_BUILD_DIR/$a/obj/*.o;
	done

	echo "Making fat lib for iOS Boost '$VERSION_STRING'"
	
	mkdir -p $COMMON_BUILD_PATH/lib/universal
	lipo -c $COMMON_BUILD_PATH/lib/armv7/libboost.a \
            $COMMON_BUILD_PATH/lib/arm64/libboost.a \
            $COMMON_BUILD_PATH/lib/i386/libboost.a \
            $COMMON_BUILD_PATH/lib/x86_64/libboost.a \
            -output $COMMON_BUILD_PATH/lib/universal/libboost.a
	rm -rf $IOS_BUILD_DIR
    done_section "fat lib"
}
#===============================================================================
function copy_headers
{
	mkdir -p $COMMON_BUILD_PATH/include
    echo "------------------"
    echo "Copying Includes to Final Dir $COMMON_BUILD_PATH/include"
    LOG="$LOG_DIR/buildIncludes.log"
    set +e
    cp -r $PREFIXDIR/include/*  $COMMON_BUILD_PATH/include > "${LOG}" 2>&1
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
#cleanEverythingReadyToStart #may want to comment if repeatedly running during dev
#restoreBoost
echo "BOOST_VERSION:     $VERSION_STRING"
echo "BOOST_LIBS:        $BOOST_LIBS"
echo "BOOST_SRC:         $BOOST_SRC"
echo "PREFIXDIR:         $PREFIXDIR"
echo "IPHONE_SDKVERSION: $IPHONE_SDKVERSION"
echo "XCODE_ROOT:        $XCODE_ROOT"
echo "COMPILER:          $COMPILER"
if [ -z ${BITCODE} ]; then
    echo "BITCODE EMBEDDED: NO $BITCODE"
else 
    echo "BITCODE EMBEDDED: YES with: $BITCODE"
fi
downloadBoost
unpackBoost
inventMissingHeaders
prepare
bootstrapBoost
updateBoost
buildBoostForIPhoneOS
scrunchAllLibsTogetherInOneLibPerPlatform
copy_headers
#restoreBoost
postcleanEverything
echo "Completed successfully"

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

CPPSTD=c++11    #c++89, c++99, c++14
STDLIB=libc++   # libstdc++
COMPILER=clang++
PARALLEL_MAKE=7   # how many threads to make boost with

VERSION_STRING=1.60.0
BOOST_VERSION2=${VERSION_STRING//./_}

#BITCODE="-fembed-bitcode"  # Uncomment this line for Bitcode generation

CURRENTPATH=`pwd`
LOGDIR="$CURRENTPATH/build/logs/"
IOS_MIN_VERSION=7.0

source get-apple-vars.sh
source helpers.sh

case $CURRENTPATH in  
     *\ * )
           echo "Your path contains whitespaces, which is not supported by 'make install'."
           exit 1
          ;;
esac
: ${BOOST_LIBS:="random regex graph random chrono thread signals filesystem system date_time"}

: ${EXTRA_CPPFLAGS:="-fPIC -DBOOST_SP_USE_SPINLOCK -std=$CPPSTD -stdlib=$STDLIB -miphoneos-version-min=$IOS_MIN_VERSION $BITCODE -fvisibility=hidden -fvisibility-inlines-hidden"}
: ${TARBALLDIR:=`pwd`/downloads}
: ${BOOST_SRC:=`pwd`/boost_$BOOST_VERSION2/src}
: ${IOSBUILDDIR:=`pwd`/boost_$BOOST_VERSION2/build/libs/boost/lib}
: ${IOSINCLUDEDIR:=`pwd`/boost_$BOOST_VERSION2/build/libs/boost/include/boost}
: ${PREFIXDIR:=`pwd`/boost_$BOOST_VERSION2/build/ios/prefix}
: ${OUTPUT_DIR:=`pwd`/boost_$BOOST_VERSION2/libs/boost/}
: ${OUTPUT_DIR_LIB:=`pwd`/boost_$BOOST_VERSION2/libs/boost/ios/}
: ${OUTPUT_DIR_SRC:=`pwd`/boost_$BOOST_VERSION2/libs/boost/include/boost}
BOOST_TARBALL=$TARBALLDIR/boost_$BOOST_VERSION2.tar.bz2
BOOST_INCLUDE=$BOOST_SRC/boost
#===============================================================================
ARM_DEV_CMD="xcrun --sdk iphoneos"
SIM_DEV_CMD="xcrun --sdk iphonesimulator"
OSX_DEV_CMD="xcrun --sdk macosx"
#===============================================================================
#===============================================================================
# Functions
#===============================================================================

doneSection()
{
    echo
    echo "================================================================="
    echo "Done"
    echo
}
#===============================================================================
cleanEverythingReadyToStart()
{
    echo 'Cleaning everything before we start to build...'
    rm -rf iphone-build iphonesim-build osx-build
    rm -rf $IOSBUILDDIR
    rm -rf $PREFIXDIR
    rm -rf $IOSINCLUDEDIR
    rm -rf $TARBALLDIR/build
    rm -rf $LOGDIR
    doneSection
}
postcleanEverything()
{
	echo 'Cleaning everything after the build...'
	rm -rf iphone-build iphonesim-build osx-build
	rm -rf $PREFIXDIR
	rm -rf $IOSBUILDDIR/armv6/obj
    rm -rf $IOSBUILDDIR/armv7/obj
    #rm -rf $IOSBUILDDIR/armv7s/obj
	rm -rf $IOSBUILDDIR/arm64/obj
    rm -rf $IOSBUILDDIR/i386/obj
	rm -rf $IOSBUILDDIR/x86_64/obj
    rm -rf $TARBALLDIR/build
    rm -rf $LOGDIR
	doneSection
}
prepare()
{
    mkdir -p $LOGDIR
    mkdir -p $OUTPUT_DIR
    mkdir -p $OUTPUT_DIR_SRC
    mkdir -p $OUTPUT_DIR_LIB
}
#===============================================================================
downloadBoost()
{
    mkdir -p $TARBALLDIR
    if [ ! -s $BOOST_TARBALL ]; then
        echo "Downloading boost ${VERSION_STRING}"
        curl -L -o $BOOST_TARBALL http://sourceforge.net/projects/boost/files/boost/${VERSION_STRING}/boost_${BOOST_VERSION2}.tar.bz2/download
    fi
    doneSection
}
#===============================================================================
unpackBoost()
{
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
    doneSection
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
    doneSection
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
    doneSection
}
#===============================================================================
buildBoostForIPhoneOS()
{
    cd $BOOST_SRC
    # Install this one so we can copy the includes for the frameworks...
    
    set +e    
    echo "------------------"
    LOG="$LOGDIR/build-iphone-stage.log"
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
    LOG="$LOGDIR/build-iphone-install.log"
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
    LOG="$LOGDIR/build-iphone-simulator-build.log"
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
    doneSection
}
#===============================================================================
scrunchAllLibsTogetherInOneLibPerPlatform()
{
    cd $BOOST_SRC
    mkdir -p $IOSBUILDDIR/armv7/obj
    #mkdir -p $IOSBUILDDIR/armv7s/obj
	mkdir -p $IOSBUILDDIR/arm64/obj
    mkdir -p $IOSBUILDDIR/i386/obj
	mkdir -p $IOSBUILDDIR/x86_64/obj
    ALL_LIBS=""
    echo Splitting all existing fat binaries...
    for NAME in $BOOST_LIBS; do
        ALL_LIBS="$ALL_LIBS libboost_$NAME.a"
        $ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin armv7 -o $IOSBUILDDIR/armv7/libboost_$NAME.a
        #$ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin armv7s -o $IOSBUILDDIR/armv7s/libboost_$NAME.a
		$ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" -thin arm64 -o $IOSBUILDDIR/arm64/libboost_$NAME.a
		$ARM_DEV_CMD lipo "iphonesim-build/stage/lib/libboost_$NAME.a" -thin i386 -o $IOSBUILDDIR/i386/libboost_$NAME.a
		$ARM_DEV_CMD lipo "iphonesim-build/stage/lib/libboost_$NAME.a" -thin x86_64 -o $IOSBUILDDIR/x86_64/libboost_$NAME.a
  
    done
    echo "Decomposing each architecture's .a files"
    for NAME in $ALL_LIBS; do
        echo Decomposing $NAME...
        (cd $IOSBUILDDIR/armv7/obj; ar -x ../$NAME );
        #(cd $IOSBUILDDIR/armv7s/obj; ar -x ../$NAME );
		(cd $IOSBUILDDIR/arm64/obj; ar -x ../$NAME );
        (cd $IOSBUILDDIR/i386/obj; ar -x ../$NAME );
		(cd $IOSBUILDDIR/x86_64/obj; ar -x ../$NAME );
    done
    echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost.a )"
    rm $IOSBUILDDIR/*/libboost.a
    
    echo ...armv7
    (cd $IOSBUILDDIR/armv7; $ARM_DEV_CMD ar crus libboost.a obj/*.o; )
    #echo ...armv7s
    #(cd $IOSBUILDDIR/armv7s; $ARM_DEV_CMD ar crus libboost.a obj/*.o; )
    echo ...arm64
    (cd $IOSBUILDDIR/arm64; $ARM_DEV_CMD ar crus libboost.a obj/*.o; )
    echo ...i386
    (cd $IOSBUILDDIR/i386;  $SIM_DEV_CMD ar crus libboost.a obj/*.o; )
    echo ...x86_64
    (cd $IOSBUILDDIR/x86_64;  $SIM_DEV_CMD ar crus libboost.a obj/*.o; )
    echo "Making fat lib for iOS Boost '$VERSION_STRING'"
    lipo -c $IOSBUILDDIR/armv7/libboost.a \
            $IOSBUILDDIR/arm64/libboost.a \
            $IOSBUILDDIR/i386/libboost.a \
            $IOSBUILDDIR/x86_64/libboost.a \
            -output $OUTPUT_DIR_LIB/libboost.a
    echo "Completed Fat Lib"
    echo "------------------"
}
#===============================================================================
buildIncludes()
{
    
    mkdir -p $IOSINCLUDEDIR
    echo "------------------"
    echo "Copying Includes to Final Dir $OUTPUT_DIR_SRC"
    LOG="$LOGDIR/buildIncludes.log"
    set +e
    cp -r $PREFIXDIR/include/boost/*  $OUTPUT_DIR_SRC/ > "${LOG}" 2>&1
    if [ $? != 0 ]; then 
        tail -n 100 "${LOG}"
        echo "Problem while copying includes - Please check ${LOG}"
        exit 1
    else 
        echo "Copy of Includes successful"
    fi
    echo "------------------"
    doneSection
}
#===============================================================================
# Execution starts here
#===============================================================================
mkdir -p $IOSBUILDDIR
#cleanEverythingReadyToStart #may want to comment if repeatedly running during dev
#restoreBoost
echo "BOOST_VERSION:     $VERSION_STRING"
echo "BOOST_LIBS:        $BOOST_LIBS"
echo "BOOST_SRC:         $BOOST_SRC"
echo "IOSBUILDDIR:       $IOSBUILDDIR"
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
buildIncludes
#restoreBoost
postcleanEverything
echo "Completed successfully"
#===============================================================================

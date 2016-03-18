#!/bin/bash

export XCODE_XCCONFIG_FILE=$SCRIPT_DIR/no-code-sign.xcconfig

#IPHONE_SDKVERSION=`xcodebuild -showsdks | grep iphoneos | egrep "[[:digit:]]+\.[[:digit:]]+" -o | tail -1`
IPHONE_SDKVERSION=`xcrun -sdk iphoneos --show-sdk-version`
IPHONEOS_PLATFORM=`xcrun --sdk iphoneos --show-sdk-platform-path`
IPHONEOS_SYSROOT=`xcrun --sdk iphoneos --show-sdk-path`
IPHONESIMULATOR_PLATFORM=`xcrun --sdk iphonesimulator --show-sdk-platform-path`
IPHONESIMULATOR_SYSROOT=`xcrun --sdk iphonesimulator --show-sdk-path`

OS_RELEASE=`uname -r`

OSX_SDKVERSION=`xcrun -sdk macosx --show-sdk-version`
XCODE_ROOT=`xcode-select -print-path`
if [ ! -d "$XCODE_ROOT" ]; then
  echo "xcode path is not set correctly set: '$XCODE_ROOT' does not exist (most likely because of xcode > 4.3)"
  echo "run"
  echo "sudo xcode-select -switch <xcode path>"
  echo "for default installation:"
  echo "sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer"
  exit 1
fi
case $XCODE_ROOT in  
     *\ * )
           echo "Your Xcode path contains whitespaces, which is not supported."
           exit 1
          ;;
esac

# invent_missing_headers <sources dir>
function invent_missing_headers
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo 'Creating missing headers...'
    cp $XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IPHONE_SDKVERSION}.sdk/usr/include/{crt_externs,bzlib}.h $1
}

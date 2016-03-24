#!/bin/bash

brew -h || /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

git help || brew install git
cmake -h || brew install cmake
automake --help || brew install automake
autoconf --help || brew install autoconf
brew list | grep libtool || brew install libtool
#!/bin/bash -l
#------------------------------------------------------------------------------

# CLEANUP
rm -rf CMakeCache.txt
rm -rf CMakeFiles

# SOURCE AND INSTALL
SOURCE=../minisweep
INSTALL=../install

BUILD=Debug
#BUILD=Release

#------------------------------------------------------------------------------

cmake \
  -DCMAKE_BUILD_TYPE:STRING="$BUILD" \
  -DCMAKE_INSTALL_PREFIX:PATH="$INSTALL" \
  -DCMAKE_C_COMPILER:STRING=gcc \
  -DCMAKE_C_FLAGS:STRING="-DNM_VALUE=4" \
  -DCMAKE_C_FLAGS_DEBUG:STRING="-g" \
  -DCMAKE_C_FLAGS_RELEASE:STRING="-O3 -fomit-frame-pointer -funroll-loops -finline-limit=10000000" \
  $SOURCE

#------------------------------------------------------------------------------

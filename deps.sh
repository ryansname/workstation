#!/bin/bash

mkdir -p libs
pushd libs

ZIG_VERSION=0.10.0-dev.2983+2bda025ca
COMPILER_DIR=zig-${ZIG_VERSION}

[ ! -d ${COMPILER_DIR} ] && (mkdir ${COMPILER_DIR}; curl https://ziglang.org/builds/zig-macos-aarch64-${ZIG_VERSION}.tar.xz | tar xJ -C ${COMPILER_DIR} --strip-components=1)
[ ${ZIG_VERSION} != $(zig version) ] && export PATH=$(pwd)/${COMPILER_DIR}:$PATH

[ ! -d zig-imgui ] && git clone https://github.com/SpexGuy/Zig-ImGui.git
(cd zig-imgui && git fetch && git checkout 0a2cfca)

popd

. ./env.sh


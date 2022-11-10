#!/bin/bash

mkdir -p libs
pushd libs

ZIG_VERSION=0.10.0
COMPILER_DIR=zig-${ZIG_VERSION}

# [ ! -d ${COMPILER_DIR} ] && (mkdir ${COMPILER_DIR}; curl https://ziglang.org/builds/zig-macos-aarch64-${ZIG_VERSION}.tar.xz | tar xJ -C ${COMPILER_DIR} --strip-components=1)
[ ! -d ${COMPILER_DIR} ] && (mkdir ${COMPILER_DIR}; curl https://ziglang.org/download/${ZIG_VERSION}/zig-macos-aarch64-${ZIG_VERSION}.tar.xz | tar xJ -C ${COMPILER_DIR} --strip-components=1)
[ ${ZIG_VERSION} != $(zig version) ] && export PATH=$(pwd)/${COMPILER_DIR}:$PATH

[ ! -d zig-imgui ] && git clone https://github.com/SpexGuy/Zig-ImGui.git
git remote -v | grep ryansname || git remote add ryansname https://github.com/ryansname/Zig-ImGui.git
(cd zig-imgui && git fetch -a && git checkout b19ba185b6)

pushd ../..
[ ! -d zig-jira-client ] && git clone git@github.com:ryansname/zig-jira-client.git
(cd zig-jira-client && git fetch && git checkout 6865a933966b)
popd

[ ! -d jira-client ] && mkdir jira-client
ln -f ../../zig-jira-client/* jira-client/

popd

. ./env.sh


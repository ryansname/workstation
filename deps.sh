#!/bin/bash

mkdir -p libs
pushd libs

[ ! -d zig-imgui ] && git clone https://github.com/SpexGuy/Zig-ImGui.git
pushd zig-imgui
    git remote -v | grep ryansname || git remote add ryansname https://github.com/ryansname/Zig-ImGui.git
    git remote -v | grep michaelbartnett || git remote add michaelbartnett https://github.com/michaelbartnett/Zig-ImGui.git
    git fetch --all && git checkout 04f246a
popd

popd

. ./env.sh


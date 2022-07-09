#!/bin/bash

mkdir -p libs
cd libs

[ ! -d mach-glfw ] && git clone https://github.com/hexops/mach-glfw.git
(cd mach-glfw && git fetch && git checkout 385f718)

[ ! -d zig-imgui ] && git clone https://github.com/SpexGuy/Zig-ImGui.git
(cd zig-imgui && git fetch && git checkout 0a2cfca)

[ ! -d zgl ] && git clone https://github.com/ziglibs/zgl.git
(cd zgl && git fetch && git checkout 32608da)
